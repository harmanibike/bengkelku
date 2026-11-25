import 'package:material_ui/material_ui.dart';
import 'package:sqflite/sqflite.dart';

import '../../../core/auth/auth_session.dart';
import '../../../core/database/app_database.dart';

class TestTransactionModePage extends StatefulWidget {
  const TestTransactionModePage({super.key});

  @override
  State<TestTransactionModePage> createState() => _TestTransactionModePageState();
}

class _TestTransactionModePageState extends State<TestTransactionModePage> {
  bool _loading = true;
  bool _enabled = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final db = await AppDatabase.instance.database;
      final rows = await db.query('app_settings',
        columns: ['setting_value'],
        where: 'setting_key = ?',
        whereArgs: ['transaction_test_mode'],
        limit: 1);
      if (!mounted) return;
      setState(() {
        _enabled = rows.isNotEmpty && rows.first['setting_value']?.toString() == '1';
        _loading = false;
      });
    } catch (error) {
      if (mounted) setState(() => _loading = false);
      _message('Gagal memuat mode percobaan: $error');
    }
  }

  void _message(String value) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(value)));
  }

  Future<void> _setMode(bool value) async {
    if (!AuthSession.instance.isAdmin) {
      _message('Hanya Admin yang dapat mengubah mode percobaan.');
      return;
    }
    setState(() => _saving = true);
    try {
      final db = await AppDatabase.instance.database;
      await db.insert('app_settings', {
        'setting_key': 'transaction_test_mode',
        'setting_value': value ? '1' : '0',
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      if (!mounted) return;
      setState(() => _enabled = value);
      _message(value
          ? 'Mode percobaan aktif. Transaksi baru akan diberi penanda percobaan.'
          : 'Mode percobaan nonaktif. Transaksi baru dicatat sebagai transaksi biasa.');
    } catch (error) {
      _message('Gagal menyimpan mode percobaan: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mode Transaksi Percobaan')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: SwitchListTile(
                    contentPadding: const EdgeInsets.all(14),
                    title: const Text('Aktifkan Mode Percobaan',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: const Text(
                      'Transaksi penjualan, pembelian, dan servis yang dibuat setelah mode ini aktif akan diberi penanda percobaan. Matikan kembali sebelum mulai operasional sungguhan.',
                      style: TextStyle(fontSize: 12)),
                    value: _enabled,
                    onChanged: _saving ? null : _setMode,
                  ),
                ),
                const SizedBox(height: 12),
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Penting', style: TextStyle(fontWeight: FontWeight.w700)),
                        SizedBox(height: 6),
                        Text(
                          'Mode ini hanya menandai transaksi baru. Transaksi lama tidak otomatis dianggap percobaan dan belum dihapus. Pembersihan transaksi lama harus dipilih dan diperiksa secara terpisah agar data usaha asli tetap aman.',
                          style: TextStyle(fontSize: 12)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
