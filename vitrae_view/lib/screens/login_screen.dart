import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;

  Future<void> _login() async {
    if (_emailController.text.isEmpty || _passwordController.text.isEmpty) {
      _mostrarErro('Por favor, preencha todos os campos.');
      return;
    }

    setState(() => _isLoading = true);

    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );
    } on FirebaseAuthException catch (e) {
      String mensagemPersonalizada;
      switch (e.code) {
        case 'invalid-credential':
        case 'user-not-found':
        case 'wrong-password':
          mensagemPersonalizada = 'Email ou palavra-passe incorretos.';
          break;
        case 'invalid-email':
          mensagemPersonalizada = 'O formato do email não é válido.';
          break;
        case 'user-disabled':
          mensagemPersonalizada = 'Esta conta foi desativada.';
          break;
        case 'too-many-requests':
          mensagemPersonalizada = 'Demasiadas tentativas. Tente mais tarde.';
          break;
        default:
          mensagemPersonalizada = 'Erro ao entrar. Verifique os seus dados.';
      }
      _mostrarErro(mensagemPersonalizada);
    } catch (e) {
      _mostrarErro('Erro inesperado: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _mostrarErro(String mensagem) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensagem),
        backgroundColor: Colors.redAccent,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      // Esta linha garante que o ecrã se ajusta quando o teclado aparece
      resizeToAvoidBottomInset: true,
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 30.0),
        child: Column(
          // Alinha tudo ao topo
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            // Margem superior para afastar da barra de status
            const SizedBox(height: 50),

            // Logótipo ajustado para 180 (era 300)
            Image.asset(
              'assets/logoCompleto.png',
              height: 200,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) => const Icon(
                Icons.window_rounded,
                size: 100,
                color: Colors.blueAccent,
              ),
            ),

            // Texto de boas-vindas sem o Transform (mais limpo)
            const Text(
              'Bem-vindo de volta!',
              style: TextStyle(fontSize: 18, color: Colors.grey),
            ),

            const SizedBox(height: 30),

            TextField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Email',
                prefixIcon: Icon(Icons.email_outlined),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),

            TextField(
              controller: _passwordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Palavra-passe',
                prefixIcon: Icon(Icons.lock_outline),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 30),

            _isLoading
                ? const CircularProgressIndicator()
                : ElevatedButton(
                    onPressed: _login,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blueAccent,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 55),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text(
                      'ENTRAR',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),

            const SizedBox(height: 20),

            TextButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const RegisterScreen(),
                  ),
                );
              },
              child: const Text(
                'Não tem conta? Registe-se aqui',
                style: TextStyle(color: Colors.blueAccent),
              ),
            ),

            // Espaço final para garantir que o scroll funciona com o teclado aberto
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
