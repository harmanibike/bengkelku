import 'package:material_ui/material_ui.dart';

import '../data/receipt_settings_repository.dart';

class ReceiptSettingsPage extends StatefulWidget {
  const ReceiptSettingsPage({super.key});

  @override
  State<ReceiptSettingsPage> createState() => _ReceiptSettingsPageState();
}

class _ReceiptSettingsPageState extends State<ReceiptSettingsPage> {
  final _repository = ReceiptSettingsRepository();
  ReceiptPrintSettings _settings = const ReceiptPrintSettings();
  final _footerController = TextEditingController();
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final settings = await _repository.getReceiptSettings();
      _footerController.text = settings.footerNote;
      if (mounted) setState(() { _settings = settings; _loading = false; });
    } catch (error) {
      if (mounted) setState(() => _loading = false);
      _message('Gagal memuat pengaturan struk: $error');
    }
  }

  void _message(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    _footerController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await _repository.saveReceiptSettings(_settings.copyWith(footerNote: _footerController.text.trim()));
      _message('Pengaturan tampilan dan format struk berhasil disimpan.');
    } catch (error) {
      _message('Gagal menyimpan pengaturan struk: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _option(String title, String subtitle, bool value, ValueChanged<bool> onChanged) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 11)),
      value: value,
      onChanged: _saving ? null : onChanged,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tampilan & Format Struk')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(14),
              children: [
                const Text('Cetak Setelah Transaksi / Pembayaran', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Cetak otomatis setelah penjualan', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  subtitle: const Text('Aktifkan agar nota penjualan langsung dicetak setelah pembayaran berhasil.', style: TextStyle(fontSize: 11)),
                  value: _settings.autoPrintSales,
                  onChanged: _saving ? null : (v) => setState(() => _settings = _settings.copyWith(autoPrintSales: v)),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Cetak otomatis setelah pembayaran servis', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  subtitle: const Text('Cetak bukti pembayaran/pelunasan servis setelah pembayaran berhasil.', style: TextStyle(fontSize: 11)),
                  value: _settings.autoPrintServicePayments,
                  onChanged: _saving ? null : (v) => setState(() => _settings = _settings.copyWith(autoPrintServicePayments: v)),
                ),
                const SizedBox(height: 4),
                const Text('Jumlah Salinan', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                DropdownButtonFormField<int>(
                  value: _settings.printCopies,
                  decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                  items: const [
                    DropdownMenuItem(value: 1, child: Text('1 salinan')),
                    DropdownMenuItem(value: 2, child: Text('2 salinan')),
                    DropdownMenuItem(value: 3, child: Text('3 salinan')),
                  ],
                  onChanged: _saving ? null : (v) { if (v != null) setState(() => _settings = _settings.copyWith(printCopies: v)); },
                ),
                const SizedBox(height: 16),
                const Text('Ukuran Kertas', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(value: 58, label: Text('58 mm')),
                    ButtonSegment(value: 80, label: Text('80 mm')),
                  ],
                  selected: {_settings.paperWidthMm},
                  onSelectionChanged: _saving ? null : (values) => setState(() => _settings = _settings.copyWith(paperWidthMm: values.first)),
                ),
                const SizedBox(height: 16),
                const Text('Elemen yang Ditampilkan', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                _option('Logo usaha', 'Tampilkan logo pada bagian atas nota.', _settings.showLogo, (v) => setState(() => _settings = _settings.copyWith(showLogo: v))),
                _option('Nama usaha', 'Tampilkan nama toko/bengkel.', _settings.showBusinessName, (v) => setState(() => _settings = _settings.copyWith(showBusinessName: v))),
                _option('Alamat usaha', 'Tampilkan alamat pada kepala nota.', _settings.showBusinessAddress, (v) => setState(() => _settings = _settings.copyWith(showBusinessAddress: v))),
                _option('Kontak usaha', 'Tampilkan telepon dan WhatsApp.', _settings.showBusinessContact, (v) => setState(() => _settings = _settings.copyWith(showBusinessContact: v))),
                _option('Data pelanggan', 'Tampilkan nama dan nomor telepon pelanggan jika tersedia.', _settings.showCustomerDetails, (v) => setState(() => _settings = _settings.copyWith(showCustomerDetails: v))),
                _option('Catatan transaksi', 'Tampilkan catatan pada nota jika tersedia.', _settings.showTransactionNotes, (v) => setState(() => _settings = _settings.copyWith(showTransactionNotes: v))),
                _option('Catatan bawah struk', 'Tampilkan pesan penutup pada nota penjualan dan servis.', _settings.showFooter, (v) => setState(() => _settings = _settings.copyWith(showFooter: v))),
                const SizedBox(height: 8),
                TextField(
                  controller: _footerController,
                  enabled: !_saving,
                  maxLines: 2,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Catatan bawah nota dan struk',
                    hintText: 'Contoh: Terima kasih telah berbelanja',
                    border: OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                ),
                const Divider(height: 24),
                const Text('Ukuran Teks', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                Slider(
                  value: _settings.fontScale,
                  min: 0.85,
                  max: 1.25,
                  divisions: 4,
                  label: _settings.fontScale.toStringAsFixed(2),
                  onChanged: _saving ? null : (v) => setState(() => _settings = _settings.copyWith(fontScale: v)),
                ),
                const Text('Kerapatan Jarak', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                Slider(
                  value: _settings.spacing,
                  min: 0.7,
                  max: 1.6,
                  divisions: 6,
                  label: _settings.spacing.toStringAsFixed(1),
                  onChanged: _saving ? null : (v) => setState(() => _settings = _settings.copyWith(spacing: v)),
                ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('Contoh tata letak', style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Center(child: Text('BENGKEL ANDA', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12 * _settings.fontScale))),
                      if (_settings.showBusinessAddress) const Center(child: Text('Alamat usaha', style: TextStyle(fontSize: 10))),
                      if (_settings.showBusinessContact) const Center(child: Text('Telepon / WhatsApp', style: TextStyle(fontSize: 10))),
                      const Divider(),
                      const Text('NOTA PENJUALAN', textAlign: TextAlign.center),
                      const Text('No. Nota       INV-00001'),
                      const Text('Tanggal         23/11/2026'),
                      if (_settings.showCustomerDetails) const Text('Pelanggan      Nama pelanggan'),
                      const Divider(),
                      const Text('Produk x 1'),
                      const Text('Total                 Rp100.000'),
                      if (_settings.showFooter) Center(child: Text(_footerController.text.trim().isEmpty ? 'Terima kasih atas kunjungan Anda.' : _footerController.text.trim(), textAlign: TextAlign.center)),
                      const SizedBox(height: 4),
                      Text('Kertas ${_settings.paperWidthMm} mm • Contoh tampilan, bukan hasil cetak final', style: const TextStyle(fontSize: 10, color: Colors.grey)),
                    ]),
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.save_outlined),
                  label: Text(_saving ? 'Menyimpan...' : 'Simpan Pengaturan Struk'),
                ),
              ],
            ),
    );
  }
}
