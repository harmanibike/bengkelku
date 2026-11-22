
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import 'core/database/app_database.dart';
import 'core/theme/app_theme.dart';
import 'features/dashboard/dashboard_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Area navigasi Android dibuat solid agar tombol Home/gesture tidak transparan.
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    systemNavigationBarColor: Color(0xFFF4F5F8),
    systemNavigationBarDividerColor: Color(0xFFF4F5F8),
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
      home: const DashboardPage(),
    );
  }
}
