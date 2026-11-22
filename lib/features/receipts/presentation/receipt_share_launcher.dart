import 'package:material_ui/material_ui.dart';

import '../../business/data/business_profile_repository.dart';
import '../../sales/data/sale_repository.dart';
import '../../sales/data/sale_return_repository.dart';
import '../../services/data/service_repository.dart';
import '../data/receipt_document_service.dart';
import 'receipt_preview_page.dart';

class ReceiptShareLauncher {
  static Future<void> sale(BuildContext context, int id) async {
    try {
      final sale = await SaleRepository().getSaleById(id);
      if (sale == null || !context.mounted) return;
      final payments = await SaleRepository().getSalePaymentHistory(id);
      final returns = await SaleReturnRepository().getSaleReturnSummary(id);
      final profile = await BusinessProfileRepository().getProfile();
      final bytes = await ReceiptDocumentService.buildSaleReceipt(
        sale: sale,
        payments: payments,
        returnSummary: returns,
        profile: profile,
      );
      if (!context.mounted) return;
      await Navigator.push(context, MaterialPageRoute(builder: (_) => ReceiptPreviewPage(
        pdfBytes: bytes,
        fileName: '${sale['invoice_number'] ?? 'nota-penjualan'}.pdf',
        title: 'Nota Penjualan',
        shareText: 'Berikut nota penjualan ${sale['invoice_number'] ?? ''}.',
      )));
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal menyiapkan nota: $error')));
    }
  }

  static Future<void> service(BuildContext context, int id) async {
    try {
      final service = await ServiceRepository().getServiceOrderById(id);
      if (service == null || !context.mounted) return;
      final payments = await ServiceRepository().getServicePaymentHistory(id);
      final profile = await BusinessProfileRepository().getProfile();
      final bytes = await ReceiptDocumentService.buildServiceReceipt(
        service: service,
        payments: payments,
        profile: profile,
      );
      if (!context.mounted) return;
      await Navigator.push(context, MaterialPageRoute(builder: (_) => ReceiptPreviewPage(
        pdfBytes: bytes,
        fileName: '${service['order_number'] ?? 'nota-servis'}.pdf',
        title: 'Nota Servis',
        shareText: 'Berikut nota servis ${service['order_number'] ?? ''}.',
      )));
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal menyiapkan nota: $error')));
    }
  }
}
