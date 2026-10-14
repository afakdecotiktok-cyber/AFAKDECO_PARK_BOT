import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'services/api.dart';

const Color afakInk = Color(0xFF172033);
const Color afakBlue = Color(0xFF315AE7);
const Color afakCanvas = Color(0xFFF4F6FB);
const Color afakMuted = Color(0xFF68748A);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AfakdecoApp());
}

class AfakdecoApp extends StatelessWidget {
  const AfakdecoApp({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: afakBlue,
      brightness: Brightness.light,
      surface: Colors.white,
    );
    return MaterialApp(
      title: 'AFAKDECO PARK',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: scheme.copyWith(
          primary: afakBlue,
          onPrimary: Colors.white,
          secondary: const Color(0xFF19A7A1),
          surface: Colors.white,
          error: const Color(0xFFDC4545),
        ),
        scaffoldBackgroundColor: afakCanvas,
        appBarTheme: const AppBarTheme(
          backgroundColor: afakCanvas,
          foregroundColor: afakInk,
          elevation: 0,
          centerTitle: false,
          titleTextStyle: TextStyle(
            color: afakInk,
            fontSize: 20,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.35,
          ),
          iconTheme: IconThemeData(color: afakInk),
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: Color(0xFFE7EBF3)),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFFF8F9FC),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          hintStyle: const TextStyle(color: afakMuted, fontSize: 14),
          labelStyle: const TextStyle(color: afakMuted),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(15),
            borderSide: const BorderSide(color: Color(0xFFE2E7F0)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(15),
            borderSide: const BorderSide(color: Color(0xFFE2E7F0)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(15),
            borderSide: const BorderSide(color: afakBlue, width: 1.6),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: afakBlue,
            foregroundColor: Colors.white,
            minimumSize: const Size(48, 48),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
            textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: afakInk,
            minimumSize: const Size(44, 46),
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
            side: const BorderSide(color: Color(0xFFDDE3EE)),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
            textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          ),
        ),
        chipTheme: scheme.chipTheme.copyWith(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
          side: const BorderSide(color: Color(0xFFE4E8F1)),
          labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        ),
        dividerTheme: const DividerThemeData(color: Color(0xFFE9EDF4), thickness: 1),
        bottomSheetTheme: const BottomSheetThemeData(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          showDragHandle: true,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: Colors.white,
          indicatorColor: const Color(0xFFE8EEFF),
          elevation: 0,
          height: 72,
          labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
            fontSize: 11,
            fontWeight: states.contains(WidgetState.selected) ? FontWeight.w800 : FontWeight.w500,
            color: states.contains(WidgetState.selected) ? afakBlue : afakMuted,
          )),
        ),
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        progressIndicatorTheme: const ProgressIndicatorThemeData(color: afakBlue),
      ),
      home: FutureBuilder<bool>(
        future: Api.instance.hasToken(),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          if (snapshot.data == true) return const HomeScreen();
          return const LoginScreen();
        },
      ),
    );
  }
}
