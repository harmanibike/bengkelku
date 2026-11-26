import 'dart:convert';
import 'dart:io';

import 'package:material_ui/material_ui.dart';

import '../../../core/formatters/currency_input_formatter.dart';
import '../data/sale_repository.dart';
import '../../customers/data/customer_repository.dart';
import '../../customers/data/customer_wallet_repository.dart';
import '../../settings/data/payment_methods_repository.dart';
import 'barcode_scanner_page.dart';
import '../../services/presentation/service_list_page.dart';
import '../../../core/widgets/app_photo_preview.dart';

class CashierPage extends StatefulWidget {
  const CashierPage({super.key});

  @override
  State<CashierPage> createState() => _CashierPageState();
}

class _CashierPageState extends State<CashierPage> {
  final SaleRepository _repository = SaleRepository();
  final CustomerRepository _customerRepository = CustomerRepository();
  final CustomerWalletRepository _walletRepository = CustomerWalletRepository();
  final PaymentMethodsRepository _paymentMethodsRepository = PaymentMethodsRepository();
  List<Map<String, String>> _paymentMethods = PaymentMethodsRepository.defaultMethods.map(Map<String, String>.from).toList();
  Map<String, String> _paymentDetails = {};
  final TextEditingController _search = TextEditingController();
  final TextEditingController _paid = TextEditingController();
  List<Map<String, Object?>> _products = [];
  final Map<int, Map<String, Object?>> _cart = {};
  bool _loading = true;
  bool _saving = false;
  int _heldCount = 0;
  String _selectedCategory = 'Semua';
  bool _cartExpanded = false;
  final TextEditingController _buyerNameForHold = TextEditingController();

  List<String> get _categories {
    final values = _products
        .map((product) => product['category']?.toString().trim() ?? '')
        .where((category) => category.isNotEmpty)
        .toSet()
        .toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return ['Semua', ...values];
  }

  List<Map<String, Object?>> get _visibleProducts {
    if (_selectedCategory == 'Semua') return _products;
    return _products
        .where((product) => product['category']?.toString() == _selectedCategory)
        .toList();
  }

  int get _total => _cart.values.fold(0, (sum, item) =>
      sum + (item['unit_price'] as int) * (item['quantity'] as int));

  int get _cartQuantity => _cart.values.fold(
        0,
        (sum, item) => sum + (item['quantity'] as int),
      );

  @override
  void initState() {
    super.initState();
    _loadProducts();
    _loadPaymentMethods();
    _loadHeldCount();
  }

  @override
  void dispose() {
    _search.dispose();
    _paid.dispose();
    _buyerNameForHold.dispose();
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
      final details = await _paymentMethodsRepository.getPaymentDetails();
      if (!mounted) return;
      setState(() { _paymentMethods = methods; _paymentDetails = details; });
    } catch (_) {
      // Metode default tetap tersedia jika pengaturan belum dapat dibaca.
    }
  }


  Future<void> _scanProductBarcode() async {
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const BarcodeScannerPage()),
    );
    if (code == null || !mounted) return;

    _search.text = code;
    try {
      final results = await _repository.getSellableProducts(keyword: code);
      if (!mounted) return;
      setState(() => _products = results);

      final normalizedCode = code.trim().toLowerCase();
      final exactMatches = results.where((product) =>
          product['barcode']?.toString().trim().toLowerCase() == normalizedCode
      ).toList();

      if (exactMatches.length == 1) {
        _addToCart(exactMatches.first);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Barcode terbaca: ${exactMatches.first['name']}')),
        );
      } else if (exactMatches.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Barcode belum terdaftar pada produk.')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Barcode digunakan lebih dari satu produk. Periksa data barcode produk.')),
        );
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal mencari barcode: $error')),
      );
    }
  }

  Future<void> _openServicePayments() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => const ServiceListPage(showOutstandingOnly: true),
      ),
    );
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
      // Pertahankan katalog tetap lega; detail keranjang dibuka saat kasir
      // mengetuk panel keranjang.
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

  Future<void> _loadHeldCount() async {
    try {
      final held = await _repository.getHeldTransactions();
      if (!mounted) return;
      setState(() => _heldCount = held.length);
    } catch (_) {}
  }

  Future<void> _holdCurrentTransaction() async {
    if (_cart.isEmpty || _saving) return;
    try {
      await _repository.holdTransaction(
        items: _cart.values.map((item) => Map<String, Object?>.from(item)).toList(),
        buyerName: _buyerNameForHold.text,
      );
      if (!mounted) return;
      setState(() {
        _cart.clear();
        _cartExpanded = false;
        _buyerNameForHold.clear();
      });
      await _loadHeldCount();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Transaksi berhasil ditahan. Silakan layani pelanggan berikutnya.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal menahan transaksi: $error')));
    }
  }

  Future<void> _showHeldTransactions() async {
    final held = await _repository.getHeldTransactions();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Transaksi Ditahan (${held.length})'),
        content: SizedBox(
          width: double.maxFinite,
          child: held.isEmpty
              ? const Text('Belum ada transaksi yang ditahan.')
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: held.length,
                  separatorBuilder: (_, __) => const Divider(),
                  itemBuilder: (context, index) {
                    final row = held[index];
                    final decoded = jsonDecode(row['items_json'].toString()) as List<dynamic>;
                    final items = decoded.cast<Map<String, dynamic>>();
                    final total = items.fold<int>(0, (sum, item) =>
                        sum + ((item['unit_price'] as num).toInt() * (item['quantity'] as num).toInt()));
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(row['buyer_name']?.toString().trim().isNotEmpty == true
                          ? row['buyer_name'].toString()
                          : 'Pelanggan Umum'),
                      subtitle: Text('${items.length} produk • ${_rupiah(total)}'),
                      trailing: IconButton(
                        tooltip: 'Hapus transaksi ditahan',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () async {
                          await _repository.deleteHeldTransaction(row['id'] as int);
                          if (!dialogContext.mounted) return;
                          Navigator.pop(dialogContext);
                          await _loadHeldCount();
                          await _showHeldTransactions();
                        },
                      ),
                      onTap: () async {
                        if (_cart.isNotEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Tahan atau selesaikan keranjang aktif terlebih dahulu.')),
                          );
                          return;
                        }
                        setState(() {
                          _cart.clear();
                          _cartExpanded = true;
                          for (final item in items) {
                            final id = (item['product_id'] as num).toInt();
                            _cart[id] = Map<String, Object?>.from(item);
                          }
                          _buyerNameForHold.text = row['buyer_name']?.toString() ?? '';
                        });
                        await _repository.deleteHeldTransaction(row['id'] as int);
                        if (!dialogContext.mounted) return;
                        Navigator.pop(dialogContext);
                        await _loadHeldCount();
                      },
                    );
                  },
                ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Tutup'))],
      ),
    );
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

  Widget _paymentInfoRow(String label, String? value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 112, child: Text(label, style: const TextStyle(color: Colors.black))),
        Expanded(child: Text(value?.isNotEmpty == true ? value! : '-', style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w600))),
      ]),
    );
  }

  Future<void> _checkout() async {
    if (_cart.isEmpty) return;
    _paid.text = formatCurrencyInput(_total);
    final paymentController = TextEditingController(text: _paid.text);
    final discountController = TextEditingController(text: '0');
    final buyerNameController = TextEditingController(text: _buyerNameForHold.text);
    try {
      var discountAmount = 0;
      Map<String, Object?>? matchedCustomer;
      var customerLookupToken = 0;
      var paymentManuallyEdited = false;
      var selectedPaymentMethod = _paymentMethods.any((method) => method['code'] == 'cash')
          ? 'cash'
          : _paymentMethods.first['code']!;
      final confirmedMethod = await showDialog<String>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (dialogContext, setDialogState) => AlertDialog(
            scrollable: true,
            title: const Text('Pembayaran'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Subtotal: ${_rupiah(_total)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                TextField(
                  controller: buyerNameController,
                  decoration: const InputDecoration(
                    labelText: 'Nama / Nomor HP pelanggan',
                    hintText: 'Ketik nama atau nomor HP',
                  ),
                  onChanged: (value) async {
                    final token = ++customerLookupToken;
                    setDialogState(() => matchedCustomer = null);
                    final match = await _customerRepository.findCustomerByNameOrPhone(value);
                    if (!dialogContext.mounted || token != customerLookupToken) return;
                    setDialogState(() {
                      matchedCustomer = match;
                      if (!paymentManuallyEdited) {
                        final payable = _total - discountAmount;
                        final wallet = (match?['wallet_balance'] as num?)?.toInt() ?? 0;
                        paymentController.text = formatCurrencyInput(payable - (wallet < payable ? wallet : payable));
                      }
                    });
                  },
                ),
                if (matchedCustomer != null) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 5),
                    child: Row(
                      children: [
                        const Icon(Icons.verified, color: Colors.green, size: 18),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Pelanggan terdeteksi: ${matchedCustomer!['name']}',
                            style: const TextStyle(color: Colors.green, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'Saldo deposit tersedia: ${_rupiah((matchedCustomer!['wallet_balance'] as num?)?.toInt() ?? 0)}',
                      style: const TextStyle(fontSize: 12, color: Colors.blueGrey),
                    ),
                  ),
                ] else if (buyerNameController.text.trim().length >= 3)
                  const Padding(
                    padding: EdgeInsets.only(top: 5),
                    child: Text(
                      'Pelanggan belum terdaftar. Transaksi tetap bisa dilanjutkan.',
                      style: TextStyle(color: Colors.black54, fontSize: 12),
                    ),
                  ),
                const SizedBox(height: 8),
                TextField(
                  controller: discountController,
                  keyboardType: TextInputType.number,
                  inputFormatters: const [CurrencyInputFormatter()],
                  decoration: const InputDecoration(labelText: 'Diskon (Rp)', hintText: 'Masukkan nominal diskon'),
                  onChanged: (value) => setDialogState(() {
                    final parsed = parseCurrencyInput(value);
                    discountAmount = parsed.clamp(0, _total).toInt();
                    final payable = _total - discountAmount;
                    final wallet = (matchedCustomer?['wallet_balance'] as num?)?.toInt() ?? 0;
                    paymentController.text = formatCurrencyInput(payable - (wallet < payable ? wallet : payable));
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
                  items: [
                    ..._paymentMethods.map((method) => DropdownMenuItem(
                      value: method['code'],
                      child: Text(method['name']!),
                    )),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(() => selectedPaymentMethod = value);
                    }
                  },
                ),
                if (selectedPaymentMethod == 'qris' || selectedPaymentMethod == 'bank_transfer') ...[
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(top: 4),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.black12), borderRadius: BorderRadius.circular(10)),
                    child: selectedPaymentMethod == 'qris'
                        ? (_paymentDetails['qris_image_path']?.isNotEmpty == true && File(_paymentDetails['qris_image_path']!).existsSync()
                            ? Column(children: [
                                const Text('Scan QRIS untuk membayar', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                                const SizedBox(height: 8),
                                Image.file(File(_paymentDetails['qris_image_path']!), height: 190, fit: BoxFit.contain),
                              ])
                            : const Text('Gambar QRIS belum diatur. Silakan isi melalui Pengaturan > Metode Pembayaran.', style: TextStyle(color: Colors.black)))
                        : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            _paymentInfoRow('Bank', _paymentDetails['bank_name']),
                            _paymentInfoRow('Nomor rekening', _paymentDetails['bank_account_number']),
                            _paymentInfoRow('Atas nama', _paymentDetails['bank_account_holder']),
                            if ((_paymentDetails['bank_account_number'] ?? '').isEmpty)
                              const Text('Nomor rekening belum diatur. Silakan isi melalui Pengaturan > Metode Pembayaran.', style: TextStyle(color: Colors.black)),
                          ]),
                  ),
                ],
                const SizedBox(height: 10),
                TextField(
                  controller: paymentController,
                  keyboardType: TextInputType.number,
                  inputFormatters: const [CurrencyInputFormatter()],
                  onChanged: (_) => paymentManuallyEdited = true,
                  decoration: InputDecoration(
                    labelText: 'Uang diterima (Rp)',
                    helperText: 'Saldo deposit pelanggan terdaftar akan digunakan otomatis terlebih dahulu.',
                    border: const OutlineInputBorder(),
                  ),
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
      final discount = parseCurrencyInput(discountController.text);
      if (discount < 0 || discount > _total) {
        throw ArgumentError('Diskon tidak boleh melebihi subtotal.');
      }
      final finalTotal = _total - discount;
      int? customerId = matchedCustomer?['id'] as int?;
      var paid = parseCurrencyInput(paymentController.text);
      if (paid < finalTotal && customerId == null) {
        customerId = await _chooseCustomer();
        if (customerId == null || !mounted) return;
      }
      var walletBalance = 0;
      if (customerId != null) {
        walletBalance = await _walletRepository.getBalance(customerId);
        if (!paymentManuallyEdited) {
          paid = finalTotal - (walletBalance < finalTotal ? walletBalance : finalTotal);
        }
      }
      final cashApplied = paid.clamp(0, finalTotal).toInt();
      final walletPayment = (finalTotal - cashApplied).clamp(0, walletBalance).toInt();
      final paymentMethodLabel = _paymentMethods.firstWhere((method) => method['code'] == confirmedMethod)['name']!;
      setState(() => _saving = true);
      final id = await _repository.checkout(
        items: _cart.values.map((item) => {
          'product_id': item['product_id'],
          'quantity': item['quantity'],
          'unit_price': item['unit_price'],
        }).toList(),
        paid: paid,
        walletPayment: walletPayment,
        paymentMethod: paymentMethodLabel,
        customerId: customerId,
        customerName: buyerNameController.text.trim().isEmpty ? 'Pelanggan Umum' : buyerNameController.text.trim(),
        discount: discount,
      );
      if (!mounted) return;
      setState(() {
        _cart.clear();
        _cartExpanded = false;
        _buyerNameForHold.clear();
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
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Card(
              margin: EdgeInsets.zero,
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: _saving ? null : _openServicePayments,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  child: Row(
                    children: [
                      Icon(Icons.build_circle_outlined, color: Theme.of(context).colorScheme.primary, size: 23),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text('Pembayaran Servis', style: TextStyle(fontWeight: FontWeight.w600)),
                      ),
                      Text('Tagihan belum lunas', style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                      const SizedBox(width: 4),
                      const Icon(Icons.chevron_right, size: 20),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: TextField(
              controller: _search,
              onChanged: (_) => _loadProducts(),
              decoration: InputDecoration(
                hintText: 'Cari nama, SKU, atau barcode',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Scan barcode dengan kamera',
                      onPressed: _saving ? null : _scanProductBarcode,
                      icon: const Icon(Icons.qr_code_scanner),
                    ),
                    IconButton(
                      tooltip: 'Hapus pencarian',
                      onPressed: () { _search.clear(); _loadProducts(); },
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                isDense: true,
                filled: true,
                fillColor: Theme.of(context).colorScheme.surface,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
              ),
            ),
          ),
          if (_categories.length > 1)
            SizedBox(
              height: 42,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
                scrollDirection: Axis.horizontal,
                itemCount: _categories.length,
                separatorBuilder: (_, __) => const SizedBox(width: 7),
                itemBuilder: (context, index) {
                  final category = _categories[index];
                  final selected = _selectedCategory == category;
                  return ChoiceChip(
                    label: Text(category, style: const TextStyle(fontSize: 12)),
                    selected: selected,
                    onSelected: (_) => setState(() => _selectedCategory = category),
                    visualDensity: VisualDensity.compact,
                    showCheckmark: false,
                  );
                },
              ),
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _products.isEmpty
                    ? const Center(child: Text('Belum ada produk aktif. Tambahkan produk terlebih dahulu.'))
                    : _visibleProducts.isEmpty
                        ? const Center(child: Text('Tidak ada produk pada kategori ini.'))
                        : LayoutBuilder(
                        builder: (context, constraints) {
                          final width = constraints.maxWidth;
                          final columns = width >= 1100
                              ? 5
                              : width >= 800
                                  ? 4
                                  : width >= 560
                                      ? 3
                                      : 2;
                          final isCompact = width < 560;
                          return GridView.builder(
                            padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                            itemCount: _visibleProducts.length,
                            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: columns,
                              crossAxisSpacing: 8,
                              mainAxisSpacing: 8,
                              childAspectRatio: isCompact ? 0.76 : 0.92,
                            ),
                            itemBuilder: (context, index) {
                              final product = _visibleProducts[index];
                              final tracked = (product['track_stock'] as int? ?? 1) == 1;
                              final stock = product['stock'] as int? ?? 0;
                              final unavailable = tracked && stock <= 0;
                              return Card(
                                clipBehavior: Clip.antiAlias,
                                margin: EdgeInsets.zero,
                                child: InkWell(
                                  onTap: unavailable ? null : () => _addToCart(product),
                                  child: Padding(
                                    padding: const EdgeInsets.all(8),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.stretch,
                                      children: [
                                        SizedBox(
                                          height: 88,
                                          child: AppPhotoPreview(
                                            path: product['image_path']?.toString(),
                                            width: double.infinity,
                                            height: 88,
                                            fit: BoxFit.cover,
                                            borderRadius: BorderRadius.circular(10),
                                            placeholderIcon: Icons.inventory_2_outlined,
                                            placeholderLabel: 'Foto produk',
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          product['name']?.toString() ?? '-',
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          _rupiah(product['selling_price'] as int? ?? 0),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: Theme.of(context).colorScheme.primary,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          tracked ? 'Stok: $stock' : 'Stok tidak dipantau',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: unavailable ? Colors.red : Colors.black54,
                                            fontSize: 11,
                                          ),
                                        ),
                                        const SizedBox(height: 5),
                                        SizedBox(
                                          height: 30,
                                          child: FilledButton.tonalIcon(
                                            onPressed: unavailable ? null : () => _addToCart(product),
                                            icon: const Icon(Icons.add_shopping_cart, size: 16),
                                            label: const Text('Tambah', style: TextStyle(fontSize: 11)),
                                            style: FilledButton.styleFrom(
                                              padding: const EdgeInsets.symmetric(horizontal: 5),
                                              visualDensity: VisualDensity.compact,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      ),
          ),
          Container(
            decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, boxShadow: const [BoxShadow(blurRadius: 8, color: Colors.black12)]),
            padding: const EdgeInsets.fromLTRB(12, 5, 12, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                InkWell(
                  onTap: () => setState(() => _cartExpanded = !_cartExpanded),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(children: [
                      const Icon(Icons.shopping_basket_outlined, size: 19),
                      const SizedBox(width: 8),
                      const Expanded(child: Text('Keranjang', style: TextStyle(fontWeight: FontWeight.bold))),
                      Text('$_cartQuantity item • ${_rupiah(_total)}',
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(width: 5),
                      Icon(_cartExpanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_up),
                    ]),
                  ),
                ),
                if (_cart.isNotEmpty && _cartExpanded) ...[
                  TextField(
                    controller: _buyerNameForHold,
                    decoration: const InputDecoration(
                      labelText: 'Nama pembeli (opsional)',
                      hintText: 'Kosongkan = Pelanggan Umum',
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    height: 96,
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
                ],
                const Divider(),
                Row(children: [
                  const Expanded(child: Text('TOTAL', style: TextStyle(fontWeight: FontWeight.bold))),
                  Text(_rupiah(_total), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                ]),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _saving ? null : _showHeldTransactions,
                        icon: const Icon(Icons.pause_circle_outline),
                        label: Text('Ditahan ($_heldCount)'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _cart.isEmpty || _saving ? null : _holdCurrentTransaction,
                        icon: const Icon(Icons.pause),
                        label: const Text('Tahan Transaksi'),
                      ),
                    ),
                  ],
                ),
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
