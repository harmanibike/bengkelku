import 'package:cross_file/cross_file.dart';
import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/auth/auth_session.dart';
import '../../../core/database/database_backup_service.dart';
import 'media_cleanup_page.dart';

class DatabaseBackupPage extends StatefulWidget {
  const DatabaseBackupPage({super.key});

  @override
  State<DatabaseBackupPage> createState() => _DatabaseBackupPageState();
}

class _DatabaseBackupPageState extends State<DatabaseBackupPage> {
  final DatabaseBackupService _service = DatabaseBackupService();
  bool _busy = false;

  Future<void> _createBackup() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final file = await _service.createBackup();
      if (!mounted) return;
      await SharePlus.instance.share(ShareParams(
        title: 'Backup BengkelKu POS',
        text: 'Backup database BengkelKu POS. Simpan file ini di tempat yang aman.',
        files: [XFile(file.path)],
      ));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('File backup berhasil dibuat.')),
      );
    } catch (error) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Backup belum berhasil'),
          content: SingleChildScrollView(
            child: SelectableText(
              'Gagal membuat atau membagikan backup.\\n\\n$error',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Tutup'),
            ),
          ],
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restoreBackup() async {
    if (_busy) return;
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['zip', 'db', 'sqlite', 'sqlite3'],
        allowMultiple: false,
      );
      if (!mounted || result == null || result.files.isEmpty) return;
      final path = result.files.single.path;
      if (path == null || path.isEmpty) {
        throw StateError('Lokasi file backup tidak dapat dibaca.');
      }
      final selectedMode = await showDialog<RestorePhotoMode>(
        context: context,
        builder: (dialogContext) {
          var selected = RestorePhotoMode.merge;
          return StatefulBuilder(builder: (context, setDialogState) => AlertDialog(
            title: const Text('Atur pemulihan foto'),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('Pilih bagaimana foto backup dan foto di HP digabungkan.'),
              RadioListTile<RestorePhotoMode>(
                contentPadding: EdgeInsets.zero, value: RestorePhotoMode.merge,
                groupValue: selected, onChanged: (v) => setDialogState(() => selected = v!),
                title: const Text('Gabungkan foto'),
                subtitle: const Text('Foto backup menggantikan foto pada record yang sama. Jika backup tidak punya foto, foto HP dipertahankan.')),
              RadioListTile<RestorePhotoMode>(
                contentPadding: EdgeInsets.zero, value: RestorePhotoMode.keepCurrent,
                groupValue: selected, onChanged: (v) => setDialogState(() => selected = v!),
                title: const Text('Pertahankan foto HP'),
                subtitle: const Text('Foto HP yang masih ada tidak ditimpa. Foto backup hanya mengisi foto yang kosong.')),
              RadioListTile<RestorePhotoMode>(
                contentPadding: EdgeInsets.zero, value: RestorePhotoMode.backupOnly,
                groupValue: selected, onChanged: (v) => setDialogState(() => selected = v!),
                title: const Text('Gunakan foto backup saja'),
                subtitle: const Text('Foto yang tidak ada di backup akan kosong pada data hasil pemulihan.')),
              const Text('Data transaksi dan database tetap mengikuti file backup. Foto HP hanya dipasangkan ke record dengan ID yang sama.'),
            ]),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Batal')),
              FilledButton(onPressed: () => Navigator.pop(dialogContext, selected), child: const Text('Lanjutkan')),
            ],
          ));
        },
      );
      if (selectedMode == null || !mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Konfirmasi pemulihan'),
          content: const Text('Database saat ini akan diganti dengan isi backup. Salinan pengaman dibuat terlebih dahulu. File foto lama tidak langsung dihapus.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Batal')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Pulihkan')),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      setState(() => _busy = true);
      final safetyPath = await _service.restoreBackup(path, photoMode: selectedMode);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Backup berhasil dipulihkan sesuai pilihan foto. Foto lama belum dihapus; salinan database lama tetap disimpan.'),
          duration: const Duration(seconds: 6),
          action: SnackBarAction(
            label: 'Info',
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Salinan pengaman: $safetyPath')),
              );
            },
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal memulihkan database: $error')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!AuthSession.instance.isAdmin) {
      return Scaffold(
        appBar: AppBar(title: const Text('Backup & Pemulihan')),
        body: const Center(
          child: Text('Hanya Admin yang dapat mengelola backup database.'),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Backup & Pemulihan')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.backup_outlined, size: 34),
                  const SizedBox(height: 10),
                  const Text(
                    'Buat Backup',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Salin database beserta foto produk dan dokumentasi servis ke satu file .zip, '
                    'lalu simpan di tempat aman, flashdisk melalui OTG, atau cloud pribadi.',
                  ),
                  const SizedBox(height: 14),
                  FilledButton.icon(
                    onPressed: _busy ? null : _createBackup,
                    icon: const Icon(Icons.file_upload_outlined),
                    label: const Text('Buat & Bagikan Backup'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.settings_backup_restore_outlined, size: 34),
                  const SizedBox(height: 10),
                  const Text(
                    'Pulihkan dari Backup',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Pilih backup lengkap BengkelKu (.zip). File .db dari versi lama tetap didukung, '
                    'tetapi tidak membawa foto. Database saat ini disalin sebelum dipulihkan.',
                  ),
                  const SizedBox(height: 14),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _restoreBackup,
                    icon: const Icon(Icons.file_download_outlined),
                    label: const Text('Pilih File Backup'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.photo_library_outlined, size: 32),
                  const SizedBox(height: 8),
                  const Text('Pemeriksaan Penyimpanan Foto', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  const Text('Pindai foto produk, foto profil, dan dokumentasi servis yang tidak lagi dipakai. Tidak ada file yang dihapus otomatis.'),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MediaCleanupPage())),
                    icon: const Icon(Icons.search),
                    label: const Text('Periksa & Kelola Foto'),
                  ),
                ],
              ),
            ),
          ),
          if (_busy) ...[
            const SizedBox(height: 18),
            const LinearProgressIndicator(),
            const SizedBox(height: 8),
            const Center(child: Text('Sedang memproses database...')),
          ],
          const SizedBox(height: 16),
          const ListTile(
            leading: Icon(Icons.security_outlined),
            title: Text('Penting'),
            subtitle: Text(
              'Backup berisi data pelanggan, transaksi, stok, akun, dan informasi usaha. '
              'Jangan membagikannya kepada orang yang tidak berwenang. '
              'Lakukan backup rutin dan simpan salinannya di luar perangkat kasir.',
            ),
            contentPadding: EdgeInsets.zero,
          ),
        ],
      ),
    );
  }
}
