import 'package:material_ui/material_ui.dart';

import '../../../core/auth/auth_session.dart';
import '../../../core/formatters/currency_input_formatter.dart';
import '../data/saldo_toko_repository.dart';

class SaldoTokoPage extends StatefulWidget {
  const SaldoTokoPage({super.key});

  @override
  State<SaldoTokoPage> createState() => _SaldoTokoPageState();
}

class _SaldoTokoPageState extends State<SaldoTokoPage> {
  final _repository = SaldoTokoRepository();
  String _filter = 'Semua';
  late Future<Map<String, Object?>> _future;

  static const _filters = [
    'Semua', 'Modal Awal', 'Uang Masuk', 'Uang Keluar',
    'Penjualan', 'Refund', 'Pengeluaran', 'Pembelian', 'Penyesuaian',
  ];

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<Map<String, Object?>> _load() => _repository.getLedger(filter: _filter);

  void _refresh() => setState(() => _future = _load());

  String _money(Object? value) {
    final amount = (value as num?)?.toInt() ?? 0;
    final digits = amount.abs().toString();
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write('.');
      buffer.write(digits[i]);
    }
    return '${amount < 0 ? '-' : ''}Rp$buffer';
  }

  Future<void> _capitalDialog({required bool deposit}) async {
    final formKey = GlobalKey<FormState>();
    final amount = TextEditingController();
    final note = TextEditingController();
    var method = 'cash';
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(deposit ? 'Tanam Modal' : 'Tarik Modal'),
          content: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                FutureBuilder<Map<String, Object?>>(
                  future: _future,
                  builder: (context, snapshot) {
                    final balance = snapshot.data?['balance'];
                    return Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: deposit ? Colors.green.shade50 : Colors.red.shade50,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Saldo saat ini'),
                          Text(_money(balance), style: const TextStyle(fontWeight: FontWeight.bold)),
                        ],
                      ),
                    );
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: amount,
                  keyboardType: TextInputType.number,
                  inputFormatters: const [CurrencyInputFormatter()],
                  decoration: const InputDecoration(labelText: 'Jumlah (Rp)', border: OutlineInputBorder()),
                  validator: (value) => parseCurrencyInput(value) <= 0 ? 'Masukkan nominal yang valid' : null,
                ),
                const SizedBox(height: 12),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'cash', label: Text('Cash')),
                    ButtonSegment(value: 'bank_transfer', label: Text('Transfer Bank')),
                  ],
                  selected: {method},
                  onSelectionChanged: (values) => setDialogState(() => method = values.first),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: note,
                  decoration: const InputDecoration(labelText: 'Catatan (opsional)', border: OutlineInputBorder()),
                  maxLines: 2,
                ),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Batal')),
            FilledButton(
              onPressed: () {
                if (formKey.currentState?.validate() ?? false) Navigator.pop(dialogContext, true);
              },
              child: Text(deposit ? 'Tanam' : 'Tarik'),
            ),
          ],
        ),
      ),
    );
    if (saved == true) {
      try {
        await _repository.addCapitalMovement(
          isDeposit: deposit,
          amount: parseCurrencyInput(amount.text),
          paymentMethod: method,
          note: note.text,
        );
        _refresh();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(deposit ? 'Tanam modal berhasil dicatat.' : 'Tarik modal berhasil dicatat.')),
          );
        }
      } catch (error) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
    amount.dispose();
    note.dispose();
  }

  String _dateLabel(Object? raw) {
    final date = DateTime.tryParse(raw?.toString() ?? '');
    if (date == null) return '-';
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun', 'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des'];
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    final canManage = AuthSession.instance.isAdmin;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Saldo Toko'),
        actions: [
          IconButton(
            tooltip: 'Penjelasan Saldo Toko',
            icon: const Icon(Icons.help_outline),
            onPressed: () => showDialog<void>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Saldo Toko'),
                content: const Text('Saldo Toko mencatat uang tunai fisik di laci kasir. Transaksi tunai masuk dan keluar dicatat otomatis. QRIS dan transfer bank tidak menambah atau mengurangi saldo tunai laci.'),
                actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Mengerti'))],
              ),
            ),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.tune),
            onSelected: (value) => setState(() { _filter = value; _future = _load(); }),
            itemBuilder: (context) => _filters.map((value) => PopupMenuItem(value: value, child: Text(value))).toList(),
          ),
        ],
      ),
      body: FutureBuilder<Map<String, Object?>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          if (snapshot.hasError) return Center(child: Text('Gagal memuat Saldo Toko: ${snapshot.error}'));
          final data = snapshot.data ?? {};
          final balance = (data['balance'] as num?)?.toInt() ?? 0;
          final entries = (data['entries'] as List?)?.cast<Map<String, Object?>>() ?? [];
          return RefreshIndicator(
            onRefresh: () async => _refresh(),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [Color(0xFF4B00C8), Color(0xFF7900E8)]),
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: Column(children: [
                    const Text('Saldo Saat Ini', style: TextStyle(color: Colors.white70)),
                    const SizedBox(height: 8),
                    Text(_money(balance), style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 18),
                    Row(children: [
                      Expanded(child: FilledButton.tonalIcon(
                        onPressed: canManage ? () => _capitalDialog(deposit: true) : null,
                        icon: const Icon(Icons.add), label: const Text('Tanam Modal'),
                      )),
                      const SizedBox(width: 10),
                      Expanded(child: FilledButton.tonalIcon(
                        onPressed: canManage && balance > 0 ? () => _capitalDialog(deposit: false) : null,
                        icon: const Icon(Icons.remove), label: const Text('Tarik Modal'),
                      )),
                    ]),
                  ]),
                ),
                const SizedBox(height: 14),
                Card(
                  color: Colors.amber.shade50,
                  child: const ListTile(
                    leading: Icon(Icons.info_outline, color: Colors.orange),
                    title: Text('Saldo ini menunjukkan uang tunai di laci kasir, bukan omzet atau laba. QRIS dan transfer bank tidak dihitung sebagai uang tunai.'),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _filter,
                  decoration: const InputDecoration(prefixIcon: Icon(Icons.filter_list), border: OutlineInputBorder()),
                  items: _filters.map((value) => DropdownMenuItem(value: value, child: Text(value))).toList(),
                  onChanged: (value) { if (value != null) setState(() { _filter = value; _future = _load(); }); },
                ),
                const SizedBox(height: 16),
                if (entries.isEmpty)
                  const Padding(padding: EdgeInsets.all(28), child: Center(child: Text('Belum ada pergerakan saldo.')))
                else
                  ...entries.map((row) {
                    final income = row['transaction_type'] == 'income';
                    final isCash = row['is_cash'] == true;
                    final amount = (row['amount'] as num?)?.toInt() ?? 0;
                    final date = _dateLabel(row['transaction_date']);
                    final method = (row['payment_method']?.toString() ?? 'cash') == 'bank_transfer' ? 'Transfer Bank' : 'Cash';
                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: income ? Colors.green.shade50 : Colors.red.shade50,
                          child: Icon(income ? Icons.add : Icons.remove, color: income ? Colors.green : Colors.red),
                        ),
                        title: Text(row['category']?.toString() ?? 'Transaksi'),
                        subtitle: Text('${row['description'] ?? '-'}\n$date • $method${isCash ? '' : ' • Nontunai (tidak mengubah saldo laci)'}'),
                        isThreeLine: true,
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text('${income ? '+' : '-'}${_money(amount)}', style: TextStyle(fontWeight: FontWeight.bold, color: income ? Colors.green.shade700 : Colors.red.shade700)),
                            Text('Saldo: ${_money(row['running_balance'])}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                          ],
                        ),
                      ),
                    );
                  }),
              ],
            ),
          );
        },
      ),
    );
  }
}
