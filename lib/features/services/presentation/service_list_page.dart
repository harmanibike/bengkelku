
import 'package:material_ui/material_ui.dart';
import '../../../core/formatters/currency_input_formatter.dart';

import '../../../core/auth/auth_session.dart';
import '../../settings/data/account_repository.dart';

import '../data/service_repository.dart';
import '../../business/data/business_profile_repository.dart';
import '../../business/presentation/business_identity_header.dart';
import 'service_intake_page.dart';
import 'service_photo_helper.dart';
import '../../receipts/presentation/receipt_share_launcher.dart';

class ServiceListPage extends StatefulWidget {
  const ServiceListPage({super.key, this.showOutstandingOnly = false});

  final bool showOutstandingOnly;

  @override
  State<ServiceListPage> createState() => _ServiceListPageState();
}

class _ServiceListPageState extends State<ServiceListPage> {
  final ServiceRepository _repository = ServiceRepository();
  final TextEditingController _searchController = TextEditingController();

  String? _statusFilter;
  bool _showOutstandingOnly = false;
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
    _showOutstandingOnly = widget.showOutstandingOnly;
    _loadOrders();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _loadOrders() {
    final session = AuthSession.instance;
    _ordersFuture = session.isMechanic
        ? _repository.getServiceOrders(
            keyword: _searchController.text,
            status: _statusFilter,
            assignedMechanicId: session.userId,
          )
        : _showOutstandingOnly
            ? _repository.getOutstandingServiceOrders(keyword: _searchController.text)
            : _repository.getServiceOrders(keyword: _searchController.text, status: _statusFilter);
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
              .where((entry) =>
                  (!AuthSession.instance.isMechanic || const ['checking', 'in_progress', 'completed'].contains(entry.key)) &&
                  (entry.key == current ||
                  (ServiceRepository.allowedStatusTransitions[current] ??
                          const <String>[])
                      .contains(entry.key)))
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
      await _repository.updateServiceStatus(
        id: id,
        status: result,
        actingMechanicId: AuthSession.instance.isMechanic ? AuthSession.instance.userId : null,
      );
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

  Future<void> _addServicePayment(int id, {int? remainingAmount}) async {
    final order = remainingAmount == null
        ? await _repository.getServiceOrderById(id)
        : null;
    final outstanding = remainingAmount ??
        (order?['remaining_payment'] as num? ?? 0).toInt();
    if (outstanding <= 0 || !mounted) return;

    final controller = TextEditingController();
    final amount = await showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Catat Pembayaran Servis'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: const [CurrencyInputFormatter()],
          decoration: InputDecoration(
            labelText: 'Uang diterima (Rp)',
            helperText: 'Sisa tagihan: ${_rupiah(outstanding)}. Jika uang lebih, kembalian dihitung otomatis.',
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () {
              final value = int.tryParse(
                controller.text.replaceAll(RegExp(r'[^0-9]'), ''),
              );
              if (value != null && value > 0) {
                Navigator.pop(dialogContext, value);
              }
            },
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (amount == null || !mounted) return;

    final appliedAmount = amount > outstanding ? outstanding : amount;
    final change = amount - appliedAmount;
    try {
      await _repository.addPayment(id: id, amount: appliedAmount);
      if (!mounted) return;
      _refresh();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(change > 0
              ? 'Pembayaran lunas. Kembalian: ${_rupiah(change)}.'
              : 'Pembayaran berhasil dicatat ke kas.'),
        ),
      );
      final printReceipt = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Pembayaran berhasil'),
          content: const Text(
            'Apakah nota servis ingin dicetak atau dibagikan sekarang? '
            'Nota akan memuat riwayat pembayaran dan sisa tagihan terbaru.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Nanti'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(dialogContext, true),
              icon: const Icon(Icons.print_outlined),
              label: const Text('Cetak nota'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      if (printReceipt == true) {
        await ReceiptShareLauncher.service(context, id);
      }
      if (!mounted) return;
      await _showDetail({'id': id});
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal mencatat pembayaran: $error')),
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

  Future<void> _editDirectCosts(Map<String, Object?> detail) async {
    final id = detail['id'] as int;
    final parts = TextEditingController(
      text: (detail['direct_parts_cost'] as num? ?? 0).toInt().toString(),
    );
    final other = TextEditingController(
      text: (detail['other_direct_cost'] as num? ?? 0).toInt().toString(),
    );
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Biaya modal servis'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: parts,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Modal sparepart (Rp)',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: other,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Biaya langsung lain (Rp)',
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Catat biaya aktual yang benar-benar dikeluarkan. Perubahan ini tidak mengubah tagihan pelanggan atau stok.',
              style: TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
    if (saved == true) {
      int amount(TextEditingController controller) {
        final digits = controller.text.replaceAll(RegExp(r'[^0-9]'), '');
        return int.tryParse(digits) ?? 0;
      }

      try {
        await _repository.updateServiceDirectCosts(
          id: id,
          directPartsCost: amount(parts),
          otherDirectCost: amount(other),
        );
        if (!mounted) return;
        _refresh();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Biaya langsung servis diperbarui.')),
        );
        await _showDetail({'id': id});
      } catch (error) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal menyimpan biaya servis: $error')),
        );
      }
    }
    parts.dispose();
    other.dispose();
  }

  Future<void> _assignMechanic(int serviceOrderId) async {
    try {
      final mechanics = await AccountRepository().getActiveMechanics();
      if (!mounted) return;
      if (mechanics.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Belum ada akun Mekanik aktif. Buat akun Mekanik terlebih dahulu.')),
        );
        return;
      }
      int? selected = mechanics.first['id'] as int;
      final result = await showDialog<int>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (dialogContext, setDialogState) => AlertDialog(
            title: const Text('Tugaskan Mekanik'),
            content: DropdownButtonFormField<int>(
              initialValue: selected,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Pilih mekanik', border: OutlineInputBorder()),
              items: mechanics.map((mechanic) => DropdownMenuItem<int>(
                value: mechanic['id'] as int,
                child: Text(mechanic['display_name']?.toString() ?? 'Mekanik'),
              )).toList(),
              onChanged: (value) {
                if (value != null) setDialogState(() => selected = value);
              },
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Batal')),
              FilledButton(onPressed: () => Navigator.pop(dialogContext, selected), child: const Text('Simpan')),
            ],
          ),
        ),
      );
      if (result == null || !mounted) return;
      await _repository.assignMechanic(serviceOrderId: serviceOrderId, mechanicId: result);
      if (!mounted) return;
      _refresh();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Penugasan mekanik berhasil disimpan.')),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal menugaskan mekanik: $error')),
        );
      }
    }
  }

  Future<void> _showDetail(Map<String, Object?> order) async {
    final id = order['id'] as int;
    final detail = await _repository.getServiceOrderById(id);
    if (!mounted || detail == null) return;

    final status = detail['service_status']?.toString() ?? 'waiting';
    final statusHistory = await _repository.getServiceStatusHistory(id);
    final directCostHistory = AuthSession.instance.isAdmin
        ? await _repository.getServiceDirectCostHistory(id)
        : <Map<String, Object?>>[];
    final businessProfile = await BusinessProfileRepository().getProfile();
    if (!mounted) return;
    final action = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(detail['order_number']?.toString() ?? 'Detail Servis'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                BusinessIdentityHeader(profile: businessProfile),
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
                if (!AuthSession.instance.isMechanic) ...[
                const Divider(),
                _detailLine('Jasa servis', _rupiah(detail['labor_cost'])),
                _detailLine('Sparepart', _rupiah(detail['parts_cost'])),
                if (AuthSession.instance.isAdmin) ...[
                  _detailLine('Modal sparepart', _rupiah(detail['direct_parts_cost'])),
                  _detailLine('Biaya langsung lain', _rupiah(detail['other_direct_cost'])),
                ],
                _detailLine('Diskon', _rupiah(detail['discount'])),
                _detailLine('Total', _rupiah(detail['total_cost'])),
                _detailLine('Sudah dibayar', _rupiah(detail['down_payment'])),
                _detailLine('Sisa tagihan', _rupiah(detail['remaining_payment'])),
                _detailLine(
                  'Status pembayaran',
                  (detail['remaining_payment'] as int? ?? 0) <= 0
                      ? 'Lunas'
                      : (detail['down_payment'] as int? ?? 0) > 0
                          ? 'Belum lunas (sebagian dibayar)'
                          : 'Belum dibayar',
                ),
                ],
                _detailLine('Status sepeda', _statusLabels[status] ?? status),
                if (statusHistory.isNotEmpty) ...[
                  const Divider(),
                  const Text('Riwayat Status',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  ...statusHistory.map((entry) {
                    final next = entry['new_status']?.toString() ?? 'waiting';
                    final previous = entry['old_status']?.toString();
                    final label = previous == null
                        ? 'Servis diterima'
                        : '${_statusLabels[previous] ?? previous} → ${_statusLabels[next] ?? next}';
                    final note = entry['note']?.toString();
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 7),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.history, size: 16, color: Colors.grey),
                          const SizedBox(width: 7),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                                Text(_dateLabel(entry['changed_at']), style: const TextStyle(fontSize: 11, color: Colors.grey)),
                                if (note != null && note.isNotEmpty)
                                  Text(note, style: const TextStyle(fontSize: 11)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
                if (directCostHistory.isNotEmpty) ...[
                  const Divider(),
                  const Text('Riwayat Biaya Modal',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  ...directCostHistory.map((entry) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_dateLabel(entry['changed_at']),
                                style: const TextStyle(fontSize: 11, color: Colors.grey)),
                            Text('Modal sparepart: ${_rupiah(entry['old_direct_parts_cost'])} → ${_rupiah(entry['new_direct_parts_cost'])}',
                                style: const TextStyle(fontSize: 12)),
                            Text('Biaya langsung lain: ${_rupiah(entry['old_other_direct_cost'])} → ${_rupiah(entry['new_other_direct_cost'])}',
                                style: const TextStyle(fontSize: 12)),
                          ],
                        ),
                      )),
                ],
                if ((detail['notes']?.toString() ?? '').isNotEmpty)
                  _detailLine('Catatan', detail['notes']),
                if (!AuthSession.instance.isMechanic) ...[
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
              ],
            ),
          ),
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 8,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Tutup'),
                ),
                if (AuthSession.instance.isCashierOrAdmin)
                  OutlinedButton.icon(
                    onPressed: () => Navigator.pop(dialogContext, 'assign_mechanic'),
                    icon: const Icon(Icons.assignment_ind_outlined),
                    label: const Text('Tugaskan Mekanik'),
                  ),
                if (!AuthSession.instance.isMechanic)
                  OutlinedButton.icon(
                    onPressed: () => Navigator.pop(dialogContext, 'receipt_history'),
                    icon: const Icon(Icons.history),
                    label: const Text('Riwayat Nota'),
                  ),
                if (!AuthSession.instance.isMechanic)
                  OutlinedButton.icon(
                    onPressed: () => Navigator.pop(dialogContext, 'receipt'),
                    icon: const Icon(Icons.receipt_long_outlined),
                    label: const Text('Nota / Bagikan'),
                  ),
                if (!AuthSession.instance.isMechanic)
                  PopupMenuButton<String>(
                    tooltip: 'Dokumen servis',
                    onSelected: (value) => Navigator.pop(dialogContext, value),
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                        value: 'service_intake_receipt',
                        child: Text('Bukti Penerimaan Sepeda'),
                      ),
                      if ((detail['remaining_payment'] as int? ?? 0) <= 0 &&
                          status != 'cancelled')
                        const PopupMenuItem(
                          value: 'service_final_payment_receipt',
                          child: Text('Bukti Pelunasan'),
                        ),
                    ],
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.description_outlined, size: 18),
                          const SizedBox(width: 6),
                          const Text('Dokumen'),
                          const Icon(Icons.arrow_drop_down, size: 18),
                        ],
                      ),
                    ),
                  ),
                if (AuthSession.instance.isAdmin)
                  OutlinedButton.icon(
                    onPressed: () => Navigator.pop(dialogContext, 'direct_costs'),
                    icon: const Icon(Icons.edit_note_outlined),
                    label: const Text('Ubah Biaya Modal'),
                  ),
                if ((detail['remaining_payment'] as int? ?? 0) > 0 &&
                    status != 'cancelled')
                  OutlinedButton.icon(
                    onPressed: () => Navigator.pop(dialogContext, 'payment'),
                    icon: const Icon(Icons.payments_outlined),
                    label: const Text('Catat Pembayaran'),
                  ),
                FilledButton.icon(
                  onPressed: () => Navigator.pop(dialogContext, 'status'),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Ubah Status'),
                ),
              ],
            ),
          ),
        ],
    );

    if (!mounted) return;
    if (action == 'assign_mechanic') {
      await _assignMechanic(id);
    } else if (action == 'receipt') {
      await ReceiptShareLauncher.service(context, id);
    } else if (action == 'service_intake_receipt') {
      await ReceiptShareLauncher.serviceIntake(context, id);
    } else if (action == 'service_final_payment_receipt') {
      await ReceiptShareLauncher.serviceFinalPayment(context, id);
    } else if (action == 'receipt_history') {
      await ReceiptShareLauncher.showHistory(context, sourceType: 'service_order', sourceId: id);
    } else if (action == 'direct_costs') {
      await _editDirectCosts(detail);
    } else if (action == 'status') {
      await _changeStatus(detail);
    } else if (action == 'payment') {
      await _addServicePayment(id);
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
          padding: const EdgeInsets.all(12),
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
              if (!AuthSession.instance.isMechanic && (order['remaining_payment'] as int? ?? 0) > 0) ...[
                const SizedBox(height: 6),
                Text(
                  'Sisa tagihan: ${_rupiah(order['remaining_payment'])}',
                  style: const TextStyle(
                    color: Colors.red,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const Divider(height: 18),
              Row(
                children: [
                  Expanded(
                    child: Text(_dateLabel(order['received_at']),
                        style: const TextStyle(fontSize: 11, color: Colors.grey)),
                  ),
                  if (!AuthSession.instance.isMechanic)
                    Text(_rupiah(order['total_cost']),
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                  if (_showOutstandingOnly && AuthSession.instance.isCashierOrAdmin)
                    TextButton.icon(
                      onPressed: () => _addServicePayment(
                        order['id'] as int,
                        remainingAmount: (order['remaining_payment'] as num? ?? 0).toInt(),
                      ),
                      icon: const Icon(Icons.payments_outlined, size: 17),
                      label: const Text('Bayar'),
                    ),
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
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
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
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              scrollDirection: Axis.horizontal,
              children: [
                if (!AuthSession.instance.isMechanic) FilterChip(
                  label: const Text('Piutang'),
                  selected: _showOutstandingOnly,
                  avatar: const Icon(Icons.account_balance_wallet_outlined, size: 17),
                  onSelected: (selected) {
                    setState(() {
                      _showOutstandingOnly = selected;
                      if (selected) _statusFilter = null;
                      _loadOrders();
                    });
                  },
                ),
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
                          SizedBox(height: 8),
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
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 90),
                  itemCount: orders.length,
                  itemBuilder: (context, index) => _buildOrderCard(orders[index]),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: AuthSession.instance.isMechanic ? null : FloatingActionButton.extended(
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
            _showOutstandingOnly = false;
            _statusFilter = value;
            _loadOrders();
          });
        },
      ),
    );
  }
}
