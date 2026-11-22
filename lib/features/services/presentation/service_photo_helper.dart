import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

class ServicePhotoHelper {
  ServicePhotoHelper._();

  static final ImagePicker _picker = ImagePicker();

  /// Memilih kamera atau galeri, lalu menyalin foto ke penyimpanan permanen app.
  static Future<String?> pickAndSave(BuildContext context) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Ambil foto dengan kamera'),
              onTap: () => Navigator.pop(sheetContext, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Pilih dari galeri'),
              onTap: () => Navigator.pop(sheetContext, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );

    if (source == null) return null;

    final XFile? picked = await _picker.pickImage(
      source: source,
      imageQuality: 82,
      maxWidth: 1920,
      maxHeight: 1920,
    );

    if (picked == null) return null;

    final appDirectory = await getApplicationDocumentsDirectory();
    final photoDirectory = Directory(
      '${appDirectory.path}${Platform.pathSeparator}service_photos',
    );

    if (!await photoDirectory.exists()) {
      await photoDirectory.create(recursive: true);
    }

    final extension = _extension(picked.path);
    final fileName = 'service_${DateTime.now().microsecondsSinceEpoch}$extension';
    final destination = File(
      '${photoDirectory.path}${Platform.pathSeparator}$fileName',
    );

    await File(picked.path).copy(destination.path);
    return destination.path;
  }

  static String _extension(String path) {
    final dot = path.lastIndexOf('.');
    if (dot < 0) return '.jpg';
    final extension = path.substring(dot).toLowerCase();
    if (extension.length > 6) return '.jpg';
    return extension;
  }

  static Widget preview(String? path, {double height = 150}) {
    if (path == null || path.isEmpty || !File(path).existsSync()) {
      return Container(
        height: height,
        width: double.infinity,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.grey.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.withValues(alpha: 0.35)),
        ),
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add_a_photo_outlined, size: 32),
            SizedBox(height: 6),
            Text('Belum ada foto'),
          ],
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.file(
        File(path),
        height: height,
        width: double.infinity,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(
          height: height,
          alignment: Alignment.center,
          color: Colors.grey.withValues(alpha: 0.10),
          child: const Text('Foto tidak dapat ditampilkan'),
        ),
      ),
    );
  }
}
