import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'app_database.dart';
import '../auth/auth_session.dart';

class OrphanMediaFile {
  const OrphanMediaFile({required this.path, required this.bytes});

  final String path;
  final int bytes;
}

class MediaCleanupReport {
  const MediaCleanupReport({
    required this.scannedFiles,
    required this.referencedFiles,
    required this.orphans,
  });

  final int scannedFiles;
  final int referencedFiles;
  final List<OrphanMediaFile> orphans;

  int get reclaimableBytes => orphans.fold(0, (sum, item) => sum + item.bytes);
}

class MediaCleanupService {
  MediaCleanupService._();

  static final instance = MediaCleanupService._();

  Future<Set<String>> _referencedPaths(Database db) async {
    final paths = <String>{};
    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'",
    );

    // Temukan seluruh kolom path foto/gambar dari skema aktif, bukan hanya
    // daftar tabel yang diketahui saat fitur ini pertama dibuat.
    for (final tableRow in tables) {
      final table = tableRow['name']?.toString();
      if (table == null || table.isEmpty) continue;
      final columns = await db.rawQuery('PRAGMA table_info("$table")');
      for (final column in columns) {
        final name = column['name']?.toString() ?? '';
        final normalizedName = name.toLowerCase();
        final isMediaPath = normalizedName.endsWith('_path') &&
            (normalizedName.contains('photo') ||
                normalizedName.contains('image'));
        if (!isMediaPath) continue;

        final rows = await db.query(table, columns: [name]);
        for (final row in rows) {
          final value = row[name]?.toString().trim() ?? '';
          if (value.isNotEmpty) {
            paths.add(p.normalize(p.absolute(value)));
          }
        }
      }
    }
    return paths;
  }

  Future<List<File>> _managedFiles(Directory documents) async {
    final result = <File>[];

    Future<void> collect(Directory directory) async {
      if (!await directory.exists()) return;
      await for (final entity in directory.list(recursive: true, followLinks: false)) {
        if (entity is File) result.add(entity);
      }
    }

    await collect(Directory(p.join(documents.path, 'product_images')));
    await collect(Directory(p.join(documents.path, 'service_photos')));

    // Folder media hasil restore dibuat unik per proses pemulihan.
    await for (final entity in documents.list(followLinks: false)) {
      if (entity is Directory && p.basename(entity.path).startsWith('restored_media_')) {
        await collect(entity);
      }
    }

    // Foto profil disimpan langsung di root Documents dengan pola nama khusus.
    await for (final entity in documents.list(followLinks: false)) {
      if (entity is File && p.basename(entity.path).startsWith('profile_')) {
        result.add(entity);
      }
    }
    return result;
  }

  Future<MediaCleanupReport> scan() async {
    AuthSession.instance.requireAdmin('Hanya Admin yang dapat memeriksa penyimpanan foto.');
    final db = await AppDatabase.instance.database;
    final references = await _referencedPaths(db);
    final documents = await getApplicationDocumentsDirectory();
    final files = await _managedFiles(documents);
    final orphans = <OrphanMediaFile>[];

    for (final file in files) {
      final normalized = p.normalize(p.absolute(file.path));
      if (!references.contains(normalized) && await file.exists()) {
        orphans.add(OrphanMediaFile(path: normalized, bytes: await file.length()));
      }
    }
    orphans.sort((a, b) => a.path.compareTo(b.path));
    return MediaCleanupReport(
      scannedFiles: files.length,
      referencedFiles: files.length - orphans.length,
      orphans: List.unmodifiable(orphans),
    );
  }

  Future<int> deleteConfirmed(List<String> selectedPaths) async {
    AuthSession.instance.requireAdmin('Hanya Admin yang dapat menghapus foto yatim.');
    if (selectedPaths.isEmpty) return 0;

    final documents = await getApplicationDocumentsDirectory();
    final root = p.normalize(p.absolute(documents.path));
    final productRoot = p.normalize(p.join(root, 'product_images'));
    final serviceRoot = p.normalize(p.join(root, 'service_photos'));
    final db = await AppDatabase.instance.database;
    final references = await _referencedPaths(db);
    var deleted = 0;

    for (final rawPath in selectedPaths.toSet()) {
      final path = p.normalize(p.absolute(rawPath));
      final basename = p.basename(path);
      final isProduct = p.isWithin(productRoot, path);
      final isService = p.isWithin(serviceRoot, path);
      final parent = p.dirname(path);
      final relativeParts = p.isWithin(root, path)
          ? p.relative(path, from: root).split(p.separator)
          : const <String>[];
      final isRestoredMedia = relativeParts.isNotEmpty &&
          relativeParts.first.startsWith('restored_media_');
      final isProfile = parent == root && basename.startsWith('profile_');
      if (!isProduct && !isService && !isProfile && !isRestoredMedia) continue;
      if (references.contains(path)) continue;

      final file = File(path);
      if (await file.exists()) {
        await file.delete();
        deleted++;
      }
    }
    return deleted;
  }
}
