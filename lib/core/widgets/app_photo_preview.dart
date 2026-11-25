import 'dart:io';

import 'package:material_ui/material_ui.dart';

/// Tampilan foto lokal yang konsisten untuk foto produk dan dokumentasi servis.
class AppPhotoPreview extends StatelessWidget {
  const AppPhotoPreview({
    super.key,
    required this.path,
    this.width = double.infinity,
    this.height = 120,
    this.fit = BoxFit.cover,
    this.borderRadius = const BorderRadius.all(Radius.circular(12)),
    this.placeholderIcon = Icons.image_outlined,
    this.placeholderLabel = 'Belum ada foto',
  });

  final String? path;
  final double width;
  final double height;
  final BoxFit fit;
  final BorderRadius borderRadius;
  final IconData placeholderIcon;
  final String placeholderLabel;

  @override
  Widget build(BuildContext context) {
    final filePath = path?.trim() ?? '';
    final hasImage = filePath.isNotEmpty && File(filePath).existsSync();
    final borderColor = Theme.of(context).colorScheme.outlineVariant;

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: const Color(0xFFF3F6F9),
        borderRadius: borderRadius,
        border: Border.all(color: borderColor.withValues(alpha: 0.8)),
      ),
      clipBehavior: Clip.antiAlias,
      child: hasImage
          ? Image.file(
              File(filePath),
              width: width,
              height: height,
              fit: fit,
              errorBuilder: (_, __, ___) => _placeholder(context),
            )
          : _placeholder(context),
    );
  }

  Widget _placeholder(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            placeholderIcon,
            size: height < 80 ? 22 : 30,
            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.72),
          ),
          if (height >= 80) ...[
            const SizedBox(height: 6),
            Text(
              placeholderLabel,
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
}
