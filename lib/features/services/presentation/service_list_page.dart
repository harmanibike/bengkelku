
import 'package:material_ui/material_ui.dart';

import '../data/service_repository.dart';
import 'service_intake_page.dart';
import 'service_photo_helper.dart';

class ServiceListPage extends StatefulWidget {
  const ServiceListPage({super.key});

  @override
  State<ServiceListPage> createState() => _ServiceListPageState();
}

class _ServiceListPageState extends State<ServiceListPage> {
  final ServiceRepository _repository = ServiceRepository();
  final TextEditingController _searchController = TextEditingController();

  String? _statusFilter;
  late Future<List<Map<String, Object?>>> _ordersFuture;
  static const Map<String, String> _statusLabels = {
    'waiting': 'Menunggu',
    'checking': 'Pemeriksaan',
    'in_progress': 'Dikerjakan',
    'completed': 'Selesai',
    'delivered': 'Diambil',
    'cancelled': 'Dibatalkan',
  };

  @override
  void initState() {
    super.initState();
    _loadOrders();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _loadOrders() {
    _ordersFuture = _repository.getServiceOrders(
      keyword: _searchController.text,
      status: _statusFilter,
    );
  }

  void _refresh() => setState(_loadOrders);

  String _rupiah(Object? value) {
    final amount = value is num ? value.toInt() : 0;
    final digits = amount.toString();
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write('.');
      buffer.write(digits[i]);
    }
    return 'Rp$buffer';
  }

  String _dateLabel(Object? value) {
    if (value == null) return '-';
    final date = DateTime.tryParse(value.toString());
    if (date == null) return value.toString();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(date.day)}/${two(date.month)}/${date.year} '
        '${two(date.hour)}:${two(date.minute)}';
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'completed':
        return Colors.green;
      case 'delivered':
        return Colors.blue;
      case 'cancelled':
        return Colors.red;
      case 'in_progress':
        return Colors.orange;
      case 'checking':
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }

  Future<void> _openIntake() async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const ServiceIntakePage()),
    );
    if (saved == true && mounted) _refresh();
  }

  Future<void> _changeStatus(Map<String, Object?> order) async {
    final id = order['id'] as int;
    final current = order['service_status']?.toString() ?? 'waiting';
    String selected = current;
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Ubah Status Servis'),
        content: DropdownButtonFormField<String>(
          initialValue: current,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Status pengerjaan',
            border: OutlineInputBorder(),
          ),
          items: _statusLabels.entries
              .map((entry) => DropdownMenuItem(
                    value: entry.key,
                    child: Text(entry.value),
                  ))
              .toList(),
          onChanged: (value) {
            if (value != null) selected = value;
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, selected),
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
    if (result == null || !mounted) return;
    try {
      await _repository.updateServiceStatus(id: id, status: result);
      if (!mounted) return;
      _refresh();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Status servis berhasil diperbarui.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal mengubah status: $error')),
      );
    }
  }

  Future<void> _pickServicePhoto(int id, {required bool before}) async {
    try {
      final path = await ServicePhotoHelper.pickAndSave(context);
      if (path == null || !mounted) return;
      await _repository.updateServicePhotos(
        id: id,
        beforePhotoPath: before ? path : null,
        afterPhotoPath: before ? null : path,
      );
      if (!mounted) return;
      _refresh();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(before
              ? 'Foto sebelum servis berhasil disimpan.'
              : 'Foto sesudah servis berhasil disimpan.'),
        ),
      );
      // Tampilkan kembali detail agar foto terbaru langsung terlihat.
      final updatedOrder = <String, Object?>{...{'id': id}};
      await _showDetail(updatedOrder);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal menyimpan foto: $error')),
      );
    }
  }

  Future<void> _showDetail(Map<String, Object?> order) async {
    final id = order['id'] as int;
    final detail = await _repository.getServiceOrderById(id);
    if (!mounted || detail == null) return;

    final status = detail['service_status']?.toString() ?? 'waiting';
    final action = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(detail['order_number']?.toString() ?? 'Detail Servis'),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _detailLine('Pelanggan', detail['customer_name']),
                _detailLine('Telepon', detail['customer_phone']),
                _detailLine(
                  'Sepeda',
                  '${detail['bicycle_brand'] ?? ''} ${detail['bicycle_model'] ?? ''}',
                ),
                _detailLine('Nomor rangka', detail['bicycle_serial_number']),
                _detailLine('Tanggal masuk', _dateLabel(detail['received_at'])),
                _detailLine('Keluhan', detail['complaint']),
                _detailLine('Diagnosis', detail['diagnosis']),
                _detailLine('Mekanik', detail['mechanic_name']),
                const Divider(),
                _detailLine('Jasa servis', _rupiah(detail['labor_cost'])),
                _detailLine('Sparepart', _rupiah(detail['parts_cost'])),
                _detailLine('Diskon', _rupiah(detail['discount'])),
                _detailLine('Total', _rupiah(detail['total_cost'])),
                _detailLine('Sudah dibayar', _rupiah(detail['down_payment'])),
                _detailLine('Sisa tagihan', _rupiah(detail['remaining_payment'])),
                _detailLine('Status', _statusLabels[status] ?? status),
                if ((detail['notes']?.toString() ?? '').isNotEmpty)
                  _detailLine('Catatan', detail['notes']),
                const Divider(),
                const Text('Dokumentasi Servis',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                const Text('Foto sebelum servis',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 5),
                ServicePhotoHelper.preview(
                  detail['before_photo_path']?.toString(),
                  height: 145,
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () => Navigator.pop(dialogContext, 'before'),
                    icon: const Icon(Icons.add_a_photo_outlined),
                    label: Text(detail['before_photo_path'] == null
                        ? 'Tambah foto sebelum'
                        : 'Ganti foto sebelum'),
                  ),
                ),
                const SizedBox(height: 5),
                const Text('Foto sesudah servis',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 5),
                ServicePhotoHelper.preview(
                  detail['after_photo_path']?.toString(),
                  height: 145,
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () => Navigator.pop(dialogContext, 'after'),
                    icon: const Icon(Icons.add_a_photo_outlined),
                    label: Text(detail['after_photo_path'] == null
                        ? 'Tambah foto sesudah'
                        : 'Ganti foto sesudah'),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Tutup'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, 'status'),
            icon: const Icon(Icons.edit_outlined),
            label: const Text('Ubah Status'),
          ),
        ],
      ),
    );

    if (!mounted) return;
    if (action == 'status') {
      await _changeStatus(detail);
    } else if (action == 'before') {
      await _pickServicePhoto(id, before: true);
    } else if (action == 'after') {
      await _pickServicePhoto(id, before: false);
    }
  }

  Widget _detailLine(String label, Object? value) {
    final text = value?.toString().trim() ?? '';
    if (text.isEmpty || text == 'null') return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 112,
            child: Text(label,
                style: const TextStyle(color: Colors.grey, fontSize: 12)),
          ),
          const Text(': '),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }

  Widget _buildOrderCard(Map<String, Object?> order) {
    final status = order['service_status']?.toString() ?? 'waiting';
    final customer = order['customer_name']?.toString() ?? 'Pelanggan';
    final bicycle = [
      order['bicycle_brand']?.toString() ?? '',
      order['bicycle_model']?.toString() ?? '',
    ].where((part) => part.isNotEmpty).join(' ');
    final complaint = order['complaint']?.toString() ?? '';
    final number = order['order_number']?.toString() ?? '-';

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: () => _showDetail(order),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(number,
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                    decoration: BoxDecoration(
                      color: _statusColor(status).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      _statusLabels[status] ?? status,
                      style: TextStyle(
                        color: _statusColor(status),
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 9),
              Text(customer, style: const TextStyle(fontWeight: FontWeight.w600)),
              if (bicycle.isNotEmpty)
                Text(bicycle,
                    style: const TextStyle(fontSize: 12, color: Colors.grey)),
              if (complaint.isNotEmpty) ...[
                const SizedBox(height: 7),
                Text(complaint, maxLines: 2, overflow: TextOverflow.ellipsis),
              ],
              const Divider(height: 18),
              Row(
                children: [
                  Expanded(
                    child: Text(_dateLabel(order['received_at']),
                        style: const TextStyle(fontSize: 11, color: Colors.grey)),
                  ),
                  Text(_rupiah(order['total_cost']),
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'status') _changeStatus(order);
                      if (value == 'detail') _showDetail(order);
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'detail', child: Text('Lihat detail')),
                      PopupMenuItem(value: 'status', child: Text('Ubah status')),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Daftar Servis'),
        actions: [
          IconButton(
            onPressed: _refresh,
            tooltip: 'Muat ulang',
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: TextField(
              controller: _searchController,
              onChanged: (_) => _refresh(),
              decoration: InputDecoration(
                hintText: 'Cari nota, pelanggan, sepeda...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  onPressed: () {
                    _searchController.clear();
                    _refresh();
                  },
                  icon: const Icon(Icons.close),
                ),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          SizedBox(
            height: 54,
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
              scrollDirection: Axis.horizontal,
              children: [
                _filterChip('Semua', null),
                ..._statusLabels.entries.map(
                  (entry) => _filterChip(entry.value, entry.key),
                ),
              ],
            ),
          ),
          Expanded(
            child: FutureBuilder<List<Map<String, Object?>>>(
              future: _ordersFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text('Gagal memuat daftar servis:\n${snapshot.error}',
                          textAlign: TextAlign.center),
                    ),
                  );
                }
                final orders = snapshot.data ?? [];
                if (orders.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.build_circle_outlined, size: 60),
                          SizedBox(height: 12),
                          Text('Belum ada data servis',
                              style: TextStyle(fontWeight: FontWeight.bold)),
                          SizedBox(height: 5),
                          Text('Tekan tombol + untuk mencatat sepeda yang masuk.',
                              textAlign: TextAlign.center),
                        ],
                      ),
                    ),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 90),
                  itemCount: orders.length,
                  itemBuilder: (context, index) => _buildOrderCard(orders[index]),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openIntake,
        icon: const Icon(Icons.add),
        label: const Text('Servis Masuk'),
      ),
    );
  }

  Widget _filterChip(String label, String? value) {
    final selected = _statusFilter == value;
    return Padding(
      padding: const EdgeInsets.only(right: 7),
      child: FilterChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) {
          setState(() {
            _statusFilter = value;
            _loadOrders();
          });
        },
      ),
    );
  }
}
