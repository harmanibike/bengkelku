import 'package:material_ui/material_ui.dart';

import '../bicycles/presentation/bicycle_list_page.dart';
import '../customers/presentation/customer_list_page.dart';
import '../products/presentation/product_list_page.dart';
import '../reports/data/report_repository.dart';
import '../reports/presentation/reports_page.dart';
import '../sales/presentation/cashier_page.dart';
import '../services/presentation/service_list_page.dart';

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

  Future<void> _refresh() async {
    final future = _loadTodaySummary();
    setState(() => _summaryFuture = future);
    await future;
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

  String _todayLabel() {
    const months = [
      'Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni',
      'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember',
    ];
    final now = DateTime.now();
    return '${now.day} ${months[now.month - 1]} ${now.year}';
  }

  void _openCustomers() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const CustomerListPage()));
  }

  void _openBicycles() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const BicycleListPage()));
  }

  void _openServices() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const ServiceListPage()));
  }

  void _openProducts() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const ProductListPage()));
  }

  void _openCashier() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const CashierPage()));
  }

  void _openReports() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const ReportsPage()));
  }

  Widget _header() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 30),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF536DFE), Color(0xFF7B1FA2)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white24),
              ),
              child: const Icon(Icons.pedal_bike, color: Colors.white, size: 30),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('BengkelKu', style: TextStyle(color: Colors.white, fontSize: 23, fontWeight: FontWeight.bold)),
                  Text('POS • Manajemen Bengkel Sepeda', style: TextStyle(color: Colors.white70, fontSize: 12)),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  TimeOfDay.now().format(context),
                  style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
                ),
                Text(_todayLabel(), style: const TextStyle(color: Colors.white70, fontSize: 11)),
              ],
            ),
            const SizedBox(width: 10),
            Material(
              color: Colors.white.withValues(alpha: 0.18),
              shape: const CircleBorder(),
              child: IconButton(
                tooltip: 'Perbarui data',
                onPressed: () => _refresh(),
                icon: const Icon(Icons.refresh, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _shopCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: Color(0xFFE9E9EF)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: const Color(0xFFE8EAF6),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(Icons.storefront_rounded, color: Color(0xFF5C6BC0), size: 29),
            ),
            const SizedBox(width: 13),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Bengkel & Toko Sepeda', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  SizedBox(height: 3),
                  Text('Kelola servis, produk, dan transaksi', style: TextStyle(color: Colors.grey, fontSize: 12)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.grey),
          ],
        ),
      ),
    );
  }

  Widget _cashCard(AsyncSnapshot<Map<String, Object?>> snapshot) {
    final data = snapshot.data;
    final loading = snapshot.connectionState == ConnectionState.waiting;
    final failed = snapshot.hasError;
    final income = loading ? 'Memuat…' : failed ? '--' : _rupiah(_number(data, 'income'));
    final expense = loading ? '--' : failed ? '--' : _rupiah(_number(data, 'expense'));
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(19),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF6200EA), Color(0xFF9C27B0)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(color: const Color(0xFF7B1FA2).withValues(alpha: 0.22), blurRadius: 15, offset: const Offset(0, 7)),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), shape: BoxShape.circle),
            child: const Icon(Icons.account_balance_wallet_rounded, color: Colors.white, size: 30),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Kas Masuk Hari Ini', style: TextStyle(color: Colors.white70, fontSize: 13)),
                const SizedBox(height: 4),
                Text(income, style: const TextStyle(color: Colors.white, fontSize: 23, fontWeight: FontWeight.bold)),
                const SizedBox(height: 5),
                Text('Pengeluaran: $expense', style: const TextStyle(color: Colors.white70, fontSize: 11)),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: Colors.white, size: 30),
        ],
      ),
    );
  }

  Widget _startCashierCard() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _openCashier,
        borderRadius: BorderRadius.circular(22),
        child: Ink(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF9C27B0), Color(0xFFBA68C8)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(color: const Color(0xFF9C27B0).withValues(alpha: 0.18), blurRadius: 12, offset: const Offset(0, 5)),
            ],
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 27,
                backgroundColor: Color(0x33FFFFFF),
                child: Icon(Icons.point_of_sale_rounded, color: Colors.white, size: 29),
              ),
              SizedBox(height: 15),
              Text('Mulai Transaksi', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
              SizedBox(height: 4),
              Row(
                children: [
                  Text('Buka Kasir', style: TextStyle(color: Colors.white70, fontSize: 13)),
                  Spacer(),
                  Icon(Icons.arrow_forward_rounded, color: Colors.white),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statCard({
    required String title,
    required String value,
    required String suffix,
    required IconData icon,
    required List<Color> colors,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: colors, begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(19),
        boxShadow: [
          BoxShadow(color: colors.first.withValues(alpha: 0.18), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), shape: BoxShape.circle),
            child: Icon(icon, color: Colors.white, size: 25),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                const SizedBox(height: 3),
                Text(value, style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
                if (suffix.isNotEmpty)
                  Text(suffix, style: const TextStyle(color: Colors.white70, fontSize: 10)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _summary(AsyncSnapshot<Map<String, Object?>> snapshot) {
    final data = snapshot.data;
    final loading = snapshot.connectionState == ConnectionState.waiting;
    final failed = snapshot.hasError;
    String value(String key, {bool currency = false}) {
      if (loading) return '…';
      if (failed) return '--';
      final number = _number(data, key);
      return currency ? _rupiah(number) : number.toString();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Ringkasan Hari Ini', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF263238))),
        const SizedBox(height: 12),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 1.8,
          children: [
            _statCard(title: 'Penjualan', value: value('sales_amount', currency: true), suffix: '${value('sales_count')} transaksi', icon: Icons.trending_up_rounded, colors: const [Color(0xFF43A047), Color(0xFF81C784)]),
            _statCard(title: 'Kas Masuk', value: value('income', currency: true), suffix: 'penerimaan hari ini', icon: Icons.receipt_long_rounded, colors: const [Color(0xFF1E88E5), Color(0xFF64B5F6)]),
            _statCard(title: 'Stok Menipis', value: value('low_stock'), suffix: 'produk', icon: Icons.warning_amber_rounded, colors: const [Color(0xFFFB8C00), Color(0xFFFFB74D)]),
            _statCard(title: 'Pengeluaran', value: value('expense', currency: true), suffix: 'hari ini', icon: Icons.money_off_csred_rounded, colors: const [Color(0xFFE53935), Color(0xFFE57373)]),
          ],
        ),
        if (failed)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => _refresh(),
              icon: const Icon(Icons.refresh),
              label: const Text('Muat ulang ringkasan'),
            ),
          ),
      ],
    );
  }

  Widget _menuTile({
    required String title,
    required IconData icon,
    required List<Color> colors,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Column(
        children: [
          Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: colors, begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(21),
              boxShadow: [
                BoxShadow(color: colors.first.withValues(alpha: 0.2), blurRadius: 9, offset: const Offset(0, 4)),
              ],
            ),
            child: Icon(icon, color: Colors.white, size: 34),
          ),
          const SizedBox(height: 8),
          Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF37474F))),
        ],
      ),
    );
  }

  Widget _menu() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Menu Utama', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF263238))),
        const SizedBox(height: 17),
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 12,
          mainAxisSpacing: 20,
          childAspectRatio: 0.92,
          children: [
            _menuTile(title: 'Kasir', icon: Icons.shopping_cart_rounded, colors: const [Color(0xFF26A69A), Color(0xFF66BB6A)], onTap: _openCashier),
            _menuTile(title: 'Produk', icon: Icons.inventory_2_rounded, colors: const [Color(0xFFEF8D32), Color(0xFFFFB74D)], onTap: _openProducts),
            _menuTile(title: 'Servis', icon: Icons.build_rounded, colors: const [Color(0xFFE91E63), Color(0xFFF06292)], onTap: _openServices),
            _menuTile(title: 'Stok', icon: Icons.bar_chart_rounded, colors: const [Color(0xFF039BE5), Color(0xFF4FC3F7)], onTap: _openProducts),
            _menuTile(title: 'Pelanggan', icon: Icons.people_alt_rounded, colors: const [Color(0xFF3949AB), Color(0xFF7986CB)], onTap: _openCustomers),
            _menuTile(title: 'Sepeda', icon: Icons.pedal_bike_rounded, colors: const [Color(0xFF00897B), Color(0xFF4DB6AC)], onTap: _openBicycles),
            _menuTile(title: 'Laporan', icon: Icons.analytics_rounded, colors: const [Color(0xFF8E24AA), Color(0xFFBA68C8)], onTap: _openReports),
            _menuTile(title: 'Pengeluaran', icon: Icons.money_off_rounded, colors: const [Color(0xFFE64A19), Color(0xFFFF8A65)], onTap: _openReports),
            _menuTile(title: 'Pengaturan', icon: Icons.settings_rounded, colors: const [Color(0xFF546E7A), Color(0xFF90A4AE)], onTap: _openReports),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F5F8),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<Map<String, Object?>>(
          future: _summaryFuture,
          builder: (context, snapshot) {
            return CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(child: _header()),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 30),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      _shopCard(),
                      const SizedBox(height: 15),
                      _cashCard(snapshot),
                      const SizedBox(height: 15),
                      _startCashierCard(),
                      const SizedBox(height: 26),
                      _summary(snapshot),
                      const SizedBox(height: 27),
                      _menu(),
                    ]),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
