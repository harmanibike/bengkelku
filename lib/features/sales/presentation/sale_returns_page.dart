import 'package:material_ui/material_ui.dart';

import '../data/sale_repository.dart';
import '../data/sale_return_repository.dart';

class SaleReturnsPage extends StatefulWidget {
  const SaleReturnsPage({super.key, this.initialSaleId});

  final int? initialSaleId;

  @override
  State<SaleReturnsPage> createState() => _SaleReturnsPageState();
}

class _SaleReturnsPageState extends State<SaleReturnsPage> {
  final SaleRepository _salesRepository = SaleRepository();
  final SaleReturnRepository _returnRepository = SaleReturnRepository();
  final TextEditingController _refundController = TextEditingController(text: '0');
  final TextEditingController _notesController = TextEditingController();

  List<Map<String, Object?>> _sales = [];
  List<Map<String, Object?>> _returns = [];
  List<Map<String, Object?>> _saleItems = [];
  final Map<int, TextEditingController> _quantityControllers = {};
  Map<String, Object?>? _selectedSale;
  Map<String, Object?> _returnSummary = const {};
  int? _selectedSaleId;
  bool _loading = true;
  bool _loadingSale = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load().then((_) {
      if (mounted && widget.initialSaleId != null) {
        _selectSale(widget.initialSaleId);
      }
    });
  }

  @override
  void dispose() {
    _disposeQuantityControllers();
    _refundController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _disposeQuantityControllers() {
    for (final controller in _quantityControllers.values) {
      controller.dispose();
    }
    _quantityControllers.clear();
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
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final sales = await _salesRepository.getSales();
      final returns = await _returnRepository.getReturns();
      if (!mounted) return;
      setState(() {
        _sales = sales
            .where((sale) => sale['payment_status'] != 'cancelled')
            .toList();
        _returns = returns;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal memuat data retur: $error')),
      );
    }
  }

  Future<void> _selectSale(int? saleId) async {
    _disposeQuantityControllers();
    if (saleId == null) {
      setState(() {
        _selectedSaleId = null;
        _selectedSale = null;
        _saleItems = [];
        _returnSummary = const {};
      });
      return;
    }

    setState(() {
      _selectedSaleId = saleId;
      _selectedSale = null;
      _saleItems = [];
      _loadingSale = true;
      _refundController.text = '0';
      _notesController.clear();
    });

    try {
      final sale = await _salesRepository.getSaleById(saleId);
      final items = await _returnRepository.getReturnableItems(saleId);
      final summary = await _returnRepository.getSaleReturnSummary(saleId);
      if (!mounted) return;
      for (final item in items) {
        final id = item['sale_item_id'] as int;
        _quantityControllers[id] = TextEditingController(text: '0');
      }
      setState(() {
        _selectedSale = sale;
        _saleItems = items;
        _returnSummary = summary;
        _loadingSale = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loadingSale = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal memuat barang nota: $error')),
      );
    }
  }

  int _quantityFor(Map<String, Object?> item) {
    final id = item['sale_item_id'] as int;
    return int.tryParse(_quantityControllers[id]?.text.trim() ?? '') ?? 0;
  }

  int get _returnTotal {
    var total = 0;
    for (final item in _saleItems) {
      final quantity = _quantityFor(item);
      final price = item['unit_price'] as int? ?? 0;
      total += quantity * price;
    }
    return total;
  }

  int get _minimumRefund {
    final total = _selectedSale?['total'] as int? ?? 0;
    final paid = _selectedSale?['paid'] as int? ?? 0;
    final returned = _returnSummary['returned_amount'] as int? ?? 0;
    final refunded = _returnSummary['refunded_amount'] as int? ?? 0;
    final outstanding = total - paid - returned + refunded;
    return (_returnTotal - (outstanding > 0 ? outstanding : 0))
        .clamp(0, 1 << 62).toInt();
  }

  Future<void> _submitReturn() async {
    final saleId = _selectedSaleId;
    if (saleId == null) return;
    final items = <Map<String, Object?>>[];
    for (final item in _saleItems) {
      final quantity = _quantityFor(item);
      if (quantity <= 0) continue;
      final available = item['returnable_quantity'] as int? ?? 0;
      if (quantity > available) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Jumlah retur ${item['product_name']} melebihi sisa $available.')),
        );
        return;
      }
      items.add({
        'sale_item_id': item['sale_item_id'] as int,
        'quantity': quantity,
      });
    }
    if (items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Masukkan jumlah barang yang akan diretur.')),
      );
      return;
    }

    final refund = int.tryParse(_refundController.text.replaceAll('.', '').trim()) ?? 0;
    if (refund != _minimumRefund) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Jumlah pengembalian uang yang harus dicatat adalah ${_rupiah(_minimumRefund)}.')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final id = await _returnRepository.createReturn(
        saleId: saleId,
        items: items,
        refundAmount: refund,
        notes: _notesController.text,
      );
      if (!mounted) return;
      _disposeQuantityControllers();
      setState(() {
        _selectedSaleId = null;
        _selectedSale = null;
        _saleItems = [];
        _returnSummary = const {};
        _saving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Retur berhasil disimpan (#$id). Stok dan kas sudah disesuaikan.')),
      );
      await _load();
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Retur gagal: $error')),
      );
    }
  }

  Future<void> _showReturnDetail(int id) async {
    try {
      final data = await _returnRepository.getReturnById(id);
      if (!mounted || data == null) return;
      final items = List<Map<String, Object?>>.from(data['items'] as List? ?? const []);
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Detail Retur'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(data['return_number']?.toString() ?? '-',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                Text('Nota: ${data['invoice_number'] ?? '-'}'),
                Text('Tanggal: ${_dateLabel(data['return_date'])}'),
                const Divider(),
                ...items.map((item) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      Expanded(child: Text('${item['product_name']} × ${item['quantity']}')),
                      Text(_rupiah(item['subtotal'] as int? ?? 0)),
                    ],
                  ),
                )),
                const Divider(),
                Text('Total retur: ${_rupiah(data['total_amount'] as int? ?? 0)}'),
                Text('Uang dikembalikan: ${_rupiah(data['refunded_amount'] as int? ?? 0)}'),
                if ((data['notes']?.toString() ?? '').isNotEmpty)
                  Text('Catatan: ${data['notes']}'),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Tutup')),
          ],
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal membuka detail retur: $error')),
      );
    }
  }

  Widget _createReturnCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Buat Retur Penjualan',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            DropdownButtonFormField<int>(
              value: _selectedSaleId,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Pilih nota penjualan',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: _sales.map((sale) {
                final id = sale['id'] as int;
                final invoice = sale['invoice_number']?.toString() ?? '-';
                final date = _dateLabel(sale['transaction_date']);
                return DropdownMenuItem<int>(
                  value: id,
                  child: Text('$invoice • $date', overflow: TextOverflow.ellipsis),
                );
              }).toList(),
              onChanged: _saving ? null : _selectSale,
            ),
            if (_loadingSale)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              ),
            if (_selectedSale != null && !_loadingSale) ...[
              const SizedBox(height: 8),
              Text('Total nota: ${_rupiah(_selectedSale!['total'] as int? ?? 0)}  •  Dibayar: ${_rupiah(_selectedSale!['paid'] as int? ?? 0)}',
                  style: const TextStyle(fontSize: 12)),
              const SizedBox(height: 8),
              if (_saleItems.every((item) => (item['returnable_quantity'] as int? ?? 0) <= 0))
                const Text('Semua barang pada nota ini sudah diretur.',
                    style: TextStyle(color: Colors.orange)),
              ..._saleItems.where((item) => (item['returnable_quantity'] as int? ?? 0) > 0).map((item) {
                final id = item['sale_item_id'] as int;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(item['product_name']?.toString() ?? '-',
                                style: const TextStyle(fontWeight: FontWeight.w600)),
                            Text('Terjual ${item['sold_quantity']} • Sudah retur ${item['returned_quantity']} • Sisa ${item['returnable_quantity']}',
                                style: const TextStyle(fontSize: 11, color: Colors.grey)),
                            Text(_rupiah(item['unit_price'] as int? ?? 0),
                                style: const TextStyle(fontSize: 11)),
                          ],
                        ),
                      ),
                      SizedBox(
                        width: 76,
                        child: TextField(
                          controller: _quantityControllers[id],
                          enabled: !_saving,
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.center,
                          onChanged: (_) {
                            if ((int.tryParse(_refundController.text.trim()) ?? 0) < _minimumRefund) {
                              _refundController.text = _minimumRefund.toString();
                            }
                            setState(() {});
                          },
                          decoration: const InputDecoration(
                            labelText: 'Qty',
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),
              const Divider(),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Nilai barang diretur'),
                  Text(_rupiah(_returnTotal),
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _refundController,
                enabled: !_saving,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Uang dikembalikan sekarang (Rp)',
                  helperText: 'Nominal wajib agar saldo tagihan dan kas tetap seimbang: ${_rupiah(_minimumRefund)}.',
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _notesController,
                enabled: !_saving,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Alasan/catatan retur',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _saving || _returnTotal <= 0 ? null : _submitReturn,
                  icon: _saving
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.assignment_return),
                  label: Text(_saving ? 'Menyimpan...' : 'Simpan Retur'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _returnHistory() {
    if (_returns.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: Text('Belum ada riwayat retur penjualan.')),
      );
    }
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _returns.length,
      separatorBuilder: (_, __) => const SizedBox(height: 2),
      itemBuilder: (context, index) {
        final item = _returns[index];
        return Card(
          child: ListTile(
            dense: true,
            onTap: () => _showReturnDetail(item['id'] as int),
            leading: const CircleAvatar(
              radius: 18,
              child: Icon(Icons.assignment_return, size: 19),
            ),
            title: Text(item['return_number']?.toString() ?? '-',
                style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text('Nota ${item['invoice_number']} • ${_dateLabel(item['return_date'])}'),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(_rupiah(item['total_amount'] as int? ?? 0),
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                Text('Refund ${_rupiah(item['refunded_amount'] as int? ?? 0)}',
                    style: const TextStyle(fontSize: 10, color: Colors.grey)),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Retur Penjualan'),
        actions: [
          IconButton(
            tooltip: 'Muat ulang',
            onPressed: _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 16),
                children: [
                  _createReturnCard(),
                  const SizedBox(height: 12),
                  const Text('Riwayat Retur',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  _returnHistory(),
                ],
              ),
            ),
    );
  }
}
