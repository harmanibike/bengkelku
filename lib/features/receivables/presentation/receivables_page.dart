import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/receivable_repository.dart';

class ReceivablesPage extends StatefulWidget {
  const ReceivablesPage({super.key});

  @override
  State<ReceivablesPage> createState() => _ReceivablesPageState();
}

class _ReceivablesPageState extends State<ReceivablesPage> {
  final ReceivableRepository _repository = ReceivableRepository();
  final TextEditingController _search = TextEditingController();
  String _type = 'all';
  late Future<List<Map<String, Object?>>> _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _load() {
    _future = _repository.getReceivables(type: _type, keyword: _search.text);
  }

  void _refresh() => setState(_load);

  int _int(Object? value) => value is num ? value.toInt() : 0;

  String _rupiah(Object? value) {
    final digits = _int(value).toString();
    final out = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) out.write('.');
      out.write(digits[i]);
    }
    return 'Rp$out';
  }

  String _date(Object? value) {
    final parsed = DateTime.tryParse(value?.toString() ?? '');
    if (parsed == null) return '-';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(parsed.day)}/${two(parsed.month)}/${parsed.year}';
  }

  String _phone(String value) {
    var digits = value.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.startsWith('0')) digits = '62${digits.substring(1)}';
    if (digits.startsWith('8')) digits = '62$digits';
    return digits;
  }

  String _message(Map<String, Object?> row, String template) {
    final type = row['receivable_type'] == 'service' ? 'servis' : 'pembelian barang';
    return template
        .replaceAll('{nama}', row['customer_name']?.toString() ?? 'Pelanggan')
        .replaceAll('{jenis}', type)
        .replaceAll('{nota}', row['invoice_number']?.toString() ?? '-')
        .replaceAll('{tanggal}', _date(row['transaction_date']))
        .replaceAll('{total}', _rupiah(row['total_amount']))
        .replaceAll('{dibayar}', _rupiah(row['paid_amount']))
        .replaceAll('{sisa}', _rupiah(row['remaining_amount']));
  }

  Future<void> _editTemplate() async {
    final controller = TextEditingController(text: await _repository.getTemplate());
    if (!mounted) {
      controller.dispose();
      return;
    }
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Template WhatsApp'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Variabel: {nama}, {jenis}, {nota}, {tanggal}, {total}, {dibayar}, {sisa}'),
                const SizedBox(height: 10),
                TextField(
                  controller: controller,
                  maxLines: 7,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Isi pesan pengingat',
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Simpan')),
        ],
      ),
    );
    if (saved == true) {
      await _repository.saveTemplate(controller.text.trim());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Template pengingat disimpan.')),
        );
      }
    }
    controller.dispose();
  }

  Future<void> _sendReminder(Map<String, Object?> row) async {
    final phone = _phone(row['customer_phone']?.toString() ?? '');
    if (phone.length < 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nomor WhatsApp pelanggan belum valid. Periksa data pelanggan.')),
      );
      return;
    }
    try {
      final template = await _repository.getTemplate();
      final message = _message(row, template);
      final uri = Uri.parse('https://wa.me/$phone').replace(queryParameters: {'text': message});
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened) throw StateError('WhatsApp tidak dapat dibuka.');
      await _repository.recordReminder(
        type: row['receivable_type'].toString(),
        recordId: _int(row['record_id']),
        phone: phone,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('WhatsApp dibuka. Periksa pesan lalu tekan Kirim.')),
        );
        _refresh();
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Tidak dapat membuka WhatsApp: $error')),
        );
      }
    }
  }

  Future<void> _showLastReminder(Map<String, Object?> row) async {
    final last = await _repository.getLastReminder(
      row['receivable_type'].toString(),
      _int(row['record_id']),
    );
    if (!mounted) return;
    final date = last == null ? 'Belum pernah dibuka' : _date(last['opened_at']);
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Riwayat Pengingat'),
        content: Text('WhatsApp terakhir dibuka: $date\nNomor: ${last?['phone'] ?? '-'}'),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Tutup'))],
      ),
    );
  }

  Future<void> _showReceivableDetail(Map<String, Object?> row) async {
    try {
      final type = row['receivable_type'].toString();
      final detail = await _repository.getReceivableDetail(
        type: type,
        recordId: _int(row['record_id']),
      );
      if (!mounted) return;
      final record = detail['record'] as Map<String, Object?>;
      final payments = detail['payments'] as List<Map<String, Object?>>;
      final returns = detail['returns'] as List<Map<String, Object?>>;
      final sale = type == 'sale';
      final returned = _int(record['returned_amount']);
      final refunded = _int(record['refunded_amount']);
      final netTotal = sale ? _int(record['total']) - returned : _int(record['total_cost']);
      final paid = sale ? _int(record['paid']) : _int(record['down_payment']);
      final remaining = sale
          ? netTotal - paid + refunded
          : _int(record['remaining_payment']);
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text('Rincian ${sale ? 'Penjualan' : 'Servis'}'),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Nota: ${record[sale ? 'invoice_number' : 'order_number'] ?? '-}',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  Text('Pelanggan: ${record['customer_name'] ?? 'Pelanggan dihapus'}'),
                  Text('Tanggal: ${_date(record[sale ? 'transaction_date' : 'received_at'])}'),
                  const Divider(),
                  _detailAmount('Total awal', sale ? record['total'] : record['total_cost']),
                  if (sale) ...[
                    _detailAmount('Nilai barang diretur', returned),
                    _detailAmount('Dana retur dikembalikan', refunded),
                    _detailAmount('Total setelah retur', netTotal),
                  ],
                  _detailAmount('Total dibayar', paid),
                  _detailAmount('Sisa piutang', remaining),
                  const Divider(),
                  const Text('Riwayat pembayaran',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  if (payments.isEmpty)
                    const Text('Belum ada pembayaran tercatat.',
                        style: TextStyle(fontSize: 12, color: Colors.grey))
                  else
                    ...payments.map((payment) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(
                            children: [
                              Expanded(child: Text(_date(payment['transaction_date']),
                                  style: const TextStyle(fontSize: 11))),
                              Text(_rupiah(payment['amount']),
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                            ],
                          ),
                        )),
                  if (returns.isNotEmpty) ...[
                    const Divider(),
                    const Text('Riwayat retur',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    ...returns.map((entry) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(entry['return_number']?.toString() ?? 'Retur',
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                              Text('${_date(entry['return_date'])} • Nilai ${_rupiah(entry['total_amount'])} • Refund ${_rupiah(entry['refunded_amount'])}',
                                  style: const TextStyle(fontSize: 11, color: Colors.grey)),
                            ],
                          ),
                        )),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Tutup')),
          ],
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal memuat rincian piutang: $error')),
        );
      }
    }
  }

  Widget _detailAmount(String label, Object? amount) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Expanded(child: Text(label, style: const TextStyle(fontSize: 12))),
            Text(_rupiah(amount), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          ],
        ),
      );

  Widget _receivableCard(Map<String, Object?> row) {
    final service = row['receivable_type'] == 'service';
    final remaining = _int(row['remaining_amount']);
    return Card(
      margin: const EdgeInsets.only(bottom: 9),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    row['customer_name']?.toString() ?? 'Pelanggan dihapus',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: service ? const Color(0xFFEDE7F6) : const Color(0xFFE3F2FD),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(service ? 'Servis' : 'Penjualan', style: const TextStyle(fontSize: 10)),
                ),
              ],
            ),
            const SizedBox(height: 5),
            Text('Nota: ${row['invoice_number'] ?? '-'} • ${_date(row['transaction_date'])}',
                style: const TextStyle(fontSize: 11, color: Colors.grey)),
            const SizedBox(height: 7),
            Row(
              children: [
                Expanded(child: Text('Total: ${_rupiah(row['total_amount'])}\nDibayar: ${_rupiah(row['paid_amount'])}',
                    style: const TextStyle(fontSize: 11, height: 1.5))),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text('Sisa tagihan', style: TextStyle(fontSize: 10, color: Colors.grey)),
                    Text(_rupiah(remaining), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFFD84315))),
                  ],
                ),
              ],
            ),
            const Divider(height: 18),
            Row(
              children: [
                Expanded(
                  child: Text(
                    row['customer_phone']?.toString().trim().isNotEmpty == true
                        ? row['customer_phone'].toString()
                        : 'Nomor WhatsApp belum tersedia',
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ),
                IconButton(
                  tooltip: 'Rincian piutang',
                  onPressed: () => _showReceivableDetail(row),
                  icon: const Icon(Icons.receipt_long_outlined, size: 20),
                ),
                IconButton(
                  tooltip: 'Riwayat pengingat',
                  onPressed: () => _showLastReminder(row),
                  icon: const Icon(Icons.history_rounded, size: 20),
                ),
                FilledButton.icon(
                  onPressed: () => _sendReminder(row),
                  icon: const Icon(Icons.chat_rounded, size: 16),
                  label: const Text('Ingatkan'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F5F8),
      appBar: AppBar(
        title: const Text('Daftar Piutang'),
        actions: [
          IconButton(
            tooltip: 'Edit template pesan',
            onPressed: _editTemplate,
            icon: const Icon(Icons.edit_note_rounded),
          ),
          IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh_rounded)),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            child: TextField(
              controller: _search,
              onChanged: (_) => _refresh(),
              decoration: InputDecoration(
                hintText: 'Cari nama, nomor telepon, atau nota',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: IconButton(
                  onPressed: () { _search.clear(); _refresh(); },
                  icon: const Icon(Icons.close_rounded),
                ),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'all', label: Text('Semua')),
                ButtonSegment(value: 'service', label: Text('Servis')),
                ButtonSegment(value: 'sale', label: Text('Penjualan')),
              ],
              selected: {_type},
              onSelectionChanged: (value) => setState(() { _type = value.first; _load(); }),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<Map<String, Object?>>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(child: Text('Gagal memuat piutang: ${snapshot.error}'));
                }
                final rows = snapshot.data ?? [];
                if (rows.isEmpty) {
                  return const Center(child: Text('Tidak ada tagihan yang belum lunas.'));
                }
                final total = rows.fold<int>(0, (sum, row) => sum + _int(row['remaining_amount']));
                return RefreshIndicator(
                  onRefresh: () async => _refresh(),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(12, 6, 12, 18),
                    children: [
                      Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(13),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(13),
                        ),
                        child: Row(
                          children: [
                            const Expanded(child: Text('Total sisa piutang', style: TextStyle(fontWeight: FontWeight.w600))),
                            Text(_rupiah(total), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFFD84315))),
                          ],
                        ),
                      ),
                      ...rows.map(_receivableCard),
                    ],
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
