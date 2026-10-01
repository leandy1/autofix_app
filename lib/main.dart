import 'package:flutter/material.dart';
import 'package:autofix/features/auth/screens/login_screen.dart';

void main() {
  runApp(const AutoFixApp());
}

class AutoFixApp extends StatelessWidget {
  const AutoFixApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'AutoFix',
      home: const LoginScreen(),
    );
  }
}
