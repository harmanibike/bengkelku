import 'package:material_ui/material_ui.dart';

class AppTheme {
  AppTheme._();

  static const Color _primary = Color(0xFF1558A6);
  static const Color _accent = Color(0xFF16866A);
  static const Color _canvas = Color(0xFFF4F6F9);
  static const Color _surface = Colors.white;
  static const Color _border = Color(0xFFDCE2E9);
  static const Color _muted = Color(0xFF687586);
  static const Color _text = Color(0xFF202A36);

  static OutlineInputBorder _inputBorder(Color color, {double width = 1}) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: color, width: width),
      );

  static ThemeData get light {
    final base = ThemeData.light();
    final scheme = ColorScheme.fromSeed(
      seedColor: _primary,
      brightness: Brightness.light,
    ).copyWith(
      primary: _primary,
      onPrimary: Colors.white,
      secondary: _accent,
      onSecondary: Colors.white,
      surface: _surface,
      error: const Color(0xFFC62828),
      onSurface: _text,
    );

    return base.copyWith(
      useMaterial3: true,
      colorScheme: scheme,
      brightness: Brightness.light,
      visualDensity: VisualDensity.compact,
      scaffoldBackgroundColor: _canvas,
      canvasColor: _surface,
      dividerColor: _border,
      splashColor: _primary.withValues(alpha: 0.06),
      highlightColor: _primary.withValues(alpha: 0.04),
      textTheme: base.textTheme.copyWith(
        displayLarge: base.textTheme.displayLarge?.copyWith(
          fontSize: 28, fontWeight: FontWeight.w700, color: _text,
        ),
        headlineSmall: base.textTheme.headlineSmall?.copyWith(
          fontSize: 21, fontWeight: FontWeight.w700, color: _text,
        ),
        titleLarge: base.textTheme.titleLarge?.copyWith(
          fontSize: 18, fontWeight: FontWeight.w700, color: _text,
        ),
        titleMedium: base.textTheme.titleMedium?.copyWith(
          fontSize: 15, fontWeight: FontWeight.w600, color: _text,
        ),
        titleSmall: base.textTheme.titleSmall?.copyWith(
          fontSize: 13, fontWeight: FontWeight.w600, color: _text,
        ),
        bodyLarge: base.textTheme.bodyLarge?.copyWith(
          fontSize: 14, height: 1.35, color: _text,
        ),
        bodyMedium: base.textTheme.bodyMedium?.copyWith(
          fontSize: 13, height: 1.35, color: _text,
        ),
        bodySmall: base.textTheme.bodySmall?.copyWith(
          fontSize: 11, height: 1.3, color: _muted,
        ),
        labelLarge: base.textTheme.labelLarge?.copyWith(
          fontSize: 13, fontWeight: FontWeight.w600,
        ),
        labelMedium: base.textTheme.labelMedium?.copyWith(
          fontSize: 11, fontWeight: FontWeight.w500,
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: _primary,
        foregroundColor: Colors.white,
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        toolbarHeight: 54,
        titleTextStyle: TextStyle(
          color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700,
        ),
        iconTheme: IconThemeData(color: Colors.white, size: 21),
      ),
      iconTheme: const IconThemeData(color: _muted, size: 20),
      dialogTheme: DialogThemeData(
        backgroundColor: _surface,
        surfaceTintColor: Colors.transparent,
        iconColor: _text,
        insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
        constraints: const BoxConstraints(maxWidth: 560),
        titleTextStyle: const TextStyle(
          color: _text, fontSize: 17, fontWeight: FontWeight.w700,
        ),
        contentTextStyle: const TextStyle(
          color: _text, fontSize: 13, height: 1.4,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: _primary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: const Color(0xFFE5E9EF),
          disabledForegroundColor: const Color(0xFF8792A0),
          elevation: 0,
          minimumSize: const Size(40, 40),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: _primary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: const Color(0xFFE5E9EF),
          disabledForegroundColor: const Color(0xFF8792A0),
          elevation: 0,
          minimumSize: const Size(40, 40),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: _primary,
          side: const BorderSide(color: Color(0xFFB8C9DC)),
          minimumSize: const Size(40, 40),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: _primary,
          minimumSize: const Size(36, 36),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: _muted,
          minimumSize: const Size(38, 38),
          padding: const EdgeInsets.all(8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: _primary,
        foregroundColor: Colors.white,
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(14)),
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? _primary : null,
        ),
        side: const BorderSide(color: Color(0xFF9AA8B7)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        visualDensity: VisualDensity.compact,
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? _primary : _muted,
        ),
        visualDensity: VisualDensity.compact,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? _primary : null,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? const Color(0xFFD8E8F8) : null,
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: _primary,
        linearTrackColor: Color(0xFFE5ECF4),
        circularTrackColor: Color(0xFFE5ECF4),
      ),
      cardTheme: CardThemeData(
        color: _surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: Color(0xFFE7EBF0)),
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        floatingLabelStyle: const TextStyle(
          color: _primary, fontSize: 12, fontWeight: FontWeight.w600,
        ),
        labelStyle: const TextStyle(color: _muted, fontSize: 13),
        hintStyle: const TextStyle(color: Color(0xFF9AA4B1), fontSize: 13),
        helperStyle: const TextStyle(color: _muted, fontSize: 11),
        errorStyle: const TextStyle(fontSize: 11, height: 1.2),
        prefixIconColor: _muted,
        suffixIconColor: _muted,
        focusedBorder: _inputBorder(_primary, width: 1.5),
        focusedErrorBorder: _inputBorder(const Color(0xFFC62828), width: 1.5),
        errorBorder: _inputBorder(const Color(0xFFD66A6A)),
        disabledBorder: _inputBorder(const Color(0xFFE7EBF0)),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        filled: true,
        fillColor: _surface,
        border: _inputBorder(_border),
        enabledBorder: _inputBorder(_border),
      ),
      dropdownMenuTheme: DropdownMenuThemeData(
        textStyle: const TextStyle(fontSize: 13, color: _text),
        inputDecorationTheme: InputDecorationTheme(
          isDense: true,
          filled: true,
          fillColor: _surface,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          enabledBorder: _inputBorder(_border),
          focusedBorder: _inputBorder(_primary, width: 1.5),
        ),
        menuStyle: MenuStyle(
          backgroundColor: const WidgetStatePropertyAll(_surface),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          elevation: const WidgetStatePropertyAll(4),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: _surface,
        surfaceTintColor: Colors.transparent,
        elevation: 4,
        textStyle: const TextStyle(fontSize: 13, color: _text),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: const WidgetStatePropertyAll(_surface),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          elevation: const WidgetStatePropertyAll(4),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
      ),
      listTileTheme: const ListTileThemeData(
        dense: true,
        minVerticalPadding: 6,
        iconColor: _muted,
        textColor: _text,
        contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 2),
        titleTextStyle: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _text),
        subtitleTextStyle: TextStyle(fontSize: 11, color: _muted, height: 1.3),
      ),
      dividerTheme: const DividerThemeData(
        color: _border, thickness: 1, space: 1,
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: const Color(0xFFEEF3F8),
        selectedColor: const Color(0xFFDCEBFA),
        secondarySelectedColor: const Color(0xFFDDF2EA),
        labelStyle: const TextStyle(fontSize: 11, color: _text, fontWeight: FontWeight.w500),
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      ),
      tabBarTheme: const TabBarThemeData(
        labelColor: Colors.white,
        unselectedLabelColor: Color(0xFFD9E5F2),
        labelStyle: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        unselectedLabelStyle: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        indicatorSize: TabBarIndicatorSize.label,
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Colors.white,
        selectedItemColor: _primary,
        unselectedItemColor: Color(0xFF7B8794),
        selectedLabelStyle: TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
        unselectedLabelStyle: TextStyle(fontSize: 10),
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.white,
        indicatorColor: const Color(0xFFE3EFFB),
        height: 64,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 10,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700 : FontWeight.w500,
            color: states.contains(WidgetState.selected) ? _primary : _muted,
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF263544),
        contentTextStyle: const TextStyle(fontSize: 13, color: Colors.white),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: const Color(0xFF263544),
          borderRadius: BorderRadius.circular(7),
        ),
        textStyle: const TextStyle(color: Colors.white, fontSize: 11),
      ),
      textSelectionTheme: const TextSelectionThemeData(
        cursorColor: _primary,
        selectionColor: Color(0x331558A6),
        selectionHandleColor: _primary,
      ),
    );
  }
}
