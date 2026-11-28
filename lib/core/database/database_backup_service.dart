import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'app_database.dart';
import '../auth/activity_log_repository.dart';
import '../auth/auth_session.dart';

enum RestorePhotoMode { merge, keepCurrent, backupOnly }

/// Backup lengkap: database SQLite dan foto produk/dokumentasi servis.
/// File media disimpan sebagai file terpisah di dalam ZIP, bukan base64 di SQLite.
class DatabaseBackupService {
  static const String _databaseName = 'bengkelku_pos.db';
  static const String _manifestName = 'manifest.json';

  ArchiveFile? _findArchiveFile(Archive archive, String name) {
    for (final file in archive.files) {
      if (file.name == name && file.isFile) return file;
    }
    return null;
  }

  Future<String> _databasePath() async =>
      p.join(await getDatabasesPath(), _databaseName);

  Future<Directory> _backupDirectory() async {
    final documents = await getApplicationDocumentsDirectory();
    final directory = Directory(p.join(documents.path, 'BengkelKuBackups'));
    if (!await directory.exists()) await directory.create(recursive: true);
    return directory;
  }

  Future<Directory> _documentsDirectory() => getApplicationDocumentsDirectory();

  String _timestamp() {
    final now = DateTime.now();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${now.year}${two(now.month)}${two(now.day)}_${two(now.hour)}${two(now.minute)}${two(now.second)}';
  }

  Future<void> _removeSqliteSidecars(String databasePath) async {
    for (final suffix in ['-wal', '-shm']) {
      final sidecar = File('$databasePath$suffix');
      if (await sidecar.exists()) await sidecar.delete();
    }
  }

  Future<List<Map<String, Object?>>> _mediaReferences(Database db) async {
    final references = <Map<String, Object?>>[];
    final products = await db.query('products', columns: ['id', 'image_path']);
    for (final row in products) {
      final path = row['image_path']?.toString().trim() ?? '';
      if (path.isNotEmpty) {
        references.add({
          'table': 'products',
          'column': 'image_path',
          'id': row['id'],
          'originalPath': path,
          'kind': 'product',
        });
      }
    }
    final users = await db.query('app_users', columns: ['id', 'profile_photo_path']);
    for (final row in users) {
      final path = row['profile_photo_path']?.toString().trim() ?? '';
      if (path.isNotEmpty) {
        references.add({
          'table': 'app_users',
          'column': 'profile_photo_path',
          'id': row['id'],
          'originalPath': path,
          'kind': 'profile',
        });
      }
    }
    final services = await db.query(
      'service_orders',
      columns: ['id', 'before_photo_path', 'after_photo_path'],
    );
    for (final row in services) {
      for (final column in ['before_photo_path', 'after_photo_path']) {
        final path = row[column]?.toString().trim() ?? '';
        if (path.isNotEmpty) {
          references.add({
            'table': 'service_orders',
            'column': column,
            'id': row['id'],
            'originalPath': path,
            'kind': 'service',
          });
        }
      }
    }
    return references;
  }

  Future<bool> _hasColumn(Database db, String table, String column) async {
    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ? LIMIT 1",
      [table],
    );
    if (tables.isEmpty) return false;
    final columns = await db.rawQuery('PRAGMA table_info($table)');
    return columns.any((item) => item['name'] == column);
  }

  Future<void> _applyCurrentMediaFallback(
    Database db,
    Map<String, String> currentPhotoPaths,
    RestorePhotoMode photoMode, {
    required bool backupHasMedia,
  }) async {
    if (photoMode == RestorePhotoMode.backupOnly) return;
    for (final entry in currentPhotoPaths.entries) {
      if (!await File(entry.value).exists()) continue;
      final parts = entry.key.split('|');
      if (parts.length != 3) continue;
      final table = parts[0], id = parts[1], column = parts[2];
      if (!await _hasColumn(db, table, column)) continue;
      final rows = await db.query(
        table,
        columns: [column],
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (rows.isEmpty) continue;
      final backupPath = rows.first[column]?.toString().trim() ?? '';
      final backupPhotoExists =
          backupPath.isNotEmpty && await File(backupPath).exists();
      final shouldUseCurrent = photoMode == RestorePhotoMode.keepCurrent ||
          !backupHasMedia ||
          !backupPhotoExists;
      if (shouldUseCurrent) {
        await db.update(
          table,
          {column: entry.value},
          where: 'id = ?',
          whereArgs: [id],
        );
      }
    }
  }

  Future<void> _clearMediaReferences(Database db) async {
    const columnsByTable = <String, List<String>>{
      'products': ['image_path'],
      'app_users': ['profile_photo_path'],
      'service_orders': ['before_photo_path', 'after_photo_path'],
    };
    for (final entry in columnsByTable.entries) {
      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ? LIMIT 1",
        [entry.key],
      );
      if (tables.isEmpty) continue;
      final columns = await db.rawQuery('PRAGMA table_info(${entry.key})');
      final names = columns.map((column) => column['name']).toSet();
      for (final column in entry.value) {
        if (names.contains(column)) {
          await db.update(entry.key, {column: null});
        }
      }
    }
  }

  Future<File> createBackup() async {
    AuthSession.instance.requireAdmin('Hanya Admin yang dapat membuat backup.');
    final db = await AppDatabase.instance.database;
    final integrity = await db.rawQuery('PRAGMA integrity_check');
    if (integrity.isEmpty || integrity.first.values.first?.toString() != 'ok') {
      throw StateError('Database tidak lolos pemeriksaan integritas. Backup dihentikan.');
    }

    final references = await _mediaReferences(db);
    await db.rawQuery('PRAGMA wal_checkpoint(FULL)');
    await AppDatabase.instance.close();

    try {
      final timestamp = _timestamp();
      final directory = await _backupDirectory();
      final databasePath = await _databasePath();
      await _removeSqliteSidecars(databasePath);
      final source = File(databasePath);
      if (!await source.exists() || await source.length() == 0) {
        throw StateError('File database utama tidak ditemukan atau kosong.');
      }
      final databaseBytes = await source.readAsBytes();
      final archive = Archive();
      archive.addFile(ArchiveFile(
        'database/$_databaseName',
        databaseBytes.length,
        databaseBytes,
      ));

      final manifestItems = <Map<String, Object?>>[];
      final missingReferences = <Map<String, Object?>>[];
      var mediaIndex = 0;
      final seen = <String, String>{};
      for (final reference in references) {
        final originalPath = reference['originalPath']! as String;
        String? archivePath = seen[originalPath];
        if (archivePath == null) {
          final sourceFile = File(originalPath);
          if (await sourceFile.exists()) {
            final kind = reference['kind']! as String;
            final extension = p.extension(originalPath).toLowerCase();
            archivePath = 'media/$kind/${mediaIndex++}${extension.isEmpty ? '.img' : extension}';
            final bytes = await sourceFile.readAsBytes();
            archive.addFile(ArchiveFile(archivePath, bytes.length, bytes));
            seen[originalPath] = archivePath;
          } else {
            missingReferences.add(reference);
          }
        }
        manifestItems.add({
          'table': reference['table'],
          'column': reference['column'],
          'id': reference['id'],
          'originalPath': originalPath,
          'archivePath': archivePath,
        });
      }

      if (missingReferences.isNotEmpty) {
        final first = missingReferences.first;
        final table = first['table'];
        final column = first['column'];
        final id = first['id'];
        final path = first['originalPath'];
        final kindLabel = switch (table) {
          'products' => 'Foto produk',
          'app_users' => 'Foto profil pengguna',
          _ => 'Foto dokumentasi servis',
        };
        final remaining = missingReferences.length - 1;
        throw StateError(
          'Backup dibatalkan. $kindLabel tidak ditemukan '
          '(ID: $id, kolom: $column): $path'
          '${remaining > 0 ? '. Masih ada $remaining file foto lain yang hilang' : ''}. '
          'Periksa data tersebut terlebih dahulu agar backup tidak kehilangan foto.',
        );
      }

      final manifest = utf8.encode(jsonEncode({
        'format': 'bengkelku_backup',
        'formatVersion': 1,
        'createdAt': DateTime.now().toIso8601String(),
        'database': 'database/$_databaseName',
        'media': manifestItems,
        'mediaIncluded': seen.length,
        'mediaMissing': 0,
      }));
      archive.addFile(ArchiveFile(_manifestName, manifest.length, manifest));

      final zipBytes = ZipEncoder().encode(archive);
      if (zipBytes.isEmpty) {
        throw StateError('Arsip ZIP gagal dibuat.');
      }
      final destination = File(p.join(directory.path, 'BengkelKu_Backup_$timestamp.zip'));
      await destination.writeAsBytes(zipBytes, flush: true);
      final writtenBytes = await destination.length();
      if (writtenBytes < 100) {
        await destination.delete();
        throw StateError('Ukuran arsip backup tidak valid.');
      }
      // ZIP dapat lebih kecil dari database karena kompresi; validasi dengan
      // membuka ulang arsip dan memastikan entri database utuh.
      final verificationArchive = ZipDecoder().decodeBytes(
        await destination.readAsBytes(),
      );
      final verificationDatabase = _findArchiveFile(
        verificationArchive,
        'database/$_databaseName',
      );
      if (verificationDatabase == null ||
          (verificationDatabase.content as List<int>).length !=
              databaseBytes.length) {
        await destination.delete();
        throw StateError('Verifikasi arsip backup gagal.');
      }
      return destination;
    } finally {
      // Selalu buka kembali database, termasuk jika pembuatan ZIP gagal.
      await AppDatabase.instance.database;
    }
  }

  Future<String> restoreBackup(String sourcePath, {RestorePhotoMode photoMode = RestorePhotoMode.merge}) async {
    AuthSession.instance.requireAdmin('Hanya Admin yang dapat memulihkan backup.');
    final source = File(sourcePath);
    final currentDb = await AppDatabase.instance.database;
    final currentPhotoPaths = <String, String>{};
    for (final item in await _mediaReferences(currentDb)) {
      final key = '${item['table']}|${item['id']}|${item['column']}';
      currentPhotoPaths[key] = item['originalPath']! as String;
    }
    if (!await source.exists() || await source.length() < 100) {
      throw StateError('File backup tidak ditemukan atau ukurannya tidak valid.');
    }
    final directory = await _backupDirectory();
    final timestamp = _timestamp();
    final candidate = File(p.join(directory.path, 'restore_candidate_$timestamp.db'));
    final restoredMedia = Directory(
      p.join((await _documentsDirectory()).path, 'restored_media_$timestamp'),
    );
    Database? checkDb;
    var candidateValidated = false;
    var mediaCreated = false;

    try {
      if (p.extension(sourcePath).toLowerCase() == '.zip') {
        final archive = ZipDecoder().decodeBytes(await source.readAsBytes());
        final databaseEntry = _findArchiveFile(archive, 'database/$_databaseName');
        if (databaseEntry == null) {
          throw const FormatException('ZIP tidak berisi database BengkelKu.');
        }
        final databaseBytes = databaseEntry.content as List<int>;
        await candidate.writeAsBytes(databaseBytes, flush: true);

        final manifestEntry = _findArchiveFile(archive, _manifestName);
        if (manifestEntry == null) {
          throw const FormatException('Manifest backup tidak ditemukan.');
        }
        final manifest = jsonDecode(utf8.decode(manifestEntry.content as List<int>));
        if (manifest is! Map || manifest['format'] != 'bengkelku_backup' ||
            manifest['formatVersion'] != 1 || manifest['media'] is! List) {
          throw const FormatException('Format manifest backup tidak didukung.');
        }
        if (manifest['mediaMissing'] != 0 ||
            manifest['mediaIncluded'] is! int ||
            (manifest['mediaIncluded'] as int) < 0) {
          throw const FormatException(
            'Manifest menunjukkan media tidak lengkap atau jumlah media tidak valid.',
          );
        }

        final archiveFileNames = archive.files
            .where((file) => file.isFile)
            .map((file) => file.name)
            .toList();
        if (archiveFileNames.toSet().length != archiveFileNames.length) {
          throw const FormatException('Arsip ZIP memiliki nama file duplikat.');
        }

        await restoredMedia.create(recursive: true);
        mediaCreated = true;
        checkDb = await openDatabase(candidate.path, singleInstance: false);
        final mediaEntries = archiveFileNames.toSet();
        final restoredArchivePaths = <String>{};
        for (final item in (manifest['media'] as List)) {
          if (item is! Map) {
            throw const FormatException('Entri media pada manifest tidak valid.');
          }
          final table = item['table']?.toString();
          final column = item['column']?.toString();
          final originalPath = item['originalPath']?.toString();
          final archivePath = item['archivePath']?.toString();
          final id = item['id'];
          if (table == null || column == null || originalPath == null ||
              archivePath == null || id == null) {
            throw const FormatException('Entri media pada manifest tidak lengkap.');
          }
          final archiveParts = archivePath.split('/');
          final allowed = (table == 'products' && column == 'image_path') ||
              (table == 'app_users' && column == 'profile_photo_path') ||
              (table == 'service_orders' &&
                  (column == 'before_photo_path' || column == 'after_photo_path'));
          if (!allowed ||
              archiveParts.length != 3 ||
              archiveParts[0] != 'media' ||
              !['product', 'profile', 'service'].contains(archiveParts[1]) ||
              archiveParts[2].isEmpty ||
              archiveParts[2] == '.' ||
              archiveParts[2] == '..' ||
              archivePath.codeUnits.contains(92) ||
              !mediaEntries.contains(archivePath)) {
            throw FormatException('File media backup tidak valid atau hilang: $archivePath');
          }
          final entry = _findArchiveFile(archive, archivePath);
          if (entry == null) {
            throw FormatException('File media backup tidak ditemukan: $archivePath');
          }
          final safeName = p.basename(archivePath);
          final kind = table == 'products'
              ? 'products'
              : table == 'app_users'
                  ? 'profiles'
                  : 'services';
          final targetDirectory = Directory(p.join(restoredMedia.path, kind));
          await targetDirectory.create(recursive: true);
          final target = File(p.join(targetDirectory.path, safeName));
          await target.writeAsBytes(entry.content as List<int>, flush: true);
          restoredArchivePaths.add(archivePath);
          final key = '$table|$id|$column';
          final currentPath = currentPhotoPaths[key];
          final currentExists = currentPath != null && await File(currentPath).exists();
          if (photoMode != RestorePhotoMode.keepCurrent || !currentExists) {
            await checkDb.update(table, {column: target.path},
                where: 'id = ? AND $column = ?', whereArgs: [id, originalPath]);
          }
        }
        if (restoredArchivePaths.length != manifest['mediaIncluded']) {
          throw const FormatException(
            'Jumlah file media dalam ZIP tidak sesuai dengan manifest.',
          );
        }
        if (photoMode != RestorePhotoMode.backupOnly) {
          for (final entry in currentPhotoPaths.entries) {
            final parts = entry.key.split('|');
            if (parts.length != 3 || !await File(entry.value).exists()) continue;
            final table = parts[0], id = parts[1], column = parts[2];
            if (!await _hasColumn(checkDb, table, column)) continue;
            final rows = await checkDb.query(table, columns: [column],
                where: 'id = ?', whereArgs: [id], limit: 1);
            if (rows.isEmpty) continue;
            final backupPath = rows.first[column]?.toString().trim() ?? '';
            final shouldUseCurrent = photoMode == RestorePhotoMode.keepCurrent
                ? true : backupPath.isEmpty;
            if (shouldUseCurrent) {
              await checkDb.update(table, {column: entry.value}, where: 'id = ?', whereArgs: [id]);
            }
          }
        }
        await checkDb.close();
        checkDb = null;
      } else {
        await source.copy(candidate.path);
        // File .db tidak membawa media. Bersihkan semua referensi foto dari
        // database backup agar path lama dari perangkat lain tidak dianggap
        // sebagai foto backup yang valid.
        checkDb = await openDatabase(candidate.path, singleInstance: false);
        await _clearMediaReferences(checkDb);
        if (photoMode != RestorePhotoMode.backupOnly) {
          // Karena file .db tidak memiliki foto, mode merge dan keepCurrent
          // sama-sama hanya dapat mempertahankan foto lokal yang masih ada.
          for (final entry in currentPhotoPaths.entries) {
            final parts = entry.key.split('|');
            if (parts.length != 3 || !await File(entry.value).exists()) continue;
            final table = parts[0], id = parts[1], column = parts[2];
            if (!await _hasColumn(checkDb, table, column)) continue;
            await checkDb.update(table, {column: entry.value},
                where: 'id = ?', whereArgs: [id]);
          }
        }
        await checkDb.close();
        checkDb = null;
      }

      checkDb = await openDatabase(candidate.path, readOnly: true, singleInstance: false);
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
      candidateValidated = true;
    } finally {
      await checkDb?.close();
      if (!candidateValidated && await candidate.exists()) await candidate.delete();
      if (!candidateValidated && mediaCreated && await restoredMedia.exists()) {
        await restoredMedia.delete(recursive: true);
      }
    }

    final databasePath = await _databasePath();
    final currentFile = File(databasePath);
    if (!await currentFile.exists()) {
      await candidate.delete();
      if (mediaCreated && await restoredMedia.exists()) await restoredMedia.delete(recursive: true);
      throw StateError('Database saat ini tidak ditemukan. Pemulihan dihentikan demi keamanan.');
    }
    final safetyCopy = File(p.join(directory.path, 'BengkelKu_Sebelum_Pemulihan_$timestamp.db'));

    await AppDatabase.instance.close();
    try {
      await _removeSqliteSidecars(databasePath);
      await currentFile.copy(safetyCopy.path);
      await candidate.copy(databasePath);
      final restoredDb = await AppDatabase.instance.database;
      await _applyCurrentMediaFallback(
        restoredDb,
        currentPhotoPaths,
        photoMode,
        backupHasMedia: p.extension(sourcePath).toLowerCase() == '.zip',
      );
      final integrity = await restoredDb.rawQuery('PRAGMA integrity_check');
      if (integrity.isEmpty || integrity.first.values.first?.toString() != 'ok') {
        throw StateError('Database hasil pemulihan gagal pemeriksaan integritas.');
      }
      await ActivityLogRepository.record(
        restoredDb,
        action: 'database_restored',
        description: 'Memulihkan database BengkelKu dari backup. Salinan database sebelum pemulihan disimpan.',
        entityType: 'database',
      );
      await candidate.delete();
      return safetyCopy.path;
    } catch (_) {
      await AppDatabase.instance.close();
      if (await candidate.exists()) await candidate.delete();
      if (await safetyCopy.exists()) {
        await _removeSqliteSidecars(databasePath);
        await safetyCopy.copy(databasePath);
        await _removeSqliteSidecars(databasePath);
      }
      if (mediaCreated && await restoredMedia.exists()) {
        await restoredMedia.delete(recursive: true);
      }
      await AppDatabase.instance.database;
      rethrow;
    }
  }
}
