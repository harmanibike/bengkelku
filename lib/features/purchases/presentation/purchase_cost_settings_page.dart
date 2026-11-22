import 'package:material_ui/material_ui.dart';

import '../data/purchase_cost_settings_repository.dart';

class PurchaseCostSettingsPage extends StatefulWidget {
  const PurchaseCostSettingsPage({super.key});

  @override
  State<PurchaseCostSettingsPage> createState() => _PurchaseCostSettingsPageState();
}

class _PurchaseCostSettingsPageState extends State<PurchaseCostSettingsPage> {
  final _repository = PurchaseCostSettingsRepository();
  late Future<String> _methodFuture;
  bool _saving = false;

  static const _descriptions = <String, String>{
    PurchaseCostSettingsRepository.weightedAverage:
        'Harga beli master dihitung dari total nilai stok lama ditambah nilai pembelian baru, dibagi jumlah stok setelah pembelian. Cocok untuk harga pokok rata-rata.',
    PurchaseCostSettingsRepository.lastCost:
        'Harga beli master langsung mengikuti harga satuan pada pembelian terbaru. Stok lama tidak mengubah harga terakhir.',
    PurchaseCostSettingsRepository.manual:
        'Pembelian tidak mengubah harga beli master. Harga hanya berubah ketika diedit secara manual pada data produk.',
    PurchaseCostSettingsRepository.perBatch:
        'Setiap penerimaan disimpan sebagai batch dengan harga dan sisa kuantitas sendiri. Penjualan memakai batch terlama lebih dahulu (FIFO) untuk menghitung harga pokok.',
  };

  @override
  void initState() {
    super.initState();
    _methodFuture = _repository.getMethod();
  }

  Future<void> _select(String value) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await _repository.setMethod(value);
      if (!mounted) return;
      setState(() => _methodFuture = Future.value(value));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Metode harga beli: ${PurchaseCostSettingsRepository.methods[value]}')),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Pengaturan gagal disimpan: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _option(String value, String title, IconData icon) {
    return FutureBuilder<String>(
      future: _methodFuture,
      builder: (context, snapshot) {
        final selected = snapshot.data == value;
        return Card(
          margin: const EdgeInsets.only(bottom: 7),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(11),
            side: BorderSide(
              color: selected ? Theme.of(context).colorScheme.primary : Colors.grey.shade300,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(11),
            onTap: _saving || !snapshot.hasData ? null : () => _select(value),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, size: 21, color: selected ? Theme.of(context).colorScheme.primary : Colors.grey),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 3),
                        Text(_descriptions[value]!, style: const TextStyle(fontSize: 10.5, color: Colors.grey, height: 1.3)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    selected ? Icons.radio_button_checked : Icons.radio_button_off,
                    size: 19,
                    color: selected ? Theme.of(context).colorScheme.primary : Colors.grey,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Metode Update Harga Beli')),
      body: FutureBuilder<String>(
        future: _methodFuture,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Gagal memuat pengaturan: ${snapshot.error}'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          return ListView(
            padding: const EdgeInsets.all(11),
            children: [
              const Text(
                'Pilih cara aplikasi memperbarui harga beli produk ketika barang masuk dari pembelian.',
                style: TextStyle(fontSize: 12, color: Colors.black87),
              ),
              const SizedBox(height: 10),
              _option(PurchaseCostSettingsRepository.weightedAverage, 'Rata-rata tertimbang', Icons.calculate_outlined),
              _option(PurchaseCostSettingsRepository.lastCost, 'Harga akhir', Icons.update_rounded),
              _option(PurchaseCostSettingsRepository.manual, 'Manual', Icons.edit_note_rounded),
              _option(PurchaseCostSettingsRepository.perBatch, 'Per batch (FIFO)', Icons.inventory_2_outlined),
              const SizedBox(height: 5),
              Card(
                elevation: 0,
                color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
                child: const Padding(
                  padding: EdgeInsets.all(10),
                  child: Text(
                    'Catatan: pengaturan berlaku untuk transaksi pembelian berikutnya. Harga pada nota pembelian lama tetap tersimpan. Metode per batch menggunakan stok saldo awal sebagai batch pembuka untuk produk yang sudah memiliki stok.',
                    style: TextStyle(fontSize: 10.5, height: 1.35),
                  ),
                ),
              ),
              if (_saving) const LinearProgressIndicator(minHeight: 2),
            ],
          );
        },
      ),
    );
  }
}
