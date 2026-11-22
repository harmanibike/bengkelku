
import 'package:material_ui/material_ui.dart';

import '../../customers/data/customer_repository.dart';

class BicycleListPage extends StatefulWidget {
  const BicycleListPage({super.key});

  @override
  State<BicycleListPage> createState() => _BicycleListPageState();
}

class _BicycleListPageState extends State<BicycleListPage> {
  final CustomerRepository _repository = CustomerRepository();
  final TextEditingController _searchController = TextEditingController();

  List<Map<String, Object?>> _bicycles = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadBicycles();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadBicycles() async {
    setState(() => _loading = true);

    try {
      final data = await _repository.getBicycles(
        keyword: _searchController.text,
      );

      if (!mounted) return;

      setState(() {
        _bicycles = data;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() => _loading = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal memuat data sepeda: $e')),
      );
    }
  }

  Future<void> _showBicycleForm({
    Map<String, Object?>? bicycle,
  }) async {
    final customers = await _repository.getCustomers();

    if (!mounted) return;

    final brand = TextEditingController(
      text: bicycle?['brand']?.toString() ?? '',
    );

    final model = TextEditingController(
      text: bicycle?['model']?.toString() ?? '',
    );

    final color = TextEditingController(
      text: bicycle?['color']?.toString() ?? '',
    );

    final size = TextEditingController(
      text: bicycle?['frame_size']?.toString() ?? '',
    );

    final serial = TextEditingController(
      text: bicycle?['serial_number']?.toString() ?? '',
    );

    final notes = TextEditingController(
      text: bicycle?['notes']?.toString() ?? '',
    );

    const types = [
      'Standar',
      'MTB',
      'BMX',
      'Road Bike',
      'Lipat',
      'Anak',
      'E-Bike',
      'Lainnya',
    ];

    String selectedType =
        bicycle?['bicycle_type']?.toString() ?? 'Standar';

    int? selectedCustomer = bicycle?['customer_id'] == null
        ? null
        : int.tryParse(bicycle!['customer_id'].toString());

    if (selectedCustomer != null &&
        !customers.any(
          (customer) =>
              int.tryParse(customer['id'].toString()) == selectedCustomer,
        )) {
      selectedCustomer = null;
    }

    await showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(
                bicycle == null ? 'Tambah Sepeda' : 'Ubah Sepeda',
              ),
              content: SizedBox(
                width: 420,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DropdownButtonFormField<int?>(
                        initialValue: selectedCustomer,
                        decoration: const InputDecoration(
                          labelText: 'Pemilik',
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          const DropdownMenuItem<int?>(
                            value: null,
                            child: Text('Belum ada pemilik'),
                          ),
                          ...customers.map(
                            (customer) => DropdownMenuItem<int?>(
                              value: int.parse(
                                customer['id'].toString(),
                              ),
                              child: Text(
                                customer['name'].toString(),
                              ),
                            ),
                          ),
                        ],
                        onChanged: (value) {
                          setDialogState(() {
                            selectedCustomer = value;
                          });
                        },
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: brand,
                        decoration: const InputDecoration(
                          labelText: 'Merek sepeda',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: model,
                        decoration: const InputDecoration(
                          labelText: 'Model sepeda',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        initialValue: types.contains(selectedType)
                            ? selectedType
                            : 'Lainnya',
                        decoration: const InputDecoration(
                          labelText: 'Jenis sepeda',
                          border: OutlineInputBorder(),
                        ),
                        items: types.map((type) {
                          return DropdownMenuItem<String>(
                            value: type,
                            child: Text(type),
                          );
                        }).toList(),
                        onChanged: (value) {
                          if (value != null) {
                            setDialogState(() {
                              selectedType = value;
                            });
                          }
                        },
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: color,
                        decoration: const InputDecoration(
                          labelText: 'Warna',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: size,
                        decoration: const InputDecoration(
                          labelText: 'Ukuran frame',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: serial,
                        decoration: const InputDecoration(
                          labelText: 'Nomor rangka / serial',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: notes,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          labelText: 'Catatan',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Batal'),
                ),
                FilledButton(
                  onPressed: () async {
                    try {
                      final id = bicycle == null
                          ? null
                          : int.parse(bicycle['id'].toString());

                      if (id == null) {
                        await _repository.addBicycle(
                          customerId: selectedCustomer,
                          brand: brand.text,
                          model: model.text,
                          bicycleType: selectedType,
                          color: color.text,
                          frameSize: size.text,
                          serialNumber: serial.text,
                          notes: notes.text,
                        );
                      } else {
                        await _repository.updateBicycle(
                          id: id,
                          customerId: selectedCustomer,
                          brand: brand.text,
                          model: model.text,
                          bicycleType: selectedType,
                          color: color.text,
                          frameSize: size.text,
                          serialNumber: serial.text,
                          notes: notes.text,
                        );
                      }

                      if (!dialogContext.mounted) return;

                      Navigator.pop(dialogContext);
                      await _loadBicycles();
                    } catch (e) {
                      if (!dialogContext.mounted) return;

                      ScaffoldMessenger.of(dialogContext).showSnackBar(
                        SnackBar(
                          content: Text('Gagal menyimpan sepeda: $e'),
                        ),
                      );
                    }
                  },
                  child: const Text('Simpan'),
                ),
              ],
            );
          },
        );
      },
    );

    brand.dispose();
    model.dispose();
    color.dispose();
    size.dispose();
    serial.dispose();
    notes.dispose();
  }

  Future<void> _deleteBicycle(
    Map<String, Object?> bicycle,
  ) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hapus Sepeda?'),
        content: const Text(
          'Data sepeda ini akan dihapus. Lanjutkan?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await _repository.deleteBicycle(
        int.parse(bicycle['id'].toString()),
      );

      await _loadBicycles();
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal menghapus sepeda: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Data Sepeda'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showBicycleForm(),
        icon: const Icon(Icons.add),
        label: const Text('Tambah Sepeda'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _searchController,
              onChanged: (_) => _loadBicycles(),
              decoration: InputDecoration(
                hintText: 'Cari merek, model, serial, pemilik...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  onPressed: () {
                    _searchController.clear();
                    _loadBicycles();
                  },
                  icon: const Icon(Icons.clear),
                ),
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(),
                  )
                : _bicycles.isEmpty
                    ? const Center(
                        child: Text('Belum ada data sepeda.'),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(
                          16,
                          0,
                          16,
                          90,
                        ),
                        itemCount: _bicycles.length,
                        itemBuilder: (context, index) {
                          final bike = _bicycles[index];

                          final title = [
                            bike['brand'],
                            bike['model'],
                          ]
                              .where(
                                (value) =>
                                    value != null &&
                                    value.toString().isNotEmpty,
                              )
                              .join(' ');

                          return Card(
                            child: ListTile(
                              leading: const CircleAvatar(
                                child: Icon(Icons.pedal_bike),
                              ),
                              title: Text(
                                title.isEmpty
                                    ? 'Sepeda tanpa nama'
                                    : title,
                              ),
                              subtitle: Text(
                                'Pemilik: ${bike['customer_name'] ?? '-'}\n'
                                'Jenis: ${bike['bicycle_type'] ?? '-'}\n'
                                'Serial: ${bike['serial_number'] ?? '-'}',
                              ),
                              isThreeLine: true,
                              trailing: PopupMenuButton<String>(
                                onSelected: (value) {
                                  if (value == 'edit') {
                                    _showBicycleForm(bicycle: bike);
                                  } else if (value == 'delete') {
                                    _deleteBicycle(bike);
                                  }
                                },
                                itemBuilder: (context) => const [
                                  PopupMenuItem(
                                    value: 'edit',
                                    child: Text('Ubah'),
                                  ),
                                  PopupMenuItem(
                                    value: 'delete',
                                    child: Text('Hapus'),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
