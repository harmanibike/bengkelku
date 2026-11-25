
import 'dart:convert';
import 'dart:typed_data';
import 'package:image/image.dart' as img;

import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';

import '../data/customer_repository.dart';
import 'customer_wallet_page.dart';
import '../../receivables/presentation/receivables_page.dart';

class CustomerListPage extends StatefulWidget {
  const CustomerListPage({super.key});

  @override
  State<CustomerListPage> createState() => _CustomerListPageState();
}

class _CustomerListPageState extends State<CustomerListPage> {
  final CustomerRepository _repository = CustomerRepository();
  final TextEditingController _searchController = TextEditingController();

  late Future<List<Map<String, Object?>>> _customersFuture;
  bool _isImportingContacts = false;
  static const int _pageSize = 50;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _loadCustomers();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _loadCustomers() {
    _customersFuture = _repository.getCustomers(
      keyword: _searchController.text,
      limit: _pageSize,
      offset: _page * _pageSize,
    );
  }

  void _refresh() {
    setState(() { _page = 0; _loadCustomers(); });
  }

  // Simpan foto pelanggan dalam ukuran kecil agar kolom Base64 tidak
  // membengkak dan daftar pelanggan lebih ringan saat memuat foto.
  Future<Uint8List> _compressPhoto(Uint8List bytes) async {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return bytes;
    final resized = img.copyResize(
      decoded,
      width: 320,
      height: 320,
      maintainAspect: true,
      interpolation: img.Interpolation.average,
    );
    return Uint8List.fromList(img.encodeJpg(resized, quality: 70));
  }
  Future<void> _showCustomerForm({
    Map<String, Object?>? customer,
  }) async {
    final isEditing = customer != null;

    final nameController = TextEditingController(
      text: customer?['name']?.toString() ?? '',
    );
    final phoneController = TextEditingController(
      text: customer?['phone']?.toString() ?? '',
    );
    final addressController = TextEditingController(
      text: customer?['address']?.toString() ?? '',
    );
    final emailController = TextEditingController(
      text: customer?['email']?.toString() ?? '',
    );
    final notesController = TextEditingController(
      text: customer?['notes']?.toString() ?? '',
    );

    final formKey = GlobalKey<FormState>();
    String? photoBase64 = customer?['photo_base64']?.toString();

    Future<void> choosePhoto(ImageSource source, StateSetter setDialogState) async {
      final image = await ImagePicker().pickImage(source: source, imageQuality: 75, maxWidth: 512, maxHeight: 512);
      if (image == null) return;
      final bytes = await image.readAsBytes();
      final compressed = await _compressPhoto(bytes);
      setDialogState(() => photoBase64 = base64Encode(compressed));
    }

    try {
      final saved = await showDialog<bool>(
        context: context,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (context, setDialogState) => AlertDialog(
            title: Text(
              isEditing ? 'Edit Pelanggan' : 'Tambah Pelanggan',
            ),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _customerAvatar(photoBase64, radius: 38),
                      Wrap(alignment: WrapAlignment.center, spacing: 8, children: [
                        TextButton.icon(onPressed: () => choosePhoto(ImageSource.gallery, setDialogState), icon: const Icon(Icons.photo_library_outlined), label: const Text('Galeri')),
                        TextButton.icon(onPressed: () => choosePhoto(ImageSource.camera, setDialogState), icon: const Icon(Icons.camera_alt_outlined), label: const Text('Kamera')),
                        if (photoBase64 != null && photoBase64!.isNotEmpty) IconButton(tooltip: 'Hapus foto', onPressed: () => setDialogState(() => photoBase64 = null), icon: const Icon(Icons.delete_outline)),
                      ]),
                      TextFormField(
                        controller: nameController,
                        decoration: const InputDecoration(
                          labelText: 'Nama pelanggan *',
                          prefixIcon: Icon(Icons.person_outline),
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Nama pelanggan wajib diisi';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: phoneController,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(
                          labelText: 'Nomor telepon',
                          prefixIcon: Icon(Icons.phone_outlined),
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: addressController,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          labelText: 'Alamat',
                          prefixIcon: Icon(Icons.location_on_outlined),
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: emailController,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(
                          labelText: 'Email',
                          prefixIcon: Icon(Icons.email_outlined),
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: notesController,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          labelText: 'Catatan',
                          prefixIcon: Icon(Icons.notes),
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Batal'),
              ),
              FilledButton.icon(
                onPressed: () {
                  if (formKey.currentState!.validate()) {
                    Navigator.pop(dialogContext, true);
                  }
                },
                icon: const Icon(Icons.save_outlined),
                label: const Text('Simpan'),
              ),
            ],
            ),
          );
        },
      );

      if (saved != true || !mounted) return;

      if (isEditing) {
        await _repository.updateCustomer(
          id: customer['id'] as int,
          name: nameController.text,
          phone: phoneController.text,
          address: addressController.text,
          email: emailController.text,
          notes: notesController.text,
          photoBase64: photoBase64,
        );
      } else {
        await _repository.addCustomer(
          name: nameController.text,
          phone: phoneController.text,
          address: addressController.text,
          email: emailController.text,
          notes: notesController.text,
          photoBase64: photoBase64,
        );
      }

      if (!mounted) return;

      _refresh();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isEditing
                ? 'Data pelanggan berhasil diperbarui'
                : 'Pelanggan berhasil ditambahkan',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal menyimpan data: $error')),
      );
    } finally {
      nameController.dispose();
      phoneController.dispose();
      addressController.dispose();
      emailController.dispose();
      notesController.dispose();
    }
  }

  Future<void> _importPhoneContacts() async {
    if (_isImportingContacts) return;
    setState(() => _isImportingContacts = true);
    try {
      final allowed = await FlutterContacts.requestPermission(readonly: true);
      if (!allowed) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Izin membaca kontak tidak diberikan.')),
        );
        return;
      }

      // Ambil nama dan nomor saja terlebih dahulu. Foto baru dimuat untuk
      // kontak yang dipilih agar proses awal tidak membebani memori.
      final contacts = await FlutterContacts.getContacts(
        withProperties: true,
        withPhoto: false,
      );
      final usable = contacts
          .where((item) =>
              item.displayName.trim().isNotEmpty &&
              item.phones.any((phone) => phone.number.trim().isNotEmpty))
          .toList();

      if (!mounted) return;
      if (usable.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Tidak ada kontak dengan nama dan nomor telepon.'),
          ),
        );
        return;
      }

      final selected = <int>{};
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('Pilih Kontak untuk Diimpor'),
            content: SizedBox(
              width: 520,
              height: 420,
              child: Column(
                children: [
                  Text('Pilih kontak yang ingin dimasukkan. ${usable.length} kontak tersedia.'),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView.builder(
                      itemCount: usable.length,
                      itemBuilder: (context, index) {
                        final item = usable[index];
                        final phone = item.phones.firstWhere(
                          (entry) => entry.number.trim().isNotEmpty,
                        ).number;
                        return CheckboxListTile(
                          value: selected.contains(index),
                          onChanged: (value) => setDialogState(() {
                            if (value == true) {
                              selected.add(index);
                            } else {
                              selected.remove(index);
                            }
                          }),
                          secondary: const CircleAvatar(
                            child: Icon(Icons.person),
                          ),
                          title: Text(
                            item.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(phone),
                          controlAffinity: ListTileControlAffinity.leading,
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Batal'),
              ),
              TextButton(
                onPressed: () => setDialogState(() {
                  if (selected.length == usable.length) {
                    selected.clear();
                  } else {
                    selected.addAll(List<int>.generate(usable.length, (i) => i));
                  }
                }),
                child: Text(
                  selected.length == usable.length
                      ? 'Batal Pilih Semua'
                      : 'Pilih Semua',
                ),
              ),
              FilledButton(
                onPressed: selected.isEmpty
                    ? null
                    : () => Navigator.pop(dialogContext, true),
                child: Text('Impor ${selected.length}'),
              ),
            ],
          ),
        ),
      );

      if (confirmed != true || !mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Menyiapkan ${selected.length} kontak untuk diimpor...'),
          duration: const Duration(seconds: 30),
        ),
      );

      final existing = await _repository.getCustomers();
      String normalizePhone(String value) => value
          .replaceAll(RegExp(r'[^0-9]'), '')
          .replaceFirst(RegExp(r'^62'), '0');
      final phones = existing
          .map((row) => normalizePhone(row['phone']?.toString() ?? ''))
          .where((value) => value.isNotEmpty)
          .toSet();

      final rowsToImport = <Map<String, Object?>>[];
      var skipped = 0;
      for (final index in selected) {
        final basic = usable[index];
        final basicPhone = basic.phones.firstWhere(
          (entry) => entry.number.trim().isNotEmpty,
        ).number.trim();
        final normalized = normalizePhone(basicPhone);
        if (normalized.isNotEmpty && phones.contains(normalized)) {
          skipped++;
          continue;
        }

        // Detail/foto hanya diambil untuk kontak yang benar-benar dipilih.
        final detail = await FlutterContacts.getContact(
          basic.id,
          withProperties: true,
          withPhoto: true,
        );
        final photo = detail?.photo;
        rowsToImport.add({
          'name': basic.displayName.trim(),
          'phone': basicPhone,
          'email': detail == null || detail.emails.isEmpty
              ? null
              : detail.emails.first.address,
          'photo_base64': photo == null ? null : base64Encode(await _compressPhoto(photo)),
        });
        if (normalized.isNotEmpty) phones.add(normalized);
      }

      final imported = await _repository.importCustomers(rowsToImport);
      if (!mounted) return;
      _refresh();
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '$imported kontak diimpor, $skipped dilewati karena sudah terdaftar.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal mengimpor kontak: $error')),
      );
    } finally {
      if (mounted) setState(() => _isImportingContacts = false);
    }
  }

  Future<void> _deleteCustomer(
    Map<String, Object?> customer,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Hapus Pelanggan?'),
          content: Text(
            'Hapus data ${customer['name']}? '
            'Tindakan ini tidak dapat dibatalkan.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Batal'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.red,
              ),
              child: const Text('Hapus'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) return;

    try {
      await _repository.deleteCustomer(customer['id'] as int);

      if (!mounted) return;

      _refresh();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Data pelanggan berhasil dihapus'),
        ),
      );
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal menghapus data: $error')),
      );
    }
  }

  String _formatWalletAmount(Object? value) {
    final amount = (value as num?)?.toInt() ?? 0;
    final digits = amount.toString();
    final out = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) out.write('.');
      out.write(digits[i]);
    }
    return 'Rp$out';
  }

  /// Foto pelanggan opsional dengan fallback aman untuk data Base64 lama
  /// yang kosong, tidak valid, atau berisi gambar yang rusak.
  Widget _customerAvatar(String? encoded, {double radius = 24}) {
    Uint8List? bytes;
    final value = encoded?.trim() ?? '';
    if (value.isNotEmpty) {
      try {
        bytes = base64Decode(value);
      } on FormatException {
        bytes = null;
      }
    }

    final color = Theme.of(context).colorScheme.primary;
    return CircleAvatar(
      radius: radius,
      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      child: bytes == null
          ? Icon(Icons.person_outline, size: radius, color: color)
          : ClipOval(
              child: Image.memory(
                bytes,
                width: radius * 2,
                height: radius * 2,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Icon(
                  Icons.person_outline,
                  size: radius,
                  color: color,
                ),
              ),
            ),
    );
  }

  Widget _buildCustomerCard(Map<String, Object?> customer) {
    final name = customer['name']?.toString() ?? 'Tanpa nama';
    final phone = customer['phone']?.toString() ?? '';
    final address = customer['address']?.toString() ?? '';

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 8,
        ),
        leading: _customerAvatar(customer['photo_base64']?.toString()),
        title: Text(
          name,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (phone.isNotEmpty)
                Text(
                  phone,
                  style: const TextStyle(fontSize: 12),
                ),
              if (address.isNotEmpty)
                Text(
                  address,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12),
                ),
              Row(
                children: [
                  const Icon(Icons.account_balance_wallet_outlined, size: 14, color: Color(0xFF1976D2)),
                  const SizedBox(width: 4),
                  Text('Saldo: ${_formatWalletAmount(customer['wallet_balance'])}',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF1976D2))),
                ],
              ),
              Row(
                children: [
                  const Icon(Icons.stars_rounded, size: 14, color: Color(0xFFFFA000)),
                  const SizedBox(width: 4),
                  Text(
                    '${customer['loyalty_points'] ?? 0} poin loyalty',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFFB77900)),
                  ),
                ],
              ),
            ],
          ),
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (value) {
            if (value == 'wallet') {
              Navigator.push(context, MaterialPageRoute(builder: (_) => CustomerWalletPage(
                customerId: customer['id'] as int,
                customerName: customer['name']?.toString() ?? 'Pelanggan',
              )));
            } else if (value == 'edit') {
              _showCustomerForm(customer: customer);
            } else if (value == 'delete') {
              _deleteCustomer(customer);
            }
          },
          itemBuilder: (context) => const [
            PopupMenuItem(
              value: 'wallet',
              child: Row(
                children: [
                  Icon(Icons.account_balance_wallet_outlined),
                  SizedBox(width: 10),
                  Text('Saldo & Deposit'),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'edit',
              child: Row(
                children: [
                  Icon(Icons.edit_outlined),
                  SizedBox(width: 10),
                  Text('Edit'),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'delete',
              child: Row(
                children: [
                  Icon(Icons.delete_outline, color: Colors.red),
                  SizedBox(width: 10),
                  Text('Hapus'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Data Pelanggan'),
        actions: [
          IconButton(
            tooltip: 'Impor kontak',
            onPressed: _isImportingContacts ? null : _importPhoneContacts,
            icon: _isImportingContacts
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.contacts_outlined),
          ),
          IconButton(
            tooltip: 'Piutang',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ReceivablesPage()),
              );
            },
            icon: const Icon(Icons.notifications_active_outlined),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _searchController,
              onChanged: (_) => _refresh(),
              decoration: InputDecoration(
                hintText: 'Cari nama atau nomor telepon...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  onPressed: () {
                    _searchController.clear();
                    _refresh();
                  },
                  icon: const Icon(Icons.close),
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<Map<String, Object?>>>(
              future: _customersFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(),
                  );
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Gagal memuat pelanggan:\n${snapshot.error}',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }

                final customers = snapshot.data ?? [];

                if (customers.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.people_outline,
                            size: 64,
                            color: Colors.grey.shade400,
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Belum ada data pelanggan',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 5),
                          const Text(
                            'Tekan tombol tambah untuk memasukkan pelanggan.',
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return Column(
                  children: [
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        itemCount: customers.length,
                        itemBuilder: (context, index) {
                          return _buildCustomerCard(customers[index]);
                        },
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 80),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          OutlinedButton.icon(
                            onPressed: _page > 0
                                ? () => setState(() { _page--; _loadCustomers(); })
                                : null,
                            icon: const Icon(Icons.chevron_left),
                            label: const Text('Sebelumnya'),
                          ),
                          Text('Halaman ${_page + 1}'),
                          OutlinedButton.icon(
                            onPressed: customers.length == _pageSize
                                ? () => setState(() { _page++; _loadCustomers(); })
                                : null,
                            icon: const Icon(Icons.chevron_right),
                            label: const Text('Berikutnya'),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showCustomerForm(),
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Tambah'),
      ),
    );
  }
}
