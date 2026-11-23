import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

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
  final _picker = ImagePicker();
  final _bankName = TextEditingController();
  final _accountNumber = TextEditingController();
  final _accountHolder = TextEditingController();
  String _qrisImagePath = '';
  bool _detailsLoaded = false;

  @override
  void initState() {
    super.initState();
    _enabledFuture = _repository.getEnabledCodes();
    _loadPaymentDetails();
  }

  @override
  void dispose() {
    _bankName.dispose();
    _accountNumber.dispose();
    _accountHolder.dispose();
    super.dispose();
  }

  Future<void> _loadPaymentDetails() async {
    try {
      final details = await _repository.getPaymentDetails();
      if (!mounted) return;
      setState(() {
        _qrisImagePath = details['qris_image_path'] ?? '';
        _bankName.text = details['bank_name'] ?? '';
        _accountNumber.text = details['bank_account_number'] ?? '';
        _accountHolder.text = details['bank_account_holder'] ?? '';
        _detailsLoaded = true;
      });
    } catch (error) {
      if (mounted) _message('Gagal memuat detail pembayaran: $error');
    }
  }

  Future<void> _chooseQrisImage() async {
    try {
      final image = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 95,
        maxWidth: 1600,
      );
      if (image == null) return;
      final directory = await getApplicationDocumentsDirectory();
      final targetDirectory = Directory(p.join(directory.path, 'payment_methods'));
      if (!await targetDirectory.exists()) {
        await targetDirectory.create(recursive: true);
      }
      final extension = p.extension(image.path).isEmpty ? '.jpg' : p.extension(image.path);
      final destination = p.join(targetDirectory.path, 'qris$extension');
      await File(image.path).copy(destination);
      if (mounted) setState(() => _qrisImagePath = destination);
    } catch (error) {
      _message('Gagal memilih gambar QRIS: $error');
    }
  }

  void _message(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
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
      await _repository.savePaymentDetails({
        'qris_image_path': _qrisImagePath,
        'bank_name': _bankName.text.trim(),
        'bank_account_number': _accountNumber.text.trim(),
        'bank_account_holder': _accountHolder.text.trim(),
      });
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
              const SizedBox(height: 16),
              const Text('Detail Pembayaran', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              const Text('Data berikut akan ditampilkan kasir ketika metode QRIS atau Transfer Bank dipilih.', style: TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 10),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('QRIS', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    if (_qrisImagePath.isNotEmpty && File(_qrisImagePath).existsSync())
                      Center(child: Image.file(File(_qrisImagePath), height: 170, fit: BoxFit.contain)),
                    Wrap(spacing: 8, children: [
                      OutlinedButton.icon(onPressed: _saving ? null : _chooseQrisImage, icon: const Icon(Icons.photo_library_outlined), label: const Text('Pilih gambar QRIS')),
                      if (_qrisImagePath.isNotEmpty) TextButton(onPressed: _saving ? null : () => setState(() => _qrisImagePath = ''), child: const Text('Hapus')),
                    ]),
                    const SizedBox(height: 8),
                    const Divider(),
                    const Text('Transfer Bank', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    TextField(controller: _bankName, decoration: const InputDecoration(labelText: 'Nama bank', hintText: 'Contoh: BCA / BRI / Mandiri')),
                    const SizedBox(height: 8),
                    TextField(controller: _accountNumber, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Nomor rekening')),
                    const SizedBox(height: 8),
                    TextField(controller: _accountHolder, decoration: const InputDecoration(labelText: 'Nama pemilik rekening')),
                  ]),
                ),
              ),
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
