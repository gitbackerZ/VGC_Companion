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
  bool _isLoading = true;
  final List<String> _logs = [];

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
        _logs.add('Engine initialized successfully.');
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _logs.add('Error initializing engine: $e');
      });
    }
  }

  void _fetchLogs() {
    if (_jsRuntime == null) return;
    try {
      final rawJson = _jsRuntime!.evaluate("globalThis.getLogs();").stringResult;
      final List<dynamic> parsed = jsonDecode(rawJson);
      if (parsed.isNotEmpty) {
        setState(() {
          for (var chunk in parsed) {
            _logs.add(chunk.toString().trim());
          }
        });
      }
    } catch (e) {
      // Handle parse error if engine returns non-array string
    }
  }

  void _startBattle() {
    if (_jsRuntime == null) return;
    const p1Team = 'Incineroar||sitrusberry|intimidate|fakeout,flareblitz,knockoff,partingshot|Careful|252,0,156,0,100,0';
    const p2Team = 'Flutter Mane||boosterenergy|protosynthesis|dazzlinggleam,shadowball,moonblast,protect|Timid|0,0,4,252,0,252';

    _jsRuntime!.evaluate("globalThis.startVGCBattle('gen9vgc2024', '$p1Team', '$p2Team');");
    
    // Retrieve logs shortly after sending start stream
    Future.delayed(const Duration(milliseconds: 300), _fetchLogs);
  }

  @override
  void dispose() {
    _jsRuntime?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Offline Battle Simulator')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  Semantics(
                    button: true,
                    label: 'Start VGC Double Battle',
                    child: ElevatedButton(
                      onPressed: _startBattle,
                      child: const Text('Start Test Battle'),
                    ),
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
                        itemCount: _logs.length,
                        itemBuilder: (context, index) {
                          return Text(
                            '> ${_logs[index]}',
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