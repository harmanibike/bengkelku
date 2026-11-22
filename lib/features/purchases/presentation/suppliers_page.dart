import 'package:material_ui/material_ui.dart';

import '../data/supplier_repository.dart';

class SuppliersPage extends StatefulWidget {
  const SuppliersPage({super.key});

  @override
  State<SuppliersPage> createState() => _SuppliersPageState();
}

class _SuppliersPageState extends State<SuppliersPage> {
  final SupplierRepository _repository = SupplierRepository();
  final TextEditingController _searchController = TextEditingController();
  late Future<List<Map<String, Object?>>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Map<String, Object?>>> _load() =>
      _repository.getSuppliers(keyword: _searchController.text);

  Future<void> _refresh() async {
    final future = _load();
    setState(() => _future = future);
    await future;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _showSupplierDialog({Map<String, Object?>? supplier}) async {
    final name = TextEditingController(text: supplier?['name'] as String? ?? '');
    final phone = TextEditingController(text: supplier?['phone'] as String? ?? '');
    final address = TextEditingController(text: supplier?['address'] as String? ?? '');
    final email = TextEditingController(text: supplier?['email'] as String? ?? '');
    final notes = TextEditingController(text: supplier?['notes'] as String? ?? '');
    final formKey = GlobalKey<FormState>();
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(supplier == null ? 'Tambah Pemasok' : 'Edit Pemasok'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: name,
                    autofocus: true,
                    decoration: const InputDecoration(labelText: 'Nama pemasok *'),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'Nama pemasok wajib diisi' : null,
                  ),
                  const SizedBox(height: 8),
                  TextField(controller: phone, keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(labelText: 'Nomor telepon / WhatsApp')),
                  const SizedBox(height: 8),
                  TextField(controller: address, maxLines: 2,
                    decoration: const InputDecoration(labelText: 'Alamat')),
                  const SizedBox(height: 8),
                  TextField(controller: email, keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: 'Email')),
                  const SizedBox(height: 8),
                  TextField(controller: notes, maxLines: 2,
                    decoration: const InputDecoration(labelText: 'Catatan')),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Batal')),
          FilledButton(onPressed: () {
            if (formKey.currentState!.validate()) Navigator.pop(dialogContext, true);
          }, child: const Text('Simpan')),
        ],
      ),
    );

    if (saved == true && mounted) {
      try {
        final values = {
          'name': name.text,
          'phone': phone.text,
          'address': address.text,
          'email': email.text,
          'notes': notes.text,
        };
        if (supplier == null) {
          await _repository.addSupplier(
            name: values['name']!, phone: values['phone'], address: values['address'],
            email: values['email'], notes: values['notes'],
          );
        } else {
          await _repository.updateSupplier(
            id: supplier['id'] as int, name: values['name']!, phone: values['phone'],
            address: values['address'], email: values['email'], notes: values['notes'],
          );
        }
        await _refresh();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Data pemasok berhasil disimpan.')),
          );
        }
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Gagal menyimpan pemasok: $error')),
          );
        }
      }
    }
    name.dispose();
    phone.dispose();
    address.dispose();
    email.dispose();
    notes.dispose();
  }

  Widget _supplierCard(Map<String, Object?> row) {
    final phone = row['phone'] as String? ?? '';
    final address = row['address'] as String? ?? '';
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
        leading: CircleAvatar(
          radius: 20,
          backgroundColor: const Color(0xFFE8EEFF),
          child: const Icon(Icons.local_shipping_outlined, color: Color(0xFF3157B7)),
        ),
        title: Text(row['name'] as String? ?? '-', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Text([
            if (phone.isNotEmpty) phone,
            if (address.isNotEmpty) address,
          ].join(' • ').isEmpty ? 'Belum ada kontak' : [
            if (phone.isNotEmpty) phone,
            if (address.isNotEmpty) address,
          ].join(' • '), maxLines: 2, overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11)),
        ),
        trailing: IconButton(
          tooltip: 'Edit pemasok',
          onPressed: () => _showSupplierDialog(supplier: row),
          icon: const Icon(Icons.edit_outlined, size: 20),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Data Pemasok'),
        actions: [
          IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh), tooltip: 'Muat ulang'),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showSupplierDialog(),
        icon: const Icon(Icons.add),
        label: const Text('Tambah'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
            child: TextField(
              controller: _searchController,
              onChanged: (_) => _refresh(),
              decoration: InputDecoration(
                hintText: 'Cari nama, telepon, atau email',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: IconButton(
                  onPressed: () { _searchController.clear(); _refresh(); },
                  icon: const Icon(Icons.close, size: 18),
                ),
                isDense: true,
              ),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<Map<String, Object?>>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(child: Text('Gagal memuat pemasok: ${snapshot.error}'));
                }
                final rows = snapshot.data ?? [];
                if (rows.isEmpty) {
                  return const Center(child: Text('Belum ada data pemasok.'));
                }
                return RefreshIndicator(
                  onRefresh: _refresh,
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 84),
                    itemCount: rows.length,
                    itemBuilder: (_, index) => _supplierCard(rows[index]),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
