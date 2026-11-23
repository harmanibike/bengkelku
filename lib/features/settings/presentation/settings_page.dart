import 'package:material_ui/material_ui.dart';

import '../../business/presentation/business_profile_page.dart';
import 'payment_methods_page.dart';
import 'account_pages.dart';
import 'activity_log_page.dart';
import 'database_backup_page.dart';
import 'device_mode_page.dart';
import '../../../core/auth/auth_session.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  void _open(BuildContext context, Widget page) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => page));
  }

  Widget _item({
    required BuildContext context,
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required Widget page,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        leading: CircleAvatar(
          radius: 20,
          backgroundColor: color.withValues(alpha: 0.12),
          child: Icon(icon, color: color, size: 22),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 11)),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () => _open(context, page),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pengaturan')),
      body: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          if (AuthSession.instance.isAdmin) ...[
          const Text('Akun', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey)),
          const SizedBox(height: 8),
          _item(
            context: context,
            icon: Icons.history_rounded,
            color: const Color(0xFF455A64),
            title: 'Riwayat Aktivitas',
            subtitle: 'Lihat tindakan Admin, Kasir, dan Mekanik',
            page: const ActivityLogPage(),
          ),
          const SizedBox(height: 8),
          _item(
            context: context,
            icon: Icons.admin_panel_settings_rounded,
            color: const Color(0xFF5E35B1),
            title: 'Akun & Hak Akses',
            subtitle: 'Kelola akun Admin, Kasir, dan Mekanik',
            page: const AccountManagementPage(),
          ),
          const SizedBox(height: 8),
          _item(
            context: context,
            icon: Icons.devices_rounded,
            color: const Color(0xFF1565C0),
            title: 'Mode Perangkat',
            subtitle: 'Pengaturan mode Lokal, Server, dan Client',
            page: const DeviceModePage(),
          ),
          const SizedBox(height: 8),
          _item(
            context: context,
            icon: Icons.backup_outlined,
            color: const Color(0xFF0277BD),
            title: 'Backup & Pemulihan Data',
            subtitle: 'Buat salinan database atau pulihkan dari file backup',
            page: const DatabaseBackupPage(),
          ),
          const SizedBox(height: 10),
          ],
          const Text('Usaha', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey)),
          const SizedBox(height: 8),
          _item(
            context: context,
            icon: Icons.storefront_rounded,
            color: const Color(0xFF00897B),
            title: 'Profil Usaha',
            subtitle: 'Nama, alamat, kontak, logo, dan identitas usaha',
            page: const BusinessProfilePage(),
          ),
          const SizedBox(height: 10),
          const Text('Transaksi', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey)),
          const SizedBox(height: 8),
          _item(
            context: context,
            icon: Icons.payments_rounded,
            color: const Color(0xFF1565C0),
            title: 'Metode Pembayaran',
            subtitle: 'Pilih metode pembayaran yang tersedia di kasir',
            page: const PaymentMethodsPage(),
          ),
        ],
      ),
    );
  }
}
