import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/auth/auth_session.dart';
import '../data/account_repository.dart';

class AccountProfilePage extends StatefulWidget {
  const AccountProfilePage({super.key});

  @override
  State<AccountProfilePage> createState() => _AccountProfilePageState();
}

class _AccountProfilePageState extends State<AccountProfilePage> {
  final _repository = AccountRepository();
  final _name = TextEditingController();
  final _username = TextEditingController();
  final _phone = TextEditingController();
  final _picker = ImagePicker();

  Map<String, Object?>? _profile;
  String _photoPath = '';
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _name.dispose();
    _username.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    try {
      final profile = await _repository.getCurrentProfile();
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _name.text = profile['display_name']?.toString() ?? '';
        _username.text = profile['username']?.toString() ?? '';
        _phone.text = profile['phone']?.toString() ?? '';
        _photoPath = profile['profile_photo_path']?.toString() ?? '';
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _message('Gagal memuat profil: $e');
    }
  }

  void _message(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _choosePhoto() async {
    try {
      final picked = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 82,
        maxWidth: 640,
        maxHeight: 640,
      );
      if (picked == null || !mounted) return;
      final directory = await getApplicationDocumentsDirectory();
      final userId = AuthSession.instance.userId ?? 0;
      final extension = p.extension(picked.path).isEmpty ? '.jpg' : p.extension(picked.path);
      final destination = p.join(
        directory.path,
        'profile_${userId}_${DateTime.now().microsecondsSinceEpoch}$extension',
      );
      final saved = await File(picked.path).copy(destination);
      if (!mounted) return;
      setState(() => _photoPath = saved.path);
    } catch (e) {
      _message('Gagal memilih foto: $e');
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await _repository.updateOwnProfile(
        displayName: _name.text,
        username: _username.text,
        phone: _phone.text,
        profilePhotoPath: _photoPath,
      );
      if (!mounted) return;
      _message('Perubahan profil berhasil disimpan.');
      Navigator.pop(context, true);
    } catch (e) {
      _message('Gagal memperbarui profil: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _changePin() async {
    final currentPin = TextEditingController();
    final newPin = TextEditingController();
    final confirmPin = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Ganti PIN Login'),
        content: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: currentPin,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  maxLength: 8,
                  decoration: const InputDecoration(labelText: 'PIN saat ini', border: OutlineInputBorder()),
                  validator: (v) => (v == null || v.isEmpty) ? 'Masukkan PIN saat ini.' : null,
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: newPin,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  maxLength: 8,
                  decoration: const InputDecoration(labelText: 'PIN baru (6–8 digit)', border: OutlineInputBorder()),
                  validator: (v) => v == null || !RegExp(r'^[0-9]{6,8}$').hasMatch(v)
                      ? 'PIN harus 6–8 digit.'
                      : null,
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: confirmPin,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  maxLength: 8,
                  decoration: const InputDecoration(labelText: 'Ulangi PIN baru', border: OutlineInputBorder()),
                  validator: (v) => v != newPin.text ? 'Konfirmasi PIN tidak sama.' : null,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Batal')),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) {
                Navigator.pop(dialogContext, true);
              }
            },
            child: const Text('Simpan PIN'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _repository.changeOwnPin(
          currentPin: currentPin.text,
          newPin: newPin.text,
        );
        _message('PIN berhasil diganti.');
      } catch (e) {
        _message('Gagal mengganti PIN: $e');
      }
    }
    currentPin.dispose();
    newPin.dispose();
    confirmPin.dispose();
  }

  String _roleLabel(String? role) {
    switch (role) {
      case 'admin':
        return 'Admin';
      case 'cashier':
        return 'Kasir';
      default:
        return 'Mekanik';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Profil Akun')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final role = _profile?['role']?.toString();
    final hasPhoto = _photoPath.isNotEmpty && File(_photoPath).existsSync();

    return Scaffold(
      appBar: AppBar(title: const Text('Edit Profil Akun')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      children: [
                        Stack(
                          alignment: Alignment.bottomRight,
                          children: [
                            CircleAvatar(
                              radius: 48,
                              backgroundColor: const Color(0xFFE8EAF6),
                              backgroundImage: hasPhoto ? FileImage(File(_photoPath)) : null,
                              child: hasPhoto
                                  ? null
                                  : const Icon(Icons.person_rounded, size: 52, color: Color(0xFF5C6BC0)),
                            ),
                            IconButton.filled(
                              tooltip: 'Ganti foto profil',
                              onPressed: _choosePhoto,
                              icon: const Icon(Icons.camera_alt_rounded),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(_roleLabel(role), style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF3949AB))),
                        const SizedBox(height: 4),
                        const Text('Foto profil akun yang sedang login', style: TextStyle(color: Colors.grey, fontSize: 12)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text('Informasi Akun', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 14),
                        TextField(
                          controller: _name,
                          textCapitalization: TextCapitalization.words,
                          decoration: const InputDecoration(labelText: 'Nama', prefixIcon: Icon(Icons.person_outline), border: OutlineInputBorder()),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _username,
                          autocorrect: false,
                          decoration: const InputDecoration(labelText: 'Username', prefixIcon: Icon(Icons.alternate_email), border: OutlineInputBorder()),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _phone,
                          keyboardType: TextInputType.phone,
                          decoration: const InputDecoration(labelText: 'Nomor HP', prefixIcon: Icon(Icons.phone_outlined), border: OutlineInputBorder()),
                        ),
                        const SizedBox(height: 12),
                        InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Role (permanen)',
                            prefixIcon: Icon(Icons.lock_outline),
                            border: OutlineInputBorder(),
                          ),
                          child: Row(
                            children: [
                              Expanded(child: Text(_roleLabel(role), style: const TextStyle(fontWeight: FontWeight.w600))),
                              const Icon(Icons.lock, size: 17, color: Colors.grey),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        OutlinedButton.icon(
                          onPressed: _changePin,
                          icon: const Icon(Icons.password_rounded),
                          label: const Text('Ganti PIN Login'),
                        ),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          onPressed: _saving ? null : _save,
                          icon: _saving
                              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.save_rounded),
                          label: Text(_saving ? 'Menyimpan…' : 'Update Perubahan'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
