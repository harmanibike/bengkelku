import 'package:material_ui/material_ui.dart';

import '../../../core/formatters/currency_input_formatter.dart';

import '../../products/data/product_repository.dart';
import '../data/purchase_repository.dart';
import '../data/supplier_repository.dart';
import 'suppliers_page.dart';
import 'purchase_returns_page.dart';
import 'supplier_debts_page.dart';

class PurchasesPage extends StatefulWidget {
  const PurchasesPage({super.key});

  @override
  State<PurchasesPage> createState() => _PurchasesPageState();
}

class _PurchasesPageState extends State<PurchasesPage> {
  final _purchases = PurchaseRepository();
  final _suppliers = SupplierRepository();
  final _products = ProductRepository();
  final _search = TextEditingController();
  late Future<List<Map<String, Object?>>> _future;

  @override
  void initState() {
    super.initState();
    _future = _purchases.getPurchases();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  String _money(Object? value) {
    final amount = value is num ? value.toInt() : 0;
    final digits = amount.toString();
    final out = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) out.write('.');
      out.write(digits[i]);
    }
    return 'Rp$out';
  }

  Future<void> _reload() async {
    final next = _purchases.getPurchases(keyword: _search.text);
    setState(() => _future = next);
    await next;
  }

  Future<void> _createPurchase() async {
    final suppliers = await _suppliers.getSuppliers();
    final products = await _products.getProducts();
    if (!mounted) return;
    if (suppliers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tambahkan data pemasok terlebih dahulu.')),
      );
      return;
    }
    if (products.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tambahkan produk terlebih dahulu.')),
      );
      return;
    }
    final invoice = TextEditingController(text: 'PB-${DateTime.now().millisecondsSinceEpoch}');
    final discount = TextEditingController(text: '0');
    final shipping = TextEditingController(text: '0');
    final packing = TextEditingController(text: '0');
    final insurance = TextEditingController(text: '0');
    final marketplaceFee = TextEditingController(text: '0');
    final transferFee = TextEditingController(text: '0');
    final otherFee = TextEditingController(text: '0');
    final marketplace = TextEditingController();
    final orderNumber = TextEditingController();
    final trackingNumber = TextEditingController();
    final payment = TextEditingController(text: '0');
    final notes = TextEditingController();
    int? supplierId = suppliers.first['id'] as int;
    int? productId = products.first['id'] as int;
    var variants = (await _products.getProductVariants(productId)).where((item) => (item['is_active'] as int? ?? 1) == 1).toList();
    int? variantId = variants.isEmpty ? null : variants.first['id'] as int;
    final qty = TextEditingController(text: '1');
    final cost = TextEditingController(text: formatCurrencyInput(variants.isEmpty ? products.first['purchase_price'] ?? 0 : variants.first['purchase_price'] ?? 0));
    final items = <Map<String, Object?>>[];
    String purchaseType = 'direct';
    String paymentMethod = 'Tunai';
    String? errorText;

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final totalItems = items.fold<int>(0, (sum, item) => sum + (item['subtotal'] as int));
          final totalFees = [shipping, packing, insurance, marketplaceFee, transferFee, otherFee]
              .fold<int>(0, (sum, controller) => sum + parseCurrencyInput(controller.text));
          final grandTotal = totalItems - parseCurrencyInput(discount.text) + totalFees;
          return AlertDialog(
            title: const Text('Pembelian Baru'),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: purchaseType,
                      decoration: const InputDecoration(labelText: 'Jenis pembelian', border: OutlineInputBorder()),
                      items: const [
                        DropdownMenuItem(value: 'direct', child: Text('Pembelian langsung')),
                        DropdownMenuItem(value: 'online', child: Text('Pembelian online')),
                      ],
                      onChanged: (value) => setDialogState(() => purchaseType = value ?? 'direct'),
                    ),
                    const SizedBox(height: 8),
                    if (purchaseType == 'online') ...[
                      TextField(controller: marketplace, decoration: const InputDecoration(labelText: 'Marketplace / nama toko online *', border: OutlineInputBorder())),
                      const SizedBox(height: 8),
                      TextField(controller: orderNumber, decoration: const InputDecoration(labelText: 'Nomor pesanan', border: OutlineInputBorder())),
                      const SizedBox(height: 8),
                      TextField(controller: trackingNumber, decoration: const InputDecoration(labelText: 'Nomor resi / tracking', border: OutlineInputBorder())),
                      const SizedBox(height: 8),
                    ],
                    TextField(controller: invoice, decoration: const InputDecoration(labelText: 'Nomor faktur *', border: const OutlineInputBorder())),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<int>(
                      initialValue: supplierId,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Pemasok *', border: const OutlineInputBorder()),
                      items: suppliers.map((s) => DropdownMenuItem<int>(
                        value: s['id'] as int,
                        child: Text(s['name'] as String? ?? '-'),
                      )).toList(),
                      onChanged: (v) => setDialogState(() => supplierId = v),
                    ),
                    const SizedBox(height: 8),
                    const Text('Tambah barang', style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    DropdownButtonFormField<int>(
                      initialValue: productId,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Produk', border: const OutlineInputBorder()),
                      items: products.map((p) => DropdownMenuItem<int>(
                        value: p['id'] as int,
                        child: Text(p['name'] as String? ?? '-', overflow: TextOverflow.ellipsis),
                      )).toList(),
                      onChanged: (v) async {
                        if (v == null) return;
                        final nextVariants = await _products.getProductVariants(v);
                        if (!context.mounted) return;
                        setDialogState(() {
                          productId = v;
                          variants = nextVariants.where((item) => (item['is_active'] as int? ?? 1) == 1).toList();
                          variantId = variants.isEmpty ? null : variants.first['id'] as int;
                          final selected = products.firstWhere((p) => p['id'] == v);
                          final selectedVariant = variants.isEmpty ? null : variants.first;
                          cost.text = formatCurrencyInput(selectedVariant?['purchase_price'] ?? selected['purchase_price'] ?? 0);
                        });
                      },
                    ),
                    if (variants.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      DropdownButtonFormField<int>(
                        initialValue: variantId,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Varian produk', border: const OutlineInputBorder()),
                        items: variants.map((v) => DropdownMenuItem<int>(
                          value: v['id'] as int,
                          child: Text(v['name']?.toString() ?? '-', overflow: TextOverflow.ellipsis),
                        )).toList(),
                        onChanged: (v) {
                          setDialogState(() {
                            variantId = v;
                            final selected = variants.firstWhere((item) => item['id'] == v);
                            cost.text = formatCurrencyInput(selected['purchase_price'] ?? 0);
                          });
                        },
                      ),
                    ],
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(child: TextField(controller: qty, keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Jumlah', border: const OutlineInputBorder()))),
                        const SizedBox(width: 8),
                        Expanded(child: TextField(controller: cost, keyboardType: TextInputType.number, inputFormatters: const [CurrencyInputFormatter()],
                          decoration: const InputDecoration(labelText: 'Harga beli', border: const OutlineInputBorder()))),
                        IconButton(
                          tooltip: 'Tambahkan barang',
                          onPressed: () {
                            final product = products.firstWhere((p) => p['id'] == productId);
                            final matches = variants.where((v) => v['id'] == variantId).toList();
                            final selectedVariant = matches.isEmpty ? null : matches.first;
                            final q = int.tryParse(qty.text) ?? 0;
                            final price = cost.text.trim().isEmpty ? -1 : parseCurrencyInput(cost.text);
                            if (q <= 0 || price < 0 || (variants.isNotEmpty && selectedVariant == null)) {
                              setDialogState(() => errorText = 'Pilih varian, jumlah, dan harga beli yang valid.');
                              return;
                            }
                            final displayName = selectedVariant == null
                                ? product['name'] as String
                                : '${product['name']} - ${selectedVariant['name']}';
                            final existing = items.indexWhere((i) =>
                                i['product_id'] == productId && i['variant_id'] == variantId);
                            if (existing >= 0) {
                              final old = items[existing];
                              final nextQty = (old['quantity'] as int) + q;
                              old['quantity'] = nextQty;
                              old['unit_cost'] = price;
                              old['subtotal'] = nextQty * price;
                            } else {
                              items.add({
                                'product_id': productId,
                                'variant_id': variantId,
                                'product_name': displayName,
                                'quantity': q,
                                'unit_cost': price,
                                'discount': 0,
                                'subtotal': q * price,
                              });
                            }
                            errorText = null;
                            setDialogState(() {});
                          },
                          icon: const Icon(Icons.add_circle_outline),
                        ),
                      ],
                    ),
                    if (items.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      ...items.asMap().entries.map((entry) {
                        final item = entry.value;
                        return ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(item['product_name'] as String, style: const TextStyle(fontSize: 13)),
                          subtitle: Text('${item['quantity']} × ${_money(item['unit_cost'])}'),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(_money(item['subtotal'])),
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                onPressed: () => setDialogState(() => items.removeAt(entry.key)),
                                icon: const Icon(Icons.close, size: 18),
                              ),
                            ],
                          ),
                        );
                      }),
                    ],
                    const Divider(),
                    const Text('Biaya tambahan pembelian', style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    for (final entry in <MapEntry<String, TextEditingController>>[
                      MapEntry('Ongkos kirim', shipping),
                      MapEntry('Packing', packing),
                      MapEntry('Asuransi', insurance),
                      MapEntry('Admin marketplace', marketplaceFee),
                      MapEntry('Biaya transfer', transferFee),
                      MapEntry('Biaya lainnya', otherFee),
                    ]) ...[
                      TextField(controller: entry.value, keyboardType: TextInputType.number,
                        inputFormatters: const [CurrencyInputFormatter()],
                        decoration: InputDecoration(labelText: entry.key, border: const OutlineInputBorder(), isDense: true)),
                      const SizedBox(height: 6),
                    ],
                    TextField(controller: discount, keyboardType: TextInputType.number, inputFormatters: const [CurrencyInputFormatter()],
                      decoration: const InputDecoration(labelText: 'Diskon pembelian', border: const OutlineInputBorder())),
                    const SizedBox(height: 8),
                    Text('Total termasuk biaya tambahan: ${_money(grandTotal)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      initialValue: paymentMethod,
                      decoration: const InputDecoration(labelText: 'Metode pembayaran', border: OutlineInputBorder()),
                      items: const [
                        DropdownMenuItem(value: 'Tunai', child: Text('Tunai')),
                        DropdownMenuItem(value: 'Transfer Bank', child: Text('Transfer Bank')),
                      ],
                      onChanged: (value) => setDialogState(() => paymentMethod = value ?? 'Tunai'),
                    ),
                    const SizedBox(height: 8),
                    TextField(controller: payment, keyboardType: TextInputType.number, inputFormatters: const [CurrencyInputFormatter()],
                      decoration: const InputDecoration(labelText: 'Pembayaran awal', border: const OutlineInputBorder())),
                    const SizedBox(height: 8),
                    TextField(controller: notes, maxLines: 2,
                      decoration: const InputDecoration(labelText: 'Catatan', border: const OutlineInputBorder())),
                    if (errorText != null)
                      Padding(padding: const EdgeInsets.only(top: 8),
                        child: Text(errorText!, style: const TextStyle(color: Colors.red, fontSize: 12))),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Batal')),
              FilledButton(
                onPressed: () {
                  final d = discount.text.trim().isEmpty ? -1 : parseCurrencyInput(discount.text);
                  final paid = payment.text.trim().isEmpty ? -1 : parseCurrencyInput(payment.text);
                  if (invoice.text.trim().isEmpty || supplierId == null || items.isEmpty ||
                      (purchaseType == 'online' && marketplace.text.trim().isEmpty) ||
                      d < 0 || paid < 0 || d > totalItems || paid > totalItems - d + totalFees) {
                    setDialogState(() => errorText = 'Periksa faktur, barang, diskon, dan pembayaran.');
                    return;
                  }
                  Navigator.pop(dialogContext, true);
                },
                child: const Text('Simpan Pembelian'),
              ),
            ],
          );
        },
      ),
    );

    if (saved == true && mounted) {
      try {
        await _purchases.createPurchase(
          invoiceNumber: invoice.text,
          supplierId: supplierId!,
          items: items,
          discount: parseCurrencyInput(discount.text),
          purchaseType: purchaseType,
          marketplace: marketplace.text,
          orderNumber: orderNumber.text,
          trackingNumber: trackingNumber.text,
          shippingFee: parseCurrencyInput(shipping.text),
          packingFee: parseCurrencyInput(packing.text),
          insuranceFee: parseCurrencyInput(insurance.text),
          marketplaceFee: parseCurrencyInput(marketplaceFee.text),
          transferFee: parseCurrencyInput(transferFee.text),
          otherFee: parseCurrencyInput(otherFee.text),
          initialPayment: int.parse(payment.text),
          paymentMethod: paymentMethod,
          notes: notes.text,
        );
        await _reload();
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Pembelian berhasil disimpan dan stok diperbarui.')),
        );
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal menyimpan pembelian: $e')),
        );
      }
    }
    invoice.dispose();
    discount.dispose();
    shipping.dispose();
    packing.dispose();
    insurance.dispose();
    marketplaceFee.dispose();
    transferFee.dispose();
    otherFee.dispose();
    marketplace.dispose();
    orderNumber.dispose();
    trackingNumber.dispose();
    payment.dispose();
    notes.dispose();
    qty.dispose();
    cost.dispose();
  }

  Future<void> _cancelPurchase(Map<String, Object?> row) async {
    if (row['status']?.toString() == 'cancelled') return;
    final reasonController = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Batalkan Pembelian'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Faktur: ${row['invoice_number']}'),
            const SizedBox(height: 8),
            const Text(
              'Pembatalan hanya diproses jika belum ada pembayaran, kredit/retur aktif, dan seluruh stok dari faktur masih tersedia. Riwayat faktur tidak dihapus.',
              style: TextStyle(fontSize: 11, color: Colors.grey),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: reasonController,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Alasan pembatalan *',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Kembali')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              final value = reasonController.text.trim();
              if (value.isNotEmpty) Navigator.pop(dialogContext, value);
            },
            child: const Text('Batalkan Faktur'),
          ),
        ],
      ),
    );
    reasonController.dispose();
    if (reason == null || !mounted) return;
    try {
      await _purchases.cancelPurchase(
        purchaseId: row['id'] as int,
        reason: reason,
      );
      await _reload();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Faktur dibatalkan dan stok telah dikoreksi.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Pembatalan ditolak: $error')),
        );
      }
    }
  }

  Future<void> _showDetails(Map<String, Object?> row) async {
    final id = row['id'] as int;
    final results = await Future.wait([
      _purchases.getPurchaseItems(id),
      _purchases.getPurchasePayments(id),
    ]);
    if (!mounted) return;
    final items = results[0];
    final payments = results[1];
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Faktur ${row['invoice_number']}'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Pemasok: ${row['supplier_name'] ?? '-'}'),
                Text('Jenis: ${row['purchase_type'] == 'online' ? 'Online' : 'Langsung'}'),
                if (row['purchase_type'] == 'online') ...[
                  Text('Marketplace: ${row['marketplace'] ?? '-'}'),
                  Text('Nomor pesanan: ${row['order_number'] ?? '-'}'),
                  Text('Resi: ${row['tracking_number'] ?? '-'}'),
                ],
                if (row['status']?.toString() == 'cancelled')
                  Text('DIBATALKAN • ${row['cancel_reason'] ?? '-'}', style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w600, fontSize: 11)),
                const SizedBox(height: 8),
                const Text('Barang dibeli', style: TextStyle(fontWeight: FontWeight.w600)),
                ...items.map((item) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Expanded(child: Text('${item['product_name']} × ${item['quantity']}', style: const TextStyle(fontSize: 12))),
                      Text(_money(item['subtotal']), style: const TextStyle(fontSize: 12)),
                    ],
                  ),
                )),
                const Divider(),
                _detailRow('Subtotal', row['subtotal']),
                _detailRow('Diskon', row['discount']),
                _detailRow('Ongkos kirim', row['shipping_fee']),
                _detailRow('Packing', row['packing_fee']),
                _detailRow('Asuransi', row['insurance_fee']),
                _detailRow('Admin marketplace', row['marketplace_fee']),
                _detailRow('Biaya transfer', row['transfer_fee']),
                _detailRow('Biaya lainnya', row['other_fee']),
                _detailRow('Total', row['total']),
                _detailRow('Dibayar', row['paid']),
                _detailRow('Kredit retur', row['return_credit']),
                _detailRow('Sisa utang', ((row['total'] as int? ?? 0) - (row['paid'] as int? ?? 0) - (row['return_credit'] as int? ?? 0)).clamp(0, 1 << 62)),
                const Divider(),
                const Text('Riwayat pembayaran', style: TextStyle(fontWeight: FontWeight.w600)),
                if (payments.isEmpty)
                  const Padding(padding: EdgeInsets.symmetric(vertical: 6), child: Text('Belum ada pembayaran.', style: TextStyle(fontSize: 12)))
                else
                  ...payments.map((payment) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: [
                        Expanded(child: Text(payment['payment_date'] as String? ?? '-', style: const TextStyle(fontSize: 11))),
                        Text(_money(payment['amount']), style: const TextStyle(fontSize: 12)),
                      ],
                    ),
                  )),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Tutup')),
          if (row['status']?.toString() != 'cancelled')
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                _cancelPurchase(row);
              },
              child: const Text('Batalkan', style: TextStyle(color: Colors.red)),
            ),
          if (row['status']?.toString() != 'cancelled' && (row['total'] as int? ?? 0) > (row['paid'] as int? ?? 0) + (row['return_credit'] as int? ?? 0))
            FilledButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                _addPayment(row);
              },
              child: const Text('Bayar Utang'),
            ),
        ],
      ),
    );
  }

  Widget _detailRow(String label, Object? amount) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 12)),
        Text(_money(amount), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
      ],
    ),
  );

  Future<void> _addPayment(Map<String, Object?> row) async {
    final total = row['total'] as int? ?? 0;
    final paid = row['paid'] as int? ?? 0;
    final returnCredit = row['return_credit'] as int? ?? 0;
    final remaining = total - paid - returnCredit;
    final amount = TextEditingController(text: formatCurrencyInput(remaining));
    final value = await showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Bayar Utang Pemasok'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Faktur: ${row['invoice_number']}'),
            Text('Sisa utang: ${_money(remaining)}'),
            const SizedBox(height: 8),
            TextField(controller: amount, keyboardType: TextInputType.number, inputFormatters: const [CurrencyInputFormatter()],
              decoration: const InputDecoration(labelText: 'Jumlah pembayaran', border: const OutlineInputBorder())),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Batal')),
          FilledButton(onPressed: () {
            final n = parseCurrencyInput(amount.text);
            if (n > 0 && n <= remaining) Navigator.pop(dialogContext, n);
          }, child: const Text('Simpan')),
        ],
      ),
    );
    if (value != null && mounted) {
      try {
        await _purchases.addPayment(purchaseId: row['id'] as int, amount: value, paymentMethod: 'Tunai');
        await _reload();
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Pembayaran gagal: $e')));
      }
    }
    amount.dispose();
  }

  void _openSuppliers() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const SuppliersPage()));
  }

  void _openPurchaseReturns() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const PurchaseReturnsPage()));
  }

  void _openSupplierDebts() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const SupplierDebtsPage()));
  }

  Widget _purchaseMenuTile({
    required String title,
    required IconData icon,
    required List<Color> colors,
    required VoidCallback onTap,
  }) {
    final accent = colors.first;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: accent, size: 25),
              ),
              const SizedBox(height: 7),
              Text(
                title,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  height: 1.2,
                  fontWeight: FontWeight.w600,
                ),
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
        title: const Text('Pembelian Barang'),
        actions: [
          IconButton(onPressed: _reload, icon: const Icon(Icons.refresh)),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createPurchase,
        icon: const Icon(Icons.add_shopping_cart),
        label: const Text('Pembelian'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Menu Pembelian', style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.bold,
                )),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: _purchaseMenuTile(
                      title: 'Pemasok',
                      icon: Icons.local_shipping_outlined,
                      colors: const [Color(0xFF546E7A), Color(0xFF90A4AE)],
                      onTap: _openSuppliers,
                    )),
                    Expanded(child: _purchaseMenuTile(
                      title: 'Retur Beli',
                      icon: Icons.assignment_return_outlined,
                      colors: const [Color(0xFFEF6C00), Color(0xFFFFB74D)],
                      onTap: _openPurchaseReturns,
                    )),
                    Expanded(child: _purchaseMenuTile(
                      title: 'Hutang Pemasok',
                      icon: Icons.account_balance_wallet_outlined,
                      colors: const [Color(0xFFE65100), Color(0xFFFFB74D)],
                      onTap: _openSupplierDebts,
                    )),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: TextField(
              controller: _search,
              onChanged: (_) => _reload(),
              decoration: InputDecoration(
                hintText: 'Cari faktur atau pemasok',
                prefixIcon: const Icon(Icons.search, size: 20),
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
                if (snapshot.hasError) return Center(child: Text('Gagal memuat pembelian: ${snapshot.error}'));
                final rows = snapshot.data ?? [];
                if (rows.isEmpty) return const Center(child: Text('Belum ada transaksi pembelian.'));
                return RefreshIndicator(
                  onRefresh: _reload,
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 88),
                    itemCount: rows.length,
                    itemBuilder: (context, index) {
                      final row = rows[index];
                      final total = row['total'] as int? ?? 0;
                      final paid = row['paid'] as int? ?? 0;
                      final returnCredit = row['return_credit'] as int? ?? 0;
                      final remaining = total - paid - returnCredit;
                      final status = row['payment_status'] as String? ?? 'unpaid';
                      final cancelled = row['status']?.toString() == 'cancelled';
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          dense: true,
                          onTap: () => _showDetails(row),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          leading: CircleAvatar(
                            radius: 19,
                            backgroundColor: const Color(0xFFE8EEFF),
                            child: const Icon(Icons.inventory_2_outlined, color: Color(0xFF3157B7), size: 20),
                          ),
                          title: Text(row['invoice_number'] as String? ?? '-', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 3),
                            child: Text('${row['purchase_type'] == 'online' ? 'Online' : 'Langsung'} • ${row['supplier_name'] ?? 'Pemasok'} • Dibayar ${_money(paid)} • Sisa ${_money(remaining)}',
                              maxLines: 2, style: const TextStyle(fontSize: 11)),
                          ),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(_money(total), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                              Text(cancelled ? 'Dibatalkan' : status == 'paid' ? 'Lunas' : status == 'partial' ? 'Sebagian' : 'Belum lunas',
                                style: TextStyle(fontSize: 10, color: cancelled ? Colors.red : status == 'paid' ? Colors.green : Colors.orange)),
                              if (!cancelled && remaining > 0)
                                InkWell(onTap: () => _addPayment(row),
                                  child: const Text('Bayar', style: TextStyle(fontSize: 11, color: Color(0xFF3157B7), fontWeight: FontWeight.w600))),
                            ],
                          ),
                        ),
                      );
                    },
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
