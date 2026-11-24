import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../data/business_profile_repository.dart';

class BusinessProfilePage extends StatefulWidget {
  const BusinessProfilePage({super.key});

  @override
  State<BusinessProfilePage> createState() => _BusinessProfilePageState();
}

class _BusinessProfilePageState extends State<BusinessProfilePage> {
  final _repository = BusinessProfileRepository();
  final _formKey = GlobalKey<FormState>();
  final _picker = ImagePicker();
  final Map<String, TextEditingController> _controllers = {
    'business_name': TextEditingController(),
    'business_address': TextEditingController(),
    'business_phone': TextEditingController(),
    'business_whatsapp': TextEditingController(),
    'business_email': TextEditingController(),
    'business_website': TextEditingController(),
    'business_tax_number': TextEditingController(),
  };
  String _logoPath = '';
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final profile = await _repository.getProfile();
      for (final entry in _controllers.entries) {
        entry.value.text = profile[entry.key] ?? '';
      }
      if (mounted) {
        setState(() {
          _logoPath = profile['business_logo_path'] ?? '';
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        _message('Gagal memuat profil usaha: $e');
      }
    }
  }

  Future<void> _chooseLogo() async {
    try {
      final image = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 1200,
      );
      if (image == null) return;
      final directory = await getApplicationDocumentsDirectory();
      final logoDirectory = Directory(p.join(directory.path, 'business_profile'));
      if (!await logoDirectory.exists()) {
        await logoDirectory.create(recursive: true);
      }
      final extension = p.extension(image.path).isEmpty
          ? '.jpg'
          : p.extension(image.path);
      final destination = p.join(logoDirectory.path, 'business_logo$extension');
      await File(image.path).copy(destination);
      if (mounted) setState(() => _logoPath = destination);
    } catch (e) {
      _message('Gagal memilih logo: $e');
    }
  }

  Future<void> _removeLogo() async {
    setState(() => _logoPath = '');
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final values = <String, String>{
        for (final entry in _controllers.entries)
          entry.key: entry.value.text,
        'business_logo_path': _logoPath,
      };
      await _repository.saveProfile(values);
      if (mounted) _message('Profil usaha berhasil disimpan.');
    } catch (e) {
      if (mounted) _message('Gagal menyimpan profil usaha: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _message(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Widget _field(
    String key,
    String label, {
    int maxLines = 1,
    TextInputType? keyboardType,
    String? hint,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextFormField(
        controller: _controllers[key],
        maxLines: maxLines,
        keyboardType: keyboardType,
        textCapitalization: key == 'business_email' ||
                key == 'business_website'
            ? TextCapitalization.none
            : TextCapitalization.sentences,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          alignLabelWithHint: maxLines > 1,
        ),
        validator: key == 'business_name'
            ? (value) => value == null || value.trim().isEmpty
                ? 'Nama usaha wajib diisi.'
                : null
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Profil Usaha')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          Container(
                            width: 76,
                            height: 76,
                            decoration: BoxDecoration(
                              color: const Color(0xFFEAF0FF),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: const Color(0xFFD8E0F0),
                              ),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: _logoPath.isNotEmpty &&
                                    File(_logoPath).existsSync()
                                ? Image.file(
                                    File(_logoPath),
                                    fit: BoxFit.contain,
                                  )
                                : const Icon(
                                    Icons.storefront_rounded,
                                    size: 38,
                                    color: Color(0xFF4169C9),
                                  ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Logo usaha',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                const Text(
                                  'Pilih logo dari galeri untuk identitas nota.',
                                  style: TextStyle(
                                    color: Colors.grey,
                                    fontSize: 11,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Wrap(
                                  spacing: 6,
                                  children: [
                                    TextButton.icon(
                                      onPressed: _chooseLogo,
                                      icon: const Icon(
                                        Icons.photo_library_outlined,
                                        size: 17,
                                      ),
                                      label: const Text('Pilih logo'),
                                    ),
                                    if (_logoPath.isNotEmpty)
                                      TextButton(
                                        onPressed: _removeLogo,
                                        child: const Text('Hapus'),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Informasi Usaha',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _field('business_name', 'Nama usaha *'),
                  _field(
                    'business_address',
                    'Alamat lengkap',
                    maxLines: 3,
                  ),
                  _field(
                    'business_phone',
                    'Nomor telepon',
                    keyboardType: TextInputType.phone,
                  ),
                  _field(
                    'business_whatsapp',
                    'Nomor WhatsApp',
                    keyboardType: TextInputType.phone,
                  ),
                  _field(
                    'business_email',
                    'Email',
                    keyboardType: TextInputType.emailAddress,
                  ),
                  _field(
                    'business_website',
                    'Website / media sosial',
                  ),
                  _field(
                    'business_tax_number',
                    'NPWP / nomor pajak (opsional)',
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 44,
                    child: FilledButton.icon(
                      onPressed: _saving ? null : _save,
                      icon: _saving
                          ? const SizedBox(
                              width: 17,
                              height: 17,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.save_rounded),
                      label: Text(
                        _saving ? 'Menyimpan...' : 'Simpan Profil Usaha',
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
