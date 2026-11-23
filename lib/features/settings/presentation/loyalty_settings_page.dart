import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../data/business_settings_repository.dart';

class LoyaltySettingsPage extends StatefulWidget {
  const LoyaltySettingsPage({super.key});

  @override
  State<LoyaltySettingsPage> createState() => _LoyaltySettingsPageState();
}

class _LoyaltySettingsPageState extends State<LoyaltySettingsPage> {
  final _repository = BusinessSettingsRepository();
  final _spendController = TextEditingController();
  final _valueController = TextEditingController();
  final _minimumController = TextEditingController();
  LoyaltySettings _settings = const LoyaltySettings();
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _spendController.dispose();
    _valueController.dispose();
    _minimumController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final settings = await _repository.getLoyaltySettings();
      if (!mounted) return;
      setState(() {
        _settings = settings;
        _spendController.text = settings.spendAmountPerPoint.toString();
        _valueController.text = settings.pointValue.toString();
        _minimumController.text = settings.minimumRedeemPoints.toString();
        _loading = false;
      });
    } catch (error) {
      if (mounted) setState(() => _loading = false);
      _message('Gagal memuat pengaturan loyalty: $error');
    }
  }

  void _message(String value) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
  }

  int? _number(TextEditingController controller) {
    final value = int.tryParse(controller.text.trim());
    return value != null && value > 0 ? value : null;
  }

  Future<void> _save() async {
    final spend = _number(_spendController);
    final value = _number(_valueController);
    final minimum = _number(_minimumController);
    if (spend == null || value == null || minimum == null) {
      _message('Semua nilai harus berupa angka lebih dari 0.');
      return;
    }
    setState(() => _saving = true);
    try {
      await _repository.saveLoyaltySettings(_settings.copyWith(
        spendAmountPerPoint: spend,
        pointValue: value,
        minimumRedeemPoints: minimum,
      ));
      _message('Pengaturan poin loyalty berhasil disimpan.');
    } catch (error) {
      _message('Gagal menyimpan pengaturan: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _numberField(String label, String helper, TextEditingController controller, {bool currency = true}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextField(
        controller: controller,
        enabled: !_saving,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(
          labelText: label,
          helperText: helper,
          border: const OutlineInputBorder(),
          prefixText: currency ? 'Rp ' : null,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pengaturan Poin Loyalty')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Aktifkan program poin', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text('Pelanggan dapat mengumpulkan poin dari transaksi yang memenuhi ketentuan.'),
                  value: _settings.enabled,
                  onChanged: _saving ? null : (value) => setState(() => _settings = _settings.copyWith(enabled: value)),
                ),
                const Divider(),
                const Text('Aturan Perolehan Poin', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                _numberField('Belanja untuk mendapatkan 1 poin', 'Contoh: setiap belanja Rp10.000 mendapat 1 poin.', _spendController),
                const Text('Aturan Penukaran Poin', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                _numberField('Nilai 1 poin saat ditukar', 'Contoh: 1 poin bernilai Rp100 sebagai potongan.', _valueController),
                _numberField('Minimal poin untuk ditukar', 'Pelanggan harus memiliki minimal jumlah poin ini.', _minimumController, currency: false),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      'Contoh: belanja Rp10.000 = 1 poin, 1 poin bernilai Rp100, minimal penukaran 100 poin. Setelah program diaktifkan, poin otomatis masuk ketika transaksi pelanggan sudah lunas. Poin akan dikurangi kembali jika transaksi dibatalkan atau barang diretur. Penukaran poin sebagai diskon kasir akan diaktifkan pada tahap berikutnya.',
                      style: const TextStyle(fontSize: 12),
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
