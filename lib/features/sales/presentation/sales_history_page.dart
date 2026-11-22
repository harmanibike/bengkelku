import 'package:material_ui/material_ui.dart';

import '../data/sale_repository.dart';
import '../../business/data/business_profile_repository.dart';
import '../../business/presentation/business_identity_header.dart';

class SalesHistoryPage extends StatefulWidget {
  const SalesHistoryPage({super.key});

  @override
  State<SalesHistoryPage> createState() => _SalesHistoryPageState();
}

class _SalesHistoryPageState extends State<SalesHistoryPage> {
  final SaleRepository _repository = SaleRepository();
  final TextEditingController _search = TextEditingController();
  List<Map<String, Object?>> _sales = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadSales();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  String _rupiah(int amount) {
    final digits = amount.toString();
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write('.');
      buffer.write(digits[i]);
    }
    return 'Rp$buffer';
  }

  String _dateLabel(Object? value) {
    final date = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
    if (date == null) return '-';
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return '$day/$month/${date.year} $hour:$minute';
  }

  Future<void> _loadSales() async {
    setState(() => _loading = true);
    try {
      final result = await _repository.getSales(keyword: _search.text);
      if (!mounted) return;
      setState(() {
        _sales = result;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal memuat riwayat penjualan: $error')),
      );
    }
  }

  Future<void> _addPayment(int id, int remaining) async {
    final controller = TextEditingController(text: remaining.toString());
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Catat pembayaran susulan'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: 'Jumlah pembayaran (Rp)', helperText: 'Sisa tagihan: ${_rupiah(remaining)}'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Simpan pembayaran')),
        ],
      ),
    );
    if (confirmed != true || !mounted) { controller.dispose(); return; }
    final amount = int.tryParse(controller.text.replaceAll('.', '').trim()) ?? 0;
    controller.dispose();
    try {
      await _repository.addSalePayment(id: id, amount: amount);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pembayaran susulan berhasil dicatat.')));
      await _loadSales();
      if (mounted) await _showDetail(id);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Pembayaran gagal: $error')));
    }
  }

  Future<void> _showDetail(int id) async {
    try {
      final sale = await _repository.getSaleById(id);
      if (!mounted || sale == null) return;
      final items = List<Map<String, Object?>>.from(
        sale['items'] as List? ?? const [],
      );
      final businessProfile = await BusinessProfileRepository().getProfile();
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Detail Penjualan'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  BusinessIdentityHeader(profile: businessProfile),
                  Text(
                    sale['invoice_number']?.toString() ?? '-',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(_dateLabel(sale['transaction_date'])),
                  const Divider(height: 20),
                  ...items.map((item) {
                    final quantity = item['quantity'] as int? ?? 0;
                    final price = item['unit_price'] as int? ?? 0;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              '${item['product_name']}\n$quantity × ${_rupiah(price)}',
                            ),
                          ),
                          Text(
                            _rupiah(item['subtotal'] as int? ?? price * quantity),
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    );
                  }),
                  const Divider(height: 16),
                  _detailRow('Subtotal', sale['subtotal'] as int? ?? 0),
                  _detailRow('Diskon', sale['discount'] as int? ?? 0),
                  _detailRow('Total', sale['total'] as int? ?? 0, bold: true),
                  _detailRow('Dibayar', sale['paid'] as int? ?? 0),
                  _detailRow('Sisa tagihan', ((sale['total'] as int? ?? 0) - (sale['paid'] as int? ?? 0)).clamp(0, 1 << 62).toInt()),
                  _detailRow('Kembalian', sale['change_amount'] as int? ?? 0),
                  const SizedBox(height: 8),
                  Text('Status: ${_statusLabel(sale['payment_status'])}'),
                ],
              ),
            ),
          ),
          actions: [
            if (['partial', 'unpaid'].contains(sale['payment_status']?.toString()))
              TextButton.icon(
                onPressed: () {
                  Navigator.pop(dialogContext);
                  final total = sale['total'] as int? ?? 0;
                  final paid = sale['paid'] as int? ?? 0;
                  _addPayment(id, total - paid);
                },
                icon: const Icon(Icons.payments_outlined),
                label: const Text('Catat pembayaran'),
              ),
            if (['paid', 'partial', 'unpaid'].contains(sale['payment_status']?.toString()))
              TextButton.icon(
                onPressed: () {
                  Navigator.pop(dialogContext);
                  _confirmCancel(id, sale['invoice_number']?.toString() ?? '-');
                },
                icon: const Icon(Icons.cancel_outlined, color: Colors.red),
                label: const Text('Batalkan nota', style: TextStyle(color: Colors.red)),
              ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Tutup'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal membuka detail: $error')),
      );
    }
  }

  Widget _detailRow(String label, int amount, {bool bold = false}) {
    final style = TextStyle(
      fontWeight: bold ? FontWeight.bold : FontWeight.normal,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text(_rupiah(amount), style: style),
        ],
      ),
    );
  }

  String _statusLabel(Object? status) {
    switch (status?.toString()) {
      case 'cancelled':
        return 'Dibatalkan';
      case 'paid':
        return 'Lunas';
      case 'partial':
        return 'Belum Lunas (Sebagian)';
      case 'unpaid':
        return 'Belum Dibayar';
      default:
        return status?.toString() ?? 'Tidak diketahui';
    }
  }

  Future<void> _confirmCancel(int id, String invoice) async {
    final reasonController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Batalkan transaksi?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Nota $invoice akan ditandai dibatalkan. Stok akan dikembalikan dan pembalikan kas dicatat sebagai pengeluaran.'),
            const SizedBox(height: 8),
            TextField(
              controller: reasonController,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Alasan pembatalan (opsional)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Kembali'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Ya, batalkan'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      reasonController.dispose();
      return;
    }

    try {
      await _repository.cancelSale(id: id, reason: reasonController.text);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Transaksi dibatalkan. Stok dan kas sudah disesuaikan.')),
      );
      await _loadSales();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Pembatalan gagal: $error')),
      );
    } finally {
      reasonController.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Riwayat Penjualan'),
        actions: [
          IconButton(
            tooltip: 'Muat ulang',
            onPressed: _loadSales,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
            child: TextField(
              controller: _search,
              onChanged: (_) => _loadSales(),
              decoration: InputDecoration(
                hintText: 'Cari nomor nota atau catatan',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  onPressed: () {
                    _search.clear();
                    _loadSales();
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
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _sales.isEmpty
                    ? const Center(child: Text('Belum ada transaksi penjualan.'))
                    : RefreshIndicator(
                        onRefresh: _loadSales,
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                          itemCount: _sales.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 2),
                          itemBuilder: (context, index) {
                            final sale = _sales[index];
                            final status = sale['payment_status']?.toString() ?? 'paid';
                            final cancelled = status == 'cancelled';
            final remaining = ((sale['total'] as int? ?? 0) - (sale['paid'] as int? ?? 0)).clamp(0, 1 << 62).toInt();
                            return Card(
                              child: ListTile(
                                onTap: () => _showDetail(sale['id'] as int),
                                leading: CircleAvatar(
                                  backgroundColor: cancelled
                                      ? Colors.red.withValues(alpha: 0.12)
                                      : Colors.green.withValues(alpha: 0.12),
                                  child: Icon(
                                    cancelled ? Icons.cancel_outlined : (status == 'paid' ? Icons.receipt_long : Icons.pending_actions),
                                    color: cancelled ? Colors.red : (status == 'paid' ? Colors.green : Colors.orange),
                                  ),
                                ),
                                title: Text(
                                  sale['invoice_number']?.toString() ?? '-',
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                                subtitle: Text(
                                  '${_dateLabel(sale['transaction_date'])}\n${_statusLabel(status)}${remaining > 0 && !cancelled ? '\nSisa: ${_rupiah(remaining)}' : ''}',
                                ),
                                isThreeLine: true,
                                trailing: Text(
                                  _rupiah(sale['total'] as int? ?? 0),
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: cancelled ? Colors.grey : null,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}
