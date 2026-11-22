import 'package:material_ui/material_ui.dart';

import '../data/payment_methods_repository.dart';

class PaymentMethodsPage extends StatefulWidget {
  const PaymentMethodsPage({super.key});

  @override
  State<PaymentMethodsPage> createState() => _PaymentMethodsPageState();
}

class _PaymentMethodsPageState extends State<PaymentMethodsPage> {
  final PaymentMethodsRepository _repository = PaymentMethodsRepository();
  late Future<Set<String>> _enabledFuture;
  Set<String> _enabled = {};
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _enabledFuture = _repository.getEnabledCodes();
  }

  Future<void> _save() async {
    if (_enabled.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Minimal satu metode pembayaran harus aktif.')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await _repository.saveEnabledCodes(_enabled);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Metode pembayaran berhasil disimpan.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal menyimpan metode pembayaran: $error')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Metode Pembayaran')),
      body: FutureBuilder<Set<String>>(
        future: _enabledFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Gagal memuat pengaturan: ${snapshot.error}'));
          }
          if (_enabled.isEmpty) _enabled = {...?snapshot.data};
          return ListView(
            padding: const EdgeInsets.all(14),
            children: [
              const Text(
                'Aktifkan metode yang tersedia di kasir. Metode yang dinonaktifkan tidak akan muncul saat transaksi baru.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 10),
              ...PaymentMethodsRepository.defaultMethods.map((method) {
                final code = method['code']!;
                final checked = _enabled.contains(code);
                return Card(
                  margin: const EdgeInsets.only(bottom: 7),
                  child: CheckboxListTile(
                    dense: true,
                    value: checked,
                    title: Text(method['name']!, style: const TextStyle(fontSize: 14)),
                    secondary: Icon(_iconFor(code), color: const Color(0xFF546E7A)),
                    onChanged: _saving
                        ? null
                        : (value) {
                            setState(() {
                              if (value == true) {
                                _enabled.add(code);
                              } else if (_enabled.length > 1) {
                                _enabled.remove(code);
                              }
                            });
                          },
                  ),
                );
              }),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.save_rounded),
                  label: const Text('Simpan Pengaturan'),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  IconData _iconFor(String code) {
    switch (code) {
      case 'bank_transfer':
        return Icons.account_balance_rounded;
      case 'qris':
        return Icons.qr_code_2_rounded;
      case 'debit_card':
      case 'credit_card':
        return Icons.credit_card_rounded;
      default:
        return Icons.payments_rounded;
    }
  }
}
