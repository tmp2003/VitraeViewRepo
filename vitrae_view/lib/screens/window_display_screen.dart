import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class WindowDisplayScreen extends StatelessWidget {
  final String windowId;

  const WindowDisplayScreen({super.key, required this.windowId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black, // Simula a janela desligada
      body: StreamBuilder<DocumentSnapshot>(
        // Fica constantemente à escuta das alterações deste documento!
        stream: FirebaseFirestore.instance.collection('windows').doc(windowId).snapshots(),
        builder: (context, snapshot) {

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || !snapshot.data!.exists) {
            return const Center(child: Text("Janela não encontrada", style: TextStyle(color: Colors.white)));
          }

          // Retira as coordenadas da base de dados
          var data = snapshot.data!.data() as Map<String, dynamic>;

          // Se não houver coordenadas definidas, usa 0,0 por defeito
          double clockX = data['clockX']?.toDouble() ?? 0.0;
          double clockY = data['clockY']?.toDouble() ?? 0.0;

          return Stack(
            children: [
              Positioned(
                left: clockX,
                top: clockY,
                child: _buildClockWidget(), // Redesenha o relógio na nova posição!
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildClockWidget() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.transparent,
        border: Border.all(color: Colors.white30),
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Text(
        "14:30",
        style: TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold),
      ),
    );
  }
}