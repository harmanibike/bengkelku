import 'package:material_ui/material_ui.dart';

import '../../products/presentation/product_list_page.dart';
import '../../products/presentation/stock_movement_page.dart';
import '../../products/presentation/stock_opname_page.dart';
import '../../reports/presentation/inventory_valuation_page.dart';
import 'equipment_page.dart';

class InventoryPage extends StatelessWidget {
  const InventoryPage({super.key});

  void _open(BuildContext context, Widget page) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Inventory')),
    body: ListView(padding: const EdgeInsets.all(12), children: [
      const Text('Persediaan Barang', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      _tile(context, 'Daftar Barang & Stok', 'Sparepart, aksesori, dan bahan habis pakai', Icons.inventory_2_outlined, () => _open(context, const ProductListPage())),
      _tile(context, 'Pergerakan Stok', 'Barang masuk, keluar, dan penyesuaian', Icons.swap_vert_circle_outlined, () => _open(context, const StockMovementPage())),
      _tile(context, 'Stok Opname', 'Pencocokan stok fisik dengan catatan aplikasi', Icons.fact_check_outlined, () => _open(context, const StockOpnamePage())),
      _tile(context, 'Nilai Persediaan', 'Rincian jumlah dan nilai modal barang', Icons.price_check_outlined, () => _open(context, const InventoryValuationPage())),
      const SizedBox(height: 18),
      const Text('Inventaris Peralatan Bengkel', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      _tile(context, 'Daftar Peralatan', 'Alat kerja, kondisi, lokasi, nilai perolehan, dan perawatan', Icons.handyman_outlined, () => _open(context, const EquipmentPage())),
      const Padding(padding: EdgeInsets.only(top: 10), child: Text('Peralatan dicatat sebagai aset bengkel dan tidak masuk ke stok barang yang dijual.', style: TextStyle(color: Colors.grey, fontSize: 12))),
    ]),
  );

  Widget _tile(BuildContext context, String title, String subtitle, IconData icon, VoidCallback onTap) =>
    Card(child: ListTile(leading: CircleAvatar(child: Icon(icon)), title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle), trailing: const Icon(Icons.chevron_right), onTap: onTap));
}
