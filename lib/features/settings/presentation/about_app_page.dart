import 'package:material_ui/material_ui.dart';

class AboutAppPage extends StatelessWidget {
  const AboutAppPage({super.key});

  static const String _appVersion = '1.0.0';
  static const String _buildNumber = '1';

  static const List<_ReleaseNote> _releases = [
    _ReleaseNote(
      version: '1.0.0',
      date: 'Rilis awal',
      changes: [
        'BengkelKu POS untuk penjualan toko dan layanan servis sepeda.',
        'Mode operasional lokal/offline.',
      ],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tentang')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Container(
                    width: 76,
                    height: 76,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1565C0),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Image.asset(
                      'assets/branding/bengkelku_logo.jpg',
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const Icon(
                        Icons.pedal_bike_rounded,
                        color: Colors.white,
                        size: 48,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'BengkelKu POS',
                    style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Kasir dan manajemen bengkel sepeda',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEAF2FF),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'Versi $_appVersion (Build $_buildNumber)',
                      style: TextStyle(
                        color: Color(0xFF1558A6),
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            'INFO APLIKASI',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey),
          ),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: const [
                ListTile(
                  dense: true,
                  leading: Icon(Icons.apps_rounded, color: Color(0xFF1565C0)),
                  title: Text('Nama aplikasi'),
                  subtitle: Text('BengkelKu POS'),
                ),
                Divider(height: 1, indent: 56),
                ListTile(
                  dense: true,
                  leading: Icon(Icons.build_circle_outlined, color: Color(0xFF00897B)),
                  title: Text('Fungsi'),
                  subtitle: Text('Penjualan sparepart, servis, stok, dan laporan usaha'),
                ),
                Divider(height: 1, indent: 56),
                ListTile(
                  dense: true,
                  leading: Icon(Icons.storage_rounded, color: Color(0xFFEF6C00)),
                  title: Text('Penyimpanan data'),
                  subtitle: Text('Database lokal pada perangkat'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            'CHANGELOG',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey),
          ),
          const SizedBox(height: 8),
          ..._releases.map(
            (release) => Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Versi ${release.version}',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                        ),
                        Text(
                          release.date,
                          style: const TextStyle(color: Colors.grey, fontSize: 11),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    ...release.changes.map(
                      (change) => Padding(
                        padding: const EdgeInsets.only(bottom: 7),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.check_circle_outline, size: 17, color: Color(0xFF00897B)),
                            const SizedBox(width: 8),
                            Expanded(child: Text(change, style: const TextStyle(fontSize: 12))),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Catatan perubahan akan diperbarui pada setiap rilis aplikasi.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _ReleaseNote {
  final String version;
  final String date;
  final List<String> changes;

  const _ReleaseNote({
    required this.version,
    required this.date,
    required this.changes,
  });
}
