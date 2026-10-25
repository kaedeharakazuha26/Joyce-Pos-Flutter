import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';
import 'receipt_builder.dart';

class PrinterService {
  Future<void> sendBytes(
    Uint8List bytes,
    Map<String, String> settings,
  ) async {
    final conn = (settings['printer_conn'] ?? 'none').toLowerCase().trim();
    if (conn == 'none' || conn == 'browser' || conn.isEmpty) {
      throw Exception('No printer configured. Set one up in Settings > Printer.');
    }

    if (conn == 'network') {
      final rawAddr = (settings['network_addr'] ?? '').trim();
      if (rawAddr.isEmpty) {
        throw Exception('Network printer address is empty');
      }
      String host = rawAddr;
      int port = 9100;
      if (rawAddr.contains(':')) {
        final parts = rawAddr.split(':');
        host = parts.first.trim();
        port = int.tryParse(parts.last.trim()) ?? 9100;
      }
      final socket = await Socket.connect(
        host,
        port,
        timeout: const Duration(seconds: 4),
      );
      try {
        socket.add(bytes);
        await socket.flush();
      } finally {
        await socket.close();
      }
      return;
    }

    if (conn == 'serial' || conn == 'bluetooth') {
      final rawPath = (settings['serial_path'] ?? '').trim();
      if (rawPath.isEmpty) {
        throw Exception('Serial/COM port path is empty');
      }
      final winPath = (Platform.isWindows &&
              rawPath.toUpperCase().startsWith('COM') &&
              !rawPath.startsWith(r'\\.\'))
          ? r'\\.\' + rawPath
          : rawPath;
      final file = File(winPath);
      final raf = file.openSync(mode: FileMode.write);
      try {
        raf.writeFromSync(bytes);
        raf.flushSync();
      } finally {
        raf.closeSync();
      }
      return;
    }

    if (conn == 'usb') {
      final printerName = (settings['usb_vid'] ?? '').trim();
      if (Platform.isWindows) {
        _sendRawToWindowsSpooler(bytes, printerName);
        return;
      }
      throw Exception('USB printing is only supported on Windows.');
    }

    throw Exception('No printer configured. Set one up in Settings > Printer.');
  }

  Future<void> printTestPage(Map<String, String> settings) async {
    final w = ReceiptBuilder.resolveWidth(settings);
    final storeName = (settings['store_name'] ?? 'JOYCE POS').trim();
    final bytes = <int>[
      0x1B, 0x40, // ESC @
      0x1B, 0x61, 1, // Center
      0x1B, 0x45, 1, // Bold
      ...ReceiptBuilder.sanitizeAscii(storeName).codeUnits, 0x0A,
      0x1B, 0x45, 0,
      ...ReceiptBuilder.sanitizeAscii('PRINTER TEST OK').codeUnits, 0x0A,
      ...('-' * w).codeUnits, 0x0A,
      0x1B, 0x64, 3,
      0x1D, 0x56, 66, 0,
    ];
    await sendBytes(Uint8List.fromList(bytes), settings);
  }

  Future<List<Map<String, dynamic>>> listAvailablePrinters() async {
    if (!Platform.isWindows) return [];
    try {
      final res = await Process.run('powershell', [
        '-NoProfile',
        '-Command',
        'Get-Printer | Select-Object Name, PortName, DriverName | ConvertTo-Json -Compress',
      ]);
      if (res.exitCode != 0) return [];
      final out = (res.stdout as String).trim();
      if (out.isEmpty) return [];
      final decoded = jsonDecode(out);
      final list = decoded is List ? decoded : [decoded];
      return list.map<Map<String, dynamic>>((item) {
        final name = (item['Name'] ?? '').toString();
        final port = (item['PortName'] ?? '').toString();
        return {
          'vid': name,
          'pid': port,
          'name': '$name ($port)',
          'is_printer': true,
        };
      }).toList();
    } catch (_) {
      return [];
    }
  }

  void _sendRawToWindowsSpooler(Uint8List bytes, String printerName) {
    if (printerName.isEmpty) {
      throw Exception(
        'Please specify the Windows Printer Name in Settings > Printer.',
      );
    }
    using((arena) {
      final pPrinterName = printerName.toNativeUtf16(allocator: arena);
      final phPrinter = arena<HANDLE>();

      final opened = OpenPrinter(pPrinterName, phPrinter, nullptr);
      if (opened == 0) {
        throw Exception('Failed to open Windows printer "$printerName"');
      }
      final hPrinter = phPrinter.value;
      try {
        final docInfo = arena<DOC_INFO_1>()
          ..ref.pDocName = 'JOYCE POS Receipt'.toNativeUtf16(allocator: arena)
          ..ref.pOutputFile = nullptr
          ..ref.pDatatype = 'RAW'.toNativeUtf16(allocator: arena);

        final job = StartDocPrinter(hPrinter, 1, docInfo.cast());
        if (job == 0) {
          throw Exception('StartDocPrinter (RAW) failed for "$printerName"');
        }
        try {
          if (StartPagePrinter(hPrinter) == 0) {
            throw Exception('StartPagePrinter failed for "$printerName"');
          }
          try {
            final pBytes = arena<Uint8>(bytes.length);
            pBytes.asTypedList(bytes.length).setAll(0, bytes);
            final pcWritten = arena<DWORD>();
            final ok = WritePrinter(
              hPrinter,
              pBytes.cast(),
              bytes.length,
              pcWritten,
            );
            if (ok == 0 || pcWritten.value != bytes.length) {
              throw Exception('WritePrinter failed for "$printerName"');
            }
          } finally {
            EndPagePrinter(hPrinter);
          }
        } finally {
          EndDocPrinter(hPrinter);
        }
      } finally {
        ClosePrinter(hPrinter);
      }
    });
  }
}
