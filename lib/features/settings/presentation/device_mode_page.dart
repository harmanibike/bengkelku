import 'dart:async';
import 'dart:io';

import '../data/device_pairing_repository.dart';
import '../../../core/auth/auth_session.dart';
import '../data/bengkelku_server_service.dart';
import 'package:material_ui/material_ui.dart';

import '../data/device_mode_repository.dart';

class DeviceModePage extends StatefulWidget {
  const DeviceModePage({super.key});

  @override
  State<DeviceModePage> createState() => _DeviceModePageState();
}

class _DeviceModePageState extends State<DeviceModePage> {
  final DeviceModeRepository _repository = DeviceModeRepository();
  final DevicePairingRepository _pairingRepository = DevicePairingRepository();
  late Future<List<PairedDeviceInfo>> _pairedDevicesFuture;
  DevicePairingCode? _activePairingCode;
  bool _creatingPairingCode = false;
  late Future<String> _modeFuture;
  bool _saving = false;
  bool _savingClient = false;
  bool _startingServer = false;
  bool _serverRunning = false;
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
    _pairedDevicesFuture = AuthSession.instance.isAdmin
        ? _pairingRepository.getPairedDevices()
        : Future.value(const <PairedDeviceInfo>[]);
    _hostController = TextEditingController();
    _portController = TextEditingController(
      text: DeviceModeRepository.defaultClientPort.toString(),
    );
    _clientConfigFuture = _loadClientConfig();
    unawaited(_refreshServerStatus());
  }

  Future<void> _refreshServerStatus() async {
    try {
      final running = await BengkelKuServerService.instance.isRunning;
      if (mounted) setState(() => _serverRunning = running);
    } catch (_) {
      // Status yang gagal dibaca tidak boleh mengubah mode atau menghentikan app.
    }
  }

  Future<void> _loadClientConfig() async {
    final config = await _repository.getClientConfig();
    _hostController.text = config['host'] ?? '';
    _portController.text = config['port'] ??
        DeviceModeRepository.defaultClientPort.toString();
  }

  @override
  void dispose() {
    // Jangan hentikan API di sini: lifecycle layanan tidak mengikuti halaman.
    _hostController.dispose();
    _portController.dispose();
    super.dispose();
  }

  Future<void> _startLocalApiServer() async {
    setState(() {
      _startingServer = true;
      _serverMessage = 'Menyiapkan layanan HTTPS Server...';
    });
    try {
      final port = await BengkelKuServerService.instance.startServer();
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
        _serverRunning = true;
        _serverMessage = addresses.isEmpty
            ? 'HTTPS aktif pada port $port. IP Wi-Fi belum terdeteksi; pastikan kedua HP berada pada jaringan yang sama.'
            : 'HTTPS aktif. Alamat Server: ${addresses.join(', ')}:$port';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _serverMessage = 'Gagal menyalakan API Server: $error');
    } finally {
      if (mounted) setState(() => _startingServer = false);
    }
  }

  Future<void> _stopLocalApiServer() async {
    await BengkelKuServerService.instance.stopServer();
    if (!mounted) return;
    setState(() {
      _serverRunning = false;
      _serverMessage = 'Layanan HTTPS Server dihentikan.';
    });
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

  Future<void> _refreshPairedDevices() async {
    setState(() {
      _pairedDevicesFuture = _pairingRepository.getPairedDevices();
    });
  }

  Future<void> _createPairingCode() async {
    setState(() => _creatingPairingCode = true);
    try {
      final code = await _pairingRepository.createPairingCode();
      if (!mounted) return;
      setState(() => _activePairingCode = code);
      await _refreshPairedDevices();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal membuat kode pairing: $error')),
      );
    } finally {
      if (mounted) setState(() => _creatingPairingCode = false);
    }
  }

  Future<void> _revokePairedDevice(PairedDeviceInfo device) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Putuskan perangkat?'),
        content: Text(
          'Perangkat "${device.deviceName}" tidak akan dapat memakai token ini lagi.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Putuskan'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _pairingRepository.revokeDevice(device.id);
      if (!mounted) return;
      await _refreshPairedDevices();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Perangkat berhasil diputus.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal memutus perangkat: $error')),
      );
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
                        'Uji Layanan HTTPS Server',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 5),
                      const Text(
                        'Menyalakan endpoint pemeriksaan melalui HTTPS dengan identitas sertifikat tersimpan. Tahap ini belum membuka data transaksi atau database ke Client.',
                        style: TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: _startingServer || _serverRunning
                                  ? null
                                  : _startLocalApiServer,
                              icon: _startingServer
                                  ? const SizedBox(width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 2))
                                  : const Icon(Icons.play_arrow),
                              label: Text(_startingServer ? 'Menyalakan...' : 'Jalankan HTTPS'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _serverRunning ? _stopLocalApiServer : null,
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
              if (AuthSession.instance.isAdmin) ...[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'Pairing Perangkat Client',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 5),
                        const Text(
                          'Admin dapat membuat kode sekali pakai untuk menghubungkan perangkat. Kode berlaku 3 menit. Pertukaran kode melalui jaringan belum diaktifkan sampai koneksi terenkripsi tersedia.',
                          style: TextStyle(fontSize: 11, color: Colors.grey),
                        ),
                        const SizedBox(height: 8),
                        FilledButton.icon(
                          onPressed: _creatingPairingCode ? null : _createPairingCode,
                          icon: _creatingPairingCode
                              ? const SizedBox(width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.vpn_key_outlined),
                          label: Text(_creatingPairingCode ? 'Membuat kode...' : 'Buat Kode Pairing'),
                        ),
                        if (_activePairingCode != null) ...[
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Column(
                              children: [
                                const Text('KODE PAIRING', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600)),
                                const SizedBox(height: 4),
                                SelectableText(
                                  _activePairingCode!.code,
                                  style: const TextStyle(fontSize: 27, fontWeight: FontWeight.w800, letterSpacing: 4),
                                ),
                                Text(
                                  'Berlaku sampai ${_activePairingCode!.expiresAt.toLocal().toString().substring(0, 16)}',
                                  style: const TextStyle(fontSize: 10, color: Colors.grey),
                                ),
                                const SizedBox(height: 4),
                                const Text(
                                  'Kode hanya ditampilkan di perangkat Admin ini. Jangan bagikan kepada orang yang tidak dipercaya.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(fontSize: 10, color: Colors.grey),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const Divider(height: 20),
                        Row(
                          children: [
                            const Expanded(
                              child: Text('Perangkat Terhubung', style: TextStyle(fontWeight: FontWeight.w600)),
                            ),
                            IconButton(
                              tooltip: 'Muat ulang',
                              onPressed: _refreshPairedDevices,
                              icon: const Icon(Icons.refresh),
                            ),
                          ],
                        ),
                        FutureBuilder<List<PairedDeviceInfo>>(
                          future: _pairedDevicesFuture,
                          builder: (context, devicesSnapshot) {
                            if (devicesSnapshot.connectionState == ConnectionState.waiting) {
                              return const Padding(
                                padding: EdgeInsets.all(12),
                                child: Center(child: CircularProgressIndicator()),
                              );
                            }
                            if (devicesSnapshot.hasError) {
                              return Text('Gagal memuat perangkat: ${devicesSnapshot.error}');
                            }
                            final devices = devicesSnapshot.data ?? const <PairedDeviceInfo>[];
                            if (devices.isEmpty) {
                              return const Text('Belum ada perangkat Client yang dipasangkan.', style: TextStyle(fontSize: 11, color: Colors.grey));
                            }
                            return Column(
                              children: devices.map((device) => ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: const Icon(Icons.phone_android),
                                title: Text(device.deviceName, style: const TextStyle(fontSize: 13)),
                                subtitle: Text(
                                  device.lastSeenAt == null
                                      ? 'Dipairing: ${device.createdAt}'
                                      : 'Terakhir aktif: ${device.lastSeenAt}',
                                  style: const TextStyle(fontSize: 10),
                                ),
                                trailing: IconButton(
                                  tooltip: 'Putuskan perangkat',
                                  onPressed: () => _revokePairedDevice(device),
                                  icon: const Icon(Icons.link_off, color: Colors.red),
                                ),
                              )).toList(),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              const Text(
                'Konfigurasi Client',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              const Text(
                'Alamat Server akan diperoleh dan diverifikasi melalui pairing sertifikat. Pemeriksaan Client belum dibuka sebelum proses pairing aman selesai; tidak ada fallback HTTP. Transaksi Client belum dialihkan ke database pusat.',
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
                              onPressed: null,
                              icon: const Icon(Icons.lock_outline),
                              label: const Text(
                                'Tes TLS belum tersedia (menunggu pairing aman)',
                              ),
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
                              label: const Text('Tes TLS (setelah pairing)'),
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
