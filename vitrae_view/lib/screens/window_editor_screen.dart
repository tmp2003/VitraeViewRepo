import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:google_sign_in/google_sign_in.dart'; // <--- OBRIGATÓRIO PARA O CALENDÁRIO

class WindowEditorScreen extends StatefulWidget {
  final String windowId;

  const WindowEditorScreen({super.key, required this.windowId});

  @override
  State<WindowEditorScreen> createState() => _WindowEditorScreenState();
}

class _WindowEditorScreenState extends State<WindowEditorScreen> {
  bool _isMenuOpen = false;
  final GlobalKey _windowKey = GlobalKey();

  final Map<String, String> _fusosHorariosMap = {
    'Local': 'Hora Local do Sistema',
    'UTC': 'Tempo Universal (UTC)',
    'Europe/Lisbon': 'Europa / Lisboa',
    // ... podes manter aqui a tua lista enorme de fusos horários do ficheiro original para não ficar gigante neste bloco de código ...
  };

  // --- MOTOR DE DETEÇÃO DE COLISÕES ---
  bool _hasOverlap(String skipId, double testX, double testY, String testType, Map<String, dynamic> widgetsData, double resW, double resH) {
    // ATUALIZADO PARA SUPORTAR O TAMANHO DO CALENDÁRIO
    double getRelW(String t) => (t == 'clock' ? 250 : t == 'weather' ? 200 : t == 'calendar' ? 310 : 220) / resW;
    double getRelH(String t) => (t == 'gas' ? 80 : t == 'calendar' ? 250 : 120) / resH;

    Rect testRect = Rect.fromLTWH(testX, testY, getRelW(testType), getRelH(testType));

    for (var entry in widgetsData.entries) {
      if (entry.key == skipId) continue;
      Map<String, dynamic> w = entry.value;
      double wx = (w['x'] ?? 0.5).toDouble();
      double wy = (w['y'] ?? 0.5).toDouble();

      Rect existingRect = Rect.fromLTWH(wx, wy, getRelW(w['type']), getRelH(w['type']));

      if (testRect.overlaps(existingRect)) return true;
    }
    return false;
  }

  // --- FUNÇÃO MÁGICA: SINCRONIZAR COM O GOOGLE CALENDAR ---
  Future<void> _syncCalendarWithGoogle(String widgetId) async {
    try {
      // 1. Pedir acesso ao Google
      final GoogleSignIn googleSignIn = GoogleSignIn(
        scopes: ['https://www.googleapis.com/auth/calendar.readonly'],
        // Usamos o Web Client ID que configuraste na Fase 0
        serverClientId: '555974802803-4na1f4nbj856kmqkfc2hv5808fc17kmk.apps.googleusercontent.com',
      );

      final account = await googleSignIn.signIn();
      if (account == null) return; // Utilizador cancelou o pop-up

      final auth = await account.authentication;
      final String? token = auth.accessToken;

      if (token == null) throw Exception("Token de acesso inválido.");

      // 2. Fetch dos Eventos via API REST da Google
      DateTime agora = DateTime.now();
      DateTime daqui7Dias = agora.add(const Duration(days: 7));

      final url = Uri.parse(
          "https://www.googleapis.com/calendar/v3/calendars/primary/events"
              "?timeMin=${agora.toUtc().toIso8601String()}"
              "&timeMax=${daqui7Dias.toUtc().toIso8601String()}"
              "&singleEvents=true"
              "&orderBy=startTime"
      );

      final response = await http.get(
        url,
        headers: { 'Authorization': 'Bearer $token' },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final items = data['items'] as List<dynamic>? ?? [];

        List<Map<String, dynamic>> tarefasParaPython = [];

        // 3. Formatar os eventos para a estrutura {day, time, title} do Python
        for (var item in items) {
          String? startString = item['start']['dateTime'] ?? item['start']['date'];
          if (startString == null) continue;

          DateTime dataInicio = DateTime.parse(startString).toLocal();
          String diaFormatado = "${dataInicio.day.toString().padLeft(2, '0')}/${dataInicio.month.toString().padLeft(2, '0')}";

          String horaFormatada = item['start']['dateTime'] != null
              ? "${dataInicio.hour.toString().padLeft(2, '0')}:${dataInicio.minute.toString().padLeft(2, '0')}"
              : "Dia todo";

          tarefasParaPython.add({
            "day": diaFormatado,
            "time": horaFormatada,
            "title": item['summary'] ?? "Sem Título",
          });
        }

        // 4. Enviar para a Firebase no local exato do Widget
        await FirebaseFirestore.instance.collection('windows').doc(widget.windowId).update({
          'widgets.$widgetId.events': tarefasParaPython
        });

        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ Tarefas do Google enviadas para a janela!')));
      } else {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('❌ Erro ao ler eventos da Google.')));
      }
    } catch (e) {
      debugPrint("Erro Sincronização Calendário: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade900,
      appBar: AppBar(title: Text("Configurar Layout: ${widget.windowId}")),
      body: Stack(
        children: [
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
                Map<String, dynamic> widgetsData = data['widgets'] ?? {};

                return Center(
                  child: AspectRatio(
                    aspectRatio: aspect,
                    child: DragTarget<String>(
                      onAcceptWithDetails: (details) {
                        final RenderBox renderBox = _windowKey.currentContext!.findRenderObject() as RenderBox;
                        final localPosition = renderBox.globalToLocal(details.offset);

                        double relX = (localPosition.dx / renderBox.size.width).clamp(0.0, 1.0);
                        double relY = (localPosition.dy / renderBox.size.height).clamp(0.0, 1.0);

                        if (_hasOverlap('novo', relX, relY, details.data, widgetsData, resW, resH)) {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Espaço ocupado! Mova para uma zona livre.")));
                          return;
                        }

                        _addNewWidget(details.data, relX, relY);
                        setState(() => _isMenuOpen = false);
                      },
                      builder: (context, candidateData, rejectedData) {
                        return Container(
                          key: _windowKey,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: candidateData.isNotEmpty ? Colors.green : Colors.blueAccent, width: 3),
                            boxShadow: [BoxShadow(color: Colors.blueAccent.withOpacity(0.2), blurRadius: 30, spreadRadius: 5)],
                          ),
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final double areaW = constraints.maxWidth;
                              final double areaH = constraints.maxHeight;
                              double scaleX = areaW / resW;
                              double scaleY = areaH / resH;

                              List<Widget> renderedWidgets = [];

                              widgetsData.forEach((widgetId, wData) {
                                String type = wData['type'];
                                double x = (wData['x'] ?? 0.5).toDouble();
                                double y = (wData['y'] ?? 0.5).toDouble();

                                // ATUALIZADO COM O CALENDÁRIO
                                double wWidth = type == 'clock' ? 250 : type == 'weather' ? 200 : type == 'calendar' ? 310 : 220;
                                double wHeight = type == 'gas' ? 80 : type == 'calendar' ? 250 : 120;

                                renderedWidgets.add(
                                  SmartDraggable(
                                    key: ValueKey(widgetId),
                                    initialX: x, initialY: y,
                                    areaW: areaW, areaH: areaH,
                                    widgetW: wWidth * scaleX, widgetH: wHeight * scaleY,
                                    child: _buildWidgetDesign(type, wData),
                                    onCheckOverlap: (nx, ny) => _hasOverlap(widgetId, nx, ny, type, widgetsData, resW, resH),
                                    onSave: (nx, ny) => _updateWidgetPosition(widgetId, nx, ny),
                                    onDelete: () => _deleteWidget(widgetId),
                                    onEdit: () => _openSettingsMenu(widgetId, type, wData),
                                  ),
                                );
                              });

                              return Stack(clipBehavior: Clip.none, children: renderedWidgets);
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

          Positioned(
            top: 20, left: 0, right: 0,
            child: Align(
              alignment: Alignment.topCenter,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
                height: 60,
                width: _isMenuOpen ? 300 : 60, // Ligeiramente mais largo para caber mais 1 ícone
                clipBehavior: Clip.hardEdge,
                decoration: BoxDecoration(
                  color: Colors.blueAccent,
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 10, offset: Offset(0, 5))],
                ),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  physics: const NeverScrollableScrollPhysics(),
                  child: SizedBox(
                    width: _isMenuOpen ? 300 : 60, height: 60,
                    child: Row(
                      mainAxisAlignment: _isMenuOpen ? MainAxisAlignment.spaceEvenly : MainAxisAlignment.center,
                      children: [
                        IconButton(
                          icon: Icon(_isMenuOpen ? Icons.close : Icons.add_circle_outline, color: Colors.white, size: 30),
                          onPressed: () => setState(() => _isMenuOpen = !_isMenuOpen),
                        ),
                        if (_isMenuOpen) ...[
                          _buildMenuDraggableIcon('clock', Icons.access_time),
                          _buildMenuDraggableIcon('weather', Icons.cloud),
                          _buildMenuDraggableIcon('gas', Icons.gas_meter),
                          _buildMenuDraggableIcon('calendar', Icons.calendar_month), // <--- ADICIONADO O CALENDÁRIO AQUI
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

  Widget _buildMenuDraggableIcon(String type, IconData icon) {
    return Draggable<String>(
      data: type,
      feedback: Icon(icon, color: Colors.white, size: 40),
      childWhenDragging: Icon(icon, color: Colors.white38, size: 30),
      child: Icon(icon, color: Colors.white, size: 30),
    );
  }

  Future<void> _addNewWidget(String type, double x, double y) async {
    String uniqueId = "${type}_${DateTime.now().millisecondsSinceEpoch}";
    Map<String, dynamic> newData = {'type': type, 'x': x, 'y': y};
    if (type == 'clock') newData['timezone'] = 'Local';
    if (type == 'weather') newData['location'] = 'Lisboa';
    if (type == 'calendar') newData['events'] = []; // Array vazio de início

    await FirebaseFirestore.instance.collection('windows').doc(widget.windowId).set({'widgets': {uniqueId: newData}}, SetOptions(merge: true));
  }

  Future<void> _updateWidgetPosition(String id, double x, double y) async {
    await FirebaseFirestore.instance.collection('windows').doc(widget.windowId).update({'widgets.$id.x': x, 'widgets.$id.y': y});
  }

  Future<void> _deleteWidget(String id) async {
    await FirebaseFirestore.instance.collection('windows').doc(widget.windowId).update({'widgets.$id': FieldValue.delete()});
    if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Widget removido!')));
  }

  Future<void> _updateWidgetSettings(String id, String field, String value) async {
    await FirebaseFirestore.instance.collection('windows').doc(widget.windowId).update({'widgets.$id.$field': value});
  }

  // ==========================================
  // MENU DE CONFIGURAÇÕES (Com Sincronização de Calendário)
  // ==========================================
  void _openSettingsMenu(String id, String type, Map<String, dynamic> wData) {
    if (type == 'gas') return;

    String selectedCity = wData['location'] ?? 'Lisboa, Portugal';
    TextEditingController searchController = TextEditingController();
    String selectedTimezoneKey = wData['timezone'] ?? 'Local';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return StatefulBuilder(builder: (context, setModalState) {

          List<MapEntry<String, String>> filteredList = _fusosHorariosMap.entries
              .where((entry) => entry.value.toLowerCase().contains(searchController.text.toLowerCase())).toList();

          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 20, right: 20, top: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    "Configurar ${type == 'clock' ? 'Relógio' : type == 'weather' ? 'Meteorologia' : 'Calendário'}",
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)
                ),
                const SizedBox(height: 20),

                // --- CONFIG RELÓGIO ---
                if (type == 'clock') ...[
                  TextField(
                    controller: searchController,
                    decoration: InputDecoration(hintText: "Pesquisar Fuso Horário...", prefixIcon: const Icon(Icons.search), border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))),
                    onChanged: (value) => setModalState(() {}),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    height: 200,
                    decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(10)),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: filteredList.length,
                      separatorBuilder: (context, index) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        String fusoKey = filteredList[index].key;
                        String fusoNomePT = filteredList[index].value;
                        bool isSelected = selectedTimezoneKey == fusoKey;

                        return ListTile(
                          title: Text(fusoNomePT, style: TextStyle(fontWeight: isSelected ? FontWeight.bold : FontWeight.normal, color: isSelected ? Colors.blueAccent : Colors.black87)),
                          trailing: isSelected ? const Icon(Icons.check, color: Colors.blueAccent) : null,
                          onTap: () => setModalState(() => selectedTimezoneKey = fusoKey),
                        );
                      },
                    ),
                  ),
                ],

                // --- CONFIG METEOROLOGIA ---
                if (type == 'weather') ...[
                  Autocomplete<String>(
                    initialValue: TextEditingValue(text: selectedCity),
                    optionsBuilder: (TextEditingValue textEditingValue) async {
                      selectedCity = textEditingValue.text;
                      if (textEditingValue.text.length < 3) return const Iterable<String>.empty();
                      try {
                        final url = Uri.parse('https://nominatim.openstreetmap.org/search?q=${textEditingValue.text}&format=json&limit=5&featuretype=settlement');
                        final response = await http.get(url, headers: {'User-Agent': 'VitraeViewApp'});
                        if (response.statusCode == 200) {
                          final List data = json.decode(response.body);
                          return data.map((item) {
                            String fullName = item['display_name'].toString();
                            List<String> parts = fullName.split(',');
                            if (parts.length > 1) return "${parts.first.trim()}, ${parts.last.trim()}";
                            return fullName;
                          }).toSet().toList();
                        }
                      } catch (e) {
                        debugPrint("Erro a procurar cidades: $e");
                      }
                      return const Iterable<String>.empty();
                    },
                    onSelected: (String selection) => selectedCity = selection,
                    fieldViewBuilder: (context, tEController, focusNode, onFieldSubmitted) {
                      return TextField(
                        controller: tEController,
                        focusNode: focusNode,
                        decoration: InputDecoration(
                            labelText: "Localidade",
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            prefixIcon: const Icon(Icons.location_city)
                        ),
                        onChanged: (val) => selectedCity = val,
                      );
                    },
                  ),
                ],

                // --- CONFIG CALENDÁRIO ---
                if (type == 'calendar') ...[
                  const Text("Para mostrar os próximos 7 dias do seu calendário na janela, é necessário autorizar a sincronização com a Google.", style: TextStyle(color: Colors.grey, fontSize: 14)),
                  const SizedBox(height: 20),
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(context); // Fecha o menu
                      _syncCalendarWithGoogle(id); // Aciona o login e a busca
                    },
                    icon: const Icon(Icons.sync),
                    label: const Text("Sincronizar Tarefas da Google"),
                    style: ElevatedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 50),
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black87,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: Colors.grey.shade300))
                    ),
                  )
                ],

                // Botão Guardar para Clima e Relógio
                if (type != 'calendar') ...[
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: () {
                      if (type == 'clock') _updateWidgetSettings(id, 'timezone', selectedTimezoneKey);
                      if (type == 'weather') _updateWidgetSettings(id, 'location', selectedCity);
                      Navigator.pop(context);
                    },
                    style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 50), backgroundColor: Colors.blueAccent, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                    child: const Text("GUARDAR"),
                  ),
                ],
                const SizedBox(height: 20),
              ],
            ),
          );
        });
      },
    );
  }

  Widget _buildWidgetDesign(String type, Map<String, dynamic> data) {
    if (type == 'clock') {
      String nomeApresentacao = _fusosHorariosMap[data['timezone']] ?? data['timezone'] ?? 'Local';
      return Container(
        decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(6)),
        alignment: Alignment.center,
        child: FittedBox(fit: BoxFit.scaleDown, child: Padding(padding: const EdgeInsets.all(4.0), child: Column(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.access_time, color: Colors.white, size: 24), const SizedBox(height: 2), Text(nomeApresentacao, style: const TextStyle(color: Colors.grey, fontSize: 10))]))),
      );
    } else if (type == 'weather') {
      return Container(
        decoration: BoxDecoration(color: Colors.blueAccent.shade700, borderRadius: BorderRadius.circular(6)),
        alignment: Alignment.center,
        child: FittedBox(fit: BoxFit.scaleDown, child: Padding(padding: const EdgeInsets.all(4.0), child: Column(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.cloud, color: Colors.white, size: 24), const SizedBox(height: 2), Text(data['location'] ?? 'Lisboa', style: const TextStyle(color: Colors.white, fontSize: 10))]))),
      );
    } else if (type == 'calendar') {
      return Container(
        decoration: BoxDecoration(color: Colors.deepPurple.shade700, borderRadius: BorderRadius.circular(6)),
        alignment: Alignment.center,
        child: const FittedBox(fit: BoxFit.scaleDown, child: Padding(padding: EdgeInsets.all(4.0), child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.calendar_month, color: Colors.white, size: 24), SizedBox(height: 2), Text("Calendário (Click p/ Sync)", style: TextStyle(color: Colors.white, fontSize: 10))]))),
      );
    } else {
      return Container(decoration: BoxDecoration(color: Colors.green, borderRadius: BorderRadius.circular(6)), alignment: Alignment.center, child: const FittedBox(fit: BoxFit.scaleDown, child: Padding(padding: EdgeInsets.all(4.0), child: Text("GÁS", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)))));
    }
  }
}

// ... Mantém a tua classe SmartDraggable intacta abaixo disto ...
class SmartDraggable extends StatefulWidget {
  final double initialX, initialY, areaW, areaH, widgetW, widgetH;
  final Widget child;
  final bool Function(double, double) onCheckOverlap;
  final Function(double, double) onSave;
  final VoidCallback onDelete, onEdit;

  const SmartDraggable({
    super.key, required this.initialX, required this.initialY, required this.areaW,
    required this.areaH, required this.widgetW, required this.widgetH, required this.child,
    required this.onCheckOverlap, required this.onSave, required this.onDelete, required this.onEdit,
  });

  @override
  State<SmartDraggable> createState() => _SmartDraggableState();
}

class _SmartDraggableState extends State<SmartDraggable> {
  late double currentX, currentY;
  bool isDragging = false;
  Offset? startPointer;
  late double startX, startY;

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

  bool _isMarkedForDeletion() {
    double relWidgetW = widget.widgetW / widget.areaW;
    double relWidgetH = widget.widgetH / widget.areaH;
    return currentX < -(0.70 * relWidgetW) || currentX > 1.0 - (0.30 * relWidgetW) ||
        currentY < -(0.70 * relWidgetH) || currentY > 1.0 - (0.30 * relWidgetH);
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: currentX * widget.areaW,
      top: currentY * widget.areaH,
      child: GestureDetector(
        onLongPress: widget.onEdit,
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
            currentX = (startX + (dx / widget.areaW)).clamp(-1.0, 2.0);
            currentY = (startY + (dy / widget.areaH)).clamp(-1.0, 2.0);
          });
        },
        onPanEnd: (_) {
          setState(() => isDragging = false);

          if (_isMarkedForDeletion()) {
            widget.onDelete();
            return;
          }

          bool maxLeft = currentX <= 1.0 - (widget.widgetW / widget.areaW);
          bool maxTop = currentY <= 1.0 - (widget.widgetH / widget.areaH);

          double snapX = currentX.clamp(0.0, 1.0 - (widget.widgetW / widget.areaW));
          double snapY = currentY.clamp(0.0, 1.0 - (widget.widgetH / widget.areaH));

          if (widget.onCheckOverlap(snapX, snapY)) {
            setState(() {
              currentX = widget.initialX;
              currentY = widget.initialY;
            });
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Colisão! Regressando à posição original.")));
          } else {
            setState(() {
              currentX = snapX;
              currentY = snapY;
            });
            widget.onSave(currentX, currentY);
          }
        },
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 150),
          opacity: _isMarkedForDeletion() ? 0.3 : 1.0,
          child: SizedBox(width: widget.widgetW, height: widget.widgetH, child: widget.child),
        ),
      ),
    );
  }
}