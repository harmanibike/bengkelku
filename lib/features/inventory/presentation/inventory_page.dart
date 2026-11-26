import 'package:flutter/material.dart';

import '../../products/presentation/product_list_page.dart';
import '../../products/presentation/stock_movement_page.dart';
import '../../products/presentation/stock_opname_page.dart';
import '../../reports/presentation/inventory_valuation_page.dart';

class InventoryPage extends StatelessWidget {
  const InventoryPage({super.key});

  void _open(BuildContext context, Widget page) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    final items = <_InventoryAction>[
      _InventoryAction(
        title: 'Daftar Barang',
        subtitle: 'Kelola produk, SKU, barcode, harga, dan jumlah stok.',
        icon: Icons.inventory_2_outlined,
        color: const Color(0xFF1976D2),
        page: const ProductListPage(),
      ),
      _InventoryAction(
        title: 'Audit Pergerakan Stok',
        subtitle: 'Telusuri stok masuk dan keluar beserta sumber transaksinya.',
        icon: Icons.swap_vert_circle_outlined,
        color: const Color(0xFF00897B),
        page: const StockMovementPage(),
      ),
      _InventoryAction(
        title: 'Stok Opname',
        subtitle: 'Cocokkan stok sistem dengan jumlah fisik di toko.',
        icon: Icons.fact_check_outlined,
        color: const Color(0xFFEF8C24),
        page: const StockOpnamePage(),
      ),
      _InventoryAction(
        title: 'Nilai Persediaan',
        subtitle: 'Lihat jumlah stok dan estimasi nilai modal barang.',
        icon: Icons.account_balance_outlined,
        color: const Color(0xFF7B4BC4),
        page: const InventoryValuationPage(),
      ),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Inventory')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFEAF3FC),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.warehouse_outlined, color: Color(0xFF1558A6), size: 30),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Manajemen Persediaan', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                      SizedBox(height: 4),
                      Text(
                        'Pantau barang, periksa perubahan stok, lakukan stok opname, dan lihat nilai modal persediaan.',
                        style: TextStyle(fontSize: 12, height: 1.4, color: Color(0xFF455A64)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          ...items.map((item) => Card(
            margin: const EdgeInsets.only(bottom: 9),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              leading: CircleAvatar(
                radius: 22,
                backgroundColor: item.color.withValues(alpha: 0.12),
                child: Icon(item.icon, color: item.color),
              ),
              title: Text(item.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text(item.subtitle, style: const TextStyle(fontSize: 11, height: 1.3)),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _open(context, item.page),
            ),
          )),
        ],
      ),
    );
  }
}

class _InventoryAction {
  const _InventoryAction({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.page,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final Widget page;
}
