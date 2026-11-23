import 'package:material_ui/material_ui.dart';

import '../../../core/formatters/currency_input_formatter.dart';

import '../data/customer_wallet_repository.dart';

class CustomerWalletPage extends StatefulWidget {
  const CustomerWalletPage({super.key, required this.customerId, required this.customerName});

  final int customerId;
  final String customerName;

  @override
  State<CustomerWalletPage> createState() => _CustomerWalletPageState();
}

class _CustomerWalletPageState extends State<CustomerWalletPage> {
  final CustomerWalletRepository _repository = CustomerWalletRepository();
  bool _loading = true;
  int _balance = 0;
  List<Map<String, Object?>> _entries = const [];

  String _rupiah(Object? value) {
    final amount = (value as num?)?.toInt() ?? 0;
    final digits = amount.abs().toString();
    final out = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) out.write('.');
      out.write(digits[i]);
    }
    return 'Rp${amount < 0 ? '-' : ''}$out';
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final balance = await _repository.getBalance(widget.customerId);
      final entries = await _repository.getLedger(widget.customerId);
      if (!mounted) return;
      setState(() { _balance = balance; _entries = entries; _loading = false; });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal memuat saldo: $error')));
    }
  }

  Future<void> _deposit() async {
    final amountController = TextEditingController();
    final noteController = TextEditingController();
    String method = 'cash';
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Tambah Deposit'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: amountController,
              keyboardType: TextInputType.number,
              inputFormatters: const [CurrencyInputFormatter()],
              decoration: const InputDecoration(labelText: 'Nominal deposit (Rp)', border: OutlineInputBorder(), prefixText: 'Rp '),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: method,
              decoration: const InputDecoration(labelText: 'Metode pembayaran', border: OutlineInputBorder()),
              items: const [
                DropdownMenuItem(value: 'cash', child: Text('Tunai')),
                DropdownMenuItem(value: 'transfer', child: Text('Transfer')),
                DropdownMenuItem(value: 'qris', child: Text('QRIS')),
              ],
              onChanged: (value) => setDialogState(() => method = value ?? 'cash'),
            ),
            const SizedBox(height: 10),
            TextField(controller: noteController, decoration: const InputDecoration(labelText: 'Catatan (opsional)', border: OutlineInputBorder())),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Batal')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Simpan deposit')),
          ],
        ),
      ),
    );
    final amount = int.tryParse(amountController.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
    final note = noteController.text.trim();
    amountController.dispose();
    noteController.dispose();
    if (result != true) return;
    if (amount <= 0) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nominal deposit harus lebih dari nol.')));
      return;
    }
    try {
      await _repository.addDeposit(customerId: widget.customerId, amount: amount, paymentMethod: method, note: note);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Deposit pelanggan berhasil dicatat.')));
      _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal menyimpan deposit: $error')));
    }
  }

  Future<void> _withdraw() async {
    if (_balance <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saldo pelanggan masih kosong.')));
      return;
    }
    final amountController = TextEditingController();
    final noteController = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Tarik Tunai Saldo'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Saldo tersedia: ${_rupiah(_balance)}'),
          const SizedBox(height: 10),
          TextField(
            controller: amountController,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: const [CurrencyInputFormatter()],
            decoration: const InputDecoration(labelText: 'Nominal penarikan (Rp)', prefixText: 'Rp ', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 10),
          TextField(controller: noteController, decoration: const InputDecoration(labelText: 'Catatan (opsional)', border: OutlineInputBorder())),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Tarik tunai')),
        ],
      ),
    );
    final amount = int.tryParse(amountController.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
    final note = noteController.text.trim();
    amountController.dispose();
    noteController.dispose();
    if (result != true) return;
    if (amount <= 0 || amount > _balance) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(amount <= 0 ? 'Nominal penarikan harus lebih dari nol.' : 'Nominal melebihi saldo tersedia ${_rupiah(_balance)}.')));
      return;
    }
    try {
      await _repository.withdrawCash(customerId: widget.customerId, amount: amount, note: note);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Penarikan tunai ${_rupiah(amount)} berhasil dicatat.')));
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal menarik saldo: $error')));
    }
  }

  @override
  void initState() { super.initState(); _load(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Saldo Pelanggan'),
        actions: [IconButton(tooltip: 'Tarik tunai', onPressed: _loading || _balance <= 0 ? null : _withdraw, icon: const Icon(Icons.payments_outlined))],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _deposit,
        icon: const Icon(Icons.add),
        label: const Text('Tambah Deposit'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
                children: [
                  Card(child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(widget.customerName, style: const TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      const Text('Saldo tersedia', style: TextStyle(color: Colors.grey)),
                      Text(_rupiah(_balance), style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 6),
                      const Text('Deposit adalah titipan pelanggan, bukan omzet bengkel. Saldo dapat digunakan untuk pembayaran atau ditarik tunai.', style: TextStyle(fontSize: 11, color: Colors.grey)),
                    ]),
                  )),
                  const SizedBox(height: 12),
                  const Text('Riwayat mutasi saldo', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  if (_entries.isEmpty)
                    const Card(child: Padding(padding: EdgeInsets.all(14), child: Text('Belum ada riwayat deposit atau pemakaian saldo.')))
                  else
                    ..._entries.map((row) {
                      final type = row['entry_type']?.toString() ?? '';
                      final isCredit = type == 'deposit' || type == 'refund';
                      final label = switch (type) {
                        'deposit' => 'Deposit masuk',
                        'service_payment' => 'Pembayaran servis',
                        'sale_payment' => 'Pembayaran penjualan',
                        'refund' => 'Pengembalian saldo',
                        'adjustment' when row['description']?.toString().toLowerCase().contains('penarikan tunai') == true => 'Penarikan tunai',
                        _ => 'Penyesuaian saldo',
                      };
                      final amount = (row['amount'] as num?)?.toInt() ?? 0;
                      return Card(child: ListTile(
                        leading: Icon(isCredit ? Icons.add_circle_outline : Icons.remove_circle_outline, color: isCredit ? Colors.green : Colors.orange),
                        title: Text(label),
                        subtitle: Text('${row['description'] ?? ''}\n${row['created_at'] ?? ''}'),
                        isThreeLine: true,
                        trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                          Text('${isCredit ? '+' : '-'}${_rupiah(amount)}', style: TextStyle(fontWeight: FontWeight.bold, color: isCredit ? Colors.green : Colors.orange)),
                          Text('Saldo ${_rupiah(row['balance_after'])}', style: const TextStyle(fontSize: 10, color: Colors.grey)),
                        ]),
                      ));
                    }),
                ],
              ),
            ),
    );
  }
}
