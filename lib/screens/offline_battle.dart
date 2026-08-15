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
            _rawLogs.add(chunk.toString().trim());
          }
        });
      }
    } catch (e) {
      debugPrint('Error fetching logs: $e');
    }
  }

  void _startBattle() {
    if (_jsRuntime == null) return;
    const p1Team = 'Incineroar||sitrusberry|intimidate|fakeout,flareblitz,knockoff,partingshot|Careful|252,0,156,0,100,0';
    const p2Team = 'Flutter Mane||boosterenergy|protosynthesis|dazzlinggleam,shadowball,moonblast,protect|Timid|0,0,4,252,0,252';

    _jsRuntime!.evaluate("globalThis.startVGCBattle('gen9vgc2024', '$p1Team', '$p2Team');");
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
        .expand((chunk) => chunk.split('\n'))
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

  @override
  void dispose() {
    _logTimer?.cancel();
    _jsRuntime?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
                  const SizedBox(height: 16),
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
