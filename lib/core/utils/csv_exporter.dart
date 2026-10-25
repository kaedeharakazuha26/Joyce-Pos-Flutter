import 'dart:io';

class CsvExporter {
  static String toCsv(List<String> headers, List<List<dynamic>> rows) {
    String esc(dynamic v) {
      final s = (v ?? '').toString();
      if (s.contains(',') || s.contains('"') || s.contains('\n')) {
        return '"${s.replaceAll('"', '""')}"';
      }
      return s;
    }

    final sb = StringBuffer();
    sb.writeln(headers.map(esc).join(','));
    for (final row in rows) {
      sb.writeln(row.map(esc).join(','));
    }
    return sb.toString();
  }

  static Future<String?> pickSaveFile({
    required String defaultFileName,
    String filter = 'CSV files (*.csv)|*.csv|All files (*.*)|*.*',
  }) async {
    if (!Platform.isWindows) return null;
    final script = '''
Add-Type -AssemblyName System.Windows.Forms
\$dlg = New-Object System.Windows.Forms.SaveFileDialog
\$dlg.FileName = "${defaultFileName.replaceAll('"', '')}"
\$dlg.Filter = "${filter.replaceAll('"', '')}"
if (\$dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
  Write-Output \$dlg.FileName
}
''';
    final res = await Process.run('powershell', ['-NoProfile', '-Sta', '-Command', script]);
    if (res.exitCode != 0) return null;
    final out = (res.stdout as String).trim();
    return out.isEmpty ? null : out;
  }

  static Future<String?> pickOpenFile({
    String filter = 'All files (*.*)|*.*',
  }) async {
    if (!Platform.isWindows) return null;
    final script = '''
Add-Type -AssemblyName System.Windows.Forms
\$dlg = New-Object System.Windows.Forms.OpenFileDialog
\$dlg.Filter = "${filter.replaceAll('"', '')}"
if (\$dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
  Write-Output \$dlg.FileName
}
''';
    final res = await Process.run('powershell', ['-NoProfile', '-Sta', '-Command', script]);
    if (res.exitCode != 0) return null;
    final out = (res.stdout as String).trim();
    return out.isEmpty ? null : out;
  }

  static Future<String?> pickFolder() async {
    if (!Platform.isWindows) return null;
    final script = '''
Add-Type -AssemblyName System.Windows.Forms
\$dlg = New-Object System.Windows.Forms.FolderBrowserDialog
if (\$dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
  Write-Output \$dlg.SelectedPath
}
''';
    final res = await Process.run('powershell', ['-NoProfile', '-Sta', '-Command', script]);
    if (res.exitCode != 0) return null;
    final out = (res.stdout as String).trim();
    return out.isEmpty ? null : out;
  }

  static Future<String?> exportCsvDialog({
    required String defaultFileName,
    required List<String> headers,
    required List<List<dynamic>> rows,
  }) async {
    final path = await pickSaveFile(defaultFileName: defaultFileName);
    if (path == null || path.isEmpty) return null;
    final csv = toCsv(headers, rows);
    File(path).writeAsStringSync(csv);
    return path;
  }
}
