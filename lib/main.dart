
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import 'core/database/app_database.dart';
import 'features/settings/data/bengkelku_server_service.dart';
import 'core/theme/app_theme.dart';
import 'features/settings/presentation/account_pages.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  BengkelKuServerService.initialize();

  // Area navigasi Android dibuat solid agar tombol Home/gesture tidak transparan.
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    systemNavigationBarColor: Colors.white,
    systemNavigationBarDividerColor: Colors.white,
    systemNavigationBarIconBrightness: Brightness.dark,
    systemNavigationBarContrastEnforced: false,
  ));

  // Membuka atau membuat database lokal BengkelKu POS.
  await AppDatabase.instance.database;

  runApp(const BengkelKuApp());
}

class BengkelKuApp extends StatelessWidget {
  const BengkelKuApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BengkelKu POS',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      // Sisakan area aman di atas tombol navigasi Android untuk semua halaman,
      // sehingga footer aplikasi tidak tertutup system navigation bar.
      builder: (context, child) => SafeArea(
        top: false,
        bottom: true,
        child: child ?? const SizedBox.shrink(),
      ),
      home: const AuthGate(),
    );
  }
}
