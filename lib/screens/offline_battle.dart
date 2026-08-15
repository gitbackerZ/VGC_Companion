import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_js/flutter_js.dart';

class OfflineBattleScreen extends StatefulWidget {
  const OfflineBattleScreen({super.key});

  @override
  State<OfflineBattleScreen> createState() => _OfflineBattleScreenState();
}

class _OfflineBattleScreenState extends State<OfflineBattleScreen> {
  JavascriptRuntime? _jsRuntime;
  Timer? _logTimer;
  bool _isLoading = true;
  final List<String> _rawLogs = [];
  
  Map<String, dynamic>? _currentRequest;
  int _p1Slot1Move = 1;
  int _p1Slot2Move = 1;

  @override
  void initState() {
    super.initState();
    _initEngine();
  }

  Future<void> _initEngine() async {
    try {
      final runtime = getJavascriptRuntime();
      final engineCode = await rootBundle.loadString('assets/engine.js');
      runtime.evaluate(engineCode);

      setState(() {
        _jsRuntime = runtime;
        _isLoading = false;
        _rawLogs.add('Engine initialized successfully.');
      });

      _startLogPolling();
    } catch (e) {
      setState(() {
        _isLoading = false;
        _rawLogs.add('Error initializing engine: $e');
      });
    }
  }

  void _startLogPolling() {
    _logTimer = Timer.periodic(const Duration(milliseconds: 300), (_) {
      _fetchLogs();
    });
  }

  void _fetchLogs() {
    if (_jsRuntime == null) return;
    try {
      final String rawJson = _jsRuntime!.evaluate("globalThis.getLogs();").stringResult;
      final List<dynamic> parsed = jsonDecode(rawJson);
      if (parsed.isNotEmpty) {
        setState(() {
          for (var chunk in parsed) {
            final lines = chunk.toString().split('\n');
            for (var line in lines) {
              if (line.startsWith('|request|')) {
                _parseRequest(line.substring(9));
              }
              _rawLogs.add(line.trim());
            }
          }
        });
      }
    } catch (e) {
      debugPrint('Error fetching logs: $e');
    }
  }

  void _parseRequest(String jsonString) {
    if (jsonString.isEmpty) return;
    try {
      final data = jsonDecode(jsonString);
      setState(() {
        _currentRequest = data;
      });
    } catch (e) {
      debugPrint('Error parsing request JSON: $e');
    }
  }

  void _startBattle() {
    if (_jsRuntime == null) return;
    _currentRequest = null;
    
    // Test VGC 2v2 Teams
    const p1Team = 'Incineroar||sitrusberry|intimidate|fakeout,flareblitz,knockoff,partingshot|Careful|252,0,156,0,100,0]Urshifu-Rapid-Strike||focussash|unseenfist|surgingstrikes,closecombat,aquajet,detect|Jolly|0,252,4,0,0,252';
    const p2Team = 'Flutter Mane||boosterenergy|protosynthesis|dazzlinggleam,shadowball,moonblast,protect|Timid|0,0,4,252,0,252]Ogerpon-Hearthflame||hearthflamemask|moldbreaker|ivycudgel,hornleech,spikyshield,followme|Jolly|0,252,4,0,0,252';

    _jsRuntime!.evaluate("globalThis.startVGCBattle('gen9vgc2024', '$p1Team', '$p2Team');");
  }

  void _sendTurnCommands() {
    if (_jsRuntime == null) return;

    // Send choices for both active Pokemon in doubles
    final p1Action = '>p1 move $_p1Slot1Move 1, move $_p1Slot2Move 1';
    const p2Action = '>p2 default'; // AI auto-choice for player 2

    _jsRuntime!.evaluate("globalThis.sendAction('$p1Action');");
    _jsRuntime!.evaluate("globalThis.sendAction('$p2Action');");

    setState(() {
      _currentRequest = null; // Clear decision request until next turn
    });
  }

  String _translateShowdownLog(String rawLine) {
    final parts = rawLine.split('|');
    if (parts.length < 2) return '';

    switch (parts[1]) {
      case 'turn':
        return 'Turn ${parts[2]}';
      case 'move':
        final attacker = parts[2].split(': ').last;
        final move = parts[3];
        final target = parts.length > 4 && parts[4].isNotEmpty 
            ? parts[4].split(': ').last 
            : null;
        return target != null 
            ? '$attacker used $move against $target.' 
            : '$attacker used $move.';
      case '-damage':
        final pokemon = parts[2].split(': ').last;
        final health = parts[3];
        return '$pokemon health is now at $health.';
      case 'faint':
        final pokemon = parts[2].split(': ').last;
        return '$pokemon fainted!';
      case 'switch':
        final pokemon = parts[2].split(': ').last;
        return 'Opponent sent out $pokemon.';
      default:
        return '';
    }
  }

  void _showBattleSummary(BuildContext context) {
    final List<String> readableLogs = _rawLogs
        .map((line) => _translateShowdownLog(line))
        .where((translated) => translated.isNotEmpty)
        .toList();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('Accessible Battle Summary'),
            actions: [
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
                tooltip: 'Close Summary',
              ),
            ],
          ),
          body: readableLogs.isEmpty
              ? const Center(child: Text('No battle events logged yet.'))
              : ListView.builder(
                  itemCount: readableLogs.length,
                  itemBuilder: (context, index) {
                    final log = readableLogs[index];
                    return Semantics(
                      container: true,
                      label: log,
                      child: ListTile(
                        title: Text(
                          log,
                          style: const TextStyle(fontSize: 16),
                        ),
                      ),
                    );
                  },
                ),
        );
      },
    );
  }

  List<dynamic> _getSlotMoves(int slotIndex) {
    if (_currentRequest == null || !_currentRequest!.containsKey('active')) return [];
    final activeList = _currentRequest!['active'] as List<dynamic>;
    if (slotIndex >= activeList.length) return [];
    return activeList[slotIndex]['moves'] ?? [];
  }

  @override
  void dispose() {
    _logTimer?.cancel();
    _jsRuntime?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final slot1Moves = _getSlotMoves(0);
    final slot2Moves = _getSlotMoves(1);
    final bool isTurnReady = _currentRequest != null && slot1Moves.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Offline Battle Simulator'),
        actions: [
          IconButton(
            icon: const Icon(Icons.description),
            tooltip: 'Open Accessible Battle Summary',
            onPressed: () => _showBattleSummary(context),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      Semantics(
                        button: true,
                        label: 'Start VGC Double Battle',
                        child: ElevatedButton(
                          onPressed: _startBattle,
                          child: const Text('Start Test Battle'),
                        ),
                      ),
                      Semantics(
                        button: true,
                        label: 'Review Accessible Battle Summary',
                        child: ElevatedButton.icon(
                          onPressed: () => _showBattleSummary(context),
                          icon: const Icon(Icons.subtitles),
                          label: const Text('Summary'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (isTurnReady) ...[
                    Card(
                      color: Colors.deepPurple.shade900,
                      child: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Column(
                          children: [
                            const Text('Choose Actions for Turn',
                                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                              children: [
                                Column(
                                  children: [
                                    const Text('Slot 1 Move', style: TextStyle(color: Colors.white70)),
                                    DropdownButton<int>(
                                      value: _p1Slot1Move,
                                      dropdownColor: Colors.grey[850],
                                      style: const TextStyle(color: Colors.white),
                                      items: List.generate(slot1Moves.length, (index) {
                                        return DropdownMenuItem(
                                          value: index + 1,
                                          child: Text(slot1Moves[index]['move']),
                                        );
                                      }),
                                      onChanged: (val) {
                                        if (val != null) setState(() => _p1Slot1Move = val);
                                      },
                                    ),
                                  ],
                                ),
                                if (slot2Moves.isNotEmpty)
                                  Column(
                                    children: [
                                      const Text('Slot 2 Move', style: TextStyle(color: Colors.white70)),
                                      DropdownButton<int>(
                                        value: _p1Slot2Move,
                                        dropdownColor: Colors.grey[850],
                                        style: const TextStyle(color: Colors.white),
                                        items: List.generate(slot2Moves.length, (index) {
                                          return DropdownMenuItem(
                                            value: index + 1,
                                            child: Text(slot2Moves[index]['move']),
                                          );
                                        }),
                                        onChanged: (val) {
                                          if (val != null) setState(() => _p1Slot2Move = val);
                                        },
                                      ),
                                    ],
                                  ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Semantics(
                              button: true,
                              label: 'Submit Selected Turn Actions',
                              child: ElevatedButton(
                                onPressed: _sendTurnCommands,
                                style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                                child: const Text('Submit Turn Actions'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  Expanded(
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey[900],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: ListView.builder(
                        itemCount: _rawLogs.length,
                        itemBuilder: (context, index) {
                          return Text(
                            '> ${_rawLogs[index]}',
                            style: const TextStyle(
                              color: Colors.greenAccent,
                              fontFamily: 'monospace',
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
