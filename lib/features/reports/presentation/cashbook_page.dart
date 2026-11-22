import 'package:material_ui/material_ui.dart';

import '../data/cashbook_repository.dart';

class CashbookPage extends StatefulWidget {
  const CashbookPage({super.key});

  @override
  State<CashbookPage> createState() => _CashbookPageState();
}

class _CashbookPageState extends State<CashbookPage> {
  final _repo = CashbookRepository();
  String _period = 'today';
  String _type = 'all';
  late Future<Map<String,Object?>> _future;

  @override
  void initState() { super.initState(); _future = _load(); }

  (DateTime,DateTime) _range() {
    final now=DateTime.now();
    if(_period=='today') {
      final start=DateTime(now.year,now.month,now.day);
      return (start,start.add(const Duration(days:1)));
    }
    if(_period=='month') {
      return (DateTime(now.year,now.month),DateTime(now.year,now.month+1));
    }
    return (DateTime(2000),now.add(const Duration(days:1)));
  }

  Future<Map<String,Object?>> _load() {
    final range=_range();
    return _repo.getLedger(start:range.$1,end:range.$2,type:_type);
  }

  void _refresh() => setState(()=>_future=_load());

  String _money(Object? value) {
    final amount=(value as num?)?.toInt() ?? 0;
    final digits=amount.abs().toString();
    final buffer=StringBuffer();
    for(var i=0;i<digits.length;i++) {
      if(i>0 && (digits.length-i)%3==0) buffer.write('.');
      buffer.write(digits[i]);
    }
    return '${amount<0?'-':''}Rp$buffer';
  }

  Future<void> _addEntry() async {
    final formKey=GlobalKey<FormState>();
    final category=TextEditingController();
    final description=TextEditingController();
    final amount=TextEditingController();
    var type='expense';
    final saved=await showDialog<bool>(context:context,builder:(dialogContext)=>StatefulBuilder(
      builder:(context,setDialogState)=>AlertDialog(
        title:const Text('Catat transaksi kas'),
        content:SingleChildScrollView(child:Form(
          key:formKey,
          child:Column(mainAxisSize:MainAxisSize.min,children:[
            DropdownButtonFormField<String>(
              initialValue:type,
              decoration:const InputDecoration(labelText:'Jenis transaksi'),
              items:const [
                DropdownMenuItem(value:'income',child:Text('Kas masuk')),
                DropdownMenuItem(value:'expense',child:Text('Kas keluar')),
              ],
              onChanged:(v){if(v!=null)setDialogState(()=>type=v);},
            ),
            TextFormField(controller:category,decoration:const InputDecoration(labelText:'Kategori'),validator:(v)=>v==null||v.trim().isEmpty?'Wajib diisi':null),
            TextFormField(controller:description,decoration:const InputDecoration(labelText:'Keterangan'),validator:(v)=>v==null||v.trim().isEmpty?'Wajib diisi':null),
            TextFormField(controller:amount,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'Nominal (Rp)'),validator:(v){final n=int.tryParse(v?.replaceAll('.','').trim()??'');return n==null||n<=0?'Nominal tidak valid':null;}),
          ]),
        )),
        actions:[
          TextButton(onPressed:()=>Navigator.pop(dialogContext,false),child:const Text('Batal')),
          FilledButton(onPressed:(){
            if(formKey.currentState?.validate()??false) Navigator.pop(dialogContext,true);
          },child:const Text('Simpan')),
        ],
      ),
    ));
    if(saved==true) {
      try {
        await _repo.addManualTransaction(
          type:type,category:category.text,description:description.text,
          amount:int.parse(amount.text.replaceAll('.','').trim()));
        _refresh();
        if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Transaksi kas disimpan.')));
      } catch(e) {
        if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.toString())));
      }
    }
    category.dispose(); description.dispose(); amount.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar:AppBar(title:const Text('Buku Kas')),
    floatingActionButton:FloatingActionButton.extended(
      onPressed:_addEntry,icon:const Icon(Icons.add),label:const Text('Catat Kas')),
    body:FutureBuilder<Map<String,Object?>>(
      future:_future,
      builder:(context,snapshot) {
        if(snapshot.connectionState==ConnectionState.waiting) return const Center(child:CircularProgressIndicator());
        if(snapshot.hasError) return Center(child:Text('Gagal memuat buku kas: ${snapshot.error}'));
        final data=snapshot.data ?? {};
        final entries=(data['entries'] as List?) ?? [];
        final income=(data['income'] as num?)?.toInt() ?? 0;
        final expense=(data['expense'] as num?)?.toInt() ?? 0;
        return RefreshIndicator(onRefresh:() async=>_refresh(),child:ListView(
          padding:const EdgeInsets.fromLTRB(12,8,12,88),
          children:[
            Row(children:[
              Expanded(child:DropdownButtonFormField<String>(
                initialValue:_period,
                decoration:const InputDecoration(labelText:'Periode',isDense:true),
                items:const [
                  DropdownMenuItem(value:'today',child:Text('Hari ini')),
                  DropdownMenuItem(value:'month',child:Text('Bulan ini')),
                  DropdownMenuItem(value:'all',child:Text('Semua waktu')),
                ],
                onChanged:(v){if(v!=null)setState(()=>_period=v);_refresh();},
              )),
              const SizedBox(width:8),
              Expanded(child:DropdownButtonFormField<String>(
                initialValue:_type,
                decoration:const InputDecoration(labelText:'Jenis',isDense:true),
                items:const [
                  DropdownMenuItem(value:'all',child:Text('Semua')),
                  DropdownMenuItem(value:'income',child:Text('Kas masuk')),
                  DropdownMenuItem(value:'expense',child:Text('Kas keluar')),
                ],
                onChanged:(v){if(v!=null)setState(()=>_type=v);_refresh();},
              )),
            ]),
            const SizedBox(height:10),
            Card(child:Padding(padding:const EdgeInsets.all(12),child:Column(children:[
              _balanceLine('Saldo awal',data['opening_balance']),
              const Divider(height:14),
              _balanceLine('Kas masuk',income,color:Colors.green),
              _balanceLine('Kas keluar',expense,color:Colors.red),
              const Divider(height:14),
              _balanceLine('Saldo akhir',data['closing_balance'],bold:true),
            ]))),
            const SizedBox(height:8),
            Text('Riwayat Transaksi (${data['count'] ?? 0})',style:Theme.of(context).textTheme.titleMedium),
            if(entries.isEmpty) const Card(child:Padding(padding:EdgeInsets.all(12),child:Text('Belum ada transaksi pada periode ini.')))
            else ...entries.map((raw) {
              final row=raw as Map<String,Object?>;
              final incomeRow=row['transaction_type']=='income';
              final amount=(row['amount'] as num?)?.toInt() ?? 0;
              final balance=(row['running_balance'] as num?)?.toInt() ?? 0;
              return Card(child:ListTile(
                dense:true,
                leading:Icon(incomeRow?Icons.south_west:Icons.north_east,color:incomeRow?Colors.green:Colors.red),
                title:Text(row['description']?.toString() ?? row['category']?.toString() ?? 'Transaksi'),
                subtitle:Text('${row['category'] ?? '-'} • ${row['transaction_date'] ?? ''}'),
                trailing:Column(mainAxisAlignment:MainAxisAlignment.center,crossAxisAlignment:CrossAxisAlignment.end,children:[
                  Text('${incomeRow?'+':'-'}${_money(amount)}',style:TextStyle(fontWeight:FontWeight.w600,color:incomeRow?Colors.green:Colors.red,fontSize:12)),
                  Text('Saldo ${_money(balance)}',style:const TextStyle(fontSize:10,color:Colors.grey)),
                ]),
              ));
            }),
          ],
        ));
      },
    ),
  );

  Widget _balanceLine(String label,Object? amount,{Color? color,bool bold=false}) => Padding(
    padding:const EdgeInsets.symmetric(vertical:3),
    child:Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[
      Text(label,style:TextStyle(fontSize:12,fontWeight:bold?FontWeight.bold:FontWeight.normal)),
      Text(_money(amount),style:TextStyle(fontSize:bold?16:13,fontWeight:bold?FontWeight.bold:FontWeight.w600,color:color)),
    ]),
  );
}
