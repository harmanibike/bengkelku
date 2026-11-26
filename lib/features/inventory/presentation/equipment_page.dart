import 'package:material_ui/material_ui.dart';

import '../../../core/auth/auth_session.dart';
import '../data/equipment_repository.dart';

class EquipmentPage extends StatefulWidget {
  const EquipmentPage({super.key});
  @override
  State<EquipmentPage> createState() => _EquipmentPageState();
}

class _EquipmentPageState extends State<EquipmentPage> {
  final _repository = EquipmentRepository();
  final _search = TextEditingController();
  String _status = 'all';
  late Future<List<Map<String, Object?>>> _future;

  @override
  void initState() { super.initState(); _future = _load(); }
  Future<List<Map<String, Object?>>> _load() => _repository.getAssets(keyword: _search.text, status: _status);
  Future<void> _refresh() async { final f = _load(); setState(() => _future = f); await f; }
  @override
  void dispose() { _search.dispose(); super.dispose(); }

  String _money(Object? value) {
    final n = value is num ? value.toInt() : int.tryParse('$value') ?? 0;
    final s = n.toString(); final b = StringBuffer();
    for (var i = 0; i < s.length; i++) { if (i > 0 && (s.length-i)%3 == 0) b.write('.'); b.write(s[i]); }
    return 'Rp$b';
  }
  String _statusLabel(String value) => switch (value) {
    'active' => 'Aktif', 'repair' => 'Dalam Perbaikan', 'damaged' => 'Rusak', _ => 'Dipensiunkan'
  };
  Color _statusColor(String value) => switch (value) {
    'active' => Colors.green, 'repair' => Colors.orange, 'damaged' => Colors.red, _ => Colors.grey
  };

  Future<void> _edit([Map<String, Object?>? item]) async {
    if (!AuthSession.instance.isAdmin) return;
    final code = TextEditingController(text: item?['asset_code']?.toString() ?? '');
    final name = TextEditingController(text: item?['name']?.toString() ?? '');
    final category = TextEditingController(text: item?['category']?.toString() ?? '');
    final brand = TextEditingController(text: item?['brand']?.toString() ?? '');
    final model = TextEditingController(text: item?['model']?.toString() ?? '');
    final serial = TextEditingController(text: item?['serial_number']?.toString() ?? '');
    final date = TextEditingController(text: item?['purchase_date']?.toString() ?? '');
    final cost = TextEditingController(text: item?['purchase_cost']?.toString() ?? '0');
    final supplier = TextEditingController(text: item?['supplier_name']?.toString() ?? '');
    final location = TextEditingController(text: item?['location']?.toString() ?? '');
    final person = TextEditingController(text: item?['responsible_person']?.toString() ?? '');
    final warranty = TextEditingController(text: item?['warranty_until']?.toString() ?? '');
    final notes = TextEditingController(text: item?['notes']?.toString() ?? '');
    var condition = item?['condition_label']?.toString() ?? 'Baik';
    var status = item?['status']?.toString() ?? 'active';
    final formKey = GlobalKey<FormState>();
    try {
      final saved = await showDialog<bool>(context: context, builder: (dialogContext) => StatefulBuilder(builder: (context, setDialog) => AlertDialog(
        title: Text(item == null ? 'Tambah Peralatan' : 'Edit Peralatan'),
        content: SizedBox(width: 480, child: SingleChildScrollView(child: Form(key: formKey, child: Column(mainAxisSize: MainAxisSize.min, children: [
          _field(code, 'Kode aset *'), _field(name, 'Nama peralatan *'),
          _field(category, 'Kategori (mis. alat servis)'), _field(brand, 'Merek'), _field(model, 'Model'),
          _field(serial, 'Nomor seri'), _field(date, 'Tanggal pembelian (YYYY-MM-DD)'),
          _field(cost, 'Harga perolehan (Rupiah)', number: true), _field(supplier, 'Pemasok/toko'),
          _field(location, 'Lokasi penyimpanan'), _field(person, 'Penanggung jawab'),
          _field(warranty, 'Garansi sampai (YYYY-MM-DD)'),
          DropdownButtonFormField<String>(value: condition, decoration: const InputDecoration(labelText: 'Kondisi'), items: const [
            DropdownMenuItem(value: 'Baik', child: Text('Baik')), DropdownMenuItem(value: 'Perlu Perawatan', child: Text('Perlu Perawatan')), DropdownMenuItem(value: 'Rusak', child: Text('Rusak')),
          ], onChanged: (v) => setDialog(() => condition = v ?? 'Baik')),
          DropdownButtonFormField<String>(value: status, decoration: const InputDecoration(labelText: 'Status'), items: const [
            DropdownMenuItem(value: 'active', child: Text('Aktif')), DropdownMenuItem(value: 'repair', child: Text('Dalam Perbaikan')), DropdownMenuItem(value: 'damaged', child: Text('Rusak')), DropdownMenuItem(value: 'retired', child: Text('Dipensiunkan')),
          ], onChanged: (v) => setDialog(() => status = v ?? 'active')),
          _field(notes, 'Catatan', lines: 2),
        ])))),
        actions: [TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Batal')),
          FilledButton(onPressed: () {
            if (formKey.currentState?.validate() ?? false) Navigator.pop(dialogContext, true);
          }, child: const Text('Simpan'))],
      )));
      if (saved != true) return;
      await _repository.saveAsset(id: item?['id'] as int?, code: code.text, name: name.text,
        category: category.text, brand: brand.text, model: model.text, serialNumber: serial.text,
        purchaseDate: date.text, supplierName: supplier.text,
        purchaseCost: int.tryParse(cost.text.replaceAll('.', '').replaceAll(',', '')) ?? 0,
        condition: condition, status: status, location: location.text, responsiblePerson: person.text,
        warrantyUntil: warranty.text, notes: notes.text);
      await _refresh();
    } catch (e) { if (mounted) _message('Gagal menyimpan: $e'); }
    finally { for (final c in [code,name,category,brand,model,serial,date,cost,supplier,location,person,warranty,notes]) { c.dispose(); } }
  }

  Widget _field(TextEditingController controller, String label, {bool number = false, int lines = 1}) =>
    Padding(padding: const EdgeInsets.only(bottom: 8), child: TextFormField(controller: controller, maxLines: lines,
      keyboardType: number ? TextInputType.number : TextInputType.text,
      decoration: InputDecoration(labelText: label, border: const OutlineInputBorder(), isDense: true),
      validator: label.endsWith('*') ? (v) => (v == null || v.trim().isEmpty) ? 'Wajib diisi' : null : null));

  void _message(String text) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text))); }

  Future<void> _maintenance(Map<String, Object?> item) async {
    final id = item['id'] as int;
    final logs = await _repository.getMaintenanceLogs(id);
    if (!mounted) return;
    await showDialog<void>(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setDialog) => AlertDialog(
      title: Text('Perawatan • ${item['name']}'),
      content: SizedBox(width: 460, child: logs.isEmpty
        ? const Text('Belum ada riwayat perawatan.')
        : ListView(shrinkWrap: true, children: logs.map((log) => ListTile(
          contentPadding: EdgeInsets.zero, title: Text(log['maintenance_type'].toString()),
          subtitle: Text('${log['maintenance_date']} • ${log['description']}\nBiaya: ${_money(log['cost'])}'),
        )).toList())),
      actions: [
        if (AuthSession.instance.isAdmin) TextButton.icon(onPressed: () async {
          await _addMaintenance(id); final updated = await _repository.getMaintenanceLogs(id);
          logs..clear()..addAll(updated); setDialog(() {});
        }, icon: const Icon(Icons.add), label: const Text('Catat perawatan')),
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Tutup')),
      ],
    )));
  }

  Future<void> _addMaintenance(int assetId) async {
    final type = TextEditingController(); final description = TextEditingController();
    final date = TextEditingController(text: DateTime.now().toIso8601String().substring(0,10));
    final cost = TextEditingController(text: '0'); final person = TextEditingController();
    final due = TextEditingController(); final notes = TextEditingController();
    final key = GlobalKey<FormState>();
    try {
      final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
        title: const Text('Catat Perawatan'),
        content: SizedBox(width: 420, child: Form(key: key, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          _field(type, 'Jenis perawatan *'), _field(description, 'Keterangan *'), _field(date, 'Tanggal (YYYY-MM-DD)'),
          _field(cost, 'Biaya (Rupiah)', number: true), _field(person, 'Dikerjakan oleh'), _field(due, 'Jadwal perawatan berikutnya'),
          _field(notes, 'Catatan', lines: 2),
        ])))),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          FilledButton(onPressed: () { if (key.currentState?.validate() ?? false) Navigator.pop(ctx, true); }, child: const Text('Simpan'))],
      ));
      if (ok == true) {
        await _repository.addMaintenance(assetId: assetId, date: date.text, type: type.text,
          description: description.text, cost: int.tryParse(cost.text.replaceAll('.', '')) ?? 0,
          performedBy: person.text, nextDueDate: due.text, notes: notes.text);
      }
    } catch (e) { if (mounted) _message('Gagal mencatat perawatan: $e'); }
    finally { for (final c in [type,description,date,cost,person,due,notes]) { c.dispose(); } }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Peralatan Bengkel'), actions: [IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh))]),
    floatingActionButton: AuthSession.instance.isAdmin ? FloatingActionButton.extended(onPressed: () => _edit(), icon: const Icon(Icons.add), label: const Text('Tambah')) : null,
    body: Column(children: [
      Padding(padding: const EdgeInsets.fromLTRB(12, 12, 12, 8), child: Column(children: [
        TextField(controller: _search, onChanged: (_) => _refresh(), decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Cari kode atau nama peralatan', border: OutlineInputBorder(), isDense: true)),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(value: _status, decoration: const InputDecoration(labelText: 'Filter status', border: OutlineInputBorder(), isDense: true),
          items: const [DropdownMenuItem(value: 'all', child: Text('Semua status')), DropdownMenuItem(value: 'active', child: Text('Aktif')), DropdownMenuItem(value: 'repair', child: Text('Dalam Perbaikan')), DropdownMenuItem(value: 'damaged', child: Text('Rusak')), DropdownMenuItem(value: 'retired', child: Text('Dipensiunkan'))],
          onChanged: (v) { _status = v ?? 'all'; _refresh(); }),
      ])),
      Expanded(child: FutureBuilder<List<Map<String, Object?>>>(future: _future, builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
        if (snapshot.hasError) return Center(child: Text('Gagal memuat peralatan: ${snapshot.error}'));
        final items = snapshot.data ?? [];
        if (items.isEmpty) return const Center(child: Text('Belum ada peralatan. Tekan Tambah untuk mencatat aset bengkel.'));
        return RefreshIndicator(onRefresh: _refresh, child: ListView.separated(padding: const EdgeInsets.fromLTRB(12, 4, 12, 88), itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(height: 6), itemBuilder: (context, index) {
            final item = items[index]; final status = item['status'].toString();
            return Card(child: ListTile(
              leading: CircleAvatar(backgroundColor: _statusColor(status).withValues(alpha: .12), child: Icon(Icons.handyman_outlined, color: _statusColor(status))),
              title: Text(item['name'].toString(), style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text('${item['asset_code']} • ${item['category'] ?? 'Tanpa kategori'}\n${_statusLabel(status)} • ${item['location'] ?? 'Lokasi belum diatur'}\nNilai perolehan: ${_money(item['purchase_cost'])}'),
              isThreeLine: true,
              trailing: PopupMenuButton<String>(onSelected: (v) async {
                if (v == 'edit') await _edit(item);
                if (v == 'maintenance') await _maintenance(item);
                if (v == 'retire') { await _repository.updateStatus(item['id'] as int, 'retired'); await _refresh(); }
              }, itemBuilder: (_) => [
                if (AuthSession.instance.isAdmin) const PopupMenuItem(value: 'edit', child: Text('Edit data')),
                const PopupMenuItem(value: 'maintenance', child: Text('Riwayat perawatan')),
                if (AuthSession.instance.isAdmin && status != 'retired') const PopupMenuItem(value: 'retire', child: Text('Pensiunkan aset')),
              ]),
              onTap: () => _maintenance(item),
            ));
          }));
      })),
    ]),
  );
}
