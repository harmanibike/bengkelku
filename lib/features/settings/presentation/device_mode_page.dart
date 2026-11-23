import 'package:material_ui/material_ui.dart';

import '../data/device_mode_repository.dart';

class DeviceModePage extends StatefulWidget {
  const DeviceModePage({super.key});

  @override
  State<DeviceModePage> createState() => _DeviceModePageState();
}

class _DeviceModePageState extends State<DeviceModePage> {
  final DeviceModeRepository _repository = DeviceModeRepository();
  late Future<String> _modeFuture;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _modeFuture = _repository.getMode();
  }

  Future<void> _keepLocalMode() async {
    setState(() => _saving = true);
    try {
      await _repository.saveMode(DeviceModeRepository.localMode);
      if (!mounted) return;
      setState(() {
        _modeFuture = Future.value(DeviceModeRepository.localMode);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Mode Lokal tetap digunakan.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal menyimpan mode perangkat: $error')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mode Perangkat')),
      body: FutureBuilder<String>(
        future: _modeFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text('Gagal membaca mode perangkat: ${snapshot.error}'),
              ),
            );
          }

          final mode = snapshot.data ?? DeviceModeRepository.localMode;
          return ListView(
            padding: const EdgeInsets.all(14),
            children: [
              const Text(
                'Pilih cara perangkat BengkelKu POS bekerja. Semua perangkat nantinya tetap memakai aplikasi dan modul yang sama; hak akses mengikuti akun yang login.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 12),
              Card(
                child: ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Color(0xFFE8F5E9),
                    child: Icon(Icons.phone_android_rounded, color: Color(0xFF2E7D32)),
                  ),
                  title: const Text('Mode Lokal', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text('Aplikasi menggunakan database pada perangkat ini. Dapat digunakan tanpa Wi-Fi atau internet.'),
                  trailing: mode == DeviceModeRepository.localMode
                      ? const Icon(Icons.check_circle, color: Color(0xFF2E7D32))
                      : const Icon(Icons.radio_button_unchecked),
                ),
              ),
              Card(
                child: ListTile(
                  enabled: false,
                  leading: const CircleAvatar(
                    backgroundColor: Color(0xFFE3F2FD),
                    child: Icon(Icons.dns_rounded, color: Color(0xFF1565C0)),
                  ),
                  title: const Text('Mode Server', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text('Perangkat menjadi pusat data Wi-Fi sekaligus tetap bisa dipakai transaksi. Belum diaktifkan.'),
                  trailing: const Text('Tahap berikutnya', style: TextStyle(fontSize: 10)),
                ),
              ),
              Card(
                child: ListTile(
                  enabled: false,
                  leading: const CircleAvatar(
                    backgroundColor: Color(0xFFFFF3E0),
                    child: Icon(Icons.devices_rounded, color: Color(0xFFEF6C00)),
                  ),
                  title: const Text('Mode Client', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text('Perangkat terhubung ke Server untuk transaksi, input data, stok, dan laporan dari database pusat. Belum diaktifkan.'),
                  trailing: const Text('Tahap berikutnya', style: TextStyle(fontSize: 10)),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _saving ? null : _keepLocalMode,
                icon: _saving
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.save_outlined),
                label: Text(_saving ? 'Menyimpan...' : 'Pastikan Mode Lokal'),
              ),
              const SizedBox(height: 10),
              const Text(
                'Penting: Mode Server dan Client belum dapat dipakai untuk menghubungkan dua HP. Mode Lokal tetap menjadi pilihan aman sampai layanan jaringan, keamanan, dan sinkronisasi selesai diuji.',
                style: TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ],
          );
        },
      ),
    );
  }
}
