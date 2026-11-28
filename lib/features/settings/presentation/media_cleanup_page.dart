import 'package:material_ui/material_ui.dart';

import '../../../core/auth/auth_session.dart';
import '../../../core/database/media_cleanup_service.dart';

class MediaCleanupPage extends StatefulWidget {
  const MediaCleanupPage({super.key});

  @override
  State<MediaCleanupPage> createState() => _MediaCleanupPageState();
}

class _MediaCleanupPageState extends State<MediaCleanupPage> {
  MediaCleanupReport? _report;
  bool _busy = false;
  final Set<String> _selected = {};

  String _size(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  Future<void> _scan() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final report = await MediaCleanupService.instance.scan();
      if (!mounted) return;
      setState(() {
        _report = report;
        _selected.clear();
      });
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Pemeriksaan gagal: $error')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    if (_selected.isEmpty || _busy) return;
    final count = _selected.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hapus foto yang tidak digunakan?'),
        content: Text(
          '$count file terpilih akan dihapus permanen. '
          'File diperiksa ulang terhadap database sebelum dihapus. '
          'Foto yang masih direferensikan tidak akan dihapus.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Hapus file terpilih')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final deleted = await MediaCleanupService.instance.deleteConfirmed(_selected.toList());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$deleted file foto berhasil dihapus.')),
      );
      setState(() => _busy = false);
      await _scan();
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Penghapusan gagal: $error')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _scan();
  }

  @override
  Widget build(BuildContext context) {
    if (!AuthSession.instance.isAdmin) {
      return Scaffold(
        appBar: AppBar(title: const Text('Pemeriksaan Penyimpanan Foto')),
        body: const Center(child: Text('Hanya Admin yang dapat mengelola foto.')),
      );
    }
    final report = _report;
    return Scaffold(
      appBar: AppBar(title: const Text('Pemeriksaan Penyimpanan Foto')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Pemeriksaan hanya mencakup folder foto milik aplikasi: product_images, service_photos, restored_media_*, dan file profil berpola profile_ di Documents. Foto di luar lokasi tersebut tidak disentuh.',
          ),
          const SizedBox(height: 12),
          if (_busy) const LinearProgressIndicator(),
          if (report == null && !_busy)
            FilledButton.icon(onPressed: _scan, icon: const Icon(Icons.refresh), label: const Text('Pindai ulang')),
          if (report != null) ...[
            Card(child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('File diperiksa: ${report.scannedFiles}'),
                Text('File yang masih dipakai: ${report.referencedFiles}'),
                Text('File tidak direferensikan: ${report.orphans.length}'),
                const SizedBox(height: 6),
                Text('Potensi ruang kembali: ${_size(report.reclaimableBytes)}', style: Theme.of(context).textTheme.titleMedium),
              ]),
            )),
            Row(children: [
              TextButton(onPressed: _busy ? null : _scan, child: const Text('Pindai ulang')),
              const Spacer(),
              TextButton(onPressed: _busy || report.orphans.isEmpty ? null : () => setState(() {
                if (_selected.length == report.orphans.length) {
                  _selected.clear();
                } else {
                  _selected.addAll(report.orphans.map((item) => item.path));
                }
              }), child: Text(_selected.length == report.orphans.length ? 'Batalkan semua' : 'Pilih semua')),
            ]),
            if (report.orphans.isEmpty)
              const ListTile(leading: Icon(Icons.check_circle_outline), title: Text('Tidak ditemukan foto yatim.'))
            else
              ...report.orphans.map((item) => CheckboxListTile(
                value: _selected.contains(item.path),
                onChanged: _busy ? null : (value) => setState(() {
                  if (value == true) { _selected.add(item.path); } else { _selected.remove(item.path); }
                }),
                title: Text(item.path.split('/').last, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(_size(item.bytes)),
                controlAffinity: ListTileControlAffinity.leading,
                dense: true,
              )),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _busy || _selected.isEmpty ? null : _delete,
              icon: const Icon(Icons.delete_outline),
              label: Text('Hapus terpilih (${_selected.length})'),
            ),
          ],
          const SizedBox(height: 12),
          const Text('Catatan: file foto lama tidak pernah dihapus otomatis setelah pemulihan backup. Hapus hanya setelah memeriksa daftar hasil pemindaian.'),
        ],
      ),
    );
  }
}
