import 'dart:io';
import 'package:material_ui/material_ui.dart';
import '../../settings/data/receipt_settings_repository.dart';

class ReceiptLayout extends StatelessWidget {
  const ReceiptLayout({super.key, required this.receiptType, required this.payload, required this.settings});
  final String receiptType;
  final Map<String, Object?> payload;
  final ReceiptPrintSettings settings;

  int n(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
  String s(Object? v) { final x = v?.toString().trim() ?? ''; return x == 'null' ? '' : x; }
  String money(Object? v) {
    final d = n(v).toString(); final b = StringBuffer('Rp.');
    for (var i = 0; i < d.length; i++) { if (i > 0 && (d.length-i)%3==0) b.write('.'); b.write(d[i]); }
    return b.toString();
  }
  String date(Object? v) {
    final d = DateTime.tryParse(s(v))?.toLocal(); if (d == null) return '-';
    String z(int x) => x.toString().padLeft(2,'0');
    return z(d.day)+'/'+z(d.month)+'/'+d.year.toString()+' '+z(d.hour)+':'+z(d.minute);
  }
  String method(Object? v) {
    final x=s(v); final k=x.toLowerCase().replaceAll('-','_');
    const m={'cash':'TUNAI','tunai':'TUNAI','bank_transfer':'TRANSFER','transfer':'TRANSFER','transfer bank':'TRANSFER','qris':'QRIS','debit_card':'KARTU DEBIT','credit_card':'KARTU KREDIT','e_wallet':'E-WALLET','customer_wallet':'SALDO PELANGGAN'};
    return m[k] ?? x.toUpperCase();
  }
  Widget dash(double w) => SizedBox(
    width: w,
    height: 8,
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: List.generate((w / 8).floor(), (_) => Container(width: 4, height: 1, color: Colors.black)),
    ),
  );
  Widget rowText(String label,String value,double w,{bool bold=false, bool singleLine=false}) => SizedBox(width:w, child:Row(crossAxisAlignment:CrossAxisAlignment.start,children:[
    SizedBox(width:w*.30,child:Text(label,softWrap:false,overflow:TextOverflow.clip,style:TextStyle(fontSize:16*settings.fontScale,fontWeight:bold?FontWeight.bold:FontWeight.normal))),
    Text(' : ',style:TextStyle(fontSize:16*settings.fontScale)),
    Expanded(child:singleLine
        ? FittedBox(fit:BoxFit.scaleDown,alignment:Alignment.centerLeft,child:Text(value,maxLines:1,style:TextStyle(fontSize:16*settings.fontScale,fontWeight:bold?FontWeight.bold:FontWeight.normal)))
        : Text(value,softWrap:true,style:TextStyle(fontSize:16*settings.fontScale,fontWeight:bold?FontWeight.bold:FontWeight.normal))),
  ]));
  Widget summaryRow(String label,String value,double w,{bool bold=false}) => SizedBox(width:w, child:Row(crossAxisAlignment:CrossAxisAlignment.start,children:[
    Expanded(child:Text(label,softWrap:false,overflow:TextOverflow.clip,style:TextStyle(fontSize:(bold?21:18)*settings.fontScale,fontWeight:bold?FontWeight.bold:FontWeight.normal))),
    SizedBox(width:4*settings.spacing),
    Expanded(child:Text(value,textAlign:TextAlign.right,softWrap:false,overflow:TextOverflow.clip,style:TextStyle(fontSize:(bold?21:18)*settings.fontScale,fontWeight:bold?FontWeight.bold:FontWeight.normal))),
  ]));
  @override
  Widget build(BuildContext context) {
    final sale=receiptType=='sale', finalPay=receiptType=='service_final_payment';
    final source=Map<String,Object?>.from(payload[sale?'sale':'service'] as Map);
    final profile=Map<String,String>.from(payload['profile'] as Map);
    final payments=List<Map<String,Object?>>.from((payload['payments'] as List? ?? const []).map((e)=>Map<String,Object?>.from(e as Map)));
    final items=List<Map<String,Object?>>.from((source['items'] as List? ?? const []).map((e)=>Map<String,Object?>.from(e as Map)));
    // 18 logical px x 1.2 raster = sekitar 22 dot atau 3 mm pada 58 mm.
    // Margin ini dipakai bersama oleh teks, garis, dan kolom harga.
    const horizontalPadding = 18.0;
    final w=settings.thermalLayoutWidth, inner=w-(horizontalPadding*2);
    final total=n(sale?source['total']:source['total_cost']);
    final returnSummary=Map<String,Object?>.from(payload['return_summary'] as Map? ?? const {});
    final paid=finalPay? (total-n(source['remaining_payment'])).clamp(0,1<<62).toInt() : n(sale?source['paid']:source['down_payment']);
    final remaining=sale?(total-paid-n(returnSummary['returned_amount'])+n(returnSummary['refunded_amount'])).clamp(0,1<<62).toInt():n(source['remaining_payment']);
    final logo=s(profile['business_logo_path']);
    final number=s(sale?source['invoice_number']:source['order_number']);
    final when=sale?source['transaction_date']:source['received_at'];
    final title=sale?'NOTA PENJUALAN':finalPay?'BUKTI PELUNASAN SERVIS':'NOTA SERVIS';
    final textScale = settings.fontScale;
    final gap = settings.spacing;
    return Container(width:w,color:Colors.white,padding:EdgeInsets.symmetric(horizontal:horizontalPadding,vertical:10*gap),
      child:DefaultTextStyle(style:TextStyle(color:Colors.black,fontFamily:'monospace',fontSize:20*textScale,height:1.15),
      child:Column(crossAxisAlignment:CrossAxisAlignment.start,mainAxisSize:MainAxisSize.min,children:[
        Row(children:[
          if(settings.showLogo && logo.isNotEmpty && File(logo).existsSync()) SizedBox(width:w*.29,height:80*textScale,child:Image.file(File(logo),fit:BoxFit.contain))
          else SizedBox(width:w*.29,child:Icon(Icons.pedal_bike,size:54*textScale,color:Colors.black)),
          SizedBox(width:8*gap), Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            if(settings.showBusinessName) Text(s(profile['business_name']).isEmpty?'HARMANI BIKE':s(profile['business_name']),style:TextStyle(fontWeight:FontWeight.w900,fontSize:27*textScale,height:1.05)),
            if(settings.showBusinessAddress && s(profile['business_address']).isNotEmpty) Text(s(profile['business_address']),style:TextStyle(fontSize:15*textScale)),
            if(settings.showBusinessContact && s(profile['business_phone']).isNotEmpty) Text('Telp. '+s(profile['business_phone']),style:TextStyle(fontSize:14*textScale)),
          ])),
        ]),
        const Divider(color:Colors.black,thickness:1.5),
        Center(child:Text(title,style:TextStyle(fontSize:23*textScale,fontWeight:FontWeight.w900))),
        SizedBox(height:4*gap), dash(inner),
        rowText('No. Nota',number,inner,singleLine:true),
        rowText('Tanggal',date(when),inner,singleLine:true),
        if(settings.showCustomerDetails)...[
          rowText('Nama',s(source['customer_name']).isEmpty?'-':s(source['customer_name']),inner,singleLine:true),
          rowText('No. Telp',s(source['customer_phone']).isEmpty?'-':s(source['customer_phone']),inner,singleLine:true),
        ],
        dash(inner),
        if(sale)...[
          Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[Text('Barang',style:TextStyle(fontSize:18*textScale,fontWeight:FontWeight.bold)),Text('Harga',style:TextStyle(fontSize:18*textScale,fontWeight:FontWeight.bold))]),
          dash(inner),
          ...items.map((it)=>Padding(padding:EdgeInsets.only(bottom:5*gap),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            Text(s(it['product_name']),style:TextStyle(fontSize:18*textScale)),
            Row(crossAxisAlignment:CrossAxisAlignment.start,children:[Expanded(child:Text(n(it['quantity']).toString()+' x '+money(it['unit_price']),softWrap:false,overflow:TextOverflow.clip,style:TextStyle(fontSize:16*textScale))),SizedBox(width:4*gap),Expanded(child:Text(money(it['subtotal']),textAlign:TextAlign.right,softWrap:false,overflow:TextOverflow.clip,style:TextStyle(fontSize:17*textScale,fontWeight:FontWeight.bold)))]),
          ]))),
          dash(inner), summaryRow('Subtotal',money(source['subtotal']),inner), summaryRow('Diskon',money(source['discount']),inner),
          summaryRow('Total',money(total),inner,bold:true), summaryRow('Dibayar',money(paid),inner), summaryRow('Sisa',money(remaining),inner,bold:true),
        ] else ...[
          rowText('Sepeda',(s(source['bicycle_brand'])+' '+s(source['bicycle_model'])).trim(),inner),
          rowText('Keluhan',s(source['complaint']),inner), dash(inner),
          if(finalPay)...[
            summaryRow('Total servis',money(total),inner,bold:true),rowText('Dibayar',money(paid),inner,bold:true,singleLine:true),rowText('Sisa',money(remaining),inner,bold:true,singleLine:true),
          ] else ...[
            rowText('Jasa servis',money(source['labor_cost']),inner),
            ...items.map((it)=>Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
              Text(s(it['item_name']),style:TextStyle(fontSize:18*textScale)),
              Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[Text(n(it['quantity']).toString()+' x '+money(it['unit_price']),style:TextStyle(fontSize:16*textScale)),Text(money(it['subtotal']),style:TextStyle(fontSize:17*textScale,fontWeight:FontWeight.bold))]),
            ])),
            summaryRow('Total biaya',money(total),inner,bold:true),rowText('Dibayar',money(paid),inner),rowText('Sisa',money(remaining),inner,bold:true),
          ],
        ],
        dash(inner),
        if(payments.isNotEmpty)...[
          const Center(child:Text('RIWAYAT PEMBAYARAN',style:TextStyle(fontWeight:FontWeight.bold))),
          ...payments.map((p){
            final d=DateTime.tryParse(s(p['transaction_date']))?.toLocal();
            String z(int x)=>x.toString().padLeft(2,'0');
            final dt=d==null?'-':z(d.day)+'/'+z(d.month)+' '+z(d.hour)+':'+z(d.minute);
            return Padding(padding:EdgeInsets.symmetric(vertical:gap),child:Row(children:[Expanded(child:Text(dt+' · '+method(p['payment_method']??p['method']??p['payment_method_name']),style:TextStyle(fontSize:17*textScale))),Text(money(p['amount']),style:TextStyle(fontWeight:FontWeight.bold,fontSize:17*textScale))]));
          }),
        ],
        if(settings.showTransactionNotes && s(source['notes']).isNotEmpty) Text('Catatan: '+s(source['notes'])),
        SizedBox(height:12*gap),
        if(settings.showFooter) Center(child:Text(settings.footerNote.trim().isEmpty?'Terima kasih atas kunjungan Anda.':settings.footerNote.trim(),textAlign:TextAlign.center,style:TextStyle(fontSize:16*textScale))),
      ])));
  }
}
