import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'app_database.dart';
import '../auth/activity_log_repository.dart';
import '../auth/auth_session.dart';

class DatabaseBackupService {
  static const String _databaseName = 'bengkelku_pos.db';

  Future<String> _databasePath() async {
    return p.join(await getDatabasesPath(), _databaseName);
  }

  Future<Directory> _backupDirectory() async {
    final documents = await getApplicationDocumentsDirectory();
    final directory = Directory(p.join(documents.path, 'BengkelKuBackups'));
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  String _timestamp() {
    final now = DateTime.now();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${now.year}${two(now.month)}${two(now.day)}_${two(now.hour)}${two(now.minute)}${two(now.second)}';
  }

  Future<File> createBackup() async {
    final db = await AppDatabase.instance.database;
    final integrity = await db.rawQuery('PRAGMA integrity_check');
    if (integrity.isEmpty || integrity.first.values.first?.toString() != 'ok') {
      throw StateError('Database tidak lolos pemeriksaan integritas. Backup dihentikan.');
    }
    await db.rawQuery('PRAGMA wal_checkpoint(FULL)');
    await AppDatabase.instance.close();

    try {
      final source = File(await _databasePath());
      if (!await source.exists() || await source.length() == 0) {
        throw StateError('File database utama tidak ditemukan atau kosong.');
      }
      final directory = await _backupDirectory();
      final destination = File(p.join(directory.path, 'BengkelKu_Backup_${_timestamp()}.db'));
      final backup = await source.copy(destination.path);
      if (await backup.length() != await source.length()) {
        await backup.delete();
        throw StateError('Ukuran file backup tidak sesuai. Backup dibatalkan.');
      }
      return backup;
    } finally {
      await AppDatabase.instance.database;
    }
  }

  Future<String> restoreBackup(String sourcePath) async {
    AuthSession.instance.requireAdmin('Hanya Admin yang dapat memulihkan database.');
    final source = File(sourcePath);
    if (!await source.exists() || await source.length() < 100) {
      throw StateError('File backup tidak ditemukan atau ukurannya tidak valid.');
    }

    final directory = await _backupDirectory();
    final candidate = File(p.join(directory.path, 'restore_candidate_${_timestamp()}.db'));
    await source.copy(candidate.path);

    Database? checkDb;
    try {
      checkDb = await openDatabase(
        candidate.path,
        readOnly: true,
        singleInstance: false,
      );
      final integrity = await checkDb.rawQuery('PRAGMA integrity_check');
      if (integrity.isEmpty || integrity.first.values.first?.toString() != 'ok') {
        throw const FormatException('File backup rusak atau tidak valid.');
      }
      final versionRows = await checkDb.rawQuery('PRAGMA user_version');
      final version = versionRows.isEmpty
          ? 0
          : (versionRows.first.values.first as num?)?.toInt() ?? 0;
      if (version < 1 || version > AppDatabase.currentVersion) {
        throw FormatException('Versi database backup ($version) tidak didukung aplikasi ini.');
      }
      final tables = await checkDb.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table'",
      );
      final tableNames = tables.map((row) => row['name']?.toString()).toSet();
      const requiredTables = ['products', 'sales', 'service_orders', 'app_settings'];
      final missing = requiredTables.where((name) => !tableNames.contains(name)).toList();
      if (missing.isNotEmpty) {
        throw FormatException('File bukan backup BengkelKu yang valid. Tabel tidak ditemukan: ${missing.join(', ')}.');
      }
    } finally {
      await checkDb?.close();
    }

    final databasePath = await _databasePath();
    final currentFile = File(databasePath);
    if (!await currentFile.exists()) {
      await candidate.delete();
      throw StateError('Database saat ini tidak ditemukan. Pemulihan dihentikan demi keamanan.');
    }
    final safetyCopy = File(p.join(directory.path, 'BengkelKu_Sebelum_Pemulihan_${_timestamp()}.db'));

    await AppDatabase.instance.close();
    try {
      await currentFile.copy(safetyCopy.path);
      await candidate.copy(databasePath);
      final restoredDb = await AppDatabase.instance.database;
      final integrity = await restoredDb.rawQuery('PRAGMA integrity_check');
      if (integrity.isEmpty || integrity.first.values.first?.toString() != 'ok') {
        throw StateError('Database hasil pemulihan gagal pemeriksaan integritas.');
      }
      await ActivityLogRepository.record(
        restoredDb,
        action: 'database_restored',
        description: 'Memulihkan database dari file backup. Salinan sebelum pemulihan disimpan untuk pemulihan darurat.',
        entityType: 'database',
      );
      await candidate.delete();
      return safetyCopy.path;
    } catch (error) {
      await AppDatabase.instance.close();
      if (await safetyCopy.exists()) {
        await safetyCopy.copy(databasePath);
        await AppDatabase.instance.database;
      }
      rethrow;
    }
  }
}
