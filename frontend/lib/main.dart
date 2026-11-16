import 'package:flutter/material.dart';
import 'screens/auth_screen.dart';

void main() => runApp(const VaultlineApp());

class VaultlineApp extends StatelessWidget {
  const VaultlineApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Vaultline',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          colorSchemeSeed: const Color(0xFF14B8A6),
          scaffoldBackgroundColor: const Color(0xFF0B1220),
        ),
        home: const AuthScreen(),
      );
}
