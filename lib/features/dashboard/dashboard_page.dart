import 'dart:io';
import 'package:material_ui/material_ui.dart';

import '../../core/auth/auth_session.dart';
import '../../core/notifications/stock_reminder_notification_service.dart';
import '../settings/presentation/account_pages.dart';
import '../settings/presentation/account_profile_page.dart';

import '../bicycles/presentation/bicycle_list_page.dart';
import '../customers/presentation/customer_list_page.dart';
import '../purchases/presentation/purchases_page.dart';
import '../settings/presentation/settings_page.dart';
import '../reports/data/report_repository.dart';
import '../reports/presentation/reports_page.dart';
import '../reports/presentation/cashbook_page.dart';
import '../reports/presentation/saldo_toko_page.dart';
import '../sales/presentation/cashier_page.dart';
import '../sales/presentation/sales_history_page.dart';
import '../sales/presentation/sale_returns_page.dart';
import '../services/presentation/service_list_page.dart';
import '../services/presentation/service_pricing_page.dart';

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
    StockReminderNotificationService.instance.syncStockReminder();
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
    await StockReminderNotificationService.instance.syncStockReminder();
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

  void _openServicePricing() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const ServicePricingPage()));
  }

  void _openCashier() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const CashierPage()));
  }

  void _openSalesHistory() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const SalesHistoryPage()));
  }

  void _openSaleReturns() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const SaleReturnsPage()));
  }

  void _openSettings() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsPage()));
  }

  void _openReports() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const ReportsPage()));
  }

  void _openCashbook() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const CashbookPage()));
  }

  void _openSaldoToko() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const SaldoTokoPage()));
  }

  void _openPurchases() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const PurchasesPage()));
  }




  Widget _header() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF1558A6), Color(0xFF2478C8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.9),
                  width: 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF0756D8).withValues(alpha: 0.28),
                    blurRadius: 9,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: Image.asset(
                'assets/branding/bike_pos_icon.png',
                width: 50,
                height: 50,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const ColoredBox(
                  color: Color(0xFF0756D8),
                  child: Icon(Icons.pedal_bike_rounded, color: Colors.white, size: 38),
                ),
              ),
            ),
            const Spacer(),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  TimeOfDay.now().format(context),
                  style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                ),
                Text(_todayLabel(), style: const TextStyle(color: Colors.white70, fontSize: 9)),
              ],
            ),
            const SizedBox(width: 4),
            IconButton(
              tooltip: 'Keluar',
              onPressed: () async {
                await clearRememberedLogin();
                AuthSession.instance.signOut();
                if (!mounted) return;
                Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const LoginPage()), (route) => false);
              },
              icon: const Icon(Icons.logout_rounded, color: Colors.white),
            ),
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
    final user = AuthSession.instance.user;
    final role = user?['role'] == 'admin' ? 'Admin' : user?['role'] == 'cashier' ? 'Kasir' : 'Mekanik';
    final photoPath = user?['profile_photo_path']?.toString() ?? '';
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: Color(0xFFE9E9EF)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () async {
          await Navigator.push(context, MaterialPageRoute(builder: (_) => const AccountProfilePage()));
          if (mounted) setState(() {});
        },
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              Container(
                width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFFE8EAF6),
                borderRadius: BorderRadius.circular(13),
              ),
              child: const Icon(Icons.storefront_rounded, color: Color(0xFF5C6BC0), size: 24),
            ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Bengkel & Toko Sepeda', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 17,
                          backgroundColor: const Color(0xFFE8EAF6),
                          backgroundImage: photoPath.isNotEmpty && File(photoPath).existsSync() ? FileImage(File(photoPath)) : null,
                          child: photoPath.isEmpty || !File(photoPath).existsSync()
                              ? Icon(user?['role'] == 'admin' ? Icons.admin_panel_settings : user?['role'] == 'cashier' ? Icons.point_of_sale : Icons.build, size: 18, color: const Color(0xFF5C6BC0))
                              : null,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(user?['display_name']?.toString() ?? '-', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                              Text('@${user?['username'] ?? '-'} • $role', style: const TextStyle(fontSize: 10, color: Colors.grey)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 5),
              const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.edit_outlined, color: Color(0xFF5C6BC0), size: 19),
                  Text('Edit', style: TextStyle(fontSize: 9, color: Color(0xFF5C6BC0))),
                ],
              ),
            ],
          ),
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
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1558A6), Color(0xFF16866A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(17),
        boxShadow: [
          BoxShadow(color: const Color(0xFF1558A6).withValues(alpha: 0.18), blurRadius: 15, offset: const Offset(0, 7)),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), shape: BoxShape.circle),
            child: const Icon(Icons.account_balance_wallet_rounded, color: Colors.white, size: 26),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Kas Masuk Hari Ini', style: TextStyle(color: Colors.white70, fontSize: 13)),
                const SizedBox(height: 4),
                Text(income, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
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
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          width: double.infinity,
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF1767B1), Color(0xFF3B91D5)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(color: const Color(0xFF1558A6).withValues(alpha: 0.16), blurRadius: 12, offset: const Offset(0, 5)),
            ],
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 19,
                backgroundColor: Color(0x33FFFFFF),
                child: Icon(Icons.point_of_sale_rounded, color: Colors.white, size: 29),
              ),
              SizedBox(height: 9),
              Text('Mulai Transaksi', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              SizedBox(height: 3),
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
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: colors, begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(color: colors.first.withValues(alpha: 0.18), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), shape: BoxShape.circle),
            child: Icon(icon, color: Colors.white, size: 26),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                const SizedBox(height: 2),
                Text(value, style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
                if (suffix.isNotEmpty)
                  Text(suffix, style: const TextStyle(color: Colors.white70, fontSize: 9)),
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
        const Text('Ringkasan Hari Ini', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF263238))),
        const SizedBox(height: 5),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 560 ? 3 : 2;
            final ratio = constraints.maxWidth >= 380 ? 2.45 : 2.15;
            return GridView.count(
          crossAxisCount: columns,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 7,
          mainAxisSpacing: 7,
          childAspectRatio: ratio,
          children: [
            _statCard(title: 'Penjualan', value: value('sales_amount', currency: true), suffix: '${value('sales_count')} transaksi', icon: Icons.trending_up_rounded, colors: const [Color(0xFF43A047), Color(0xFF81C784)]),
            _statCard(title: 'Kas Masuk', value: value('income', currency: true), suffix: 'penerimaan hari ini', icon: Icons.receipt_long_rounded, colors: const [Color(0xFF1E88E5), Color(0xFF64B5F6)]),
            _statCard(title: 'Stok Menipis', value: value('low_stock'), suffix: 'produk', icon: Icons.warning_amber_rounded, colors: const [Color(0xFFFB8C00), Color(0xFFFFB74D)]),
            _statCard(title: 'Pengeluaran', value: value('expense', currency: true), suffix: 'hari ini', icon: Icons.money_off_csred_rounded, colors: const [Color(0xFFE53935), Color(0xFFE57373)]),
          ],
            );
          },
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
      borderRadius: BorderRadius.circular(14),
      child: Column(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: colors, begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(color: colors.first.withValues(alpha: 0.2), blurRadius: 9, offset: const Offset(0, 4)),
              ],
            ),
            child: Icon(icon, color: Colors.white, size: 32),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 28,
            child: Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11, height: 1.15, fontWeight: FontWeight.w600, color: Color(0xFF37474F)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _menu() {
    final role = AuthSession.instance.role;
    final tiles = <Widget>[
      if (role != 'mechanic') ...[
        _menuTile(title: 'Kasir', icon: Icons.shopping_cart_rounded, colors: const [Color(0xFF26A69A), Color(0xFF66BB6A)], onTap: _openCashier),
        _menuTile(title: 'Riwayat', icon: Icons.receipt_long_rounded, colors: const [Color(0xFF3949AB), Color(0xFF7986CB)], onTap: _openSalesHistory),
        _menuTile(title: 'Retur', icon: Icons.assignment_return_rounded, colors: const [Color(0xFFEF6C00), Color(0xFFFFB74D)], onTap: _openSaleReturns),
        _menuTile(title: 'Pelanggan', icon: Icons.people_alt_rounded, colors: const [Color(0xFF3949AB), Color(0xFF7986CB)], onTap: _openCustomers),
        _menuTile(title: 'Sepeda', icon: Icons.pedal_bike_rounded, colors: const [Color(0xFF00897B), Color(0xFF4DB6AC)], onTap: _openBicycles),
      ],
      _menuTile(title: 'Servis', icon: Icons.build_rounded, colors: const [Color(0xFFE91E63), Color(0xFFF06292)], onTap: _openServices),
      if (AuthSession.instance.isAdmin) ...[
        _menuTile(title: 'Harga Jasa', icon: Icons.price_change_rounded, colors: const [Color(0xFF1565C0), Color(0xFF64B5F6)], onTap: _openServicePricing),
        _menuTile(title: 'Laporan', icon: Icons.analytics_rounded, colors: const [Color(0xFF8E24AA), Color(0xFFBA68C8)], onTap: _openReports),
        _menuTile(title: 'Saldo Toko', icon: Icons.account_balance_wallet_rounded, colors: const [Color(0xFF00897B), Color(0xFF4DB6AC)], onTap: _openSaldoToko),
        _menuTile(title: 'Buku Kas', icon: Icons.menu_book_rounded, colors: const [Color(0xFF546E7A), Color(0xFF90A4AE)], onTap: _openCashbook),
        _menuTile(title: 'Pengeluaran', icon: Icons.money_off_rounded, colors: const [Color(0xFFE64A19), Color(0xFFFF8A65)], onTap: _openReports),
        _menuTile(title: 'Pembelian', icon: Icons.add_shopping_cart_rounded, colors: const [Color(0xFF00897B), Color(0xFF4DB6AC)], onTap: _openPurchases),
        _menuTile(title: 'Pengaturan', icon: Icons.settings_rounded, colors: const [Color(0xFF546E7A), Color(0xFF90A4AE)], onTap: _openSettings),
      ],
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Menu Utama', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF263238))),
      const SizedBox(height: 4),
      LayoutBuilder(builder: (context, constraints) {
        final columns = constraints.maxWidth >= 560 ? 4 : 3;
        // Beri tinggi cukup untuk ikon dan label agar tidak bertabrakan
        // pada layar ponsel yang memiliki lebar kolom terbatas.
        final ratio = constraints.maxWidth >= 560 ? 1.35 : 1.10;
        return GridView.count(
          padding: EdgeInsets.zero,
          crossAxisCount: columns,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 8,
          mainAxisSpacing: 14,
          childAspectRatio: ratio,
          children: tiles,
        );
      }),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F5F8),
      body: Column(
        children: [
          // Header berada di luar area scroll agar selalu diam di bagian atas.
          _header(),
          // Hanya konten utama yang bergerak saat pengguna menggulir.
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refresh,
              child: FutureBuilder<Map<String, Object?>>(
                future: _summaryFuture,
                builder: (context, snapshot) {
                  return CustomScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
                        sliver: SliverList(
                          delegate: SliverChildListDelegate([
                            _shopCard(),
                            const SizedBox(height: 10),
                            if (AuthSession.instance.isAdmin) ...[
                              _cashCard(snapshot),
                              const SizedBox(height: 10),
                            ],
                            if (!AuthSession.instance.isMechanic) ...[
                              _startCashierCard(),
                              const SizedBox(height: 7),
                            ],
                            if (AuthSession.instance.isAdmin) ...[
                              _summary(snapshot),
                              const SizedBox(height: 9),
                            ],
                            _menu(),
                          ])
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
