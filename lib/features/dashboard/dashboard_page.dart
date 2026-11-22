import 'package:material_ui/material_ui.dart';

import '../customers/presentation/customer_list_page.dart';
import '../bicycles/presentation/bicycle_list_page.dart';
import '../services/presentation/service_list_page.dart';
import '../products/presentation/product_list_page.dart';
import '../sales/presentation/cashier_page.dart';
import '../reports/data/report_repository.dart';
import '../reports/presentation/reports_page.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final ReportRepository _reportRepository = ReportRepository();
  late Future<Map<String, Object?>> _summaryFuture;

  @override
  void initState() {
    super.initState();
    _summaryFuture = _loadTodaySummary();
  }

  Future<Map<String, Object?>> _loadTodaySummary() {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    return _reportRepository.getSummary(
      start: start,
      end: start.add(const Duration(days: 1)),
    );
  }

  void _refreshSummary() {
    setState(() => _summaryFuture = _loadTodaySummary());
  }

  int _number(Map<String, Object?>? data, String key) {
    final value = data?[key];
    return value is num ? value.toInt() : 0;
  }

  String _rupiah(int amount) {
    final digits = amount.toString();
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write('.');
      buffer.write(digits[i]);
    }
    return 'Rp$buffer';
  }

  void _showComingSoon(BuildContext context, String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$feature akan tersedia pada tahap berikutnya.')),
    );
  }

  void _openCustomers(BuildContext context) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const CustomerListPage()));
  }

  void _openBicycles(BuildContext context) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const BicycleListPage()));
  }

  void _openServices(BuildContext context) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const ServiceListPage()));
  }

  void _openProducts(BuildContext context) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const ProductListPage()));
  }

  void _openCashier(BuildContext context) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const CashierPage()));
  }

  void _openReports(BuildContext context) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const ReportsPage()));
  }

  Widget _summaryCards(AsyncSnapshot<Map<String, Object?>> snapshot) {
    final data = snapshot.data;
    final loading = snapshot.connectionState == ConnectionState.waiting;
    final failed = snapshot.hasError;
    final income = loading ? '…' : failed ? '--' : _rupiah(_number(data, 'income'));
    final services = loading ? '…' : failed ? '--' : '${_number(data, 'service_count')}';
    final sales = loading ? '…' : failed ? '--' : '${_number(data, 'sales_count')}';
    final lowStock = loading ? '…' : failed ? '--' : '${_number(data, 'low_stock')}';

    return Column(
      children: [
        Row(children: [
          Expanded(child: _SummaryCard(title: 'Pendapatan Hari Ini', value: income, icon: Icons.payments_outlined, color: Colors.green)),
          const SizedBox(width: 12),
          Expanded(child: _SummaryCard(title: 'Servis Masuk', value: services, icon: Icons.build_outlined, color: Colors.blue)),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _SummaryCard(title: 'Penjualan', value: sales, icon: Icons.shopping_cart_outlined, color: Colors.orange)),
          const SizedBox(width: 12),
          Expanded(child: _SummaryCard(title: 'Stok Menipis', value: lowStock, icon: Icons.inventory_2_outlined, color: Colors.red)),
        ]),
        if (failed)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              children: [
                const Expanded(child: Text('Ringkasan belum dapat dimuat.', style: TextStyle(color: Colors.red, fontSize: 12))),
                TextButton(onPressed: _refreshSummary, child: const Text('Coba lagi')),
              ],
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('BengkelKu POS', style: TextStyle(fontWeight: FontWeight.bold)),
            Text('Manajemen Bengkel & Toko Sepeda', style: TextStyle(fontSize: 11)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Perbarui ringkasan',
            onPressed: _refreshSummary,
            icon: const Icon(Icons.refresh),
          ),
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
              const Text('Selamat Datang!', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              const Text('Ringkasan aktivitas bengkel dan toko hari ini.', style: TextStyle(color: Colors.grey)),
              const SizedBox(height: 20),
              FutureBuilder<Map<String, Object?>>(
                future: _summaryFuture,
                builder: (context, snapshot) => _summaryCards(snapshot),
              ),
              const SizedBox(height: 24),
              const Text('Menu Utama', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              GridView.count(
                crossAxisCount: 3,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 0.95,
                children: [
                  _MenuItem(title: 'Kasir', icon: Icons.point_of_sale, onTap: () => _openCashier(context)),
                  _MenuItem(title: 'Servis', icon: Icons.build, onTap: () => _openServices(context)),
                  _MenuItem(title: 'Sepeda', icon: Icons.pedal_bike, onTap: () => _openBicycles(context)),
                  _MenuItem(title: 'Produk', icon: Icons.inventory_2, onTap: () => _openProducts(context)),
                  _MenuItem(title: 'Pelanggan', icon: Icons.people, onTap: () => _openCustomers(context)),
                  _MenuItem(title: 'Laporan', icon: Icons.bar_chart, onTap: () => _openReports(context)),
                ],
              ),
              const SizedBox(height: 24),
              Card(
                child: ListTile(
                  leading: const CircleAvatar(backgroundColor: Color(0xFFE3F2FD), child: Icon(Icons.settings, color: Colors.blue)),
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
  const _SummaryCard({required this.title, required this.value, required this.icon, required this.color});
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
            Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(title, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}

class _MenuItem extends StatelessWidget {
  const _MenuItem({required this.title, required this.icon, required this.onTap});
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
              Icon(icon, size: 30, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 8),
              Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}
