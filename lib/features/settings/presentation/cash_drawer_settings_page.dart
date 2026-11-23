import 'package:material_ui/material_ui.dart';

import '../../../core/auth/auth_session.dart';
import '../data/receipt_settings_repository.dart';

class CashDrawerSettingsPage extends StatefulWidget {
  const CashDrawerSettingsPage({super.key});

  @override
  State<CashDrawerSettingsPage> createState() => _CashDrawerSettingsPageState();
}

class _CashDrawerSettingsPageState extends State<CashDrawerSettingsPage> {
  final _repository = ReceiptSettingsRepository();
  bool _autoOpen = false;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final enabled = await _repository.getCashDrawerAutoOpen();
      if (mounted) setState(() { _autoOpen = enabled; _loading = false; });
    } catch (error) {
      if (mounted) setState(() => _loading = false);
      _message('Gagal memuat pengaturan laci uang: $error');
    }
  }

  void _message(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _setAutoOpen(bool value) async {
    setState(() { _autoOpen = value; _saving = true; });
    try {
      await _repository.saveCashDrawerAutoOpen(value);
      _message(value
          ? 'Buka otomatis diaktifkan. Perintah baru bekerja setelah printer dan laci terintegrasi.'
          : 'Buka otomatis dinonaktifkan.');
    } catch (error) {
      if (mounted) setState(() => _autoOpen = !value);
      _message('Gagal menyimpan pengaturan: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canManage = AuthSession.instance.isCashierOrAdmin;
    return Scaffold(
      appBar: AppBar(title: const Text('Laci Uang Otomatis')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(14),
              children: [
                Card(
                  child: SwitchListTile(
                    title: const Text('Buka otomatis setelah pembayaran', style: TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: const Text('Jika aktif, laci akan diperintahkan terbuka setelah pembayaran berhasil tersimpan.'),
                    value: _autoOpen,
                    onChanged: !canManage || _saving ? null : _setAutoOpen,
                  ),
                ),
                const SizedBox(height: 10),
                const ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.cable_outlined),
                  title: Text('Koneksi laci uang'),
                  subtitle: Text('Laci disambungkan ke port cash drawer RJ11/RJ12 pada printer thermal yang mendukungnya.'),
                ),
                const ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.info_outline),
                  title: Text('Status integrasi'),
                  subtitle: Text('Pengaturan ON/OFF sudah tersimpan. Perintah buka laci, tes koneksi, dan buka manual belum aktif sampai integrasi ESC/POS printer selesai. Tidak semua printer memiliki port atau dukungan laci uang.'),
                ),
                if (!canManage)
                  const Text('Hanya Admin dan Kasir yang dapat mengubah pengaturan ini.', style: TextStyle(color: Colors.red)),
                if (_saving) const LinearProgressIndicator(),
              ],
            ),
    );
  }
}
