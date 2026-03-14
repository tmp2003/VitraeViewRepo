import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'firebase_options.dart';
import 'package:vitrae_view/screens/login_screen.dart';
import 'package:vitrae_view/screens/dashboard_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  runApp(const VitraeViewApp());
}

class VitraeViewApp extends StatelessWidget {
  const VitraeViewApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VitraeView',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueAccent),
        useMaterial3: true,
      ),
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          // 1. Enquanto o Firebase verifica a sessão (Splash Screen)
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Scaffold(
              backgroundColor: Colors.white,
              body: Center(
                child: Image.asset(
                  'assets/logoCompleto.png',
                  width: 250, // Ajusta o tamanho conforme necessário
                  fit: BoxFit.contain,
                ),
              ),
            );
          }

          // 2. Se o utilizador já estiver logado
          if (snapshot.hasData) {
            return const DashboardScreen();
          }

          // 3. Se não houver sessão ativa, vai para o Login
          return const LoginScreen();
        },
      ),
    );
  }
}
