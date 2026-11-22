import 'package:material_ui/material_ui.dart';
import '../data/service_pricing_repository.dart';

class ServicePricingPage extends StatefulWidget {
  const ServicePricingPage({super.key});
  @override
  State<ServicePricingPage> createState() => _ServicePricingPageState();
}

class _ServicePricingPageState extends State<ServicePricingPage> with SingleTickerProviderStateMixin {
  final _repo = ServicePricingRepository();
  late final TabController _tabs = TabController(length: 3, vsync: this);
  final _search = TextEditingController();
  List<Map<String, Object?>> _items = [];
  List<Map<String, Object?>> _history = [];
  bool _loading = true;
  bool _authorized = false;
  String _mode = ServicePricingRepository.modeBoth;

  @override
  void initState() { super.initState(); _authorize(); }
  @override
  void dispose() { _tabs.dispose(); _search.dispose(); super.dispose(); }


  Future<void> _authorize() async {
    final configured = await _repo.hasAdminPin();
    if (!mounted) return;
    final pin = TextEditingController();
    final confirm = TextEditingController();
    final ok = await showDialog<bool>(context: context, barrierDismissible: false, builder: (ctx) => AlertDialog(
      title: Text(configured ? 'Verifikasi Admin' : 'Buat PIN Admin'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(configured ? 'Masukkan PIN admin untuk mengelola harga jasa.' : 'Buat PIN admin 6–8 angka. Hanya admin yang boleh mengubah harga jasa.'),
        const SizedBox(height: 10),
        TextField(controller: pin, obscureText: true, keyboardType: TextInputType.number, maxLength: 8, decoration: const InputDecoration(labelText: 'PIN admin')),
        if (!configured) TextField(controller: confirm, obscureText: true, keyboardType: TextInputType.number, maxLength: 8, decoration: const InputDecoration(labelText: 'Ulangi PIN')),
      ]),
      actions: [
        if (configured) TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(configured ? 'Masuk' : 'Simpan PIN')),
      ],
    ));
    try {
      if (ok == true) {
        if (configured) {
          if (!await _repo.verifyAdminPin(pin.text)) throw StateError('PIN admin salah.');
        } else {
          if (pin.text != confirm.text) throw StateError('Konfirmasi PIN tidak cocok.');
          await _repo.setupAdminPin(pin.text);
        }
        if (mounted) { setState(() => _authorized = true); await _load(); }
      } else if (mounted) { Navigator.pop(context); }
    } catch (e) {
      _message(e.toString().replaceFirst('Bad state: ', ''));
      if (mounted) Navigator.pop(context);
    } finally { pin.dispose(); confirm.dispose(); }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final values = await Future.wait([_repo.getServices(keyword: _search.text), _repo.getPriceHistory()]);
      final mode = await _repo.getPriceMode();
      if (!mounted) return;
      setState(() { _items = values[0]; _history = values[1]; _mode = mode; _loading = false; });
    } catch (e) { if (mounted) setState(() => _loading = false); _message('Gagal memuat data: $e'); }
  }

  String _money(Object? value) {
    final s = (value as num? ?? 0).toInt().toString();
    final b = StringBuffer();
    for (var i=0;i<s.length;i++) { if (i>0 && (s.length-i)%3==0) b.write('.'); b.write(s[i]); }
    return 'Rp$b';
  }
  void _message(String s) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s))); }

  Future<void> _edit([Map<String,Object?>? item]) async {
    final name = TextEditingController(text: item?['name']?.toString() ?? '');
    final category = TextEditingController(text: item?['category']?.toString() ?? '');
    final desc = TextEditingController(text: item?['description']?.toString() ?? '');
    final price = TextEditingController(text: (item?['standard_price'] ?? 0).toString());
    final reason = TextEditingController();
    final form = GlobalKey<FormState>();
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: Text(item == null ? 'Tambah Master Jasa' : 'Ubah Master Jasa'),
      content: Form(key: form, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextFormField(controller: name, decoration: const InputDecoration(labelText: 'Nama jasa *'), validator: (v)=>v==null||v.trim().isEmpty?'Wajib diisi':null),
        TextFormField(controller: category, decoration: const InputDecoration(labelText: 'Kategori')),
        TextFormField(controller: desc, decoration: const InputDecoration(labelText: 'Keterangan')),
        TextFormField(controller: price, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Harga standar (Rp) *'), validator: (v)=>int.tryParse(v??'')==null||int.parse(v!)<0?'Nominal tidak valid':null),
        if (item != null) TextFormField(controller: reason, decoration: const InputDecoration(labelText: 'Alasan perubahan harga *'), validator: (v)=>int.tryParse(price.text)!=(item['standard_price'] as int? ?? 0)&&(v==null||v.trim().isEmpty)?'Alasan wajib diisi':null),
      ]))),
      actions: [TextButton(onPressed: ()=>Navigator.pop(ctx,false), child: const Text('Batal')), FilledButton(onPressed: ()=>Navigator.pop(ctx,form.currentState!.validate()), child: const Text('Simpan'))],
    ));
    if (ok == true) {
      try {
        await _repo.saveService(id: item?['id'] as int?, name: name.text, category: category.text, description: desc.text, standardPrice: int.parse(price.text), reason: reason.text);
        await _load(); _message('Master jasa berhasil disimpan.');
      } catch(e) { _message('Gagal menyimpan: $e'); }
    }
    name.dispose(); category.dispose(); desc.dispose(); price.dispose(); reason.dispose();
  }

  @override
  Widget build(BuildContext context) => !_authorized ? const Scaffold(body: Center(child: CircularProgressIndicator())) : Scaffold(
    appBar: AppBar(title: const Text('Harga Jasa Servis'), bottom: TabBar(controller: _tabs, onTap: (_) => setState(() {}), tabs: const [Tab(text:'Master Jasa'),Tab(text:'Riwayat Harga'),Tab(text:'Pengaturan')])),
    floatingActionButton: _tabs.index == 0 ? FloatingActionButton.small(onPressed: ()=>_edit(), child: const Icon(Icons.add)) : null,
    body: _loading ? const Center(child:CircularProgressIndicator()) : TabBarView(controller:_tabs, children:[
      Column(children:[
        Padding(padding: const EdgeInsets.fromLTRB(11,8,11,4), child: TextField(controller:_search, onChanged:(_)=>_load(), decoration: const InputDecoration(prefixIcon:Icon(Icons.search), hintText:'Cari nama atau kategori jasa', isDense:true, border:OutlineInputBorder()))),
        Expanded(child:_items.isEmpty?const Center(child:Text('Belum ada master jasa. Tekan + untuk menambahkan.')):ListView.separated(padding:const EdgeInsets.all(10), itemCount:_items.length, separatorBuilder:(_,__)=>const SizedBox(height:5), itemBuilder:(ctx,i){final x=_items[i]; final active=(x['is_active'] as int? ?? 1)==1; return Card(elevation:0, child:ListTile(dense:true, title:Text(x['name'].toString(),style:const TextStyle(fontWeight:FontWeight.w600)), subtitle:Text('${x['category']??'Tanpa kategori'} • ${_money(x['standard_price'])}'), trailing:PopupMenuButton<String>(onSelected:(v)async{if(v=='edit')_edit(x);if(v=='toggle'){await _repo.setActive(x['id'] as int,!active);_load();}},itemBuilder:(_)=>[const PopupMenuItem(value:'edit',child:Text('Ubah harga/detail')),PopupMenuItem(value:'toggle',child:Text(active?'Nonaktifkan':'Aktifkan'))]))); })),
      _history.isEmpty?const Center(child:Text('Belum ada perubahan harga.')):ListView.separated(padding:const EdgeInsets.all(10),itemCount:_history.length,separatorBuilder:(_,__)=>const SizedBox(height:5),itemBuilder:(ctx,i){final h=_history[i];return Card(elevation:0,child:ListTile(dense:true,title:Text(h['service_name'].toString()),subtitle:Text('${_money(h['old_price'])} → ${_money(h['new_price'])}\n${h['change_reason']??'Tanpa alasan'}'),isThreeLine:true,trailing:Text(h['changed_at'].toString().split('.').first,style:const TextStyle(fontSize:10))));}),
      ListView(padding:const EdgeInsets.all(12),children:[
        Card(elevation:0,child:ListTile(leading:const Icon(Icons.tune),title:const Text('Metode harga: Keduanya'),subtitle:const Text('Harga standar otomatis digunakan sebagai acuan. Admin dapat mengubah harga master secara manual.'),trailing:const Icon(Icons.check_circle,color:Colors.green))),
        const SizedBox(height:8),
        const Card(elevation:0,child:Padding(padding:EdgeInsets.all(12),child:Text('Hak perubahan harga: Admin saja.\n\nCatatan penting: aplikasi saat ini belum memiliki sistem akun dan peran pengguna. Karena itu pembatasan admin secara teknis belum dapat diberlakukan aman pada perangkat bersama. Menu ini belum boleh dianggap sebagai kontrol akses admin sampai modul akun/PIN admin diterapkan.'))),
      ])
    ]),
  );
}
