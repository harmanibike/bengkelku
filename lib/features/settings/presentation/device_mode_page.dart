import 'dart:io';

import '../data/client_connection_service.dart';
import '../data/local_api_server.dart';
import 'package:material_ui/material_ui.dart';

import '../data/device_mode_repository.dart';

class DeviceModePage extends StatefulWidget {
  const DeviceModePage({super.key});

  @override
  State<DeviceModePage> createState() => _DeviceModePageState();
}

class _DeviceModePageState extends State<DeviceModePage> {
  final DeviceModeRepository _repository = DeviceModeRepository();
  final ClientConnectionService _clientConnectionService =
      ClientConnectionService();
  final LocalApiServer _localApiServer = LocalApiServer();
  late Future<String> _modeFuture;
  bool _saving = false;
  bool _savingClient = false;
  bool _testingClient = false;
  bool _startingServer = false;
  String? _serverMessage;
  late final TextEditingController _hostController;
  late final TextEditingController _portController;
  late final Future<void> _clientConfigFuture;
  String? _connectionMessage;
  bool? _connectionOk;

  @override
  void initState() {
    super.initState();
    _modeFuture = _repository.getMode();
    _hostController = TextEditingController();
    _portController = TextEditingController(
      text: DeviceModeRepository.defaultClientPort.toString(),
    );
    _clientConfigFuture = _loadClientConfig();
  }

  Future<void> _loadClientConfig() async {
    final config = await _repository.getClientConfig();
    _hostController.text = config['host'] ?? '';
    _portController.text = config['port'] ??
        DeviceModeRepository.defaultClientPort.toString();
  }

  @override
  void dispose() {
    _localApiServer.stop();
    _hostController.dispose();
    _portController.dispose();
    super.dispose();
  }

  Future<void> _startLocalApiServer() async {
    setState(() {
      _startingServer = true;
      _serverMessage = 'Menyalakan layanan pemeriksaan Server...';
    });
    try {
      final port = await _localApiServer.start();
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      final addresses = interfaces
          .expand((interface) => interface.addresses)
          .where((address) => !address.isLoopback)
          .map((address) => address.address)
          .toSet()
          .toList();
      if (!mounted) return;
      setState(() {
        _serverMessage = addresses.isEmpty
            ? 'API aktif pada port $port. IP Wi-Fi belum terdeteksi; pastikan kedua HP berada pada jaringan yang sama.'
            : 'API pemeriksaan aktif. Alamat Server: ${addresses.join(', ')}:$port';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _serverMessage = 'Gagal menyalakan API Server: $error');
    } finally {
      if (mounted) setState(() => _startingServer = false);
    }
  }

  Future<void> _stopLocalApiServer() async {
    await _localApiServer.stop();
    if (!mounted) return;
    setState(() => _serverMessage = 'API pemeriksaan Server dihentikan.');
  }

  Future<void> _saveClientConfig() async {
    final port = int.tryParse(_portController.text.trim());
    if (port == null || port < 1 || port > 65535) {
      setState(() {
        _connectionOk = false;
        _connectionMessage = 'Port tidak valid. Gunakan angka 1–65535.';
      });
      return;
    }
    setState(() => _savingClient = true);
    try {
      await _repository.saveClientConfig(
        host: _hostController.text,
        port: port,
      );
      if (!mounted) return;
      setState(() {
        _connectionOk = null;
        _connectionMessage = 'Alamat Server berhasil disimpan pada perangkat ini.';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _connectionOk = false;
        _connectionMessage = error.toString();
      });
    } finally {
      if (mounted) setState(() => _savingClient = false);
    }
  }

  Future<void> _testClientConnection() async {
    final host = _hostController.text.trim();
    final port = int.tryParse(_portController.text.trim());
    if (host.isEmpty || port == null || port < 1 || port > 65535) {
      setState(() {
        _connectionOk = false;
        _connectionMessage = 'Isi alamat Server dan port yang valid terlebih dahulu.';
      });
      return;
    }

    setState(() {
      _testingClient = true;
      _connectionMessage = 'Memeriksa koneksi jaringan...';
      _connectionOk = null;
    });
    try {
      final result = await _clientConnectionService.checkServer(
        host: host,
        port: port,
      );
      if (!mounted) return;
      setState(() {
        _connectionOk = result.isApiReady;
        _connectionMessage = result.message;
      });
    } finally {
      if (mounted) setState(() => _testingClient = false);
    }
  }

  Future<void> _keepLocalMode() async {
    setState(() => _saving = true);
    try {
      await _repository.saveMode(DeviceModeRepository.localMode);
      if (!mounted) return;
      setState(() {
        _modeFuture = Future.value(DeviceModeRepository.localMode);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Mode Lokal tetap digunakan.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal menyimpan mode perangkat: $error')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mode Perangkat')),
      body: FutureBuilder<String>(
        future: _modeFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text('Gagal membaca mode perangkat: ${snapshot.error}'),
              ),
            );
          }

          final mode = snapshot.data ?? DeviceModeRepository.localMode;
          return ListView(
            padding: const EdgeInsets.all(14),
            children: [
              const Text(
                'Pilih cara perangkat BengkelKu POS bekerja. Semua perangkat nantinya tetap memakai aplikasi dan modul yang sama; hak akses mengikuti akun yang login.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 12),
              Card(
                child: ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Color(0xFFE8F5E9),
                    child: Icon(Icons.phone_android_rounded, color: Color(0xFF2E7D32)),
                  ),
                  title: const Text('Mode Lokal', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text('Aplikasi menggunakan database pada perangkat ini. Dapat digunakan tanpa Wi-Fi atau internet.'),
                  trailing: mode == DeviceModeRepository.localMode
                      ? const Icon(Icons.check_circle, color: Color(0xFF2E7D32))
                      : const Icon(Icons.radio_button_unchecked),
                ),
              ),
              Card(
                child: ListTile(
                  enabled: false,
                  leading: const CircleAvatar(
                    backgroundColor: Color(0xFFE3F2FD),
                    child: Icon(Icons.dns_rounded, color: Color(0xFF1565C0)),
                  ),
                  title: const Text('Mode Server', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text('Perangkat menjadi pusat data Wi-Fi sekaligus tetap bisa dipakai transaksi. Belum diaktifkan.'),
                  trailing: const Text('Tahap berikutnya', style: TextStyle(fontSize: 10)),
                ),
              ),
              Card(
                child: ListTile(
                  enabled: false,
                  leading: const CircleAvatar(
                    backgroundColor: Color(0xFFFFF3E0),
                    child: Icon(Icons.devices_rounded, color: Color(0xFFEF6C00)),
                  ),
                  title: const Text('Mode Client', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text('Perangkat terhubung ke Server untuk transaksi, input data, stok, dan laporan dari database pusat. Belum diaktifkan.'),
                  trailing: const Text('Tahap berikutnya', style: TextStyle(fontSize: 10)),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Uji Layanan Server (Tahap Awal)',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 5),
                      const Text(
                        'Menyalakan endpoint pemeriksaan versi dan koneksi pada port 8765. Tahap ini belum membuka data transaksi atau database ke Client.',
                        style: TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: _startingServer || _localApiServer.isRunning
                                  ? null
                                  : _startLocalApiServer,
                              icon: _startingServer
                                  ? const SizedBox(width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 2))
                                  : const Icon(Icons.play_arrow),
                              label: Text(_startingServer ? 'Menyalakan...' : 'Jalankan API'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _localApiServer.isRunning ? _stopLocalApiServer : null,
                              icon: const Icon(Icons.stop),
                              label: const Text('Hentikan API'),
                            ),
                          ),
                        ],
                      ),
                      if (_serverMessage != null) ...[
                        const SizedBox(height: 8),
                        SelectableText(_serverMessage!, style: const TextStyle(fontSize: 11)),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Konfigurasi Client',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              const Text(
                'Simpan alamat HP Server yang akan dituju. Tombol tes memeriksa endpoint API BengkelKu, bukan hanya apakah port Wi-Fi terbuka. Transaksi Client belum dialihkan ke database pusat.',
                style: TextStyle(fontSize: 11, color: Colors.grey),
              ),
              const SizedBox(height: 8),
              FutureBuilder<void>(
                future: _clientConfigFuture,
                builder: (context, configSnapshot) {
                  if (configSnapshot.connectionState == ConnectionState.waiting) {
                    return const Padding(
                      padding: EdgeInsets.all(12),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  if (configSnapshot.hasError) {
                    return Text('Gagal membaca konfigurasi Client: ${configSnapshot.error}');
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: _hostController,
                        keyboardType: TextInputType.url,
                        decoration: const InputDecoration(
                          labelText: 'Alamat IP / Host Server',
                          hintText: 'Contoh: 192.168.1.10',
                          prefixIcon: Icon(Icons.dns_outlined),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _portController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Port Server',
                          hintText: '8765',
                          prefixIcon: Icon(Icons.settings_ethernet),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _savingClient || _testingClient
                                  ? null
                                  : _saveClientConfig,
                              icon: const Icon(Icons.save_outlined),
                              label: Text(_savingClient ? 'Menyimpan...' : 'Simpan Alamat'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: _savingClient || _testingClient
                                  ? null
                                  : _testClientConnection,
                              icon: _testingClient
                                  ? const SizedBox(
                                      width: 15,
                                      height: 15,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : const Icon(Icons.wifi_tethering),
                              label: Text(_testingClient ? 'Memeriksa...' : 'Tes API Server'),
                            ),
                          ),
                        ],
                      ),
                      if (_connectionMessage != null) ...[
                        const SizedBox(height: 8),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              _connectionOk == true
                                  ? Icons.check_circle_outline
                                  : _connectionOk == false
                                      ? Icons.error_outline
                                      : Icons.info_outline,
                              size: 18,
                              color: _connectionOk == true
                                  ? const Color(0xFF2E9B59)
                                  : _connectionOk == false
                                      ? const Color(0xFFD94343)
                                      : Colors.blueGrey,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                _connectionMessage!,
                                style: const TextStyle(fontSize: 11),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  );
                },
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _saving ? null : _keepLocalMode,
                icon: _saving
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.save_outlined),
                label: Text(_saving ? 'Menyimpan...' : 'Pastikan Mode Lokal'),
              ),
              const SizedBox(height: 10),
              const Text(
                'Penting: Mode Server dan Client belum dapat dipakai untuk menghubungkan dua HP. Mode Lokal tetap menjadi pilihan aman sampai layanan jaringan, keamanan, dan sinkronisasi selesai diuji.',
                style: TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ],
          );
        },
      ),
    );
  }
}
