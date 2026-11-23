
import 'package:material_ui/material_ui.dart';
import '../../../core/formatters/currency_input_formatter.dart';

import '../../../core/auth/auth_session.dart';
import '../../settings/data/account_repository.dart';

import '../data/service_repository.dart';
import '../../customers/data/customer_wallet_repository.dart';
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
  final CustomerWalletRepository _walletRepository = CustomerWalletRepository();
  final TextEditingController _searchController = TextEditingController();

  String? _statusFilter;
  bool _showOutstandingOnly = false;
  late Future<List<Map<String, Object?>>> _ordersFuture;
  static const Map<String, String> _statusLabels = {
    'active_queue': 'Antrian aktif',
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

  Future<void> _payServiceFromWallet(Map<String, Object?> detail) async {
    final customerId = detail['customer_id'] as int?;
    final id = detail['id'] as int;
    final remaining = (detail['remaining_payment'] as num?)?.toInt() ?? 0;
    if (customerId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Servis pelanggan umum tidak dapat memakai saldo deposit.')));
      return;
    }
    final balance = await _walletRepository.getBalance(customerId);
    if (!mounted) return;
    if (balance <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saldo pelanggan masih kosong.')));
      return;
    }
    final controller = TextEditingController(text: (balance < remaining ? balance : remaining).toString());
    final amount = await showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Bayar dari saldo pelanggan'),
        content: TextField(controller: controller, keyboardType: TextInputType.number,
          inputFormatters: const [CurrencyInputFormatter()],
          decoration: InputDecoration(labelText: 'Nominal digunakan (Rp)', helperText: 'Saldo: ${_rupiah(balance)} • Sisa tagihan: ${_rupiah(remaining)}', border: const OutlineInputBorder())),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Batal')),
          FilledButton(onPressed: () {
            final value = int.tryParse(controller.text.replaceAll(RegExp(r'[^0-9]'), ''));
            if (value != null && value > 0) Navigator.pop(dialogContext, value);
          }, child: const Text('Gunakan saldo')),
        ],
      ),
    );
    controller.dispose();
    if (amount == null || !mounted) return;
    try {
      await _repository.addWalletPayment(id: id, amount: amount);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pembayaran dari saldo pelanggan berhasil.')));
      _refresh();
      await _showDetail({'id': id});
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal menggunakan saldo: $error')));
    }
  }

  Future<void> _recordServiceTip(Map<String, Object?> detail) async {
    final controller = TextEditingController();
    final noteController = TextEditingController();
    final amount = await showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Catat Uang Tip'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Mekanik: ${detail['mechanic_name'] ?? 'Belum ditentukan'}'),
          const SizedBox(height: 8),
          TextField(controller: controller, keyboardType: TextInputType.number,
            inputFormatters: const [CurrencyInputFormatter()],
            decoration: const InputDecoration(labelText: 'Nominal tip (Rp)', border: OutlineInputBorder())),
          const SizedBox(height: 8),
          TextField(controller: noteController, decoration: const InputDecoration(labelText: 'Catatan (opsional)', border: OutlineInputBorder())),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Batal')),
          FilledButton(onPressed: () {
            final value = int.tryParse(controller.text.replaceAll(RegExp(r'[^0-9]'), ''));
            if (value != null && value > 0) Navigator.pop(dialogContext, value);
          }, child: const Text('Simpan tip')),
        ],
      ),
    );
    final note = noteController.text.trim();
    controller.dispose();
    noteController.dispose();
    if (amount == null || !mounted) return;
    try {
      await _walletRepository.recordTip(
        amount: amount, sourceType: 'service_order', sourceId: detail['id'] as int,
        recipientName: detail['mechanic_name']?.toString(),
        paymentMethod: 'cash', note: note,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Uang tip dicatat terpisah dari omzet.')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal mencatat tip: $error')));
    }
  }

  Future<void> _addServicePayment(int id, {int? remainingAmount}) async {
    final order = await _repository.getServiceOrderById(id);
    final outstanding = remainingAmount ??
        (order?['remaining_payment'] as num? ?? 0).toInt();
    if (outstanding <= 0 || !mounted) return;

    final controller = TextEditingController();
    final tipController = TextEditingController();
    final result = await showDialog<Map<String, int>>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Catat Pembayaran Servis'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: const [CurrencyInputFormatter()],
              decoration: InputDecoration(
                labelText: 'Pembayaran untuk tagihan (Rp)',
                helperText: 'Sisa tagihan: ${_rupiah(outstanding)}',
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: tipController,
              keyboardType: TextInputType.number,
              inputFormatters: const [CurrencyInputFormatter()],
              decoration: InputDecoration(
                labelText: 'Uang tip (opsional)',
                helperText: 'Dicatat terpisah dari tagihan dan omzet. Penerima: ${order?['mechanic_name'] ?? 'Mekanik'}',
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Batal')),
          FilledButton(
            onPressed: () {
              final value = int.tryParse(controller.text.replaceAll(RegExp(r'[^0-9]'), ''));
              final tip = int.tryParse(tipController.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
              if (value != null && value > 0 && tip >= 0) {
                Navigator.pop(dialogContext, {'amount': value, 'tip': tip});
              }
            },
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
    final amount = result?['amount'];
    final tipAmount = result?['tip'] ?? 0;
    controller.dispose();
    tipController.dispose();
    if (amount == null || !mounted) return;

    final appliedAmount = amount > outstanding ? outstanding : amount;
    final change = amount - appliedAmount;
    try {
      await _repository.addPayment(
        id: id,
        amount: appliedAmount,
        tipAmount: tipAmount,
        tipRecipientName: order?['mechanic_name']?.toString(),
      );
      if (!mounted) return;
      _refresh();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text([
            change > 0 ? 'Pembayaran lunas. Kembalian: ${_rupiah(change)}.' : 'Pembayaran servis berhasil dicatat.',
            if (tipAmount > 0) 'Tip ${_rupiah(tipAmount)} dicatat terpisah.',
          ].join(' ')),
        ),
      );
      final printReceipt = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Pembayaran berhasil'),
          content: const Text(
            'Apakah nota servis ingin dicetak atau dibagikan sekarang? '
            'Nota akan memuat riwayat pembayaran dan sisa tagihan terbaru. Uang tip dicatat terpisah.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Nanti')),
            FilledButton.icon(
              onPressed: () => Navigator.pop(dialogContext, true),
              icon: const Icon(Icons.print_outlined),
              label: const Text('Cetak nota'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      if (printReceipt == true) await ReceiptShareLauncher.service(context, id);
      if (!mounted) return;
      await _showDetail({'id': id});
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal mencatat pembayaran: $error')));
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


  Future<void> _editServiceEstimate(Map<String, Object?> detail) async {
    final id = detail['id'] as int;
    final estimateController = TextEditingController(text: (detail['estimated_cost'] as num? ?? 0).toInt().toString());
    final laborController = TextEditingController(text: (detail['labor_cost'] as num? ?? 0).toInt().toString());
    final discountController = TextEditingController(text: (detail['discount'] as num? ?? 0).toInt().toString());
    final reasonController = TextEditingController();
    final approvalController = TextEditingController();
    bool customerApproved = false;
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Ubah estimasi servis'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(controller: estimateController, keyboardType: TextInputType.number,
                  inputFormatters: const [CurrencyInputFormatter()],
                  decoration: const InputDecoration(labelText: 'Estimasi biaya (Rp)', border: OutlineInputBorder())),
                const SizedBox(height: 8),
                TextField(controller: laborController, keyboardType: TextInputType.number,
                  inputFormatters: const [CurrencyInputFormatter()],
                  decoration: const InputDecoration(labelText: 'Jasa servis (Rp)', border: OutlineInputBorder())),
                const SizedBox(height: 8),
                TextField(controller: discountController, keyboardType: TextInputType.number,
                  inputFormatters: const [CurrencyInputFormatter()],
                  decoration: const InputDecoration(labelText: 'Diskon (Rp)', border: OutlineInputBorder())),
                const SizedBox(height: 8),
                TextField(controller: reasonController, maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Alasan perubahan', border: OutlineInputBorder())),
                CheckboxListTile(contentPadding: EdgeInsets.zero, value: customerApproved,
                  onChanged: (v) => setDialogState(() => customerApproved = v ?? false),
                  title: const Text('Pelanggan menyetujui estimasi baru')),
                TextField(controller: approvalController, maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Catatan persetujuan (telepon/WA)', border: OutlineInputBorder())),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Batal')),
            FilledButton(
              onPressed: customerApproved ? () => Navigator.pop(dialogContext, true) : null,
              child: const Text('Simpan perubahan'),
            ),
          ],
        ),
      ),
    );
    int amount(TextEditingController controller) =>
        int.tryParse(controller.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
    final estimate = amount(estimateController);
    final labor = amount(laborController);
    final discount = amount(discountController);
    final reason = reasonController.text.trim();
    final approvalNote = approvalController.text.trim();
    estimateController.dispose();
    laborController.dispose();
    discountController.dispose();
    reasonController.dispose();
    approvalController.dispose();
    if (result != true) return;
    try {
      await _repository.updateServiceOrder(
        id: id,
        estimatedCost: estimate,
        laborCost: labor,
        partsCost: (detail['parts_cost'] as num? ?? 0).toInt(),
        discount: discount,
        customerApproved: true,
        customerApprovalNote: approvalNote,
        changeReason: reason,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Estimasi servis diperbarui dan riwayat perubahan dicatat.')));
      _refresh();
      await _showDetail({'id': id});
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal mengubah estimasi: $error')));
    }
  }

  Future<void> _proposePartChange(int serviceId, {int? cancelItemId}) async {
    final noteController = TextEditingController();
    if (cancelItemId != null) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Usulkan pembatalan sparepart'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Ajukan pembatalan hanya jika sparepart belum dipakai atau dipasang. Setelah disetujui dan pelanggan mengizinkan, stok akan dikembalikan ke batch asal.'),
            const SizedBox(height: 8),
            TextField(controller: noteController, maxLines: 2,
              decoration: const InputDecoration(labelText: 'Alasan / catatan', border: OutlineInputBorder())),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Batal')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Kirim usulan')),
          ],
        ),
      );
      final note = noteController.text.trim();
      noteController.dispose();
      if (confirmed != true) return;
      try {
        await _repository.proposeServicePartChange(serviceOrderId: serviceId, requestType: 'cancel',
          serviceOrderItemId: cancelItemId, mechanicNote: note);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Usulan dikirim ke Admin/Kasir.')));
        await _showDetail({'id': serviceId});
      } catch (error) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal mengirim usulan: $error')));
      }
      return;
    }

    final products = await _repository.getActiveSpareparts();
    if (!mounted) return;
    if (products.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Belum ada sparepart aktif.')));
      return;
    }
    int? selectedId = products.first['id'] as int?;
    final quantityController = TextEditingController(text: '1');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Usulkan penambahan sparepart'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<int>(
              initialValue: selectedId, isExpanded: true,
              decoration: const InputDecoration(labelText: 'Sparepart', border: OutlineInputBorder()),
              items: products.map((p) => DropdownMenuItem<int>(value: p['id'] as int,
                child: Text(p['name']?.toString() ?? 'Sparepart', overflow: TextOverflow.ellipsis))).toList(),
              onChanged: (value) => setDialogState(() => selectedId = value),
            ),
            const SizedBox(height: 8),
            TextField(controller: quantityController, keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Jumlah', border: OutlineInputBorder())),
            const SizedBox(height: 8),
            TextField(controller: noteController, maxLines: 2,
              decoration: const InputDecoration(labelText: 'Alasan / catatan', border: OutlineInputBorder())),
            const SizedBox(height: 8),
            const Text('Usulan belum mengubah stok atau tagihan. Admin/Kasir akan meminta izin pelanggan dan menentukan harga.',
              style: TextStyle(fontSize: 12, color: Colors.grey)),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Batal')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Kirim usulan')),
          ],
        ),
      ),
    );
    final quantity = int.tryParse(quantityController.text.trim()) ?? 0;
    final note = noteController.text.trim();
    quantityController.dispose();
    noteController.dispose();
    if (confirmed != true) return;
    try {
      await _repository.proposeServicePartChange(serviceOrderId: serviceId, requestType: 'add',
        productId: selectedId, quantity: quantity, mechanicNote: note);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Usulan dikirim. Stok dan tagihan belum berubah.')));
      await _showDetail({'id': serviceId});
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal mengirim usulan: $error')));
    }
  }

  Future<void> _reviewPartChange(int serviceId, Map<String, Object?> request) async {
    final isAdd = request['request_type'] == 'add';
    final priceController = TextEditingController();
    final noteController = TextEditingController();
    bool customerApproved = false;
    final result = await showDialog<Map<String, Object?>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(isAdd ? 'Tinjau penambahan sparepart' : 'Tinjau pembatalan sparepart'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('${request['item_name']} • Qty ${request['quantity']}\nCatatan mekanik: ${request['mechanic_note'] ?? '-'}'),
            if (isAdd) ...[
              const SizedBox(height: 8),
              TextField(controller: priceController, keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Harga jual per unit (Rp)', border: OutlineInputBorder())),
            ],
            CheckboxListTile(contentPadding: EdgeInsets.zero, value: customerApproved,
              onChanged: (v) => setDialogState(() => customerApproved = v ?? false),
              title: const Text('Pelanggan sudah menyetujui'),
              subtitle: const Text('Wajib sebelum perubahan diterapkan.')),
            TextField(controller: noteController, maxLines: 2,
              decoration: const InputDecoration(labelText: 'Catatan persetujuan (telepon/WA)', border: OutlineInputBorder())),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, {'approve': false}), child: const Text('Tolak')),
            FilledButton(
              onPressed: customerApproved ? () => Navigator.pop(dialogContext, {
                'approve': true, 'customer_approved': true,
                'price': int.tryParse(priceController.text.trim()), 'note': noteController.text.trim(),
              }) : null,
              child: const Text('Setujui & terapkan'),
            ),
          ],
        ),
      ),
    );
    priceController.dispose();
    noteController.dispose();
    if (result == null) return;
    try {
      await _repository.reviewServicePartChange(
        requestId: request['id'] as int,
        approve: result['approve'] == true,
        customerApproved: result['customer_approved'] == true,
        approvedUnitPrice: isAdd && result['approve'] == true ? result['price'] as int? : null,
        customerApprovalNote: result['note']?.toString(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(result['approve'] == true ? 'Perubahan sparepart diterapkan.' : 'Usulan ditolak.')));
      _refresh();
      await _showDetail({'id': serviceId});
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal meninjau usulan: $error')));
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
    final partChangeRequests = AuthSession.instance.isCashierOrAdmin
        ? await _repository.getServicePartChangeRequests(id)
        : <Map<String, Object?>>[];
    final estimateHistory = AuthSession.instance.isCashierOrAdmin
        ? await _repository.getServiceEstimateHistory(id)
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
                if ((detail['items'] as List? ?? const []).isNotEmpty) ...[
                  const Divider(),
                  const Text('Sparepart pada servis', style: TextStyle(fontWeight: FontWeight.bold)),
                  ...((detail['items'] as List).map((rawItem) {
                    final item = Map<String, Object?>.from(rawItem as Map);
                    final itemId = item['id'] as int?;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(children: [
                        Expanded(child: Text('${item['item_name']} • Qty ${item['quantity']}', style: const TextStyle(fontSize: 13))),
                        if (!AuthSession.instance.isMechanic) Text(_rupiah(item['subtotal']), style: const TextStyle(fontSize: 12)),
                        if (AuthSession.instance.isMechanic && itemId != null && const ['waiting', 'checking', 'in_progress'].contains(status))
                          TextButton(onPressed: () => Navigator.pop(dialogContext, 'part_cancel:$itemId'), child: const Text('Usulkan batal')),
                      ]),
                    );
                  })),
                ],
                if (AuthSession.instance.isMechanic && const ['waiting', 'checking', 'in_progress'].contains(status))
                  OutlinedButton.icon(onPressed: () => Navigator.pop(dialogContext, 'part_add'),
                    icon: const Icon(Icons.add_box_outlined), label: const Text('Usulkan tambah sparepart')),
                if (estimateHistory.isNotEmpty) ...[
                  const Divider(),
                  const Text('Riwayat perubahan estimasi', style: TextStyle(fontWeight: FontWeight.bold)),
                  ...estimateHistory.map((entry) => Padding(
                    padding: const EdgeInsets.only(top: 6, bottom: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${_dateLabel(entry['changed_at'])} • ${entry['changed_by_name'] ?? 'Admin/Kasir'}',
                          style: const TextStyle(fontSize: 11, color: Colors.grey)),
                        Text('Total: ${_rupiah(entry['old_total_cost'])} → ${_rupiah(entry['new_total_cost'])}',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                        if ((entry['reason']?.toString() ?? '').isNotEmpty)
                          Text('Alasan: ${entry['reason']}', style: const TextStyle(fontSize: 11)),
                        if ((entry['customer_approval_note']?.toString() ?? '').isNotEmpty)
                          Text('Persetujuan pelanggan: ${entry['customer_approval_note']}', style: const TextStyle(fontSize: 11)),
                      ],
                    ),
                  )),
                ],
                if (partChangeRequests.isNotEmpty) ...[
                  const Divider(),
                  const Text('Usulan perubahan sparepart', style: TextStyle(fontWeight: FontWeight.bold)),
                  ...partChangeRequests.map((request) => ListTile(
                    dense: true, contentPadding: EdgeInsets.zero,
                    title: Text('${request['request_type'] == 'add' ? 'Tambah' : 'Batalkan'}: ${request['item_name']} × ${request['quantity']}'),
                    subtitle: Text('Status: ${request['status']} • Mekanik: ${request['proposed_by_name'] ?? '-'}'),
                    trailing: request['status'] == 'pending'
                        ? TextButton(onPressed: () => Navigator.pop(dialogContext, 'review_part:${request['id']}'), child: const Text('Tinjau'))
                        : null,
                  )),
                ],
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
                if (AuthSession.instance.isCashierOrAdmin &&
                    const ['waiting', 'checking', 'in_progress'].contains(status))
                  OutlinedButton.icon(
                    onPressed: () => Navigator.pop(dialogContext, 'estimate'),
                    icon: const Icon(Icons.edit_note_outlined),
                    label: const Text('Ubah Estimasi'),
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
                if ((detail['remaining_payment'] as int? ?? 0) > 0 &&
                    detail['customer_id'] != null && status != 'cancelled')
                  OutlinedButton.icon(
                    onPressed: () => Navigator.pop(dialogContext, 'wallet_payment'),
                    icon: const Icon(Icons.account_balance_wallet_outlined),
                    label: const Text('Bayar dari Saldo'),
                  ),
                if (AuthSession.instance.isCashierOrAdmin && status != 'cancelled')
                  OutlinedButton.icon(
                    onPressed: () => Navigator.pop(dialogContext, 'tip'),
                    icon: const Icon(Icons.volunteer_activism_outlined),
                    label: const Text('Catat Uang Tip'),
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
      ),
    );

    if (!mounted) return;
    if (action?.startsWith('part_cancel:') == true) {
      final itemId = int.tryParse(action!.split(':').last);
      if (itemId != null) await _proposePartChange(id, cancelItemId: itemId);
    } else if (action == 'part_add') {
      await _proposePartChange(id);
    } else if (action?.startsWith('review_part:') == true) {
      final requestId = int.tryParse(action!.split(':').last);
      Map<String, Object?>? selectedRequest;
      for (final row in partChangeRequests) {
        if (row['id'] == requestId) selectedRequest = row;
      }
      if (selectedRequest != null) await _reviewPartChange(id, selectedRequest);
    } else if (action == 'assign_mechanic') {
      await _assignMechanic(id);
    } else if (action == 'receipt') {
      await ReceiptShareLauncher.service(context, id);
    } else if (action == 'service_intake_receipt') {
      await ReceiptShareLauncher.serviceIntake(context, id);
    } else if (action == 'service_final_payment_receipt') {
      await ReceiptShareLauncher.serviceFinalPayment(context, id);
    } else if (action == 'receipt_history') {
      await ReceiptShareLauncher.showHistory(context, sourceType: 'service_order', sourceId: id);
    } else if (action == 'estimate') {
      await _editServiceEstimate(detail);
    } else if (action == 'direct_costs') {
      await _editDirectCosts(detail);
    } else if (action == 'status') {
      await _changeStatus(detail);
    } else if (action == 'wallet_payment') {
      await _payServiceFromWallet(detail);
    } else if (action == 'tip') {
      await _recordServiceTip(detail);
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
    final queueNumber = order['queue_number'];
    final isPriority = (order['queue_priority'] as num? ?? 0).toInt() == 1;

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
                  if (queueNumber != null) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                      decoration: BoxDecoration(color: Theme.of(context).colorScheme.primaryContainer, borderRadius: BorderRadius.circular(8)),
                      child: Text('A${queueNumber.toString().padLeft(3, '0')}', style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onPrimaryContainer)),
                    ),
                    const SizedBox(width: 8),
                  ],
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
              if (isPriority) const Padding(padding: EdgeInsets.only(top: 6), child: Row(children: [Icon(Icons.priority_high, size: 16, color: Colors.deepOrange), SizedBox(width: 4), Text('Prioritas', style: TextStyle(color: Colors.deepOrange, fontSize: 12, fontWeight: FontWeight.bold))])),
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
                      if (value == 'priority') _setPriority(order, !isPriority);
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(value: 'detail', child: Text('Lihat detail')),
                      const PopupMenuItem(value: 'status', child: Text('Ubah status')),
                      if (AuthSession.instance.isAdmin && const ['waiting', 'checking', 'in_progress'].contains(status))
                        PopupMenuItem(value: 'priority', child: Text(isPriority ? 'Hapus prioritas' : 'Jadikan prioritas')),
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


  Future<void> _setPriority(Map<String, Object?> order, bool priority) async {
    try {
      await _repository.setQueuePriority(serviceOrderId: order['id'] as int, priority: priority);
      if (!mounted) return;
      _refresh();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(priority ? 'Servis ditandai sebagai prioritas.' : 'Prioritas servis dihapus.')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal mengubah prioritas: $error')));
    }
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
