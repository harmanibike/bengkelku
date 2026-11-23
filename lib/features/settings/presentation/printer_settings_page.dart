import 'package:material_ui/material_ui.dart';
import 'package:unified_esc_pos_printer/unified_esc_pos_printer.dart';

import '../../../core/auth/auth_session.dart';
import '../data/receipt_settings_repository.dart';

class PrinterSettingsPage extends StatefulWidget {
  const PrinterSettingsPage({super.key});

  @override
  State<PrinterSettingsPage> createState() => _PrinterSettingsPageState();
}

class _PrinterSettingsPageState extends State<PrinterSettingsPage> {
  final _repository = ReceiptSettingsRepository();
  final _manager = PrinterManager();
  List<BluetoothPrinterDevice> _printers = [];
  Map<String, String>? _savedPrinter;
  bool _scanning = false;
  bool _connecting = false;
  bool _printingTest = false;
  bool _connected = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadSavedPrinter();
  }

  Future<void> _loadSavedPrinter() async {
    try {
      final saved = await _repository.getSavedPrinter();
      if (mounted) setState(() => _savedPrinter = saved);
    } catch (error) {
      if (mounted) setState(() => _error = 'Gagal membaca printer tersimpan: $error');
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _scan() async {
    if (_scanning || _connecting) return;
    setState(() {
      _scanning = true;
      _error = null;
      _printers = [];
    });
    try {
      final devices = await _manager.scanPrinters(
        timeout: const Duration(seconds: 8),
        types: {PrinterConnectionType.bluetooth},
      );
      final bluetoothDevices = devices.whereType<BluetoothPrinterDevice>().toList();
      if (!mounted) return;
      setState(() => _printers = bluetoothDevices);
      if (bluetoothDevices.isEmpty) {
        _showMessage('Tidak ditemukan printer Bluetooth. Pastikan printer menyala dan sudah dipasangkan melalui pengaturan Bluetooth Android.');
      }
    } catch (error) {
      if (mounted) setState(() => _error = 'Gagal mencari printer: $error');
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _connect(BluetoothPrinterDevice device) async {
    if (_connecting) return;
    setState(() {
      _connecting = true;
      _error = null;
    });
    try {
      await _manager.connect(device);
      await _repository.savePrinter(name: device.name, address: device.address);
      if (!mounted) return;
      setState(() {
        _connected = true;
        _savedPrinter = {'name': device.name, 'address': device.address};
      });
      _showMessage('Printer ${device.name} berhasil terhubung.');
    } catch (error) {
      if (mounted) setState(() {
        _connected = false;
        _error = 'Gagal menghubungkan printer: $error';
      });
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  Future<void> _connectSaved() async {
    final saved = _savedPrinter;
    if (saved == null) return;
    await _connect(BluetoothPrinterDevice(
      name: saved['name']!,
      address: saved['address']!,
    ));
  }

  Future<void> _testPrint() async {
    if (!_connected || _printingTest) return;
    setState(() => _printingTest = true);
    try {
      final ticket = await Ticket.create(PaperSize.mm58);
      ticket.text(
        'BENGKELKU POS',
        align: PrintAlign.center,
        style: const PrintTextStyle(bold: true),
      );
      ticket.text('TES CETAK PRINTER', align: PrintAlign.center);
      ticket.text('Koneksi Bluetooth berhasil.');
      ticket.text('Kertas: 58 mm');
      ticket.text('--------------------------------');
      ticket.text('Jika tulisan terlihat jelas, printer siap.', linesAfter: 2);
      ticket.cut();
      await _manager.printTicket(ticket);
      await _manager.waitWriteComplete();
      _showMessage('Perintah tes cetak sudah dikirim. Periksa hasil kertas pada printer.');
    } catch (error) {
      if (mounted) setState(() => _error = 'Tes cetak gagal: $error');
    } finally {
      if (mounted) setState(() => _printingTest = false);
    }
  }

  Future<void> _disconnect() async {
    try {
      await _manager.disconnect();
      if (mounted) setState(() => _connected = false);
      _showMessage('Printer diputus.');
    } catch (error) {
      if (mounted) setState(() => _error = 'Gagal memutus printer: $error');
    }
  }

  Future<void> _removeSavedPrinter() async {
    await _disconnect();
    await _repository.clearSavedPrinter();
    if (mounted) setState(() {
      _savedPrinter = null;
      _connected = false;
    });
  }

  @override
  void dispose() {
    _manager.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canManage = AuthSession.instance.isCashierOrAdmin;
    return Scaffold(
      appBar: AppBar(title: const Text('Pengaturan Printer')),
      body: !canManage
          ? const Center(child: Text('Hanya Admin dan Kasir yang dapat mengatur printer.'))
          : ListView(
              padding: const EdgeInsets.all(14),
              children: [
                Card(
                  child: ListTile(
                    leading: Icon(
                      _connected ? Icons.print_rounded : Icons.print_disabled_rounded,
                      color: _connected ? Colors.green : Colors.grey,
                    ),
                    title: Text(_connected ? 'Printer terhubung' : 'Printer belum terhubung'),
                    subtitle: Text(_savedPrinter == null
                        ? 'Belum ada printer utama yang disimpan.'
                        : '${_savedPrinter!['name']}\n${_savedPrinter!['address']}'),
                    isThreeLine: _savedPrinter != null,
                  ),
                ),
                const SizedBox(height: 8),
                if (_savedPrinter != null && !_connected)
                  OutlinedButton.icon(
                    onPressed: _connecting ? null : _connectSaved,
                    icon: const Icon(Icons.bluetooth_connected),
                    label: const Text('Hubungkan printer tersimpan'),
                  ),
                if (_connected) ...[
                  FilledButton.icon(
                    onPressed: _printingTest ? null : _testPrint,
                    icon: _printingTest
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.receipt_long),
                    label: Text(_printingTest ? 'Mengirim tes cetak...' : 'Tes cetak 58 mm'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _disconnect,
                    icon: const Icon(Icons.link_off),
                    label: const Text('Putuskan koneksi'),
                  ),
                ],
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _scanning || _connecting ? null : _scan,
                  icon: _scanning
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.bluetooth_searching),
                  label: Text(_scanning ? 'Mencari printer...' : 'Cari printer Bluetooth'),
                ),
                const SizedBox(height: 12),
                if (_connecting) const LinearProgressIndicator(),
                if (_printers.isNotEmpty) ...[
                  const Text('Printer ditemukan', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  ..._printers.map((device) => Card(
                    child: ListTile(
                      leading: const Icon(Icons.print_outlined),
                      title: Text(device.name.isEmpty ? 'Printer tanpa nama' : device.name),
                      subtitle: Text(device.address),
                      trailing: TextButton(
                        onPressed: _connecting ? null : () => _connect(device),
                        child: const Text('Hubungkan'),
                      ),
                    ),
                  )),
                ],
                if (_savedPrinter != null)
                  TextButton.icon(
                    onPressed: _connecting ? null : _removeSavedPrinter,
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Hapus printer tersimpan'),
                  ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(_error!, style: const TextStyle(color: Colors.red)),
                ],
                const SizedBox(height: 12),
                const ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.info_outline),
                  title: Text('Catatan'),
                  subtitle: Text('Printer harus dinyalakan dan dipasangkan terlebih dahulu melalui Bluetooth Android. Fitur ini menguji koneksi Bluetooth Classic dan tes cetak ESC/POS 58 mm. Cetak nota transaksi dan pembukaan laci otomatis akan dihubungkan pada tahap berikutnya.'),
                ),
              ],
            ),
    );
  }
}
