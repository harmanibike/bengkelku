
import 'package:material_ui/material_ui.dart';

import '../customers/presentation/customer_list_page.dart';
import '../bicycles/presentation/bicycle_list_page.dart';

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  void _showComingSoon(BuildContext context, String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$feature akan tersedia pada tahap berikutnya.'),
      ),
    );
  }

  void _openCustomers(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const CustomerListPage(),
      ),
    );
  }

  void _openBicycles(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const BicycleListPage(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'BengkelKu POS',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            Text(
              'Manajemen Bengkel & Toko Sepeda',
              style: TextStyle(fontSize: 11),
            ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: () => _showComingSoon(context, 'Notifikasi'),
            icon: const Icon(Icons.notifications_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Selamat Datang!',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Ringkasan aktivitas bengkel dan toko hari ini.',
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 20),
              const Row(
                children: [
                  Expanded(
                    child: _SummaryCard(
                      title: 'Pendapatan',
                      value: 'Rp0',
                      icon: Icons.payments_outlined,
                      color: Colors.green,
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: _SummaryCard(
                      title: 'Servis Masuk',
                      value: '0',
                      icon: Icons.build_outlined,
                      color: Colors.blue,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Row(
                children: [
                  Expanded(
                    child: _SummaryCard(
                      title: 'Penjualan',
                      value: '0',
                      icon: Icons.shopping_cart_outlined,
                      color: Colors.orange,
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: _SummaryCard(
                      title: 'Stok Menipis',
                      value: '0',
                      icon: Icons.inventory_2_outlined,
                      color: Colors.red,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              const Text(
                'Menu Utama',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              GridView.count(
                crossAxisCount: 3,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 0.95,
                children: [
                  _MenuItem(
                    title: 'Kasir',
                    icon: Icons.point_of_sale,
                    onTap: () => _showComingSoon(context, 'Kasir'),
                  ),
                  _MenuItem(
                    title: 'Servis',
                    icon: Icons.build,
                    onTap: () => _showComingSoon(context, 'Servis'),
                  ),
                  _MenuItem(
                    title: 'Sepeda',
                    icon: Icons.pedal_bike,
                    onTap: () => _openBicycles(context),
                  ),
                  _MenuItem(
                    title: 'Produk',
                    icon: Icons.inventory_2,
                    onTap: () => _showComingSoon(context, 'Produk'),
                  ),
                  _MenuItem(
                    title: 'Pelanggan',
                    icon: Icons.people,
                    onTap: () => _openCustomers(context),
                  ),
                  _MenuItem(
                    title: 'Laporan',
                    icon: Icons.bar_chart,
                    onTap: () => _showComingSoon(context, 'Laporan'),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Card(
                child: ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Color(0xFFE3F2FD),
                    child: Icon(Icons.settings, color: Colors.blue),
                  ),
                  title: const Text('Pengaturan Aplikasi'),
                  subtitle: const Text('Profil, perangkat, dan konfigurasi'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _showComingSoon(context, 'Pengaturan'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String title;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 25),
            const SizedBox(height: 12),
            Text(
              value,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: const TextStyle(
                fontSize: 12,
                color: Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MenuItem extends StatelessWidget {
  const _MenuItem({
    required this.title,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 30,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 8),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
