import 'package:material_ui/material_ui.dart';

import '../../../core/formatters/currency_input_formatter.dart';
import '../data/service_pricing_repository.dart';

class ServicePricingPage extends StatefulWidget {
  const ServicePricingPage({super.key});
  @override
  State<ServicePricingPage> createState() => _ServicePricingPageState();
}

class _ServicePricingPageState extends State<ServicePricingPage> with SingleTickerProviderStateMixin {
  final _repo = ServicePricingRepository();
  final _search = TextEditingController();
  late final TabController _tabs = TabController(length: 3, vsync: this);
  List<Map<String, Object?>> _services = [];
  List<Map<String, Object?>> _history = [];
  bool _authorized = false;
  bool _loading = true;

  @override
  void initState() { super.initState(); _authorize(); }
  @override
  void dispose() { _tabs.dispose(); _search.dispose(); super.dispose(); }

  void _message(String value) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
  }

  Future<void> _authorize() async {
    final exists = await _repo.hasAdminPin();
    if (!mounted) return;
    final pin = TextEditingController();
    final confirm = TextEditingController();
    final ok = await showDialog<bool>(context: context, barrierDismissible: false, builder: (ctx) => AlertDialog(
      title: Text(exists ? 'Verifikasi Admin' : 'Buat PIN Admin'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(exists ? 'Masukkan PIN admin.' : 'Buat PIN admin 6–8 angka. PIN diperlukan untuk mengubah harga jasa.'),
        TextField(controller: pin, obscureText: true, keyboardType: TextInputType.number, maxLength: 8, decoration: const InputDecoration(labelText: 'PIN admin')),
        if (!exists) TextField(controller: confirm, obscureText: true, keyboardType: TextInputType.number, maxLength: 8, decoration: const InputDecoration(labelText: 'Ulangi PIN')),
      ]),
      actions: [
        if (exists) TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(exists ? 'Masuk' : 'Simpan PIN')),
      ],
    ));
    try {
      if (ok != true) { if (mounted) Navigator.pop(context); return; }
      if (exists) {
        if (!await _repo.verifyAdminPin(pin.text)) throw StateError('PIN admin salah.');
      } else {
        if (pin.text != confirm.text) throw StateError('Konfirmasi PIN tidak cocok.');
        await _repo.setupAdminPin(pin.text);
      }
      if (mounted) { setState(() => _authorized = true); await _load(); }
    } catch (e) {
      _message(e.toString().replaceFirst('Bad state: ', ''));
      if (mounted) Navigator.pop(context);
    } finally { pin.dispose(); confirm.dispose(); }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final a = await _repo.getServices(keyword: _search.text);
      final b = await _repo.getPriceHistory();
      if (mounted) setState(() { _services = a; _history = b; _loading = false; });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
      _message('Gagal memuat data: $e');
    }
  }

  String _money(Object? value) {
    final s = (value as num? ?? 0).toInt().toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) { if (i > 0 && (s.length - i) % 3 == 0) b.write('.'); b.write(s[i]); }
    return 'Rp$b';
  }

  Future<void> _edit([Map<String, Object?>? item]) async {
    final name = TextEditingController(text: item?['name']?.toString() ?? '');
    final category = TextEditingController(text: item?['category']?.toString() ?? '');
    final description = TextEditingController(text: item?['description']?.toString() ?? '');
    final price = TextEditingController(text: formatCurrencyInput(item?['standard_price'] ?? 0));
    final reason = TextEditingController();
    final form = GlobalKey<FormState>();
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: Text(item == null ? 'Tambah Master Jasa' : 'Ubah Master Jasa'),
      content: Form(key: form, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextFormField(controller: name, decoration: const InputDecoration(labelText: 'Nama jasa *'), validator: (v) => v == null || v.trim().isEmpty ? 'Wajib diisi' : null),
        TextFormField(controller: category, decoration: const InputDecoration(labelText: 'Kategori')),
        TextFormField(controller: description, decoration: const InputDecoration(labelText: 'Keterangan')),
        TextFormField(controller: price, keyboardType: TextInputType.number, inputFormatters: const [CurrencyInputFormatter()], decoration: const InputDecoration(labelText: 'Harga standar (Rp)'), validator: (v) { final n = parseCurrencyInput(v); return n == null || n < 0 ? 'Nominal tidak valid' : null; }),
        if (item != null) TextFormField(controller: reason, decoration: const InputDecoration(labelText: 'Alasan perubahan harga')),
      ]))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
        FilledButton(onPressed: () => Navigator.pop(ctx, form.currentState!.validate()), child: const Text('Simpan')),
      ],
    ));
    if (ok == true) {
      try {
        await _repo.saveService(id: item?['id'] as int?, name: name.text, category: category.text, description: description.text, standardPrice: parseCurrencyInput(price.text), reason: reason.text);
        await _load();
        _message('Master jasa tersimpan.');
      } catch (e) { _message('Gagal menyimpan: $e'); }
    }
    name.dispose(); category.dispose(); description.dispose(); price.dispose(); reason.dispose();
  }

  Future<void> _delete(Map<String, Object?> item) async {
    final name = item['name']?.toString() ?? 'jasa ini';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus master jasa?'),
        content: Text(
          'Master "$name" akan dihapus dari daftar pilihan servis. '
          'Riwayat perubahan harga milik master ini juga dihapus. '
          'Nota servis yang sudah tersimpan tidak ikut berubah.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _repo.deleteService(item['id'] as int);
      await _load();
      _message('Master jasa berhasil dihapus.');
    } catch (e) {
      _message('Gagal menghapus master jasa: $e');
    }
  }

  Widget _master() => Column(children: [
    Padding(padding: const EdgeInsets.all(10), child: TextField(controller: _search, onChanged: (_) => _load(), decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Cari nama/kategori jasa', isDense: true, border: OutlineInputBorder()))),
    Expanded(child: _services.isEmpty ? const Center(child: Text('Belum ada master jasa. Tekan + untuk menambahkan.')) : ListView.builder(padding: const EdgeInsets.all(10), itemCount: _services.length, itemBuilder: (ctx, i) {
      final x = _services[i];
      final active = (x['is_active'] as int? ?? 1) == 1;
      return Card(elevation: 0, child: ListTile(dense: true, title: Text(x['name'].toString()), subtitle: Text((x['category'] ?? 'Tanpa kategori').toString() + ' • ' + _money(x['standard_price'])), trailing: PopupMenuButton<String>(onSelected: (v) async {
        if (v == 'edit') await _edit(x);
        if (v == 'toggle') { await _repo.setActive(x['id'] as int, !active); await _load(); }
        if (v == 'delete') await _delete(x);
      }, itemBuilder: (_) => [
        const PopupMenuItem(value: 'edit', child: Text('Ubah')),
        PopupMenuItem(value: 'toggle', child: Text(active ? 'Nonaktifkan' : 'Aktifkan')),
        const PopupMenuItem(value: 'delete', child: Text('Hapus')),
      ])));
    })),
  ]);

  Widget _historyTab() => _history.isEmpty ? const Center(child: Text('Belum ada perubahan harga.')) : ListView.builder(itemCount: _history.length, itemBuilder: (ctx, i) {
    final h = _history[i];
    return Card(elevation: 0, margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), child: ListTile(dense: true, title: Text(h['service_name'].toString()), subtitle: Text(_money(h['old_price']) + ' → ' + _money(h['new_price']) + '\n' + (h['change_reason'] ?? '').toString()), isThreeLine: true, trailing: Text(h['changed_at'].toString().split('.').first, style: const TextStyle(fontSize: 10))));
  });

  @override
  Widget build(BuildContext context) {
    if (!_authorized) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    return Scaffold(
      appBar: AppBar(title: const Text('Harga Jasa Servis'), bottom: TabBar(controller: _tabs, tabs: const [Tab(text: 'Master Jasa'), Tab(text: 'Riwayat Harga'), Tab(text: 'Pengaturan')])),
      floatingActionButton: AnimatedBuilder(animation: _tabs, builder: (_, __) => _tabs.index == 0 ? FloatingActionButton.small(onPressed: () => _edit(), child: const Icon(Icons.add)) : const SizedBox.shrink()),
      body: _loading ? const Center(child: CircularProgressIndicator()) : TabBarView(controller: _tabs, children: [
        _master(),
        _historyTab(),
        ListView(padding: const EdgeInsets.all(12), children: [
          Card(elevation: 0, child: ListTile(leading: Icon(Icons.tune), title: Text('Metode harga: Keduanya'), subtitle: Text('Harga standar menjadi acuan otomatis. Admin dapat mengubah harga master secara manual.'))),
          Card(elevation: 0, child: Padding(padding: EdgeInsets.all(12), child: Text('Hak perubahan harga: Admin saja. Akses menu memerlukan PIN admin. PIN disimpan dalam bentuk hash dengan salt acak.'))),
        ]),
      ]),
    );
  }
}
