import 'package:material_ui/material_ui.dart';

import '../../../core/auth/auth_session.dart';
import '../data/loyalty_reward_repository.dart';

class LoyaltyRewardsPage extends StatefulWidget {
  const LoyaltyRewardsPage({super.key});

  @override
  State<LoyaltyRewardsPage> createState() => _LoyaltyRewardsPageState();
}

class _LoyaltyRewardsPageState extends State<LoyaltyRewardsPage> {
  final _repository = LoyaltyRewardRepository();
  bool _loading = true;
  List<Map<String, Object?>> _rewards = [];
  List<Map<String, Object?>> _customers = [];
  List<Map<String, Object?>> _history = [];

  bool get _isAdmin => AuthSession.instance.isAdmin;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        _repository.getRewards(),
        _repository.getCustomers(),
        _repository.getRedemptionHistory(),
      ]);
      if (!mounted) return;
      setState(() {
        _rewards = results[0];
        _customers = results[1];
        _history = results[2];
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      _message('Gagal memuat katalog reward: $error');
    }
  }

  void _message(String value) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
  }

  String _typeLabel(String type) {
    switch (type) {
      case 'voucher':
        return 'Voucher belanja';
      case 'service':
        return 'Diskon / jasa servis';
      case 'discount':
        return 'Potongan harga';
      default:
        return 'Hadiah / produk';
    }
  }

  Future<void> _editReward([Map<String, Object?>? reward]) async {
    final name = TextEditingController(text: reward?['name']?.toString() ?? '');
    final points = TextEditingController(text: reward?['points_cost']?.toString() ?? '100');
    final description = TextEditingController(text: reward?['description']?.toString() ?? '');
    var type = reward?['reward_type']?.toString() ?? 'voucher';
    final formKey = GlobalKey<FormState>();
    try {
      final saved = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: Text(reward == null ? 'Tambah Reward' : 'Edit Reward'),
            content: SizedBox(
              width: 440,
              child: SingleChildScrollView(
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        controller: name,
                        decoration: const InputDecoration(labelText: 'Nama reward', border: OutlineInputBorder()),
                        validator: (value) => value == null || value.trim().isEmpty ? 'Nama wajib diisi' : null,
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        value: type,
                        decoration: const InputDecoration(labelText: 'Jenis reward', border: OutlineInputBorder()),
                        items: const [
                          DropdownMenuItem(value: 'voucher', child: Text('Voucher belanja')),
                          DropdownMenuItem(value: 'discount', child: Text('Potongan harga')),
                          DropdownMenuItem(value: 'service', child: Text('Diskon / jasa servis')),
                          DropdownMenuItem(value: 'gift', child: Text('Hadiah / produk')),
                        ],
                        onChanged: (value) => setDialogState(() => type = value ?? 'gift'),
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: points,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Poin yang dibutuhkan', border: OutlineInputBorder()),
                        validator: (value) {
                          final number = int.tryParse(value ?? '');
                          return number == null || number <= 0 ? 'Masukkan poin lebih dari 0' : null;
                        },
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: description,
                        maxLines: 3,
                        decoration: const InputDecoration(labelText: 'Keterangan / syarat penggunaan', border: OutlineInputBorder()),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Batal')),
              FilledButton(
                onPressed: () {
                  if (formKey.currentState!.validate()) Navigator.pop(dialogContext, true);
                },
                child: const Text('Simpan'),
              ),
            ],
          ),
        ),
      );
      if (saved != true) return;
      await _repository.saveReward(
        id: reward?['id'] as int?,
        name: name.text,
        type: type,
        pointsCost: int.parse(points.text),
        description: description.text,
      );
      await _load();
      _message('Reward berhasil disimpan.');
    } catch (error) {
      _message('Gagal menyimpan reward: $error');
    } finally {
      name.dispose();
      points.dispose();
      description.dispose();
    }
  }

  Future<void> _redeem(Map<String, Object?> reward) async {
    if (_customers.isEmpty) {
      _message('Belum ada data pelanggan. Tambahkan pelanggan terlebih dahulu.');
      return;
    }
    int? selectedCustomer;
    final available = _customers.where((c) => (c['points'] as int? ?? 0) >= (reward['points_cost'] as int)).toList();
    if (available.isEmpty) {
      _message('Belum ada pelanggan dengan poin yang cukup untuk reward ini.');
      return;
    }
    selectedCustomer = available.first['id'] as int;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Tukar Poin Pelanggan'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Reward: ${reward['name']}'),
              Text('Biaya: ${reward['points_cost']} poin'),
              const SizedBox(height: 14),
              DropdownButtonFormField<int>(
                value: selectedCustomer,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Pilih pelanggan', border: OutlineInputBorder()),
                items: available.map((customer) => DropdownMenuItem<int>(
                  value: customer['id'] as int,
                  child: Text('${customer['name']} — ${customer['points']} poin', overflow: TextOverflow.ellipsis),
                )).toList(),
                onChanged: (value) => setDialogState(() => selectedCustomer = value),
              ),
              const SizedBox(height: 10),
              const Text('Poin akan langsung dipotong dan penukaran dicatat setelah dikonfirmasi. Pastikan hadiah diberikan kepada pelanggan.'),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Batal')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Konfirmasi Penukaran')),
          ],
        ),
      ),
    );
    if (confirmed != true || selectedCustomer == null) return;
    try {
      await _repository.redeem(customerId: selectedCustomer!, rewardId: reward['id'] as int);
      await _load();
      _message('Penukaran berhasil dicatat dan poin pelanggan telah dipotong.');
    } catch (error) {
      _message('Penukaran gagal: $error');
    }
  }

  Future<void> _toggleReward(Map<String, Object?> reward) async {
    try {
      final active = (reward['is_active'] as int? ?? 1) == 1;
      await _repository.setRewardActive(reward['id'] as int, !active);
      await _load();
    } catch (error) {
      _message('Gagal mengubah status reward: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Loyalty & Reward'),
        actions: [
          if (_isAdmin)
            IconButton(
              tooltip: 'Tambah reward',
              onPressed: () => _editReward(),
              icon: const Icon(Icons.add),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(14),
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        children: [
                          const Icon(Icons.stars_rounded, size: 34, color: Color(0xFFFFA000)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Katalog Loyalty & Reward', style: TextStyle(fontWeight: FontWeight.bold)),
                                Text(_isAdmin
                                    ? 'Admin dapat mengatur hadiah. Kasir dapat mencatat penukaran poin.'
                                    : 'Pilih hadiah dan tukarkan poin pelanggan.'),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Expanded(child: Text('Daftar Reward', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
                      if (_isAdmin)
                        TextButton.icon(onPressed: () => _editReward(), icon: const Icon(Icons.add), label: const Text('Tambah')),
                    ],
                  ),
                  if (_rewards.isEmpty)
                    const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('Belum ada reward. Admin dapat menambahkan hadiah pertama.'))),
                  ..._rewards.map((reward) {
                    final active = (reward['is_active'] as int? ?? 1) == 1;
                    return Card(
                      child: ListTile(
                        leading: CircleAvatar(child: Icon(reward['reward_type'] == 'voucher' ? Icons.confirmation_number_outlined : Icons.card_giftcard)),
                        title: Text(reward['name']?.toString() ?? ''),
                        subtitle: Text('${reward['points_cost']} poin • ${_typeLabel(reward['reward_type']?.toString() ?? 'gift')}\n${reward['description'] ?? ''}'),
                        isThreeLine: true,
                        trailing: _isAdmin
                            ? PopupMenuButton<String>(
                                onSelected: (value) {
                                  if (value == 'edit') _editReward(reward);
                                  if (value == 'toggle') _toggleReward(reward);
                                },
                                itemBuilder: (_) => [
                                  const PopupMenuItem(value: 'edit', child: Text('Edit')),
                                  PopupMenuItem(value: 'toggle', child: Text(active ? 'Nonaktifkan' : 'Aktifkan')),
                                ],
                              )
                            : null,
                        enabled: active,
                        onTap: active ? () => _redeem(reward) : null,
                      ),
                    );
                  }),
                  const SizedBox(height: 12),
                  const Text('Riwayat Penukaran', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  if (_history.isEmpty)
                    const Card(child: Padding(padding: EdgeInsets.all(14), child: Text('Belum ada penukaran reward.')))
                  else
                    ..._history.take(30).map((entry) => ListTile(
                      dense: true,
                      leading: const Icon(Icons.check_circle_outline, color: Colors.green),
                      title: Text(entry['reward_name']?.toString() ?? 'Reward'),
                      subtitle: Text('Pelanggan ID: ${entry['customer_id']} • ${entry['created_at']}'),
                      trailing: Text('-${entry['points_spent']} poin'),
                    )),
                ],
              ),
            ),
    );
  }
}
