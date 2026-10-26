import 'dart:async';
import 'package:flutter/services.dart';

typedef BarcodeCallback = void Function(String barcode);

class _KeyStroke {
  final String char;
  final DateTime time;
  const _KeyStroke(this.char, this.time);
}

/// Global hardware barcode scanner service.
/// Intercepts rapid keystrokes from USB/HID/Bluetooth handheld barcode scanners
/// and dispatches the decoded barcode string to the active subscriber or modal.
class BarcodeScannerService {
  BarcodeScannerService._();
  static final BarcodeScannerService instance = BarcodeScannerService._();

  final List<BarcodeCallback> _subscribers = [];
  final List<_KeyStroke> _buffer = [];
  Timer? _debounceTimer;
  bool _initialized = false;

  void init() {
    if (_initialized) return;
    _initialized = true;
    HardwareKeyboard.instance.addHandler(_onKeyEvent);
  }

  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKeyEvent);
    _debounceTimer?.cancel();
    _subscribers.clear();
    _buffer.clear();
    _initialized = false;
  }

  /// Subscribe to barcode scans. Returns an unsubscribe callback.
  /// If multiple subscribers exist (e.g. modal on top of screen), the topmost subscriber receives the scan.
  void Function() subscribe(BarcodeCallback callback) {
    init();
    _subscribers.add(callback);
    return () {
      _subscribers.remove(callback);
    };
  }

  /// Manually dispatch or simulate a barcode scan.
  void dispatch(String raw) {
    final clean = raw.trim();
    if (clean.isEmpty) return;
    // Dispatch to the active (topmost) subscriber
    for (int i = _subscribers.length - 1; i >= 0; i--) {
      _subscribers[i](clean);
      break; // Only the topmost active subscriber receives the scan
    }
  }

  bool _onKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return false;

    final now = DateTime.now();

    // Check for barcode terminating keys: Enter, NumpadEnter, or Tab
    final isEnter = event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter;
    final isTab = event.logicalKey == LogicalKeyboardKey.tab;

    if (isEnter || isTab) {
      _debounceTimer?.cancel();
      if (_buffer.isNotEmpty) {
        final barcode = _processBuffer(now);
        _buffer.clear();
        if (barcode != null && barcode.isNotEmpty) {
          dispatch(barcode);
          // If we have subscribers, swallow the Enter key so it doesn't trigger active dialog buttons
          return _subscribers.isNotEmpty;
        }
      }
      return false;
    }

    final char = _extractChar(event);
    if (char != null && char.isNotEmpty) {
      // If gap between keystrokes is too large (> 600ms), start a fresh buffer
      if (_buffer.isNotEmpty) {
        final gap = now.difference(_buffer.last.time).inMilliseconds;
        if (gap > 600) {
          _buffer.clear();
        }
      }

      _buffer.add(_KeyStroke(char, now));

      // Automatic fallback for scanners that have Enter suffix disabled
      _debounceTimer?.cancel();
      _debounceTimer = Timer(const Duration(milliseconds: 90), () {
        if (_buffer.length >= 6) {
          final barcode = _processBuffer(DateTime.now());
          _buffer.clear();
          if (barcode != null && barcode.isNotEmpty) {
            dispatch(barcode);
          }
        } else {
          _buffer.clear();
        }
      });
    }

    return false;
  }

  String? _processBuffer(DateTime now) {
    if (_buffer.isEmpty) return null;

    final bufferStr = _buffer.map((k) => k.char).join();

    // Calculate timing characteristics
    if (_buffer.length >= 2) {
      final totalElapsed = _buffer.last.time.difference(_buffer.first.time).inMilliseconds;
      final avgInterval = totalElapsed / (_buffer.length - 1);

      // Scanners typically produce keystrokes within 0 to 45ms intervals
      // Humans typically produce > 100ms intervals
      // If buffer is long (>= 4) and reasonably fast (< 80ms avg), or short (< 35ms avg)
      if (avgInterval <= 85 || _buffer.length >= 8) {
        return bufferStr.trim();
      }
    } else if (_buffer.length == 1 && _buffer.first.char.length >= 2) {
      return bufferStr.trim();
    }

    // If buffer length is at least 3 alphanumeric characters
    if (_buffer.length >= 3) {
      return bufferStr.trim();
    }

    return null;
  }

  static String? _extractChar(KeyEvent event) {
    // 1. Direct character from event if printable
    if (event.character != null && event.character!.isNotEmpty) {
      final code = event.character!.codeUnitAt(0);
      if (code >= 32 && code != 127) {
        return event.character;
      }
    }

    // 2. Map logical keys
    final k = event.logicalKey;
    if (k == LogicalKeyboardKey.digit0 || k == LogicalKeyboardKey.numpad0) return '0';
    if (k == LogicalKeyboardKey.digit1 || k == LogicalKeyboardKey.numpad1) return '1';
    if (k == LogicalKeyboardKey.digit2 || k == LogicalKeyboardKey.numpad2) return '2';
    if (k == LogicalKeyboardKey.digit3 || k == LogicalKeyboardKey.numpad3) return '3';
    if (k == LogicalKeyboardKey.digit4 || k == LogicalKeyboardKey.numpad4) return '4';
    if (k == LogicalKeyboardKey.digit5 || k == LogicalKeyboardKey.numpad5) return '5';
    if (k == LogicalKeyboardKey.digit6 || k == LogicalKeyboardKey.numpad6) return '6';
    if (k == LogicalKeyboardKey.digit7 || k == LogicalKeyboardKey.numpad7) return '7';
    if (k == LogicalKeyboardKey.digit8 || k == LogicalKeyboardKey.numpad8) return '8';
    if (k == LogicalKeyboardKey.digit9 || k == LogicalKeyboardKey.numpad9) return '9';
    if (k == LogicalKeyboardKey.minus || k == LogicalKeyboardKey.numpadSubtract) return '-';
    if (k == LogicalKeyboardKey.period || k == LogicalKeyboardKey.numpadDecimal) return '.';

    if (k.keyLabel.length == 1) {
      return k.keyLabel;
    }

    return null;
  }
}
