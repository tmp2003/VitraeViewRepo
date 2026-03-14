import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();
  final _locationController = TextEditingController();

  bool _isLoading = false;
  List<dynamic> _suggestions = [];
  double? _selectedLat;
  double? _selectedLon;

  Future<void> _searchLocation(String query) async {
    if (query.length < 3) {
      setState(() => _suggestions = []);
      return;
    }

    final url =
        'https://geocoding-api.open-meteo.com/v1/search?name=$query&count=5&language=pt&format=json';

    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          _suggestions = data['results'] ?? [];
        });
      }
    } catch (e) {
      debugPrint('Erro na pesquisa: $e');
    }
  }

  Future<void> _register() async {
    if (_selectedLat == null || _selectedLon == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Por favor, selecione uma localização da lista.'),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      // 1. Criação no Firebase Auth
      UserCredential userCredential = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(
            email: _emailController.text.trim(),
            password: _passwordController.text.trim(),
          );

      // 2. Armazenamento no Firestore (Coleção 'users')
      await FirebaseFirestore.instance
          .collection('users')
          .doc(userCredential.user!.uid)
          .set({
            'nome': _nameController.text.trim(),
            'email': _emailController.text.trim(),
            'localizacao': _locationController.text.trim(),
            'latitude': _selectedLat,
            'longitude': _selectedLon,
            'data_registo': FieldValue.serverTimestamp(),
          });

      // ============================================================
      // ALTERAÇÃO: Forçar Logout após registo para não entrar direto
      // ============================================================
      await FirebaseAuth.instance.signOut();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Conta criada com sucesso! Por favor, faça login.'),
            backgroundColor: Colors.green,
          ),
        );
        // Volta para o ecrã de Login
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erro: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Registo VitraeView')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            const Icon(Icons.person_add_alt_1, size: 80, color: Colors.blue),
            const SizedBox(height: 20),

            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Nome de Utilizador',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.person),
              ),
            ),
            const SizedBox(height: 15),

            TextField(
              controller: _emailController,
              decoration: const InputDecoration(
                labelText: 'Email',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.email),
              ),
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 15),

            TextField(
              controller: _passwordController,
              decoration: const InputDecoration(
                labelText: 'Palavra-passe',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.lock),
              ),
              obscureText: true,
            ),
            const SizedBox(height: 15),

            TextField(
              controller: _locationController,
              decoration: const InputDecoration(
                labelText: 'Localização',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.location_on),
              ),
              onChanged: _searchLocation,
            ),

            if (_suggestions.isNotEmpty)
              Card(
                elevation: 4,
                child: ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _suggestions.length,
                  itemBuilder: (context, index) {
                    final place = _suggestions[index];
                    return ListTile(
                      leading: const Icon(Icons.map),
                      title: Text("${place['name']}"),
                      subtitle: Text(
                        "${place['admin1'] ?? ''}, ${place['country']}",
                      ),
                      onTap: () {
                        setState(() {
                          _locationController.text =
                              "${place['name']}, ${place['country']}";
                          _selectedLat = place['latitude'];
                          _selectedLon = place['longitude'];
                          _suggestions = [];
                        });
                      },
                    );
                  },
                ),
              ),

            const SizedBox(height: 30),

            _isLoading
                ? const CircularProgressIndicator()
                : ElevatedButton(
                    onPressed: _register,
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 50),
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Registar'),
                  ),
          ],
        ),
      ),
    );
  }
}
