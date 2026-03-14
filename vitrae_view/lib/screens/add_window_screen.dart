import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AddWindowScreen extends StatefulWidget {
  const AddWindowScreen({super.key});

  @override
  State<AddWindowScreen> createState() => _AddWindowScreenState();
}

class _AddWindowScreenState extends State<AddWindowScreen> {
  final _idController = TextEditingController();
  final _nomeController = TextEditingController();
  final _novaAreaController =
      TextEditingController(); // Controlador para o pop-up

  String? _areaIdSelecionada;
  String?
  _nomeNovaAreaVisual; // Apenas para mostrar o nome na UI antes de criar
  bool _isLoading = false;

  final String? _uid = FirebaseAuth.instance.currentUser?.uid;

  // Função para abrir o Pop-up de criação de área
  void _mostrarPopUpNovaArea() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Nova Área"),
        content: TextField(
          controller: _novaAreaController,
          decoration: const InputDecoration(
            labelText: "Nome da Área (ex: Sótão)",
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
              setState(() {
                _nomeNovaAreaVisual = _novaAreaController.text.trim();
                _areaIdSelecionada = null; // Prioriza a nova área
              });
              Navigator.pop(context);
            },
            child: const Text("Definir"),
          ),
        ],
      ),
    );
  }

  Future<void> _validarERegistar() async {
    final windowId = _idController.text.trim().toUpperCase();
    final nomeJanela = _nomeController.text.trim();

    // Validação: ou tem área selecionada, ou tem nome de nova área definido
    if (windowId.isEmpty ||
        nomeJanela.isEmpty ||
        (_areaIdSelecionada == null && _nomeNovaAreaVisual == null)) {
      _mostrarSnack("Preencha todos os campos e defina uma área.");
      return;
    }

    setState(() => _isLoading = true);

    try {
      // 1. Verificação de Fábrica (Segurança)
      var fabricaDoc = await FirebaseFirestore.instance
          .collection('janelas_fabrica')
          .doc(windowId)
          .get();
      if (!fabricaDoc.exists) {
        _mostrarSnack("Código inválido! Produto não oficial.");
        return;
      }

      // 2. Verificação de Duplicado
      var janelaExistente = await FirebaseFirestore.instance
          .collection('windows')
          .doc(windowId)
          .get();
      if (janelaExistente.exists) {
        _mostrarSnack("Esta janela já está registada.");
        return;
      }

      // 3. SE O UTILIZADOR DEFINIU UMA NOVA ÁREA NO POP-UP, CRIÁ-LA PRIMEIRO
      String finalAreaId = _areaIdSelecionada ?? "";

      if (_nomeNovaAreaVisual != null && _areaIdSelecionada == null) {
        DocumentReference novaAreaRef = await FirebaseFirestore.instance
            .collection('areas')
            .add({
              'nome': _nomeNovaAreaVisual,
              'userId': _uid,
              'criadoEm': FieldValue.serverTimestamp(),
            });
        finalAreaId =
            novaAreaRef.id; // Obtemos o ID da área que acabou de ser criada
      }

      // 4. Registar a Janela com o ID da área (existente ou nova)
      await FirebaseFirestore.instance.collection('windows').doc(windowId).set({
        'windowId': windowId,
        'nome': nomeJanela,
        'userId': _uid,
        'areaId': finalAreaId,
        'estado': 'Fechado',
        'luminosidade': 0,
        'gas': 0,
        'dataRegisto': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        _mostrarSnack("Janela e Área configuradas!", cor: Colors.green);
        Navigator.pop(context);
      }
    } catch (e) {
      _mostrarSnack("Erro: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _mostrarSnack(String texto, {Color cor = Colors.redAccent}) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(texto), backgroundColor: cor));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Configurar Janela")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            const Icon(
              Icons.add_to_home_screen,
              size: 70,
              color: Colors.blueAccent,
            ),
            const SizedBox(height: 25),
            TextField(
              controller: _idController,
              decoration: const InputDecoration(
                labelText: 'ID VITRAE',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 15),
            TextField(
              controller: _nomeController,
              decoration: const InputDecoration(
                labelText: 'Nome da Janela',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 25),

            // SEÇÃO DA ÁREA
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('areas')
                  .where('userId', isEqualTo: _uid)
                  .snapshots(),
              builder: (context, snapshot) {
                List<QueryDocumentSnapshot> areas = snapshot.data?.docs ?? [];

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (areas.isNotEmpty) ...[
                      DropdownButtonFormField<String>(
                        decoration: const InputDecoration(
                          labelText: "Escolher Divisão",
                          border: OutlineInputBorder(),
                        ),
                        value: _areaIdSelecionada,
                        items: areas
                            .map(
                              (doc) => DropdownMenuItem(
                                value: doc.id,
                                child: Text(doc['nome']),
                              ),
                            )
                            .toList(),
                        onChanged: (val) => setState(() {
                          _areaIdSelecionada = val;
                          _nomeNovaAreaVisual =
                              null; // Limpa a criação manual se escolher do dropdown
                        }),
                      ),
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: Text("OU"),
                        ),
                      ),
                    ],

                    // Botão para criar nova área via Pop-up
                    OutlinedButton.icon(
                      onPressed: _mostrarPopUpNovaArea,
                      icon: const Icon(Icons.add_location_alt),
                      label: Text(
                        _nomeNovaAreaVisual == null
                            ? "Criar Nova Divisão"
                            : "Área Definida: $_nomeNovaAreaVisual",
                      ),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 50),
                        side: BorderSide(
                          color: _nomeNovaAreaVisual != null
                              ? Colors.green
                              : Colors.blueAccent,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),

            const SizedBox(height: 40),
            _isLoading
                ? const CircularProgressIndicator()
                : ElevatedButton(
                    onPressed: _validarERegistar,
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 55),
                      backgroundColor: Colors.blueAccent,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text("FINALIZAR"),
                  ),
          ],
        ),
      ),
    );
  }
}
