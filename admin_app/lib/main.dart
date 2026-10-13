import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'services/api.dart';

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
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF111111),
          ),
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
