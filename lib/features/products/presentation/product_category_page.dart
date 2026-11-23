import 'package:material_ui/material_ui.dart';

import '../data/product_repository.dart';

class ProductCategoryPage extends StatefulWidget {
  const ProductCategoryPage({super.key});

  @override
  State<ProductCategoryPage> createState() => _ProductCategoryPageState();
}

class _ProductCategoryPageState extends State<ProductCategoryPage> {
  final ProductRepository _repository = ProductRepository();
  late Future<List<Map<String, Object?>>> _categoriesFuture;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() => _categoriesFuture = _repository.getCategories();

  void _refresh() => setState(_load);

  Future<void> _editCategory({Map<String, Object?>? category}) async {
    final controller = TextEditingController(text: category?['name']?.toString() ?? '');
    final formKey = GlobalKey<FormState>();
    try {
      final saved = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(category == null ? 'Tambah Kategori' : 'Edit Kategori'),
          content: Form(
            key: formKey,
            child: TextFormField(
              controller: controller,
              autofocus: true,
              maxLength: 40,
              decoration: const InputDecoration(
                labelText: 'Nama kategori',
                hintText: 'Contoh: Sparepart',
                border: OutlineInputBorder(),
              ),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Nama kategori wajib diisi.'
                  : null,
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Batal')),
            FilledButton(onPressed: () {
              if (formKey.currentState!.validate()) Navigator.pop(dialogContext, true);
            }, child: const Text('Simpan')),
          ],
        ),
      );
      if (saved != true || !mounted) return;
      if (category == null) {
        await _repository.addCategory(controller.text);
      } else {
        await _repository.updateCategory(id: category['id'] as int, name: controller.text);
      }
      if (!mounted) return;
      _refresh();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(category == null ? 'Kategori ditambahkan.' : 'Kategori diperbarui.'),
      ));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal menyimpan kategori: $error')));
    } finally {
      controller.dispose();
    }
  }

  Future<void> _deleteCategory(Map<String, Object?> category) async {
    final name = category['name']?.toString() ?? 'kategori';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Hapus Kategori?'),
        content: Text('Kategori "$name" akan dihapus. Produk yang memakai kategori ini tetap tersimpan, tetapi kategorinya dikosongkan.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Hapus')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await _repository.deleteCategory(category['id'] as int);
      if (!mounted) return;
      _refresh();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Kategori dihapus. Data produk tetap aman.')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal menghapus kategori: $error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Kategori Produk')),
      body: FutureBuilder<List<Map<String, Object?>>>(
        future: _categoriesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Gagal memuat kategori: ${snapshot.error}'));
          }
          final categories = snapshot.data ?? [];
          if (categories.isEmpty) return const Center(child: Text('Belum ada kategori.'));
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: categories.length,
            separatorBuilder: (_, __) => const SizedBox(height: 6),
            itemBuilder: (context, index) {
              final item = categories[index];
              return Card(
                margin: EdgeInsets.zero,
                child: ListTile(
                  dense: true,
                  leading: const Icon(Icons.category_outlined),
                  title: Text(item['name']?.toString() ?? '-'),
                  trailing: Wrap(
                    spacing: 0,
                    children: [
                      IconButton(tooltip: 'Edit kategori', onPressed: () => _editCategory(category: item), icon: const Icon(Icons.edit_outlined)),
                      IconButton(tooltip: 'Hapus kategori', onPressed: () => _deleteCategory(item), icon: const Icon(Icons.delete_outline)),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _editCategory(),
        icon: const Icon(Icons.add),
        label: const Text('Tambah Kategori'),
      ),
    );
  }
}
