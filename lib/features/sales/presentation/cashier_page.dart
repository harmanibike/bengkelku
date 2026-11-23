import 'dart:io';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../data/sale_repository.dart';
import '../../customers/data/customer_repository.dart';
import '../../settings/data/payment_methods_repository.dart';

class CashierPage extends StatefulWidget {
  const CashierPage({super.key});

  @override
  State<CashierPage> createState() => _CashierPageState();
}

class _CashierPageState extends State<CashierPage> {
  final SaleRepository _repository = SaleRepository();
  final CustomerRepository _customerRepository = CustomerRepository();
  final PaymentMethodsRepository _paymentMethodsRepository = PaymentMethodsRepository();
  List<Map<String, String>> _paymentMethods = PaymentMethodsRepository.defaultMethods.map(Map<String, String>.from).toList();
  final TextEditingController _search = TextEditingController();
  final TextEditingController _paid = TextEditingController();
  List<Map<String, Object?>> _products = [];
  final Map<int, Map<String, Object?>> _cart = {};
  bool _loading = true;
  bool _saving = false;

  int get _total => _cart.values.fold(0, (sum, item) =>
      sum + (item['unit_price'] as int) * (item['quantity'] as int));

  @override
  void initState() {
    super.initState();
    _loadProducts();
    _loadPaymentMethods();
  }

  @override
  void dispose() {
    _search.dispose();
    _paid.dispose();
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

  Future<void> _loadPaymentMethods() async {
    try {
      final methods = await _paymentMethodsRepository.getMethods();
      if (!mounted) return;
      setState(() => _paymentMethods = methods);
    } catch (_) {
      // Metode default tetap tersedia jika pengaturan belum dapat dibaca.
    }
  }

  Future<void> _loadProducts() async {
    setState(() => _loading = true);
    try {
      final result = await _repository.getSellableProducts(keyword: _search.text);
      if (!mounted) return;
      setState(() {
        _products = result;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal memuat produk: $error')));
    }
  }

  void _addToCart(Map<String, Object?> product) {
    final id = product['id'] as int;
    final tracked = (product['track_stock'] as int? ?? 1) == 1;
    final stock = product['stock'] as int? ?? 0;
    final current = _cart[id]?['quantity'] as int? ?? 0;
    if (tracked && current >= stock) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Stok tidak mencukupi.')));
      return;
    }
    setState(() {
      final price = product['selling_price'] as int? ?? 0;
      _cart[id] = {
        'product_id': id,
        'name': product['name']?.toString() ?? '-',
        'unit': product['unit']?.toString() ?? 'pcs',
        'unit_price': _cart[id]?['unit_price'] ?? price,
        'quantity': current + 1,
        'stock': stock,
        'track_stock': tracked,
      };
    });
  }

  void _changeQuantity(int id, int delta) {
    final item = _cart[id];
    if (item == null) return;
    final next = (item['quantity'] as int) + delta;
    final stock = item['stock'] as int;
    if (next <= 0) {
      setState(() => _cart.remove(id));
    } else if (item['track_stock'] == true && next > stock) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Jumlah melebihi stok.')));
    } else {
      setState(() => item['quantity'] = next);
    }
  }

  Future<int?> _chooseCustomer() async {
    final customers = await _customerRepository.getCustomers();
    if (!mounted) return null;
    return showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Pilih pelanggan untuk piutang'),
        content: SizedBox(
          width: double.maxFinite,
          child: customers.isEmpty
              ? const Text('Belum ada data pelanggan. Tambahkan pelanggan terlebih dahulu.')
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: customers.length,
                  itemBuilder: (context, index) {
                    final customer = customers[index];
                    return ListTile(
                      title: Text(customer['name']?.toString() ?? '-'),
                      subtitle: Text(customer['phone']?.toString() ?? 'Tanpa nomor WhatsApp'),
                      onTap: () => Navigator.pop(dialogContext, customer['id'] as int),
                    );
                  },
                ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Batal'))],
      ),
    );
  }

  Future<void> _checkout() async {
    if (_cart.isEmpty) return;
    _paid.text = _total.toString();
    final paymentController = TextEditingController(text: _paid.text);
    final discountController = TextEditingController(text: '0');
    final buyerNameController = TextEditingController();
    try {
      var discountAmount = 0;
      var selectedPaymentMethod = _paymentMethods.any((method) => method['code'] == 'cash')
          ? 'cash'
          : _paymentMethods.first['code']!;
      final confirmedMethod = await showDialog<String>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (dialogContext, setDialogState) => AlertDialog(
            title: const Text('Pembayaran'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Subtotal: ${_rupiah(_total)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                TextField(
                  controller: buyerNameController,
                  decoration: const InputDecoration(labelText: 'Nama pembeli (opsional)', hintText: 'Kosongkan = Pelanggan Umum'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: discountController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(labelText: 'Diskon (Rp)', hintText: 'Masukkan nominal diskon'),
                  onChanged: (value) => setDialogState(() {
                    final parsed = int.tryParse(value) ?? 0;
                    discountAmount = parsed.clamp(0, _total).toInt();
                    final payable = _total - discountAmount;
                    paymentController.text = payable.toString();
                  }),
                ),
                const SizedBox(height: 8),
                Text('Total setelah diskon: ${_rupiah(_total - discountAmount)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: selectedPaymentMethod,
                  decoration: const InputDecoration(
                    labelText: 'Metode pembayaran',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: _paymentMethods.map((method) => DropdownMenuItem(
                    value: method['code'],
                    child: Text(method['name']!),
                  )).toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(() => selectedPaymentMethod = value);
                    }
                  },
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: paymentController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(labelText: 'Uang diterima (Rp)', border: OutlineInputBorder()),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Batal')),
              FilledButton(onPressed: () => Navigator.pop(dialogContext, selectedPaymentMethod), child: const Text('Lanjut')),
            ],
          ),
        ),
      );
      if (confirmedMethod == null || !mounted) return;
      final discount = int.tryParse(discountController.text) ?? 0;
      if (discount < 0 || discount > _total) {
        throw ArgumentError('Diskon tidak boleh melebihi subtotal.');
      }
      final finalTotal = _total - discount;
      final paid = int.tryParse(paymentController.text) ?? 0;
      final paymentMethodLabel = _paymentMethods.firstWhere(
        (method) => method['code'] == confirmedMethod,
      )['name']!;
      int? customerId;
      if (paid < finalTotal) {
        customerId = await _chooseCustomer();
        if (customerId == null || !mounted) return;
      }
      setState(() => _saving = true);
      final id = await _repository.checkout(
        items: _cart.values.map((item) => {
          'product_id': item['product_id'],
          'quantity': item['quantity'],
          'unit_price': item['unit_price'],
        }).toList(),
        paid: paid,
        paymentMethod: paymentMethodLabel,
        customerId: customerId,
        customerName: buyerNameController.text.trim().isEmpty ? 'Pelanggan Umum' : buyerNameController.text.trim(),
        discount: discount,
      );
      if (!mounted) return;
      setState(() {
        _cart.clear();
        _saving = false;
      });
      await _loadProducts();
      if (!mounted) return;
      final sale = await _repository.getSaleById(id);
      if (!mounted) return;
      showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Transaksi Berhasil'),
          content: Text('No. Invoice: ${sale?['invoice_number']}\nTotal: ${_rupiah(sale?['total'] as int? ?? 0)}\nKembalian: ${_rupiah(sale?['change_amount'] as int? ?? 0)}'),
          actions: [FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Selesai'))],
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Transaksi gagal: $error')));
    } finally {
      paymentController.dispose();
      discountController.dispose();
      buyerNameController.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Kasir')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _search,
              onChanged: (_) => _loadProducts(),
              decoration: InputDecoration(
                hintText: 'Cari produk / SKU / barcode',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(onPressed: () { _search.clear(); _loadProducts(); }, icon: const Icon(Icons.close)),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _products.isEmpty
                    ? const Center(child: Text('Belum ada produk aktif. Tambahkan produk terlebih dahulu.'))
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        itemCount: _products.length,
                        itemBuilder: (context, index) {
                          final product = _products[index];
                          final tracked = (product['track_stock'] as int? ?? 1) == 1;
                          final stock = product['stock'] as int? ?? 0;
                          return Card(
                            child: ListTile(
                              leading: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: SizedBox(
                                  width: 52,
                                  height: 52,
                                  child: product['image_path'] != null && product['image_path'].toString().isNotEmpty
                                      ? Image.file(File(product['image_path'].toString()), fit: BoxFit.cover,
                                          errorBuilder: (_, __, ___) => const Icon(Icons.inventory_2_outlined))
                                      : const Icon(Icons.inventory_2_outlined),
                                ),
                              ),
                              title: Text(product['name']?.toString() ?? '-'),
                              subtitle: Text('${_rupiah(product['selling_price'] as int? ?? 0)} • ${tracked ? 'Stok: $stock' : 'Stok tidak dipantau'}'),
                              trailing: IconButton(
                                tooltip: 'Tambah ke keranjang',
                                onPressed: tracked && stock <= 0 ? null : () => _addToCart(product),
                                icon: const Icon(Icons.add_shopping_cart),
                              ),
                            ),
                          );
                        },
                      ),
          ),
          Container(
            decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, boxShadow: const [BoxShadow(blurRadius: 8, color: Colors.black12)]),
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(children: [
                  const Expanded(child: Text('Keranjang', style: TextStyle(fontWeight: FontWeight.bold))),
                  Text('${_cart.length} produk'),
                ]),
                if (_cart.isNotEmpty)
                  SizedBox(
                    height: 116,
                    child: ListView(
                      children: _cart.entries.map((entry) {
                        final item = entry.value;
                        return ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(item['name'].toString()),
                          subtitle: Text('${_rupiah(item['unit_price'] as int)} × ${item['quantity']}'),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(onPressed: () => _changeQuantity(entry.key, -1), icon: const Icon(Icons.remove_circle_outline)),
                              Text(item['quantity'].toString()),
                              IconButton(onPressed: () => _changeQuantity(entry.key, 1), icon: const Icon(Icons.add_circle_outline)),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                const Divider(),
                Row(children: [
                  const Expanded(child: Text('TOTAL', style: TextStyle(fontWeight: FontWeight.bold))),
                  Text(_rupiah(_total), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                ]),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _cart.isEmpty || _saving ? null : _checkout,
                    icon: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.payments_outlined),
                    label: Text(_saving ? 'Memproses...' : 'Bayar Sekarang'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
