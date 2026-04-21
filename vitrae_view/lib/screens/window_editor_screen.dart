import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class WindowEditorScreen extends StatefulWidget {
  final String windowId;

  const WindowEditorScreen({super.key, required this.windowId});

  @override
  State<WindowEditorScreen> createState() => _WindowEditorScreenState();
}

class _WindowEditorScreenState extends State<WindowEditorScreen> {
  // Estado do Menu Bubble
  bool _isMenuOpen = false;

  // Chave para conseguir saber exatamente onde largamos o widget na janela
  final GlobalKey _windowKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade900,
      appBar: AppBar(title: Text("Configurar Layout: ${widget.windowId}")),
      body: Stack(
        children: [
          // 1. ÁREA DA JANELA (O Editor)
          Padding(
            padding: const EdgeInsets.all(40.0),
            child: StreamBuilder<DocumentSnapshot>(
              stream: FirebaseFirestore.instance.collection('windows').doc(widget.windowId).snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

                var data = snapshot.data!.data() as Map<String, dynamic>? ?? {};

                double resW = (data['resW'] ?? 1024).toDouble();
                double resH = (data['resH'] ?? 600).toDouble();
                double aspect = resW / resH;

                return Center(
                  child: AspectRatio(
                    aspectRatio: aspect,
                    // O DragTarget é a "zona de aterragem" para os ícones novos
                    child: DragTarget<String>(
                      onAcceptWithDetails: (details) {
                        // Calcula exatamente onde o dedo largou o widget dentro da área
                        final RenderBox renderBox = _windowKey.currentContext!.findRenderObject() as RenderBox;
                        final localPosition = renderBox.globalToLocal(details.offset);

                        double relX = localPosition.dx / renderBox.size.width;
                        double relY = localPosition.dy / renderBox.size.height;

                        // Guarda o novo widget na Firebase na posição do drop
                        _savePositionToFirebase(details.data, relX.clamp(0.0, 1.0), relY.clamp(0.0, 1.0));

                        // Fecha o menu depois de adicionar
                        setState(() => _isMenuOpen = false);
                      },
                      builder: (context, candidateData, rejectedData) {
                        return Container(
                          key: _windowKey,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              // Fica verde se estivermos a pairar com um widget por cima
                                color: candidateData.isNotEmpty ? Colors.green : Colors.blueAccent,
                                width: 3
                            ),
                            boxShadow: [BoxShadow(color: Colors.blueAccent.withOpacity(0.2), blurRadius: 30, spreadRadius: 5)],
                          ),
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final double areaW = constraints.maxWidth;
                              final double areaH = constraints.maxHeight;

                              double scaleX = areaW / resW;
                              double scaleY = areaH / resH;

                              return Stack(
                                clipBehavior: Clip.none, // Permite que os widgets saiam visualmente da janela ao remover
                                children: [
                                  // RELÓGIO (Só aparece se existir na Firebase)
                                  if (data.containsKey('clockX'))
                                    SmartDraggable(
                                      initialX: (data['clockX']).toDouble(),
                                      initialY: (data['clockY']).toDouble(),
                                      areaW: areaW, areaH: areaH,
                                      widgetW: 250 * scaleX, widgetH: 120 * scaleY,
                                      child: _designClock(),
                                      onSave: (x, y) => _savePositionToFirebase('clock', x, y),
                                      onDelete: () => _deleteFromFirebase('clock'),
                                    ),

                                  // CLIMA (Só aparece se existir na Firebase)
                                  if (data.containsKey('weatherX'))
                                    SmartDraggable(
                                      initialX: (data['weatherX']).toDouble(),
                                      initialY: (data['weatherY']).toDouble(),
                                      areaW: areaW, areaH: areaH,
                                      widgetW: 200 * scaleX, widgetH: 120 * scaleY,
                                      child: _designWeather(),
                                      onSave: (x, y) => _savePositionToFirebase('weather', x, y),
                                      onDelete: () => _deleteFromFirebase('weather'),
                                    ),

                                  // GÁS (Só aparece se existir na Firebase)
                                  if (data.containsKey('gasX'))
                                    SmartDraggable(
                                      initialX: (data['gasX']).toDouble(),
                                      initialY: (data['gasY']).toDouble(),
                                      areaW: areaW, areaH: areaH,
                                      widgetW: 220 * scaleX, widgetH: 80 * scaleY,
                                      child: _designGas(),
                                      onSave: (x, y) => _savePositionToFirebase('gas', x, y),
                                      onDelete: () => _deleteFromFirebase('gas'),
                                    ),
                                ],
                              );
                            },
                          ),
                        );
                      },
                    ),
                  ),
                );
              },
            ),
          ),

          // 2. O MENU BUBBLE NO TOPO
          Positioned(
            top: 20,
            left: 0,
            right: 0,
            child: Align(
              alignment: Alignment.topCenter,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
                height: 60,
                width: _isMenuOpen ? 250 : 60,
                // O clipBehavior corta os ícones que tentem aparecer fora da caixa durante a animação
                clipBehavior: Clip.hardEdge,
                decoration: BoxDecoration(
                  color: Colors.blueAccent,
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 10, offset: Offset(0, 5))],
                ),
                // O SingleChildScrollView evita o erro amarelo e preto (Overflow)
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  physics: const NeverScrollableScrollPhysics(), // Impede de fazer scroll com o dedo
                  child: SizedBox(
                    width: _isMenuOpen ? 250 : 60,
                    height: 60,
                    child: Row(
                      mainAxisAlignment: _isMenuOpen ? MainAxisAlignment.spaceEvenly : MainAxisAlignment.center,
                      children: [
                        // Botão para abrir/fechar o menu
                        IconButton(
                          icon: Icon(_isMenuOpen ? Icons.close : Icons.add_circle_outline, color: Colors.white, size: 30),
                          onPressed: () => setState(() => _isMenuOpen = !_isMenuOpen),
                        ),

                        // Ícones arrastáveis (Só aparecem se o menu estiver aberto)
                        if (_isMenuOpen) ...[
                          _buildMenuDraggableIcon('clock', Icons.access_time),
                          _buildMenuDraggableIcon('weather', Icons.cloud),
                          _buildMenuDraggableIcon('gas', Icons.gas_meter),
                        ]
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Cria um ícone arrastável para o Menu Bubble
  Widget _buildMenuDraggableIcon(String widgetId, IconData icon) {
    return Draggable<String>(
      data: widgetId, // A informação que é enviada para o DragTarget
      feedback: Icon(icon, color: Colors.white, size: 40), // Como fica no dedo enquanto arrastamos
      childWhenDragging: Icon(icon, color: Colors.white38, size: 30), // Como fica no menu enquanto arrastamos
      child: Icon(icon, color: Colors.white, size: 30), // Como fica no menu normal
    );
  }

  // --- FUNÇÕES DA FIREBASE ---
  Future<void> _savePositionToFirebase(String prefix, double x, double y) async {
    await FirebaseFirestore.instance.collection('windows').doc(widget.windowId).update({
      '${prefix}X': x,
      '${prefix}Y': y,
    });
  }

  Future<void> _deleteFromFirebase(String prefix) async {
    await FirebaseFirestore.instance.collection('windows').doc(widget.windowId).update({
      // FieldValue.delete() é a função mágica que apaga a coluna da base de dados!
      '${prefix}X': FieldValue.delete(),
      '${prefix}Y': FieldValue.delete(),
    });
    if(mounted){
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Widget removido!'), duration: Duration(seconds: 1)));
    }
  }

  // --- DESIGNS DOS WIDGETS ---
  Widget _designClock() {
    return Container(
      decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(6)),
      alignment: Alignment.center,
      // O Stream.periodic "apita" a cada 1 segundo, atualizando apenas o texto!
      child: StreamBuilder(
        stream: Stream.periodic(const Duration(seconds: 1)),
        builder: (context, snapshot) {
          final agora = DateTime.now();
          // O padLeft(2, '0') garante que as 9:5 apareçam como 09:05
          final hora = agora.hour.toString().padLeft(2, '0');
          final minuto = agora.minute.toString().padLeft(2, '0');

          return Text(
            "$hora:$minuto",
            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
          );
        },
      ),
    );
  }

  Widget _designWeather() {
    return Container(
      decoration: BoxDecoration(color: Colors.blueAccent.shade700, borderRadius: BorderRadius.circular(6)),
      alignment: Alignment.center,
      child: const Icon(Icons.cloud, color: Colors.white, size: 24),
    );
  }

  Widget _designGas() {
    return Container(
      decoration: BoxDecoration(color: Colors.green, borderRadius: BorderRadius.circular(6)),
      alignment: Alignment.center,
      child: const Text("GÁS", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10)),
    );
  }
}

// ============================================================================
// O CÉREBRO INDIVIDUAL (SMART DRAGGABLE) - COM LÓGICA DE 70% E SNAP À BORDA
// ============================================================================
class SmartDraggable extends StatefulWidget {
  final double initialX;
  final double initialY;
  final double areaW;
  final double areaH;
  final double widgetW;
  final double widgetH;
  final Widget child;
  final Function(double, double) onSave;
  final VoidCallback onDelete;

  const SmartDraggable({
    super.key,
    required this.initialX,
    required this.initialY,
    required this.areaW,
    required this.areaH,
    required this.widgetW,
    required this.widgetH,
    required this.child,
    required this.onSave,
    required this.onDelete,
  });

  @override
  State<SmartDraggable> createState() => _SmartDraggableState();
}

class _SmartDraggableState extends State<SmartDraggable> {
  late double currentX;
  late double currentY;
  bool isDragging = false;

  Offset? startPointer;
  late double startX;
  late double startY;

  @override
  void initState() {
    super.initState();
    currentX = widget.initialX;
    currentY = widget.initialY;
  }

  @override
  void didUpdateWidget(SmartDraggable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!isDragging) {
      currentX = widget.initialX;
      currentY = widget.initialY;
    }
  }

  // Função auxiliar para saber se estamos em "Zona de Perigo" (70% fora da janela)
  bool _isMarkedForDeletion() {
    // Calcula que percentagem da Janela o widget ocupa
    double relWidgetW = widget.widgetW / widget.areaW;
    double relWidgetH = widget.widgetH / widget.areaH;

    // Regras dos 70% para cada um dos 4 lados
    bool isOutLeft = currentX < -(0.70 * relWidgetW);
    bool isOutRight = currentX > 1.0 - (0.30 * relWidgetW); // Se sobram menos de 30% dentro, 70% está fora
    bool isOutTop = currentY < -(0.70 * relWidgetH);
    bool isOutBottom = currentY > 1.0 - (0.30 * relWidgetH);

    return isOutLeft || isOutRight || isOutTop || isOutBottom;
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: currentX * widget.areaW,
      top: currentY * widget.areaH,
      child: GestureDetector(
        onPanStart: (details) {
          setState(() {
            isDragging = true;
            startPointer = details.globalPosition;
            startX = currentX;
            startY = currentY;
          });
        },
        onPanUpdate: (details) {
          if (startPointer == null) return;

          double dx = details.globalPosition.dx - startPointer!.dx;
          double dy = details.globalPosition.dy - startPointer!.dy;

          setState(() {
            currentX = startX + (dx / widget.areaW);
            currentY = startY + (dy / widget.areaH);

            // Permite arrastar o widget livremente para fora para dar feedback visual
            currentX = currentX.clamp(-1.0, 2.0);
            currentY = currentY.clamp(-1.0, 2.0);
          });
        },
        onPanEnd: (_) {
          setState(() => isDragging = false);

          if (_isMarkedForDeletion()) {
            // Se 70% ou mais estiver fora, apaga!
            widget.onDelete();
          } else {
            // SE NÃO ESTIVER APAGADO, FAZ "SNAP" (Encaixa na borda interior da janela)
            double maxLeft = 1.0 - (widget.widgetW / widget.areaW);
            double maxTop = 1.0 - (widget.widgetH / widget.areaH);

            setState(() {
              currentX = currentX.clamp(0.0, maxLeft);
              currentY = currentY.clamp(0.0, maxTop);
            });

            // Grava a nova posição já com o Snap aplicado
            widget.onSave(currentX, currentY);
          }
        },
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 150),
          // Se estiver na "Zona de Perigo" fica semi-transparente para avisar que vai apagar
          opacity: _isMarkedForDeletion() ? 0.3 : 1.0,
          child: SizedBox(
            width: widget.widgetW,
            height: widget.widgetH,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}