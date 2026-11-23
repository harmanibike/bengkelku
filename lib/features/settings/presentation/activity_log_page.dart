import 'package:material_ui/material_ui.dart';

import '../../../core/auth/auth_session.dart';
import '../../../core/auth/activity_log_repository.dart';

class ActivityLogPage extends StatefulWidget {
  const ActivityLogPage({super.key});

  @override
  State<ActivityLogPage> createState() => _ActivityLogPageState();
}

class _ActivityLogPageState extends State<ActivityLogPage> {
  final ActivityLogRepository _repository = ActivityLogRepository();
  late Future<List<Map<String, Object?>>> _logs;

  @override
  void initState() {
    super.initState();
    _logs = _repository.getRecent();
  }

  String _date(Object? value) {
    final date = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
    if (date == null) return '-';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(date.day)}/${two(date.month)}/${date.year} ${two(date.hour)}:${two(date.minute)}';
  }

  String _role(Object? value) {
    switch (value?.toString()) {
      case 'admin': return 'Admin';
      case 'cashier': return 'Kasir';
      case 'mechanic': return 'Mekanik';
      default: return 'Sistem';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!AuthSession.instance.isAdmin) {
      return Scaffold(
        appBar: AppBar(title: const Text('Riwayat Aktivitas')),
        body: const Center(child: Text('Hanya Admin yang dapat melihat riwayat aktivitas.')),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Riwayat Aktivitas'),
        actions: [
          IconButton(
            tooltip: 'Muat ulang',
            onPressed: () => setState(() => _logs = _repository.getRecent()),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: FutureBuilder<List<Map<String, Object?>>>(
        future: _logs,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Gagal memuat aktivitas: ${snapshot.error}'));
          }
          final logs = snapshot.data ?? const <Map<String, Object?>>[];
          if (logs.isEmpty) {
            return const Center(child: Text('Belum ada aktivitas yang tercatat.'));
          }
          return RefreshIndicator(
            onRefresh: () async => setState(() => _logs = _repository.getRecent()),
            child: ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: logs.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final log = logs[index];
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  leading: CircleAvatar(
                    radius: 18,
                    child: Icon(log['user_role'] == 'mechanic'
                        ? Icons.build_outlined
                        : log['user_role'] == 'cashier'
                            ? Icons.point_of_sale_outlined
                            : Icons.admin_panel_settings_outlined, size: 19),
                  ),
                  title: Text(log['description']?.toString() ?? '-', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  subtitle: Text('${log['user_name']} • ${_role(log['user_role'])}\n${_date(log['created_at'])}', style: const TextStyle(fontSize: 11)),
                  isThreeLine: true,
                );
              },
            ),
          );
        },
      ),
    );
  }
}
