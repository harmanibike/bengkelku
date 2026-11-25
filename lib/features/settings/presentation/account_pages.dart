import 'package:material_ui/material_ui.dart';

import '../../../core/auth/auth_session.dart';
import '../../dashboard/dashboard_page.dart';
import '../data/account_repository.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});
  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  final _repository = AccountRepository();
  late Future<bool> _hasAccounts;
  @override
  void initState() { super.initState(); _hasAccounts = _repository.hasAccounts(); }
  @override
  Widget build(BuildContext context) => FutureBuilder<bool>(
    future: _hasAccounts,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      if (snapshot.hasError) return Scaffold(body: Center(child: Text('Gagal memeriksa akun: ${snapshot.error}')));
      return snapshot.data == true ? const LoginPage() : const FirstAdminPage();
    },
  );
}

class FirstAdminPage extends StatefulWidget {
  const FirstAdminPage({super.key});
  @override
  State<FirstAdminPage> createState() => _FirstAdminPageState();
}

class _FirstAdminPageState extends State<FirstAdminPage> {
  final _name = TextEditingController();
  final _username = TextEditingController();
  final _pin = TextEditingController();
  final _confirm = TextEditingController();
  bool _saving = false;
  @override
  void dispose() { _name.dispose(); _username.dispose(); _pin.dispose(); _confirm.dispose(); super.dispose(); }
  Future<void> _create() async {
    if (_pin.text != _confirm.text) { _message('Konfirmasi PIN tidak sama.'); return; }
    setState(() => _saving = true);
    try {
      await AccountRepository().createAccount(displayName: _name.text, username: _username.text, pin: _pin.text, role: 'admin');
      if (!mounted) return;
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginPage()));
    } catch (e) { _message('Gagal membuat Admin: $e'); }
    finally { if (mounted) setState(() => _saving = false); }
  }
  void _message(String value) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
  Widget _field(String label, TextEditingController controller, {bool pin = false}) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextField(controller: controller, obscureText: pin, keyboardType: pin ? TextInputType.number : TextInputType.text,
      decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
    ),
  );
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Pengaturan Awal Bike POS')),
    body: Center(child: SingleChildScrollView(padding: const EdgeInsets.all(20), child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 460), child: Card(
      child: Padding(padding: const EdgeInsets.all(18), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Icon(Icons.admin_panel_settings_rounded, size: 52, color: Color(0xFF1565C0)),
        const SizedBox(height: 8), const Text('Buat Akun Admin Pertama', textAlign: TextAlign.center, style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6), const Text('Akun ini memiliki akses penuh dan digunakan untuk membuat akun Kasir serta Mekanik.', textAlign: TextAlign.center),
        const SizedBox(height: 18), _field('Nama Admin', _name), _field('Username', _username), _field('PIN (6–8 digit)', _pin, pin: true), _field('Ulangi PIN', _confirm, pin: true),
        FilledButton(onPressed: _saving ? null : _create, child: Text(_saving ? 'Menyimpan…' : 'Buat Admin')),
      ])),
    )))),
  );
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _username = TextEditingController();
  final _pin = TextEditingController();
  bool _busy = false;
  @override
  void dispose() { _username.dispose(); _pin.dispose(); super.dispose(); }
  Future<void> _login() async {
    setState(() => _busy = true);
    try {
      final user = await AccountRepository().authenticate(username: _username.text, pin: _pin.text);
      if (!mounted) return;
      if (user == null) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Username atau PIN salah, atau akun tidak aktif.'))); return; }
      AuthSession.instance.signIn(user);
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const DashboardPage()));
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Login gagal: $e'))); }
    finally { if (mounted) setState(() => _busy = false); }
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(child: SingleChildScrollView(padding: const EdgeInsets.all(22), child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 420), child: Card(
      child: Padding(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Image.asset('assets/branding/bike_pos_icon.png', height: 90, errorBuilder: (_, __, ___) => const Icon(Icons.pedal_bike, size: 64)),
        const SizedBox(height: 10), const Text('Bike POS', textAlign: TextAlign.center, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 18), TextField(controller: _username, textInputAction: TextInputAction.next, decoration: const InputDecoration(labelText: 'Username', border: OutlineInputBorder(), prefixIcon: Icon(Icons.person))),
        const SizedBox(height: 12), TextField(controller: _pin, obscureText: true, keyboardType: TextInputType.number, onSubmitted: (_) => _login(), decoration: const InputDecoration(labelText: 'PIN', border: OutlineInputBorder(), prefixIcon: Icon(Icons.lock))),
        const SizedBox(height: 16), FilledButton(onPressed: _busy ? null : _login, child: Text(_busy ? 'Memeriksa…' : 'Masuk')),
      ])),
    )))),
  );
}

class AccountManagementPage extends StatefulWidget {
  const AccountManagementPage({super.key});
  @override
  State<AccountManagementPage> createState() => _AccountManagementPageState();
}

class _AccountManagementPageState extends State<AccountManagementPage> {
  final _repo = AccountRepository();
  late Future<List<Map<String, Object?>>> _future;
  @override
  void initState() { super.initState(); _load(); }
  void _load() => _future = _repo.getAccounts();
  void _refresh() => setState(_load);
  String _role(String? role) => role == 'admin' ? 'Admin' : role == 'cashier' ? 'Kasir' : 'Mekanik';
  Future<void> _create() async {
    final name = TextEditingController(); final username = TextEditingController(); final pin = TextEditingController();
    String role = 'cashier';
    final ok = await showDialog<bool>(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setDialog) => AlertDialog(
      title: const Text('Tambah Akun'), content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: name, decoration: const InputDecoration(labelText: 'Nama', border: OutlineInputBorder())), const SizedBox(height: 9),
        TextField(controller: username, decoration: const InputDecoration(labelText: 'Username', border: OutlineInputBorder())), const SizedBox(height: 9),
        DropdownButtonFormField<String>(initialValue: role, decoration: const InputDecoration(labelText: 'Peran', border: OutlineInputBorder()), items: const [DropdownMenuItem(value: 'cashier', child: Text('Kasir')), DropdownMenuItem(value: 'mechanic', child: Text('Mekanik')), DropdownMenuItem(value: 'admin', child: Text('Admin'))], onChanged: (v) { if (v != null) setDialog(() => role = v); }), const SizedBox(height: 9),
        TextField(controller: pin, obscureText: true, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'PIN 6–8 digit', border: OutlineInputBorder())),
      ])), actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Simpan'))],
    )));
    if (ok == true) {
      try { await _repo.createAccount(displayName: name.text, username: username.text, pin: pin.text, role: role); _refresh(); }
      catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal: $e'))); }
    }
    name.dispose(); username.dispose(); pin.dispose();
  }
  Future<void> _toggle(Map<String, Object?> user) async {
    final id = user['id'] as int; final active = (user['is_active'] as int? ?? 0) == 1;
    try { await _repo.setAccountActive(id: id, active: !active); _refresh(); }
    catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'))); }
  }
  Future<void> _resetPin(Map<String, Object?> user) async {
    final pin = TextEditingController();
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(title: const Text('Atur Ulang PIN'), content: TextField(controller: pin, obscureText: true, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'PIN baru 6–8 digit')), actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Simpan'))]));
    if (ok == true) { try { await _repo.resetPin(id: user['id'] as int, newPin: pin.text); if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('PIN berhasil diubah.'))); } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'))); } }
    pin.dispose();
  }
  @override
  Widget build(BuildContext context) {
    if (!AuthSession.instance.isAdmin) {
      return Scaffold(appBar: AppBar(title: const Text('Akun & Hak Akses')), body: const Center(child: Text('Akses hanya untuk Admin.')));
    }
    return Scaffold(appBar: AppBar(title: const Text('Akun & Hak Akses')), floatingActionButton: FloatingActionButton.extended(onPressed: _create, icon: const Icon(Icons.person_add_alt_1), label: const Text('Tambah Akun')), body: FutureBuilder<List<Map<String, Object?>>>(future: _future, builder: (context, snap) {
    if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
    if (snap.hasError) return Center(child: Text('Gagal memuat akun: ${snap.error}'));
    final users = snap.data ?? [];
    return ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 90), children: [const Card(child: Padding(padding: EdgeInsets.all(12), child: Text('Akun nonaktif tidak dapat login. Minimal satu Admin harus tetap aktif. PIN disimpan dalam bentuk hash.'))), ...users.map((u) {
      final active = (u['is_active'] as int? ?? 0) == 1;
      return Card(child: ListTile(leading: CircleAvatar(child: Icon(u['role'] == 'admin' ? Icons.admin_panel_settings : u['role'] == 'cashier' ? Icons.point_of_sale : Icons.build)), title: Text(u['display_name'].toString()), subtitle: Text('@${u['username']} • ${_role(u['role']?.toString())} • ${active ? 'Aktif' : 'Nonaktif'}'), trailing: PopupMenuButton<String>(onSelected: (v) { if (v == 'pin') _resetPin(u); if (v == 'active') _toggle(u); }, itemBuilder: (_) => [const PopupMenuItem(value: 'pin', child: Text('Atur ulang PIN')), PopupMenuItem(value: 'active', child: Text(active ? 'Nonaktifkan' : 'Aktifkan'))])));
    })]);
  }));
  }
}
