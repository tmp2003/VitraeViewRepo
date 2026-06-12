import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:google_sign_in/google_sign_in.dart';

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
    'Europe/London': 'Europa / Londres',
    'America/New_York': 'América / Nova Iorque',
    'Asia/Tokyo': 'Ásia / Tóquio',
  };

  bool _hasOverlap(String skipId, double testX, double testY, String testType, Map<String, dynamic> widgetsData, double resW, double resH) {
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

  Future<void> _syncCalendarWithGoogle(String widgetId) async {
    try {
      final GoogleSignIn googleSignIn = GoogleSignIn(
        scopes: ['https://www.googleapis.com/auth/calendar.readonly'],
        serverClientId: '555974802803-4na1f4nbj856kmqkfc2hv5808fc17kmk.apps.googleusercontent.com',
        forceCodeForRefreshToken: true,
      );

      // Limpa a cache para garantir que pede sempre a conta
      await googleSignIn.signOut();
      final account = await googleSignIn.signIn();
      if (account == null) return;

      final String? authCode = account.serverAuthCode;

      if (authCode != null) {
        FirebaseFirestore.instance.collection('windows').doc(widget.windowId).update({
          'widgets.$widgetId.google_auth_code': authCode
        });
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ Conta associada! A janela vai assumir as tarefas.')));
      }
    } catch (e) {
      debugPrint("Erro Sincronização Calendário: $e");
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('❌ Erro de Segurança do Google (Verifica a chave SHA-1)')));
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
                double resW = (data['resW'] is num) ? (data['resW'] as num).toDouble() : 1024.0;
                double resH = (data['resH'] is num) ? (data['resH'] as num).toDouble() : 600.0;
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

                        _addNewWidget(details.data, relX, relY, data);
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

                                // LÊ A ESCALA DA FIREBASE (Default 1.0 = 100%)
                                double scale = (wData['scale'] ?? 1.0).toDouble();

                                // APLICA A ESCALA AOS TAMANHOS ORIGINAIS
                                double wWidth = (type == 'clock' ? 250 : type == 'weather' ? 200 : type == 'calendar' ? 310 : 220) * scale;
                                double wHeight = (type == 'gas' ? 80 : type == 'calendar' ? 250 : 120) * scale;

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
                width: _isMenuOpen ? 300 : 60,
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
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        IconButton(
                          icon: Icon(_isMenuOpen ? Icons.close : Icons.add_circle_outline, color: Colors.white, size: 30),
                          onPressed: () => setState(() => _isMenuOpen = !_isMenuOpen),
                        ),
                        if (_isMenuOpen) ...[
                          _buildMenuDraggableIcon('clock', Icons.access_time),
                          _buildMenuDraggableIcon('weather', Icons.cloud),
                          _buildMenuDraggableIcon('gas', Icons.gas_meter),
                          _buildMenuDraggableIcon('calendar', Icons.calendar_month),
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

  Future<void> _addNewWidget(String type, double x, double y, Map<String, dynamic> docData) async {
    String uniqueId = "${type}_${DateTime.now().millisecondsSinceEpoch}";
    Map<String, dynamic> newData = {'type': type, 'x': x, 'y': y};

    if (type == 'clock') newData['timezone'] = 'Local';
    if (type == 'weather') newData['location'] = 'Lisboa';

    if (type == 'calendar') {
      newData['events'] = [];
      // HERDA AS PREFERÊNCIAS GLOBAIS SE ELAS EXISTIREM!
      if (docData.containsKey('calendar_prefs')) {
        var prefs = docData['calendar_prefs'];
        newData['bg_color'] = prefs['bg_color'] ?? '#1a1a1a';
        newData['title_color'] = prefs['title_color'] ?? '#ffffff';
        newData['time_color'] = prefs['time_color'] ?? '#3498db';
        newData['view_mode'] = prefs['view_mode'] ?? 'Semana';
        newData['scale'] = prefs['scale'] ?? 1.0;
      }
    }

    await FirebaseFirestore.instance.collection('windows').doc(widget.windowId).set({'widgets': {uniqueId: newData}}, SetOptions(merge: true));

    if (type == 'calendar') {
      Future.delayed(const Duration(milliseconds: 600), () => _syncCalendarWithGoogle(uniqueId));
    }
  }

  Future<void> _updateWidgetPosition(String id, double x, double y) async {
    await FirebaseFirestore.instance.collection('windows').doc(widget.windowId).update({'widgets.$id.x': x, 'widgets.$id.y': y});
  }

  Future<void> _deleteWidget(String id) async {
    await FirebaseFirestore.instance.collection('windows').doc(widget.windowId).update({'widgets.$id': FieldValue.delete()});
    if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Widget removido!')));
  }

  // ==========================================
  // MENU DE CONFIGURAÇÕES E PERSONALIZAÇÃO
  // ==========================================
  // ==========================================
  // MENU DE CONFIGURAÇÕES E PERSONALIZAÇÃO
  // ==========================================
  // ==========================================
  // MENU DE CONFIGURAÇÕES E PERSONALIZAÇÃO
  // ==========================================
  // ==========================================
  // MENU DE CONFIGURAÇÕES E PERSONALIZAÇÃO
  // ==========================================
  // ==========================================
  // MENU DE CONFIGURAÇÕES E PERSONALIZAÇÃO
  // ==========================================
  void _openSettingsMenu(String id, String type, Map<String, dynamic> wData) {
    if (type == 'gas') return;

    // --- 1. GUARDAR OS VALORES ORIGINAIS NA MEMÓRIA ---
    // (Para podermos reverter a janela caso o utilizador feche sem guardar)
    String originalViewMode = wData['view_mode'] ?? 'Semana';
    String originalBgColor = wData['bg_color'] ?? '#1a1a1a';
    String originalTitleColor = wData['title_color'] ?? '#ffffff';
    String originalTimeColor = wData['time_color'] ?? '#3498db';
    double originalScale = (wData['scale'] ?? 1.0).toDouble();

    // --- 2. VARIÁVEIS DE ESTADO DO MENU ---
    double widgetScale = originalScale;
    String calendarViewMode = originalViewMode;
    Color calendarBgColor = _hexToColor(originalBgColor);
    Color calendarTitleColor = _hexToColor(originalTitleColor);
    Color calendarTimeColor = _hexToColor(originalTimeColor);

    String selectedCity = wData['location'] ?? 'Lisboa, Portugal';
    TextEditingController searchController = TextEditingController();
    String selectedTimezoneKey = wData['timezone'] ?? 'Local';

    List<Color> colorPalette = [
      const Color(0xFF1a1a1a), const Color(0xFF2b2b2b), const Color(0xFF2c3e50),
      const Color(0xFF2980b9), const Color(0xFF8e44ad), const Color(0xFF27ae60),
      const Color(0xFFc0392b), const Color(0xFFf39c12), const Color(0xFFffffff),
      const Color(0xFFbdc3c7), const Color(0xFF3498db), const Color(0xFFe74c3c),
    ];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (context) {
        return StatefulBuilder(builder: (context, setModalState) {

          Widget _buildColorPicker(String title, Color currentColor, String firebaseField, Function(Color) onColorSelected) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 10, runSpacing: 10,
                  children: colorPalette.map((color) {
                    bool isSelected = currentColor.value == color.value;
                    return GestureDetector(
                      onTap: () {
                        setModalState(() => onColorSelected(color));
                        // ATUALIZAÇÃO EM TEMPO REAL NA JANELA (Live Preview)
                        String hexColor = '#${color.value.toRadixString(16).substring(2, 8)}';
                        FirebaseFirestore.instance.collection('windows').doc(widget.windowId).update({
                          'widgets.$id.$firebaseField': hexColor,
                        });
                      },
                      child: Container(
                        width: 35, height: 35,
                        decoration: BoxDecoration(
                          color: color, shape: BoxShape.circle,
                          border: Border.all(color: isSelected ? Colors.blueAccent : Colors.grey.shade300, width: isSelected ? 3 : 1),
                        ),
                        child: isSelected ? Icon(Icons.check, size: 20, color: color.computeLuminance() > 0.5 ? Colors.black : Colors.white) : null,
                      ),
                    );
                  }).toList(),
                ),
              ],
            );
          }

          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom + 20, left: 24, right: 24, top: 24),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          "Personalizar ${type == 'clock' ? 'Relógio' : type == 'weather' ? 'Meteorologia' : 'Calendário'}",
                          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                        ),
                      ),
                      IconButton(
                          icon: const Icon(Icons.close), padding: EdgeInsets.zero, constraints: const BoxConstraints(),
                          onPressed: () {
                            // SE CANCELAR NA CRUZ (X), REVERTE A JANELA PARA O ORIGINAL
                            if (type == 'calendar') {
                              FirebaseFirestore.instance.collection('windows').doc(widget.windowId).update({
                                'widgets.$id.view_mode': originalViewMode,
                                'widgets.$id.bg_color': originalBgColor,
                                'widgets.$id.title_color': originalTitleColor,
                                'widgets.$id.time_color': originalTimeColor,
                                'widgets.$id.scale': originalScale,
                              });
                            }
                            Navigator.pop(context);
                          }
                      ),
                    ],
                  ),
                  const Divider(height: 30),

                  if (type == 'weather') ...[
                    Autocomplete<String>(
                      initialValue: TextEditingValue(text: selectedCity),
                      optionsBuilder: (TextEditingValue textEditingValue) async {
                        selectedCity = textEditingValue.text;
                        if (textEditingValue.text.length < 3) return const Iterable<String>.empty();
                        try {
                          final res = await http.get(Uri.parse('https://nominatim.openstreetmap.org/search?q=${textEditingValue.text}&format=json&limit=5&featuretype=settlement'), headers: {'User-Agent': 'VitraeViewApp'});
                          if (res.statusCode == 200) {
                            final List data = json.decode(res.body);
                            return data.map((item) {
                              String fullName = item['display_name'].toString();
                              List<String> parts = fullName.split(',');
                              return parts.length > 1 ? "${parts.first.trim()}, ${parts.last.trim()}" : fullName;
                            }).toSet().toList();
                          }
                        } catch (_) {}
                        return const Iterable<String>.empty();
                      },
                      onSelected: (String selection) => selectedCity = selection,
                      fieldViewBuilder: (context, tEController, focusNode, onFieldSubmitted) {
                        return TextField(controller: tEController, focusNode: focusNode, decoration: InputDecoration(labelText: "Localidade", border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)), prefixIcon: const Icon(Icons.location_city)), onChanged: (val) => selectedCity = val);
                      },
                    ),
                  ],

                  if (type == 'clock') ...[
                    TextField(controller: searchController, decoration: InputDecoration(hintText: "Pesquisar Fuso Horário...", prefixIcon: const Icon(Icons.search), border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))), onChanged: (value) => setModalState(() {})),
                    const SizedBox(height: 10),
                    Container(
                      height: 200, decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(10)),
                      child: ListView.separated(
                        shrinkWrap: true, itemCount: _fusosHorariosMap.entries.where((entry) => entry.value.toLowerCase().contains(searchController.text.toLowerCase())).length, separatorBuilder: (context, index) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          var filteredList = _fusosHorariosMap.entries.where((entry) => entry.value.toLowerCase().contains(searchController.text.toLowerCase())).toList();
                          String fusoKey = filteredList[index].key;
                          bool isSelected = selectedTimezoneKey == fusoKey;
                          return ListTile(title: Text(filteredList[index].value, style: TextStyle(fontWeight: isSelected ? FontWeight.bold : FontWeight.normal, color: isSelected ? Colors.blueAccent : Colors.black87)), trailing: isSelected ? const Icon(Icons.check, color: Colors.blueAccent) : null, onTap: () => setModalState(() => selectedTimezoneKey = fusoKey));
                        },
                      ),
                    ),
                  ],

                  if (type == 'calendar') ...[
                    const Text("Modo de Apresentação", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    const SizedBox(height: 8),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'Dia', label: Text('Dia')),
                        ButtonSegment(value: 'Semana', label: Text('Semana')),
                        ButtonSegment(value: 'Mês', label: Text('Mês')),
                      ],
                      selected: {calendarViewMode},
                      onSelectionChanged: (Set<String> newSelection) {
                        setModalState(() => calendarViewMode = newSelection.first);
                        FirebaseFirestore.instance.collection('windows').doc(widget.windowId).update({
                          'widgets.$id.view_mode': newSelection.first,
                        });
                      },
                      style: ButtonStyle(
                        backgroundColor: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.selected) ? Colors.blueAccent : Colors.white),
                        foregroundColor: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.selected) ? Colors.white : Colors.black87),
                      ),
                    ),
                    const SizedBox(height: 25),

                    _buildColorPicker("Cor de Fundo da Janela", calendarBgColor, "bg_color", (c) => calendarBgColor = c),
                    const SizedBox(height: 20),
                    _buildColorPicker("Cor do Título da Tarefa", calendarTitleColor, "title_color", (c) => calendarTitleColor = c),
                    const SizedBox(height: 20),
                    _buildColorPicker("Cor das Horas (Badge)", calendarTimeColor, "time_color", (c) => calendarTimeColor = c),
                    const SizedBox(height: 25),

                    ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        _syncCalendarWithGoogle(id);
                      },
                      icon: const Icon(Icons.sync), label: const Text("Forçar Login Google"),
                      style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 45), backgroundColor: Colors.white, foregroundColor: Colors.black87, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: Colors.grey.shade300))),
                    )
                  ],

                  // --- SLIDER DE TAMANHO (ESCALA) ---
                  const Divider(height: 30),
                  const Text("Tamanho do Widget", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  Slider(
                    value: widgetScale.clamp(0.7, 1.5),
                    min: 0.7,
                    max: 1.5,
                    divisions: 8,
                    activeColor: Colors.blueAccent,
                    label: "${(widgetScale * 100).toInt()}%",
                    onChanged: (val) {
                      setModalState(() => widgetScale = val);
                      FirebaseFirestore.instance.collection('windows').doc(widget.windowId).update({
                        'widgets.$id.scale': val,
                      });
                    },
                  ),
                  const SizedBox(height: 20),

                  // BOTÃO GRAVAR GERAL
                  ElevatedButton(
                    onPressed: () {
                      if (type == 'clock') {
                        FirebaseFirestore.instance.collection('windows').doc(widget.windowId).update({'widgets.$id.timezone': selectedTimezoneKey});
                      }
                      if (type == 'weather') {
                        FirebaseFirestore.instance.collection('windows').doc(widget.windowId).update({'widgets.$id.location': selectedCity});
                      }
                      if (type == 'calendar') {
                        String hexBg = '#${calendarBgColor.value.toRadixString(16).substring(2, 8)}';
                        String hexTitle = '#${calendarTitleColor.value.toRadixString(16).substring(2, 8)}';
                        String hexTime = '#${calendarTimeColor.value.toRadixString(16).substring(2, 8)}';

                        FirebaseFirestore.instance.collection('windows').doc(widget.windowId).update({
                          'widgets.$id.view_mode': calendarViewMode,
                          'widgets.$id.bg_color': hexBg,
                          'widgets.$id.title_color': hexTitle,
                          'widgets.$id.time_color': hexTime,

                          // --- MAGIA: GRAVA ESTAS CORES GLOBALMENTE PARA FUTUROS CALENDÁRIOS ---
                          'calendar_prefs': {
                            'bg_color': hexBg,
                            'title_color': hexTitle,
                            'time_color': hexTime,
                            'view_mode': calendarViewMode,
                            'scale': widgetScale,
                          }
                        });
                      }
                      Navigator.pop(context);
                    },
                    style: ElevatedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 55), backgroundColor: Colors.blueAccent, foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))
                    ),
                    child: const Text("GUARDAR DEFINIÇÕES", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
          );
        });
      },
    );
  }

  // Função auxiliar para converter strings hex em Colors do Flutter
  Color _hexToColor(String code) {
    return Color(int.parse(code.substring(1, 7), radix: 16) + 0xFF000000);
  }

  Widget _buildWidgetDesign(String type, Map<String, dynamic> data) {
    if (type == 'clock') {
      return Container(
        decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(6)), alignment: Alignment.center,
        child: FittedBox(fit: BoxFit.scaleDown, child: Padding(padding: const EdgeInsets.all(4.0), child: Column(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.access_time, color: Colors.white, size: 24), const SizedBox(height: 2), Text(_fusosHorariosMap[data['timezone']] ?? data['timezone'] ?? 'Local', style: const TextStyle(color: Colors.grey, fontSize: 10))]))),
      );
    } else if (type == 'weather') {
      return Container(
        decoration: BoxDecoration(color: Colors.blueAccent.shade700, borderRadius: BorderRadius.circular(6)), alignment: Alignment.center,
        child: FittedBox(fit: BoxFit.scaleDown, child: Padding(padding: const EdgeInsets.all(4.0), child: Column(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.cloud, color: Colors.white, size: 24), const SizedBox(height: 2), Text(data['location'] ?? 'Lisboa', style: const TextStyle(color: Colors.white, fontSize: 10))]))),
      );
    } else if (type == 'calendar') {
      return Container(
        decoration: BoxDecoration(color: Colors.deepPurple.shade700, borderRadius: BorderRadius.circular(6)), alignment: Alignment.center,
        child: const FittedBox(fit: BoxFit.scaleDown, child: Padding(padding: EdgeInsets.all(4.0), child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.calendar_month, color: Colors.white, size: 24), SizedBox(height: 2), Text("Calendário Google", style: TextStyle(color: Colors.white, fontSize: 10))]))),
      );
    } else {
      return Container(decoration: BoxDecoration(color: Colors.green, borderRadius: BorderRadius.circular(6)), alignment: Alignment.center, child: const FittedBox(fit: BoxFit.scaleDown, child: Padding(padding: EdgeInsets.all(4.0), child: Text("GÁS", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)))));
    }
  }
}

// A LÓGICA DE ARRASTAR EXATA DO REPOSITÓRIO
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
      // MAGIA 1: Se aumentares a escala no menu e ele estiver encostado à direita,
      // o Flutter empurra-o automaticamente para dentro para não ser cortado!
      double maxAllowedX = 1.0 - (widget.widgetW / widget.areaW);
      double maxAllowedY = 1.0 - (widget.widgetH / widget.areaH);
      maxAllowedX = maxAllowedX < 0.0 ? 0.0 : maxAllowedX;
      maxAllowedY = maxAllowedY < 0.0 ? 0.0 : maxAllowedY;

      currentX = widget.initialX.clamp(0.0, maxAllowedX);
      currentY = widget.initialY.clamp(0.0, maxAllowedY);
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

          // MAGIA 2: Cálculo blindado das margens ao largar o widget arrastado
          double maxAllowedX = 1.0 - (widget.widgetW / widget.areaW);
          double maxAllowedY = 1.0 - (widget.widgetH / widget.areaH);

          // Previne limites matemáticos negativos que causam bugs no .clamp()
          maxAllowedX = maxAllowedX < 0.0 ? 0.0 : maxAllowedX;
          maxAllowedY = maxAllowedY < 0.0 ? 0.0 : maxAllowedY;

          double snapX = currentX.clamp(0.0, maxAllowedX);
          double snapY = currentY.clamp(0.0, maxAllowedY);

          if (widget.onCheckOverlap(snapX, snapY)) {
            setState(() {
              // Se colidir, volta para a posição inicial (também blindada)
              currentX = widget.initialX.clamp(0.0, maxAllowedX);
              currentY = widget.initialY.clamp(0.0, maxAllowedY);
            });
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Colisão!")));
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