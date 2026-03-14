import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _user = FirebaseAuth.instance.currentUser;
  final _nameController = TextEditingController();
  final _locationController = TextEditingController();
  final _emailController = TextEditingController();
  final _oldPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();

  bool _isLoading = false;
  List<dynamic> _suggestions = [];
  double? _selectedLat;
  double? _selectedLon;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  // Carrega os dados atuais do Firestore
  Future<void> _loadUserData() async {
    var doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(_user?.uid)
        .get();
    if (doc.exists) {
      setState(() {
        _nameController.text = doc['nome'] ?? '';
        _locationController.text = doc['localizacao'] ?? '';
        _emailController.text = _user?.email ?? '';
        _selectedLat = doc['latitude'];
        _selectedLon = doc['longitude'];
      });
    }
  }

  // Pesquisa de localização (Igual ao registo para consistência)
  Future<void> _searchLocation(String query) async {
    if (query.length < 3) return;
    final url =
        'https://geocoding-api.open-meteo.com/v1/search?name=$query&count=5&language=pt&format=json';
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() => _suggestions = data['results'] ?? []);
      }
    } catch (e) {
      debugPrint(e.toString());
    }
  }

  Future<void> _updateProfile() async {
    setState(() => _isLoading = true);
    try {
      // 1. Reautenticação se quiser mudar email ou password (Segurança Firebase)
      if (_oldPasswordController.text.isNotEmpty) {
        AuthCredential credential = EmailAuthProvider.credential(
          email: _user!.email!,
          password: _oldPasswordController.text,
        );
        await _user!.reauthenticateWithCredential(credential);

        if (_oldPasswordController.text.isNotEmpty) {
          AuthCredential credential = EmailAuthProvider.credential(
            email: _user!.email!,
            password: _oldPasswordController.text,
          );
          await _user!.reauthenticateWithCredential(credential);

          // Alterar Password (este método ainda funciona igual)
          if (_newPasswordController.text.isNotEmpty) {
            await _user!.updatePassword(_newPasswordController.text);
          }

          // Alterar Email (O NOVO MÉTODO)
          if (_emailController.text != _user!.email) {
            // Em vez de updateEmail, usamos este:
            await _user!.verifyBeforeUpdateEmail(_emailController.text.trim());

            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  "Verifique o seu novo email para confirmar a alteração!",
                ),
              ),
            );
          }
        }
      }

      // 2. Atualizar Firestore
      await FirebaseFirestore.instance
          .collection('users')
          .doc(_user!.uid)
          .update({
            'nome': _nameController.text.trim(),
            'localizacao': _locationController.text.trim(),
            'latitude': _selectedLat,
            'longitude': _selectedLon,
          });

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("Perfil atualizado!")));
        Navigator.pop(context);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Erro: Verifique a password antiga ou ligação."),
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Meu Perfil")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            const CircleAvatar(radius: 50, child: Icon(Icons.person, size: 50)),
            const SizedBox(height: 20),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: "Nome",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 15),
            TextField(
              controller: _locationController,
              decoration: const InputDecoration(
                labelText: "Localização",
                border: OutlineInputBorder(),
              ),
              onChanged: _searchLocation,
            ),
            if (_suggestions.isNotEmpty)
              Card(
                child: Column(
                  children: _suggestions
                      .map(
                        (p) => ListTile(
                          title: Text(p['name']),
                          subtitle: Text(p['country']),
                          onTap: () => setState(() {
                            _locationController.text = p['name'];
                            _selectedLat = p['latitude'];
                            _selectedLon = p['longitude'];
                            _suggestions = [];
                          }),
                        ),
                      )
                      .toList(),
                ),
              ),
            const SizedBox(height: 15),
            TextField(
              controller: _emailController,
              decoration: const InputDecoration(
                labelText: "Email",
                border: OutlineInputBorder(),
              ),
            ),
            const Divider(height: 40),
            const Text(
              "Alterar Segurança",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _oldPasswordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: "Password Antiga (Necessária para mudanças)",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _newPasswordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: "Nova Password (Opcional)",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 30),
            _isLoading
                ? const CircularProgressIndicator()
                : ElevatedButton(
                    onPressed: _updateProfile,
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 50),
                    ),
                    child: const Text("GUARDAR ALTERAÇÕES"),
                  ),
          ],
        ),
      ),
    );
  }
}
