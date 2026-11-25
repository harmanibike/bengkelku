import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/widgets/app_photo_preview.dart';

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
    return AppPhotoPreview(
      path: path,
      height: height,
      width: double.infinity,
      placeholderIcon: Icons.add_a_photo_outlined,
      placeholderLabel: 'Belum ada foto',
      borderRadius: BorderRadius.circular(12),
    );
  }
}
