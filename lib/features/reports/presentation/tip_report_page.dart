import 'package:material_ui/material_ui.dart';

import '../../../core/auth/auth_session.dart';
import '../../customers/data/customer_wallet_repository.dart';

class TipReportPage extends StatefulWidget {
  const TipReportPage({super.key});

  @override
  State<TipReportPage> createState() => _TipReportPageState();
}

class _TipReportPageState extends State<TipReportPage> {
  final CustomerWalletRepository _repository = CustomerWalletRepository();
  bool _loading = true;
  String _period = 'today';
  Map<String, Object?> _report = {};

  String _rupiah(Object? value) {
    final amount = (value as num?)?.toInt() ?? 0;
    final digits = amount.toString();
    final out = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) out.write('.');
      out.write(digits[i]);
    }
    return 'Rp$out';
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final now = DateTime.now();
    late DateTime start;
    late DateTime end;
    if (_period == 'today') {
      start = DateTime(now.year, now.month, now.day);
      end = start.add(const Duration(days: 1));
    } else if (_period == 'month') {
      start = DateTime(now.year, now.month);
      end = DateTime(now.year, now.month + 1);
    } else {
      start = DateTime(2000);
      end = now.add(const Duration(days: 1));
    }
    try {
      final result = await _repository.getTipReport(start: start, end: end);
      if (!mounted) return;
      setState(() { _report = result; _loading = false; });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal memuat laporan tip: $error')));
    }
  }

  Future<void> _handOver(Map<String, Object?> row) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Konfirmasi penyerahan tip'),
        content: Text('Tandai tip sebesar ${_rupiah(row['amount'])} untuk ${row['recipient_name'] ?? 'penerima'} sudah diserahkan?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Sudah diserahkan')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _repository.handOverTip(tipId: row['id'] as int);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Penyerahan tip dicatat.')));
      _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal mencatat penyerahan: $error')));
    }
  }

  @override
  void initState() { super.initState(); _load(); }

  @override
  Widget build(BuildContext context) {
    final entries = (_report['entries'] as List?) ?? const [];
    final byRecipient = (_report['by_recipient'] as List?) ?? const [];
    return Scaffold(
      appBar: AppBar(title: const Text('Laporan Uang Tip')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: _period,
                    decoration: const InputDecoration(labelText: 'Periode laporan', border: OutlineInputBorder()),
                    items: const [
                      DropdownMenuItem(value: 'today', child: Text('Hari ini')),
                      DropdownMenuItem(value: 'month', child: Text('Bulan ini')),
                      DropdownMenuItem(value: 'all', child: Text('Semua waktu')),
                    ],
                    onChanged: (value) { if (value == null) return; setState(() => _period = value); _load(); },
                  ),
                  const SizedBox(height: 12),
                  Card(child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('Total tip diterima', style: TextStyle(color: Colors.grey)),
                      const SizedBox(height: 4),
                      Text(_rupiah(_report['received']), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                      const Divider(),
                      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                        const Text('Belum diserahkan'), Text(_rupiah(_report['held']), style: const TextStyle(fontWeight: FontWeight.w600)),
                      ]),
                      const SizedBox(height: 6),
                      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                        const Text('Sudah diserahkan'), Text(_rupiah(_report['handed_over']), style: const TextStyle(fontWeight: FontWeight.w600)),
                      ]),
                      const SizedBox(height: 6),
                      Text('Jumlah catatan: ${_report['count'] ?? 0}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                    ]),
                  )),
                  const SizedBox(height: 12),
                  const Text('Rekap per penerima', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  if (byRecipient.isEmpty)
                    const Card(child: Padding(padding: EdgeInsets.all(12), child: Text('Belum ada rekap penerima.')))
                  else
                    ...byRecipient.map((raw) {
                      final row = Map<String, Object?>.from(raw as Map);
                      return Card(child: ListTile(
                        title: Text(row['recipient']?.toString() ?? 'Belum ditentukan'),
                        subtitle: Text('Belum diserahkan: ${_rupiah(row['held'])} • Sudah diserahkan: ${_rupiah(row['handed_over'])}'),
                        trailing: Text(_rupiah(row['received']), style: const TextStyle(fontWeight: FontWeight.bold)),
                      ));
                    }),
                  const SizedBox(height: 12),
                  const Text('Rincian tip', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  if (entries.isEmpty)
                    const Card(child: Padding(padding: EdgeInsets.all(14), child: Text('Belum ada tip pada periode ini.')))
                  else
                    ...entries.map((raw) {
                      final row = Map<String, Object?>.from(raw as Map);
                      final status = row['status']?.toString() ?? 'held';
                      return Card(child: ListTile(
                        title: Text(_rupiah(row['amount']), style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text('${row['recipient_name'] ?? 'Penerima belum ditentukan'} • ${row['source_type']} #${row['source_id'] ?? '-'}\n${row['received_at'] ?? ''}\nStatus: ${status == 'held' ? 'Belum diserahkan' : status == 'handed_over' ? 'Sudah diserahkan' : 'Dibatalkan'}'),
                        isThreeLine: true,
                        trailing: AuthSession.instance.isAdmin && status == 'held'
                            ? IconButton(icon: const Icon(Icons.check_circle_outline), tooltip: 'Konfirmasi penyerahan', onPressed: () => _handOver(row))
                            : null,
                      ));
                    }),
                  const SizedBox(height: 12),
                  const Text('Tip dicatat terpisah dari omzet dan Buku Kas. Penerimaan serta penyerahan hanya ditampilkan pada Laporan Uang Tip.', style: TextStyle(fontSize: 11, color: Colors.grey)),
                ],
              ),
            ),
    );
  }
}
