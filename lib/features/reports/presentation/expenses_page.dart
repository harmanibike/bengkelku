import 'package:material_ui/material_ui.dart';

import '../../../core/formatters/currency_input_formatter.dart';
import '../data/cashbook_repository.dart';

class ExpensesPage extends StatefulWidget {
  const ExpensesPage({super.key});

  @override
  State<ExpensesPage> createState() => _ExpensesPageState();
}

class _ExpensesPageState extends State<ExpensesPage> {
  final CashbookRepository _repository = CashbookRepository();
  String _period = 'month';
  late Future<List<Map<String, Object?>>> _future;

  static const _categories = [
    'Operasional',
    'Gaji Karyawan',
    'Komisi Mekanik',
    'Transportasi',
    'Listrik dan Air',
    'Sewa Tempat',
    'Perawatan Peralatan',
    'Perlengkapan',
    'Biaya Lainnya',
  ];

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  (DateTime, DateTime) _range() {
    final now = DateTime.now();
    if (_period == 'today') {
      final start = DateTime(now.year, now.month, now.day);
      return (start, start.add(const Duration(days: 1)));
    }
    if (_period == 'month') {
      return (DateTime(now.year, now.month), DateTime(now.year, now.month + 1));
    }
    return (DateTime(2000), now.add(const Duration(days: 1)));
  }

  Future<List<Map<String, Object?>>> _load() {
    final range = _range();
    return _repository.getManualExpenses(start: range.$1, end: range.$2);
  }

  void _refresh() => setState(() => _future = _load());

  String _money(Object? value) {
    final amount = (value as num?)?.toInt() ?? 0;
    final digits = amount.abs().toString();
    final out = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) out.write('.');
      out.write(digits[i]);
    }
    return 'Rp${amount < 0 ? '-' : ''}$out';
  }

  String _date(Object? value) {
    final date = DateTime.tryParse(value?.toString() ?? '');
    if (date == null) return '-';
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year} • ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _addExpense() async {
    final formKey = GlobalKey<FormState>();
    final description = TextEditingController();
    final amount = TextEditingController();
    var category = _categories.first;
    var paymentMethod = 'cash';

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Tambah Pengeluaran'),
          content: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: category,
                    decoration: const InputDecoration(labelText: 'Kategori'),
                    items: _categories.map((item) => DropdownMenuItem(value: item, child: Text(item))).toList(),
                    onChanged: (value) { if (value != null) setDialogState(() => category = value); },
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: paymentMethod,
                    decoration: const InputDecoration(labelText: 'Metode pembayaran'),
                    items: const [
                      DropdownMenuItem(value: 'cash', child: Text('Cash / Tunai')),
                      DropdownMenuItem(value: 'bank_transfer', child: Text('Transfer Bank')),
                    ],
                    onChanged: (value) { if (value != null) setDialogState(() => paymentMethod = value); },
                  ),
                  TextFormField(
                    controller: description,
                    decoration: const InputDecoration(labelText: 'Keterangan'),
                    textCapitalization: TextCapitalization.sentences,
                    validator: (value) => value == null || value.trim().isEmpty ? 'Keterangan wajib diisi' : null,
                  ),
                  TextFormField(
                    controller: amount,
                    keyboardType: TextInputType.number,
                    inputFormatters: const [CurrencyInputFormatter()],
                    decoration: const InputDecoration(labelText: 'Nominal (Rp)'),
                    validator: (value) => parseCurrencyInput(value) <= 0 ? 'Nominal tidak valid' : null,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Batal')),
            FilledButton(
              onPressed: () {
                if (formKey.currentState?.validate() ?? false) Navigator.pop(dialogContext, true);
              },
              child: const Text('Simpan'),
            ),
          ],
        ),
      ),
    );

    if (saved == true) {
      try {
        await _repository.addManualTransaction(
          type: 'expense',
          category: category,
          description: description.text,
          amount: parseCurrencyInput(amount.text),
          paymentMethod: paymentMethod,
        );
        _refresh();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(paymentMethod == 'cash'
                ? 'Pengeluaran tunai dicatat dan mengurangi Saldo Toko.'
                : 'Pengeluaran transfer bank berhasil dicatat. Saldo Toko tidak berubah.')),
          );
        }
      } catch (error) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
    description.dispose();
    amount.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pengeluaran')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addExpense,
        icon: const Icon(Icons.add),
        label: const Text('Tambah Pengeluaran'),
      ),
      body: FutureBuilder<List<Map<String, Object?>>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Gagal memuat pengeluaran: ${snapshot.error}'));
          }
          final entries = snapshot.data ?? [];
          final total = entries.fold<int>(0, (sum, row) => sum + ((row['amount'] as num?)?.toInt() ?? 0));
          return RefreshIndicator(
            onRefresh: () async => _refresh(),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 90),
              children: [
                DropdownButtonFormField<String>(
                  initialValue: _period,
                  decoration: const InputDecoration(labelText: 'Periode', isDense: true),
                  items: const [
                    DropdownMenuItem(value: 'today', child: Text('Hari ini')),
                    DropdownMenuItem(value: 'month', child: Text('Bulan ini')),
                    DropdownMenuItem(value: 'all', child: Text('Semua waktu')),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() { _period = value; _future = _load(); });
                  },
                ),
                const SizedBox(height: 10),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        const Icon(Icons.payments_outlined, color: Colors.deepOrange, size: 30),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Total Pengeluaran Manual', style: TextStyle(fontSize: 12, color: Colors.grey)),
                              const SizedBox(height: 4),
                              Text(_money(total), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                              Text('${entries.length} transaksi', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                if (entries.isEmpty)
                  const Card(child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Column(children: [
                      Icon(Icons.receipt_long_outlined, size: 36, color: Colors.grey),
                      SizedBox(height: 8),
                      Text('Belum ada pengeluaran pada periode ini.'),
                    ]),
                  ))
                else
                  ...entries.map((row) {
                    final method = row['payment_method']?.toString() ?? 'cash';
                    return Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: const Color(0xFFFFF0E8),
                          child: Icon(method == 'cash' ? Icons.payments_outlined : Icons.account_balance, color: Colors.deepOrange),
                        ),
                        title: Text(row['category']?.toString() ?? 'Pengeluaran', style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text('${row['description'] ?? '-'}\n${method == 'cash' ? 'Cash / Tunai' : 'Transfer Bank'} • ${_date(row['transaction_date'])}'),
                        isThreeLine: true,
                        trailing: Text(_money(row['amount']), style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
                      ),
                    );
                  }),
                const SizedBox(height: 8),
                const Text(
                  'Catatan: halaman ini menampilkan pengeluaran manual. Pembelian pemasok dan transaksi otomatis lainnya tetap tercatat pada menu terkait dan Buku Kas, sehingga tidak dihitung dua kali.',
                  style: TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
