import 'dart:typed_data';

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


  static Future<void> serviceIntake(BuildContext context, int id) async {
    try {
      final service = await ServiceRepository().getServiceOrderById(id);
      if (service == null || !context.mounted) return;
      final profile = await BusinessProfileRepository().getProfile();
      final number = service['order_number']?.toString() ?? 'nota-servis';
      final snapshotId = await _snapshots.createSnapshot(
        documentType: 'service_intake',
        sourceType: 'service_order',
        sourceId: id,
        documentNumber: '$number-TERIMA',
        payload: {'service': service, 'profile': profile},
      );
      await openSnapshot(context, snapshotId);
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal menyiapkan bukti penerimaan: $error')),
      );
    }
  }

  static Future<void> serviceFinalPayment(BuildContext context, int id) async {
    try {
      final repository = ServiceRepository();
      final service = await repository.getServiceOrderById(id);
      if (service == null || !context.mounted) return;
      final remaining = service['remaining_payment'] as int? ?? 0;
      final status = service['service_status']?.toString() ?? '';
      if (remaining > 0 || status == 'cancelled') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bukti pelunasan hanya tersedia untuk servis yang sudah lunas.')),
        );
        return;
      }
      final payments = await repository.getServicePaymentHistory(id);
      final profile = await BusinessProfileRepository().getProfile();
      final number = service['order_number']?.toString() ?? 'nota-servis';
      final snapshotId = await _snapshots.createSnapshot(
        documentType: 'service_final_payment',
        sourceType: 'service_order',
        sourceId: id,
        documentNumber: '$number-LUNAS',
        payload: {'service': service, 'payments': payments, 'profile': profile},
      );
      await openSnapshot(context, snapshotId);
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal menyiapkan bukti pelunasan: $error')),
      );
    }
  }

  static Future<void> openSnapshot(BuildContext context, int snapshotId) async {
    try {
      final record = await _snapshots.getSnapshot(snapshotId);
      if (record == null || !context.mounted) return;
      final payload = Map<String, Object?>.from(record['payload'] as Map);
      final type = record['document_type']?.toString();
      final Uint8List? pdfBytes;
      final String title;
      final String shareText;
      final String number = record['document_number']?.toString() ?? 'nota';
      if (type == 'sale') {
        pdfBytes = null;
        title = 'Nota Penjualan';
        shareText = 'Berikut nota penjualan $number.';
      } else if (type == 'service') {
        pdfBytes = null;
        title = 'Nota Servis';
        shareText = 'Berikut nota servis $number.';
      } else if (type == 'service_intake') {
        final service = Map<String, Object?>.from(payload['service'] as Map);
        final profile = Map<String, String>.from(payload['profile'] as Map);
        pdfBytes = await ReceiptDocumentService.buildServiceIntakeReceipt(
          service: service,
          profile: profile,
        );
        title = 'Bukti Penerimaan Sepeda';
        shareText = 'Berikut bukti penerimaan sepeda untuk servis $number.';
      } else if (type == 'service_final_payment') {
        pdfBytes = null;
        title = 'Bukti Pelunasan Servis';
        shareText = 'Berikut bukti pelunasan servis $number.';
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
            receiptType: type,
            receiptPayload: payload,
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

  static Future<void> showHistory(
    BuildContext context, {
    required String sourceType,
    required int sourceId,
  }) async {
    try {
      final records = await getHistory(sourceType: sourceType, sourceId: sourceId);
      if (!context.mounted) return;
      if (records.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Belum ada arsip nota untuk transaksi ini.')),
        );
        return;
      }
      final selectedId = await showModalBottomSheet<int>(
        context: context,
        isScrollControlled: true,
        builder: (sheetContext) => SafeArea(
          child: SizedBox(
            height: MediaQuery.of(sheetContext).size.height * 0.55,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: Text('Riwayat Nota', style: Theme.of(sheetContext).textTheme.titleMedium),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView.separated(
                    itemCount: records.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final item = records[index];
                      final date = DateTime.tryParse(item['issued_at']?.toString() ?? '')?.toLocal();
                      final dateText = date == null
                          ? '-'
                          : '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
                      final type = item['document_type']?.toString() ?? '';
                      final typeLabel = switch (type) {
                        'service_intake' => 'Bukti Penerimaan Sepeda',
                        'service_final_payment' => 'Bukti Pelunasan Servis',
                        'service' => 'Nota Servis',
                        'sale' => 'Nota Penjualan',
                        _ => 'Nota',
                      };
                      return ListTile(
                        leading: const Icon(Icons.receipt_long_outlined),
                        title: Text(typeLabel),
                        subtitle: Text('${item['document_number'] ?? '-'} • Diterbitkan $dateText'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.pop(sheetContext, item['id'] as int),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      if (selectedId != null && context.mounted) {
        await openSnapshot(context, selectedId);
      }
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal memuat riwayat nota: $error')),
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
