import 'dart:io';

import 'package:material_ui/material_ui.dart';

import '../../settings/data/receipt_settings_repository.dart';

class ReceiptLayout extends StatelessWidget {
  const ReceiptLayout({super.key, required this.receiptType, required this.payload, required this.settings});

  final String receiptType;
  final Map<String, Object?> payload;
  final ReceiptPrintSettings settings;

  int n(Object? value) => value is num ? value.toInt() : int.tryParse('$value') ?? 0;

  String s(Object? value) {
    final text = value?.toString().trim() ?? '';
    return text == 'null' ? '' : text;
  }

  String money(Object? value) {
    final digits = n(value).toString();
    final result = StringBuffer('Rp.');
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) result.write('.');
      result.write(digits[i]);
    }
    return result.toString();
  }

  String date(Object? value) {
    final parsed = DateTime.tryParse(s(value))?.toLocal();
    if (parsed == null) return '-';
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(parsed.day)}/${two(parsed.month)}/${parsed.year} ${two(parsed.hour)}:${two(parsed.minute)}';
  }

  String method(Object? value) {
    final raw = s(value);
    final key = raw.toLowerCase().replaceAll('-', '_');
    const names = {
      'cash': 'TUNAI',
      'tunai': 'TUNAI',
      'bank_transfer': 'TRANSFER',
      'transfer': 'TRANSFER',
      'transfer bank': 'TRANSFER',
      'qris': 'QRIS',
      'debit_card': 'KARTU DEBIT',
      'credit_card': 'KARTU KREDIT',
      'e_wallet': 'E-WALLET',
      'customer_wallet': 'SALDO PELANGGAN',
    };
    return names[key] ?? raw.toUpperCase();
  }

  Widget separator(double width) => SizedBox(
        width: width,
        child: const Text(
          '------------------------------------------------',
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.clip,
          style: TextStyle(fontFamily: 'monospace', fontSize: 12),
        ),
      );

  Widget labelRow(String label, String value, double width, {bool bold = false}) {
    final style = TextStyle(fontWeight: bold ? FontWeight.bold : FontWeight.normal);
    return SizedBox(
      width: width,
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: width * .38, child: Text(label, softWrap: true, style: style)),
        const Text(' : '),
        Expanded(child: Text(value, softWrap: true, style: style)),
      ]),
    );
  }

  Widget amountRow(String label, String value, double width, {bool bold = false}) {
    final style = TextStyle(
      fontSize: bold ? 14 : 12,
      fontWeight: bold ? FontWeight.bold : FontWeight.normal,
    );
    return SizedBox(
      width: width,
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: Text(label, softWrap: true, style: style)),
        const SizedBox(width: 4),
        Expanded(child: Text(value, textAlign: TextAlign.right, softWrap: true, style: style)),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isSale = receiptType == 'sale';
    final isFinalPayment = receiptType == 'service_final_payment';
    final source = Map<String, Object?>.from(payload[isSale ? 'sale' : 'service'] as Map);
    final profile = Map<String, String>.from(payload['profile'] as Map);
    final payments = List<Map<String, Object?>>.from(
      (payload['payments'] as List? ?? const []).map((item) => Map<String, Object?>.from(item as Map)),
    );
    final items = List<Map<String, Object?>>.from(
      (source['items'] as List? ?? const []).map((item) => Map<String, Object?>.from(item as Map)),
    );
    final width = settings.thermalLayoutWidth;
    final innerWidth = width - (settings.thermalMargin * 2);
    final total = n(isSale ? source['total'] : source['total_cost']);
    final returnSummary = Map<String, Object?>.from(payload['return_summary'] as Map? ?? const {});
    final paid = isFinalPayment
        ? (total - n(source['remaining_payment'])).clamp(0, 1 << 62).toInt()
        : n(isSale ? source['paid'] : source['down_payment']);
    final remaining = isSale
        ? (total - paid - n(returnSummary['returned_amount']) + n(returnSummary['refunded_amount'])).clamp(0, 1 << 62).toInt()
        : n(source['remaining_payment']);
    final logo = s(profile['business_logo_path']);
    final number = s(isSale ? source['invoice_number'] : source['order_number']);
    final when = isSale ? source['transaction_date'] : source['received_at'];
    final title = isSale ? 'NOTA PENJUALAN' : isFinalPayment ? 'BUKTI PELUNASAN SERVIS' : 'NOTA SERVIS';

    return Container(
      width: width,
      color: Colors.white,
      padding: EdgeInsets.symmetric(horizontal: settings.thermalMargin, vertical: 8),
      child: DefaultTextStyle(
        style: const TextStyle(color: Colors.black, fontFamily: 'monospace', fontSize: 12, height: 1.15),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            if (settings.showLogo && logo.isNotEmpty && File(logo).existsSync())
              SizedBox(width: width * .24, height: 52, child: Image.file(File(logo), fit: BoxFit.contain))
            else
              SizedBox(width: width * .24, child: const Icon(Icons.pedal_bike, size: 38, color: Colors.black)),
            const SizedBox(width: 6),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (settings.showBusinessName)
                  Text(
                    s(profile['business_name']).isEmpty ? 'HARMANI BIKE' : s(profile['business_name']),
                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, height: 1.05),
                  ),
                if (settings.showBusinessAddress && s(profile['business_address']).isNotEmpty)
                  Text(s(profile['business_address']), style: const TextStyle(fontSize: 10)),
                if (settings.showBusinessContact && s(profile['business_phone']).isNotEmpty)
                  Text('Telp. ${s(profile['business_phone'])}', style: const TextStyle(fontSize: 10)),
              ]),
            ),
          ]),
          const Divider(color: Colors.black, thickness: 1),
          Center(child: Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900))),
          const SizedBox(height: 3),
          separator(innerWidth),
          labelRow('No. Nota', number, innerWidth),
          labelRow('Tanggal', date(when), innerWidth),
          if (settings.showCustomerDetails) ...[
            labelRow('Nama Pelanggan', s(source['customer_name']).isEmpty ? '-' : s(source['customer_name']), innerWidth),
            labelRow('No. Telp', s(source['customer_phone']).isEmpty ? '-' : s(source['customer_phone']), innerWidth),
          ],
          separator(innerWidth),
          if (isSale) ...[
            const Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('Barang', style: TextStyle(fontWeight: FontWeight.bold)),
              Text('Harga', style: TextStyle(fontWeight: FontWeight.bold)),
            ]),
            separator(innerWidth),
            ...items.map((item) => Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(s(item['product_name'])),
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Expanded(child: Text('${n(item['quantity'])} x ${money(item['unit_price'])}', softWrap: true)),
                      const SizedBox(width: 4),
                      Expanded(child: Text(money(item['subtotal']), textAlign: TextAlign.right, softWrap: true, style: const TextStyle(fontWeight: FontWeight.bold))),
                    ]),
                  ]),
                )),
            separator(innerWidth),
            amountRow('Subtotal', money(source['subtotal']), innerWidth),
            amountRow('Diskon', money(source['discount']), innerWidth),
            amountRow('Total', money(total), innerWidth, bold: true),
            amountRow('Sudah dibayar', money(paid), innerWidth),
            amountRow('Sisa tagihan', money(remaining), innerWidth, bold: true),
          ] else ...[
            labelRow('Sepeda', '${s(source['bicycle_brand'])} ${s(source['bicycle_model'])}'.trim(), innerWidth),
            labelRow('Keluhan', s(source['complaint']), innerWidth),
            separator(innerWidth),
            if (isFinalPayment) ...[
              amountRow('Total biaya servis', money(total), innerWidth, bold: true),
              labelRow('Sudah dibayar', money(paid), innerWidth, bold: true),
              labelRow('Sisa tagihan', money(remaining), innerWidth, bold: true),
            ] else ...[
              labelRow('Jasa servis', money(source['labor_cost']), innerWidth),
              ...items.map((item) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(s(item['item_name'])),
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      Text('${n(item['quantity'])} x ${money(item['unit_price'])}'),
                      Text(money(item['subtotal']), style: const TextStyle(fontWeight: FontWeight.bold)),
                    ]),
                  ])),
              amountRow('Total biaya servis', money(total), innerWidth, bold: true),
              labelRow('Sudah dibayar', money(paid), innerWidth),
              labelRow('Sisa tagihan', money(remaining), innerWidth, bold: true),
            ],
          ],
          separator(innerWidth),
          if (payments.isNotEmpty) ...[
            const Center(child: Text('RIWAYAT PEMBAYARAN', style: TextStyle(fontWeight: FontWeight.bold))),
            ...payments.map((payment) {
              final parsed = DateTime.tryParse(s(payment['transaction_date']))?.toLocal();
              String two(int value) => value.toString().padLeft(2, '0');
              final dateText = parsed == null ? '-' : '${two(parsed.day)}/${two(parsed.month)} ${two(parsed.hour)}:${two(parsed.minute)}';
              return Row(children: [
                Expanded(child: Text('$dateText · ${method(payment['payment_method'] ?? payment['method'] ?? payment['payment_method_name'])}', style: const TextStyle(fontSize: 10))),
                Text(money(payment['amount']), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10)),
              ]);
            }),
          ],
          if (settings.showTransactionNotes && s(source['notes']).isNotEmpty) Text('Catatan: ${s(source['notes'])}'),
          const SizedBox(height: 8),
          if (settings.showFooter)
            Center(
              child: Text(
                settings.footerNote.trim().isEmpty ? 'Terima kasih atas kunjungan Anda.' : settings.footerNote.trim(),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 10),
              ),
            ),
        ]),
      ),
    );
  }
}
