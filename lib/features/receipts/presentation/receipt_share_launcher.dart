import 'dart:convert';

import 'package:material_ui/material_ui.dart';

import '../../business/data/business_profile_repository.dart';
import '../../sales/data/sale_repository.dart';
import '../../sales/data/sale_return_repository.dart';
import '../../services/data/service_repository.dart';
import '../data/receipt_document_service.dart';
import '../data/receipt_snapshot_repository.dart';
import 'receipt_preview_page.dart';

class ReceiptShareLauncher {
  static final _snapshots = ReceiptSnapshotRepository();

  static Future<void> sale(BuildContext context, int id) async {
    try {
      final sale = await SaleRepository().getSaleById(id);
      if (sale == null || !context.mounted) return;
      final payments = await SaleRepository().getSalePaymentHistory(id);
      final returns = await SaleReturnRepository().getSaleReturnSummary(id);
      final profile = await BusinessProfileRepository().getProfile();
      final number = sale['invoice_number']?.toString() ?? 'nota-penjualan';
      final snapshotId = await _snapshots.createSnapshot(
        documentType: 'sale',
        sourceType: 'sale',
        sourceId: id,
        documentNumber: number,
        payload: {
          'sale': sale,
          'payments': payments,
          'return_summary': returns,
          'profile': profile,
        },
      );
      await openSnapshot(context, snapshotId);
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal menyiapkan nota: $error')),
      );
    }
  }

  static Future<void> service(BuildContext context, int id) async {
    try {
      final service = await ServiceRepository().getServiceOrderById(id);
      if (service == null || !context.mounted) return;
      final payments = await ServiceRepository().getServicePaymentHistory(id);
      final profile = await BusinessProfileRepository().getProfile();
      final number = service['order_number']?.toString() ?? 'nota-servis';
      final snapshotId = await _snapshots.createSnapshot(
        documentType: 'service',
        sourceType: 'service_order',
        sourceId: id,
        documentNumber: number,
        payload: {
          'service': service,
          'payments': payments,
          'profile': profile,
        },
      );
      await openSnapshot(context, snapshotId);
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal menyiapkan nota: $error')),
      );
    }
  }

  static Future<void> openSnapshot(BuildContext context, int snapshotId) async {
    try {
      final record = await _snapshots.getSnapshot(snapshotId);
      if (record == null || !context.mounted) return;
      final payload = Map<String, Object?>.from(record['payload'] as Map);
      final type = record['document_type']?.toString();
      final Uint8List pdfBytes;
      final String title;
      final String shareText;
      final String number = record['document_number']?.toString() ?? 'nota';
      if (type == 'sale') {
        final sale = Map<String, Object?>.from(payload['sale'] as Map);
        final payments = List<Map<String, Object?>>.from(
          (payload['payments'] as List? ?? const []).map(
            (item) => Map<String, Object?>.from(item as Map),
          ),
        );
        final returns = Map<String, Object?>.from(payload['return_summary'] as Map);
        final profile = Map<String, String>.from(payload['profile'] as Map);
        pdfBytes = await ReceiptDocumentService.buildSaleReceipt(
          sale: sale,
          payments: payments,
          returnSummary: returns,
          profile: profile,
        );
        title = 'Nota Penjualan';
        shareText = 'Berikut nota penjualan $number.';
      } else if (type == 'service') {
        final service = Map<String, Object?>.from(payload['service'] as Map);
        final payments = List<Map<String, Object?>>.from(
          (payload['payments'] as List? ?? const []).map(
            (item) => Map<String, Object?>.from(item as Map),
          ),
        );
        final profile = Map<String, String>.from(payload['profile'] as Map);
        pdfBytes = await ReceiptDocumentService.buildServiceReceipt(
          service: service,
          payments: payments,
          profile: profile,
        );
        title = 'Nota Servis';
        shareText = 'Berikut nota servis $number.';
      } else {
        throw const FormatException('Jenis snapshot nota tidak dikenali.');
      }

      if (!context.mounted) return;
      final safeNumber = number.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ReceiptPreviewPage(
            pdfBytes: pdfBytes,
            fileName: '$safeNumber.pdf',
            title: title,
            shareText: shareText,
          ),
        ),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal membuka arsip nota: $error')),
      );
    }
  }

  static Future<List<Map<String, Object?>>> getHistory({
    String? sourceType,
    int? sourceId,
  }) {
    return _snapshots.getHistory(sourceType: sourceType, sourceId: sourceId);
  }
}
