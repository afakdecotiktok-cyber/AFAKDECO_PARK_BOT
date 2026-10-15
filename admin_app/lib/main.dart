import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'services/api.dart';
import 'theme/app_theme.dart';
import 'widgets/app_widgets.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AfakdecoApp());
}

class AfakdecoApp extends StatelessWidget {
  const AfakdecoApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'AFAKDECO PARK',
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(Brightness.light),
        darkTheme: buildAppTheme(Brightness.dark),
        themeMode: ThemeMode.system,
        builder: (context, child) => Directionality(
          textDirection: TextDirection.rtl,
          child: child ?? const SizedBox.shrink(),
        ),
        home: const AuthGate(),
      );
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late Future<bool> _session;

  @override
  void initState() {
    super.initState();
    _session = Api.instance.hasToken();
  }

  void _retry() => setState(() => _session = Api.instance.hasToken());

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _session,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const _AppSplash();
        }
        if (snapshot.hasError) {
          return Scaffold(
            body: ErrorState(
              message: 'تعذر التحقق من جلسة الدخول. تحقق من الاتصال ثم أعد المحاولة.',
              onRetry: _retry,
            ),
          );
        }
        return snapshot.data == true ? const HomeScreen() : const LoginScreen();
      },
    );
  }
}

class _AppSplash extends StatelessWidget {
  const _AppSplash();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                borderRadius: BorderRadius.circular(22),
              ),
              child: Icon(
                Icons.local_shipping_rounded,
                color: theme.colorScheme.onPrimary,
                size: 34,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'AFAKDECO PARK',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: .1,
              ),
            ),
            const SizedBox(height: 8),
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ],
        ),
      ),
    );
  }
}
