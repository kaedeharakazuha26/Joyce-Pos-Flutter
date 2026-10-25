import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import '../utils/dates.dart';
import 'database_service.dart';

class BranchManager {
  final String appDataDir;
  final DatabaseService dbService;
  late Map<String, dynamic> _state;

  BranchManager({
    String? appDataDir,
    required this.dbService,
  }) : appDataDir = appDataDir ?? _defaultAppDataDir() {
    final dir = Directory(this.appDataDir);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    _loadOrInitBranches();
  }

  static String _defaultAppDataDir() {
    final appData = Platform.environment['APPDATA'];
    if (appData != null && appData.isNotEmpty) {
      return p.join(appData, 'com.joyce.pos');
    }
    return p.join(Directory.current.path, '.joyce_pos_data');
  }

  String get _branchesJsonPath => p.join(appDataDir, 'branches.json');

  Map<String, dynamic> _defaultState() {
    return <String, dynamic>{
      'active_branch': 'main',
      'storage_dir': '',
      'last_backup_at': '',
      'last_backup_path': '',
      'branches': <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'main',
          'name': 'Main Store',
          'file': 'joyce_pos.db',
          'created_at': formatDateTime(DateTime.now()),
        },
      ],
    };
  }

  void _loadOrInitBranches() {
    final f = File(_branchesJsonPath);
    if (f.existsSync()) {
      try {
        final decoded = jsonDecode(f.readAsStringSync());
        if (decoded is Map<String, dynamic> &&
            decoded['branches'] is List &&
            (decoded['branches'] as List).isNotEmpty) {
          decoded['branches'] = (decoded['branches'] as List)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
          _state = decoded;
        } else {
          _state = _defaultState();
          _saveState();
        }
      } catch (_) {
        _state = _defaultState();
        _saveState();
      }
    } else {
      _state = _defaultState();
      _saveState();
    }
    _openActiveBranchDb();
  }

  void _saveState() {
    final f = File(_branchesJsonPath);
    if (!f.parent.existsSync()) {
      f.parent.createSync(recursive: true);
    }
    f.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(_state));
  }

  Map<String, dynamic> _activeBranchEntry() {
    final branches = (_state['branches'] as List).cast<Map<String, dynamic>>();
    final activeId = _state['active_branch'] as String? ?? 'main';
    return branches.firstWhere(
      (b) => b['id'] == activeId,
      orElse: () {
        _state['active_branch'] = branches.first['id'];
        _saveState();
        return branches.first;
      },
    );
  }

  void _openActiveBranchDb() {
    final entry = _activeBranchEntry();
    final fileName = entry['file'] as String;
    final localPath = p.join(appDataDir, fileName);
    final storageDir = (_state['storage_dir'] as String? ?? '').trim();

    if (!File(localPath).existsSync() && storageDir.isNotEmpty) {
      final cloudCopy = File(p.join(storageDir, fileName));
      if (cloudCopy.existsSync()) {
        try {
          cloudCopy.copySync(localPath);
        } catch (_) {}
      }
    }
    dbService.openPath(localPath);
  }

  Map<String, dynamic> getBranchInfo() {
    final entry = _activeBranchEntry();
    final localPath = p.join(appDataDir, entry['file'] as String);
    return {
      'active_branch': _state['active_branch'],
      'storage_dir': _state['storage_dir'] ?? '',
      'default_dir': appDataDir,
      'active_db_path': localPath,
      'last_backup_at': _state['last_backup_at'] ?? '',
      'last_backup_path': _state['last_backup_path'] ?? '',
      'branches': List<Map<String, dynamic>>.from(
        (_state['branches'] as List).map((e) => Map<String, dynamic>.from(e as Map)),
      ),
    };
  }

  Map<String, dynamic> createBranch(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw Exception('Branch name is required');
    }
    final slug = trimmed
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    final safeSlug = slug.isEmpty ? 'store' : slug;
    final secs = (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();
    final last4 = secs.length >= 4 ? secs.substring(secs.length - 4) : secs;
    final id = 'branch_${safeSlug}_$last4';
    final file = 'joyce_pos_$id.db';

    final branches = (_state['branches'] as List).cast<Map<String, dynamic>>();
    branches.add({
      'id': id,
      'name': trimmed,
      'file': file,
      'created_at': formatDateTime(DateTime.now()),
    });
    _state['active_branch'] = id;
    _saveState();
    _openActiveBranchDb();
    return getBranchInfo();
  }

  Map<String, dynamic> switchBranch(String branchId) {
    final branches = (_state['branches'] as List).cast<Map<String, dynamic>>();
    final exists = branches.any((b) => b['id'] == branchId);
    if (!exists) {
      throw Exception('Branch "$branchId" not found');
    }
    _state['active_branch'] = branchId;
    _saveState();
    _openActiveBranchDb();
    return getBranchInfo();
  }

  Map<String, dynamic> deleteBranch(String branchId) {
    if (branchId == 'main') {
      throw Exception('Cannot delete the main branch');
    }
    final branches = (_state['branches'] as List).cast<Map<String, dynamic>>();
    if (branches.length <= 1) {
      throw Exception('Cannot delete the only remaining branch');
    }
    branches.removeWhere((b) => b['id'] == branchId);
    if (_state['active_branch'] == branchId) {
      _state['active_branch'] = branches.first['id'];
      _openActiveBranchDb();
    }
    _saveState();
    return getBranchInfo();
  }

  Map<String, dynamic> setStorageDir(String dir) {
    final trimmed = dir.trim();
    if (trimmed.isNotEmpty) {
      final d = Directory(trimmed);
      if (!d.existsSync()) {
        d.createSync(recursive: true);
      }
    }
    _state['storage_dir'] = trimmed;
    _saveState();
    if (trimmed.isNotEmpty) {
      performEodSnapshot('INIT_${todayDateString()}');
    }
    return getBranchInfo();
  }

  Map<String, dynamic> performEodSnapshot(String tag) {
    try {
      final entry = _activeBranchEntry();
      final branchId = entry['id'] as String;
      final branchFile = entry['file'] as String;
      final storageDir = (_state['storage_dir'] as String? ?? '').trim();
      final baseDir = (storageDir.isNotEmpty && Directory(storageDir).existsSync())
          ? storageDir
          : appDataDir;
      final backupsDir = Directory(p.join(baseDir, 'EOD_Backups'));
      if (!backupsDir.existsSync()) {
        backupsDir.createSync(recursive: true);
      }

      final safeTag = tag.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
      final finalName = 'joyce_pos_${branchId}_$safeTag.db';
      final tmpName = '.tmp_${DateTime.now().millisecondsSinceEpoch}_$finalName';
      final tmpPath = p.join(backupsDir.path, tmpName);
      final finalPath = p.join(backupsDir.path, finalName);

      final escapedTmp = tmpPath.replaceAll("'", "''");
      dbService.db.execute("VACUUM INTO '$escapedTmp'");

      final finalFile = File(finalPath);
      if (finalFile.existsSync()) {
        finalFile.deleteSync();
      }
      File(tmpPath).renameSync(finalPath);

      if (storageDir.isNotEmpty && Directory(storageDir).existsSync()) {
        final latestCloudPath = p.join(storageDir, branchFile);
        File(finalPath).copySync(latestCloudPath);
      }

      final nowStr = formatDateTime(DateTime.now());
      _state['last_backup_at'] = nowStr;
      _state['last_backup_path'] = finalPath;
      _saveState();

      dbService.logAudit(
        action: 'EOD_BACKUP',
        entityType: 'system',
        entityId: finalPath,
        summary: 'Created snapshot backup ($safeTag)',
        details: {'path': finalPath, 'tag': safeTag},
      );

      return {'ok': true, 'path': finalPath, 'timestamp': nowStr};
    } catch (e) {
      return {'ok': false, 'error': e.toString()};
    }
  }
}
