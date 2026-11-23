import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class BarcodeScannerPage extends StatefulWidget {
  const BarcodeScannerPage({super.key});

  @override
  State<BarcodeScannerPage> createState() => _BarcodeScannerPageState();
}

class _BarcodeScannerPageState extends State<BarcodeScannerPage> {
  final MobileScannerController _controller = MobileScannerController();
  bool _hasReturnedResult = false;
  bool _isRetrying = false;
  String? _retryError;

  void _handleDetection(BarcodeCapture capture) {
    if (_hasReturnedResult) return;

    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue?.trim();
      if (value != null && value.isNotEmpty) {
        _hasReturnedResult = true;
        Navigator.of(context).pop(value);
        return;
      }
    }
  }

  Future<void> _retryCamera() async {
    if (_isRetrying) return;
    setState(() {
      _isRetrying = true;
      _retryError = null;
    });

    try {
      await _controller.stop();
      await _controller.start();
    } catch (error) {
      if (mounted) {
        setState(() => _retryError = error.toString());
      }
    } finally {
      if (mounted) setState(() => _isRetrying = false);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Scan Barcode Produk'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _handleDetection,
            errorBuilder: (context, error, [child]) {
              final code = error.errorCode.toString().split('.').last;
              final permissionDenied = code == 'permissionDenied';

              return ColoredBox(
                color: Colors.black,
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.camera_alt_outlined,
                          color: Colors.white,
                          size: 44,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          permissionDenied
                              ? 'Izin kamera belum diberikan'
                              : 'Kamera belum dapat dijalankan',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          permissionDenied
                              ? 'Izinkan BengkelKu POS menggunakan kamera melalui Pengaturan aplikasi, lalu coba lagi.'
                              : 'Periksa izin kamera dan pastikan kamera tidak sedang digunakan aplikasi lain. Kode: $code',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                          ),
                        ),
                        if (_retryError != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            _retryError!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.orangeAccent,
                              fontSize: 12,
                            ),
                          ),
                        ],
                        const SizedBox(height: 20),
                        FilledButton.icon(
                          onPressed: _isRetrying ? null : _retryCamera,
                          icon: _isRetrying
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.refresh),
                          label: Text(
                            _isRetrying ? 'Mencoba...' : 'Coba Lagi',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
          IgnorePointer(
            child: Center(
              child: Container(
                width: 280,
                height: 180,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.greenAccent, width: 3),
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),
          const Positioned(
            left: 20,
            right: 20,
            bottom: 36,
            child: Text(
              'Arahkan kamera ke barcode produk. Pemindaian akan berjalan otomatis.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }
}
