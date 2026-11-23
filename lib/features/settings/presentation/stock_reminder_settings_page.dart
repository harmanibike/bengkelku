import 'package:material_ui/material_ui.dart';

import '../data/business_settings_repository.dart';

class StockReminderSettingsPage extends StatefulWidget {
  const StockReminderSettingsPage({super.key});

  @override
  State<StockReminderSettingsPage> createState() => _StockReminderSettingsPageState();
}

class _StockReminderSettingsPageState extends State<StockReminderSettingsPage> {
  final _repository = BusinessSettingsRepository();
  StockReminderSettings _settings = const StockReminderSettings();
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final settings = await _repository.getStockReminderSettings();
      if (mounted) setState(() { _settings = settings; _loading = false; });
    } catch (error) {
      if (mounted) setState(() => _loading = false);
      _message('Gagal memuat pengaturan reminder stok: $error');
    }
  }

  void _message(String value) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await _repository.saveStockReminderSettings(_settings);
      _message('Pengaturan reminder stok berhasil disimpan.');
    } catch (error) {
      _message('Gagal menyimpan pengaturan: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _option(String title, String subtitle, bool value, ValueChanged<bool> onChanged) =>
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
        value: value,
        onChanged: _saving ? null : onChanged,
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reminder Stok')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _option(
                  'Aktifkan reminder stok',
                  'Aktifkan pemantauan produk yang stoknya menipis atau habis.',
                  _settings.enabled,
                  (value) => setState(() => _settings = _settings.copyWith(enabled: value)),
                ),
                const Divider(),
                _option(
                  'Gunakan batas minimum stok produk',
                  'Produk diingatkan saat stok sama dengan atau di bawah nilai Minimum Stok pada data produk.',
                  _settings.checkAtMinimumStock,
                  (value) => setState(() => _settings = _settings.copyWith(checkAtMinimumStock: value)),
                ),
                _option(
                  'Ingatkan kembali setiap hari',
                  'Pengingat dapat muncul kembali selama stok produk masih berada di bawah batas minimum.',
                  _settings.repeatDaily,
                  (value) => setState(() => _settings = _settings.copyWith(repeatDaily: value)),
                ),
                const SizedBox(height: 12),
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(12),
                    child: Text(
                      'Catatan: halaman ini menyimpan aturan reminder. Notifikasi Android terjadwal, izin notifikasi, dan pemicu otomatis belum diaktifkan. Integrasi notifikasi akan dibuat terpisah agar reminder benar-benar muncul di perangkat.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: const Icon(Icons.save_outlined),
                  label: Text(_saving ? 'Menyimpan...' : 'Simpan Pengaturan'),
                ),
              ],
            ),
    );
  }
}
