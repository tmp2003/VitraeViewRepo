import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:vitrae_view/screens/window_editor_screen.dart';
import 'add_area_screen.dart';
import 'add_window_screen.dart';
import 'profile_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _selectedIndex = 0;
  final String? _uid = FirebaseAuth.instance.currentUser?.uid;
  final _newAreaController = TextEditingController();

  // Widget auxiliar para construir o título da AppBar (Logótipo + Bem-vindo)
  Widget _buildAppBarTitle() {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(_uid)
          .snapshots(),
      builder: (context, snapshot) {
        String nome = "Utilizador";
        if (snapshot.hasData && snapshot.data!.exists) {
          nome = snapshot.data!['nome'] ?? "Utilizador";
        }

        return Row(
          children: [
            // LOGÓTIPO EM IMAGEM
            ClipRRect(
              borderRadius: BorderRadius.circular(8), // Cantos arredondados
              child: Image.asset(
                'assets/logo.png',
                height: 35, // Altura ajustada para a AppBar
                width: 35,
                fit: BoxFit.contain,
                // Se a imagem não existir ainda, mostra um ícone de erro para não quebrar a app
                errorBuilder: (context, error, stackTrace) =>
                const Icon(Icons.broken_image, color: Colors.grey),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Bem-vindo, $nome',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        );
      },
    );
  }

  // --- POP-UP DE CONFIRMAÇÃO DE LOGOUT ---
  void _showLogoutConfirmation(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.logout, color: Colors.redAccent),
            SizedBox(width: 10),
            Text("Terminar Sessão"),
          ],
        ),
        content: const Text("Tem a certeza que quer sair da sua conta?"),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancelar", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.pop(context); // Fecha o pop-up
              FirebaseAuth.instance.signOut(); // Termina a sessão
            },
            child: const Text("Sair"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('areas')
          .where('userId', isEqualTo: _uid)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        List<QueryDocumentSnapshot> areasDocs = snapshot.data?.docs ?? [];
        List<String> nomesAreas = areasDocs
            .map((doc) => doc['nome'].toString())
            .toList();

        if (nomesAreas.isEmpty) {
          return _buildEmptyState(context);
        }

        if (_selectedIndex >= areasDocs.length) _selectedIndex = 0;
        String currentAreaId = areasDocs[_selectedIndex].id;

        return Scaffold(
          appBar: AppBar(
            title: _buildAppBarTitle(), // <--- Título Dinâmico
            actions: [
              IconButton(
                icon: const Icon(Icons.person_outline),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const ProfileScreen(),
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(
                  Icons.add_circle_outline,
                  color: Colors.blueAccent,
                ),
                onPressed: () => _showAddOptions(context),
              ),
              IconButton(
                icon: const Icon(Icons.logout),
                onPressed: () => _showLogoutConfirmation(context), // <--- Pop-up adicionado aqui
              ),
            ],
          ),
          body: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Área: ${nomesAreas[_selectedIndex]}',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 20),
                Expanded(
                  child: StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('windows')
                        .where('areaId', isEqualTo: currentAreaId)
                        .where('userId', isEqualTo: _uid)
                        .snapshots(),
                    builder: (context, windowSnapshot) {
                      if (windowSnapshot.connectionState ==
                          ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      var windows = windowSnapshot.data?.docs ?? [];
                      if (windows.isEmpty) {
                        return const Center(
                          child: Text(
                            'Nenhuma janela nesta área.',
                            style: TextStyle(color: Colors.grey),
                          ),
                        );
                      }
                      return GridView.builder(
                        gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 15,
                          mainAxisSpacing: 15,
                          childAspectRatio: 0.85,
                        ),
                        itemCount: windows.length,
                        itemBuilder: (context, index) {
                          var windowData =
                          windows[index].data() as Map<String, dynamic>;

                          String windowId = windows[index].id;

                          return _buildWindowCard(
                            windowId,
                            windowData['nome'] ?? 'Sem nome',
                            windowData['estado'] ?? 'Desligada', // Default para Desligada
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          bottomNavigationBar: nomesAreas.length > 1
              ? BottomNavigationBar(
            currentIndex: _selectedIndex,
            selectedItemColor: Colors.blueAccent,
            onTap: (index) => setState(() => _selectedIndex = index),
            items: nomesAreas
                .map(
                  (nome) => BottomNavigationBarItem(
                icon: const Icon(Icons.place),
                label: nome,
              ),
            )
                .toList(),
          )
              : null,
        );
      },
    );
  }

  // --- MÉTODOS AUXILIARES ---

  Widget _buildEmptyState(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: _buildAppBarTitle(),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_outline),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const ProfileScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => _showLogoutConfirmation(context), // <--- Pop-up adicionado aqui também
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.home_work_outlined, size: 80, color: Colors.grey),
            const SizedBox(height: 20),
            const Text(
              'A sua casa ainda está vazia.',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 30),
            ElevatedButton.icon(
              onPressed: _showQuickAreaDialog,
              icon: const Icon(Icons.add),
              label: const Text('ADICIONAR PRIMEIRA ÁREA'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blueAccent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 30,
                  vertical: 15,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showQuickAreaDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Nova Divisão"),
        content: TextField(
          controller: _newAreaController,
          decoration: const InputDecoration(
            labelText: "Nome da área",
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancelar"),
          ),
          ElevatedButton(
            onPressed: () {
              _saveQuickArea();
              Navigator.pop(context);
            },
            child: const Text("Criar"),
          ),
        ],
      ),
    );
  }

  Future<void> _saveQuickArea() async {
    if (_newAreaController.text.isEmpty) return;
    await FirebaseFirestore.instance.collection('areas').add({
      'nome': _newAreaController.text.trim(),
      'userId': _uid,
      'criadoEm': FieldValue.serverTimestamp(),
    });
    _newAreaController.clear();
  }

  // --- ADICIONA ESTE NOVO MÉTODO (Pop-Up de Apagar Janela) ---
  void _showDeleteWindowDialog(String windowId, String nome) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.delete_forever, color: Colors.redAccent),
            SizedBox(width: 10),
            Text("Remover Janela"),
          ],
        ),
        content: Text("Tem a certeza que quer apagar a janela '$nome'? Esta ação é irreversível."),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancelar", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
            onPressed: () async {
              Navigator.pop(context); // Fecha o pop-up
              // Apaga a janela definitivamente da base de dados!
              await FirebaseFirestore.instance.collection('windows').doc(windowId).delete();
              if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Janela removida com sucesso!')));
            },
            child: const Text("Apagar"),
          ),
        ],
      ),
    );
  }

  // --- SUBSTITUI O TEU _buildWindowCard POR ESTE (Agora tem onLongPress) ---
  Widget _buildWindowCard(String windowId, String nome, String estado) {
    bool isOn = (estado == 'Ligada' || estado == 'Aberto');
    String displayEstado = isOn ? 'Ligada' : 'Desligada';

    return InkWell(
      onTap: () {
        Navigator.push(context, MaterialPageRoute(builder: (context) => WindowEditorScreen(windowId: windowId)));
      },
      // MAGIA: Pressionar longo para apagar a janela!
      onLongPress: () => _showDeleteWindowDialog(windowId, nome),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, 5))],
          border: Border.all(color: Colors.blueAccent.withOpacity(0.1)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(isOn ? Icons.window : Icons.window_outlined, size: 50, color: Colors.blueAccent),
            const SizedBox(height: 12),
            Text(nome, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16), maxLines: 1),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: isOn ? Colors.green.withOpacity(0.1) : Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(displayEstado, style: TextStyle(color: isOn ? Colors.green : Colors.red, fontWeight: FontWeight.bold, fontSize: 12)),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.grid_view, color: Colors.blue),
              title: const Text('Adicionar Área (Divisão)'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const AddAreaScreen(),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.window_outlined, color: Colors.blue),
              title: const Text('Adicionar Janela'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const AddWindowScreen(),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}