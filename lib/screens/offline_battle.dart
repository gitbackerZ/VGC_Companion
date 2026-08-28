import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_js/flutter_js.dart';
import '../services/team_text_codec.dart';

enum BattleStage { setup, teamPreview, inBattle, ended }

class OfflineBattleScreen extends StatefulWidget {
  const OfflineBattleScreen({super.key});

  @override
  State<OfflineBattleScreen> createState() => _OfflineBattleScreenState();
}

class _OfflineBattleScreenState extends State<OfflineBattleScreen> {
  JavascriptRuntime? _jsRuntime;
  Timer? _logTimer;
  bool _isLoading = true;
  BattleStage _stage = BattleStage.setup;

  final List<String> _rawLogs = [];
  Map<String, dynamic>? _currentRequest;

  final TextEditingController _p1TeamController = TextEditingController();
  final TextEditingController _p2TeamController = TextEditingController();

  // Team Preview
  List<dynamic> _p1TeamList = [];
  List<dynamic> _p2TeamList = [];
  final List<int> _selectedPreviewSlots = [];

  // Active State Tracker
  final Map<String, String> _activeHp = {};
  final Map<String, String> _activeNames = {};

  // Slot 1 Action State
  bool _s1IsSwitch = false;
  int _s1MoveChoice = 1;
  int _s1Target = 1;
  int _s1SwitchChoice = 1;
  bool _s1Mega = false;

  // Slot 2 Action State
  bool _s2IsSwitch = false;
  int _s2MoveChoice = 1;
  int _s2Target = 1;
  int _s2SwitchChoice = 1;
  bool _s2Mega = false;

  String _statusMessage = 'Engine initializing...';

  static const String _defaultP1Team = '''
Raichu @ Raichunite X
Ability: Static
Level: 50
Gender: F
EVs: 252 Atk / 252 SpA / 4 Spe
Hardy Nature
- Fake Out
- Rising Voltage
- Volt Tackle
- Volt Switch

Bellibolt @ Sitrus Berry
Ability: Electromorphosis
Level: 50
Gender: M
EVs: 252 Def / 4 SpA / 252 SpD
Bold Nature
- Soak
- Light Screen
- Thunder
- Parabolic Charge

Pelipper @ Damp Rock
Ability: Drizzle
Level: 50
Gender: M
EVs: 252 HP / 252 Def / 4 SpD
Bold Nature
- Hurricane
- Tailwind
- Soak
- Wide Guard

Archaludon @ Light Clay
Ability: Stamina
Level: 50
Gender: M
EVs: 252 HP / 252 SpA / 4 Spe
Modest Nature
- Dragon Pulse
- Body Press
- Electro Shot
- Steel Beam

Basculegion @ Life Orb
Ability: Swift Swim
Level: 50
Gender: M
EVs: 4 HP / 252 Atk / 252 Spe
Jolly Nature
- Wave Crash
- Last Respects
- Soak
- Protect

Whimsicott @ Focus Sash
Ability: Prankster
Level: 50
Gender: M
EVs: 252 SpA / 4 SpD / 252 Spe
Modest Nature
- Tailwind
- Worry Seed
- Beat Up
- Energy Ball''';

  static const String _defaultP2Team = '''
Miraidon @ Choice Specs
Ability: Hadron Engine
Level: 50
EVs: 252 SpA / 4 SpD / 252 Spe
Timid Nature
- Electro Drift
- Draco Meteor
- Volt Switch
- Dazzling Gleam

Iron Bundle @ Booster Energy
Ability: Quark Drive
Level: 50
EVs: 252 SpA / 4 SpD / 252 Spe
Timid Nature
- Freeze-Dry
- Hydro Pump
- Icy Wind
- Protect

Ogerpon-Hearthflame @ Hearthflame Mask
Ability: Mold Breaker
Level: 50
Gender: F
EVs: 252 Atk / 4 Def / 252 Spe
Jolly Nature
- Ivy Cudgel
- Horn Leech
- Spiky Shield
- Follow Me

Flutter Mane @ Focus Sash
Ability: Protosynthesis
Level: 50
EVs: 252 SpA / 4 SpD / 252 Spe
Timid Nature
- Moonblast
- Shadow Ball
- Dazzling Gleam
- Protect''';

  @override
  void initState() {
    super.initState();
    _p1TeamController.text = _defaultP1Team;
    _p2TeamController.text = _defaultP2Team;
    _initEngine();
  }

  Future<void> _initEngine() async {
    try {
      final runtime = getJavascriptRuntime();

      const String envPolyfill = '''
        var global = globalThis;
        var window = globalThis;
        var exports = globalThis;
        var module = { exports: globalThis };
        var process = { env: { NODE_ENV: 'production' }, argv: [], cwd: function() { return '/'; } };
      ''';
      runtime.evaluate(envPolyfill);

      final engineCode = await rootBundle.loadString('assets/engine.js');
      final engineResult = runtime.evaluate(engineCode);
      if (engineResult.isError) {
        throw Exception('Engine JS Evaluation Failed: ${engineResult.stringResult}');
      }

      try {
        final dexJs = await rootBundle.loadString('assets/js/dex.js');
        runtime.evaluate(dexJs);
      } catch (e) {
        debugPrint('dex.js asset load warning: $e');
      }

      try {
        final learnsetsJson = await rootBundle.loadString('assets/js/learnsets.json');
        runtime.evaluate('if (typeof Dex !== "undefined") { Dex.data = Dex.data || {}; Dex.data.Learnsets = $learnsetsJson; }');
      } catch (e) {
        debugPrint('learnsets.json asset load warning: $e');
      }

      const String jsPatchCode = '''
        globalThis.logBuffer = [];

        globalThis.getBattleConstructor = function() {
          if (globalThis.Battle) return globalThis.Battle;
          if (globalThis.Sim && globalThis.Sim.Battle) return globalThis.Sim.Battle;
          if (globalThis.Dex && globalThis.Dex.Battle) return globalThis.Dex.Battle;
          if (typeof module !== 'undefined' && module.exports) {
            if (module.exports.Battle) return module.exports.Battle;
            if (module.exports.Sim && module.exports.Sim.Battle) return module.exports.Sim.Battle;
          }
          if (typeof exports !== 'undefined' && exports.Battle) return exports.Battle;
          return null;
        };

        globalThis.getDexObject = function() {
          if (globalThis.Dex) return globalThis.Dex;
          if (globalThis.Sim && globalThis.Sim.Dex) return globalThis.Sim.Dex;
          if (typeof module !== 'undefined' && module.exports && module.exports.Dex) return module.exports.Dex;
          if (globalThis.PokemonShowdown && globalThis.PokemonShowdown.Dex) return globalThis.PokemonShowdown.Dex;
          return null;
        };

        globalThis.ensureCustomDexEntries = function(targetDex) {
          const dex = targetDex || globalThis.getDexObject();
          if (!dex) return;
          
          dex.data = dex.data || {};
          dex.data.Items = dex.data.Items || {};
          dex.data.Pokedex = dex.data.Pokedex || {};

          // 1. Register Item
          dex.data.Items['raichunitex'] = {
            name: "Raichunite X",
            spritenum: 608,
            megaStone: "Raichu-Mega-X",
            megaEvolves: "Raichu",
            itemUser: ["Raichu"],
            onTakeItem: function(item, pokemon, source) {
              if ((source && source.baseSpecies.baseSpecies === 'Raichu') || pokemon.baseSpecies.baseSpecies === 'Raichu') {
                return false;
              }
              return true;
            },
            num: -1001,
            gen: 9,
            exists: true,
            isNonstandard: null
          };

          // 2. Register Form Species
          dex.data.Pokedex['raichumegax'] = {
            num: 26,
            name: "Raichu-Mega-X",
            baseSpecies: "Raichu",
            forme: "Mega-X",
            isMega: true,
            types: ["Electric", "Fighting"],
            baseStats: { hp: 60, atk: 120, def: 75, spa: 110, spd: 80, spe: 125 },
            abilities: { 0: "Lightning Rod" },
            heightm: 0.8,
            weightkg: 30.0,
            eggGroups: ["Field", "Fairy"],
            requiredItem: "Raichunite X",
            exists: true
          };

          // 3. Link form back to base species formes list
          if (dex.species && typeof dex.species.get === 'function') {
            var base = dex.species.get('raichu');
            if (base && base.exists) {
              base.otherFormes = base.otherFormes || [];
              if (base.otherFormes.indexOf('Raichu-Mega-X') === -1) {
                base.otherFormes.push('Raichu-Mega-X');
              }
            }
          }

          // 4. Clear internal lookup caches so fresh objects are loaded
          if (dex.items && dex.items.cache) {
            if (typeof dex.items.cache.clear === 'function') {
              dex.items.cache.clear();
            } else if (typeof dex.items.cache.delete === 'function') {
              dex.items.cache.delete('raichunitex');
            }
          }
          if (dex.species && dex.species.cache) {
            if (typeof dex.species.cache.clear === 'function') {
              dex.species.cache.clear();
            } else if (typeof dex.species.cache.delete === 'function') {
              dex.species.cache.delete('raichumegax');
              dex.species.cache.delete('raichu');
            }
          }
        };

        globalThis.getLogs = function() {
          const logs = JSON.stringify(globalThis.logBuffer);
          globalThis.logBuffer = [];
          return logs;
        };

        globalThis.sendAction = function(action) {
          if (!globalThis.battle) return;
          try {
            globalThis.battle.choose(action);
          } catch (err) {
            globalThis.logBuffer.push('|error| Action Exception: ' + (err.stack || err.message));
          }
        };

        globalThis.startVGCBattle = function(formatId, p1RawText, p2RawText) {
          globalThis.logBuffer = [];
          try {
            const dex = globalThis.getDexObject();
            if (globalThis.ensureCustomDexEntries) {
              globalThis.ensureCustomDexEntries(dex);
            }

            // Parse teams natively inside JS to preserve custom items/formats
            const p1Team = (dex && dex.teams && typeof dex.teams.import === 'function') 
              ? dex.teams.import(p1RawText) 
              : p1RawText;
              
            const p2Team = (dex && dex.teams && typeof dex.teams.import === 'function') 
              ? dex.teams.import(p2RawText) 
              : p2RawText;

            const targetFormat = formatId || 'gen9doublescustomgame';
            const BattleConstructor = globalThis.getBattleConstructor();

            if (!BattleConstructor) {
              throw new Error('Battle constructor not found on global scope.');
            }

            globalThis.battle = new BattleConstructor({
              formatid: targetFormat,
              p1: { name: 'Player 1', team: p1Team },
              p2: { name: 'Computer AI', team: p2Team },
              send: function(type, data) {
                if (Array.isArray(data)) {
                  globalThis.logBuffer.push(data.join('\\n'));
                } else if (data) {
                  globalThis.logBuffer.push(data);
                }
              }
            });

            if (globalThis.battle.dex) {
              globalThis.ensureCustomDexEntries(globalThis.battle.dex);
            }

            globalThis.battle.start();
          } catch (err) {
            globalThis.logBuffer.push('|error| Engine Crash: ' + (err.stack || err.message));
          }
        };
      ''';

      final patchResult = runtime.evaluate(jsPatchCode);
      if (patchResult.isError) {
        throw Exception('JS Patch Injection Failed: ${patchResult.stringResult}');
      }

      setState(() {
        _jsRuntime = runtime;
        _isLoading = false;
        _statusMessage = 'Engine & Custom Dex ready. Gen 9 Custom Doubles Active.';
      });
      _announce('Engine initialized successfully with custom Dex support.');
      _startLogPolling();
    } catch (e) {
      setState(() {
        _isLoading = false;
        _statusMessage = 'Error initializing engine: $e';
      });
    }
  }

  void _announce(String message) {
    if (message.isEmpty) return;
    SemanticsService.announce(message, TextDirection.ltr);
  }

  void _startLogPolling() {
    _logTimer = Timer.periodic(const Duration(milliseconds: 250), (_) => _fetchLogs());
  }

  void _fetchLogs() {
    if (_jsRuntime == null) return;
    try {
      final JsEvalResult result = _jsRuntime!.evaluate("globalThis.getLogs();");
      if (result.isError) {
        debugPrint("JS Error: ${result.stringResult}");
        return;
      }
      final String rawJson = result.stringResult;
      final List<dynamic> parsed = jsonDecode(rawJson);
      if (parsed.isNotEmpty) {
        setState(() {
          for (var chunk in parsed) {
            for (var line in chunk.toString().split('\n')) {
              final trimmed = line.trim();
              if (trimmed.isEmpty) continue;
              _processProtocolLine(trimmed);
              _rawLogs.add(trimmed);
            }
          }
        });
      }
    } catch (e) {
      debugPrint('Error fetching logs: $e');
    }
  }

  void _processProtocolLine(String line) {
    if (line.startsWith('|error|')) {
      setState(() {
        _statusMessage = line.substring(7);
      });
      _announce('Engine Error: $_statusMessage');
      return;
    }

    if (line.startsWith('|request|')) {
      _parseRequest(line.substring(9));
      return;
    }

    final parts = line.split('|');
    if (parts.length < 3) return;

    switch (parts[1]) {
      case 'poke':
        if (parts[2] == 'p2') {
          final p2Mon = parts[3].split(',')[0];
          if (!_p2TeamList.contains(p2Mon)) _p2TeamList.add(p2Mon);
        }
        break;
      case 'switch':
      case 'drag':
        final slot = parts[2].split(':').first;
        final name = parts[2].split(': ').last;
        final hp = parts.length > 4 ? parts[4] : '';
        _activeNames[slot] = name;
        _activeHp[slot] = hp;
        _announce('$name entered battle on $slot.');
        break;
      case '-mega':
        final pokemon = parts[2].split(': ').last;
        final megaStone = parts[3];
        _announce('$pokemon Mega Evolved into $megaStone!');
        break;
      case '-damage':
        final slot = parts[2].split(':').first;
        final name = parts[2].split(': ').last;
        if (parts.length > 3) _activeHp[slot] = parts[3];
        _announce('$name took damage. Health is now ${parts[3]}.');
        break;
      case 'faint':
        final slot = parts[2].split(':').first;
        final name = parts[2].split(': ').last;
        _activeHp[slot] = '0/100';
        _announce('$name fainted!');
        break;
      case 'win':
        final winner = parts[2];
        _announce('Battle finished! Winner is $winner.');
        setState(() {
          _stage = BattleStage.ended;
          _statusMessage = 'Battle ended! Winner: $winner';
        });
        break;
    }
  }

  void _parseRequest(String jsonString) {
    if (jsonString.isEmpty) return;
    try {
      final data = jsonDecode(jsonString);
      setState(() {
        _currentRequest = data;

        if (data.containsKey('teamPreview') && data['teamPreview'] == true) {
          _stage = BattleStage.teamPreview;
          _p1TeamList = data['side']['pokemon'] ?? [];
          _selectedPreviewSlots.clear();
          _statusMessage = 'Team preview active. Choose 4 Pokémon.';
          _announce('Team preview started. Select 4 Pokémon for your battle lineup.');
        } else {
          _stage = BattleStage.inBattle;
          _s1IsSwitch = false;
          _s2IsSwitch = false;
          _s1Mega = false;
          _s2Mega = false;
          _s1MoveChoice = 1;
          _s2MoveChoice = 1;
          _statusMessage = 'Waiting for player actions...';
          _announce('New turn requested. Select moves, switches, or Mega Evolutions.');
        }
      });
    } catch (e) {
      debugPrint('Error parsing request JSON: $e');
    }
  }

  String _formatTeamSheet(String rawText) {
    try {
      return TeamTextCodec.toPackedFormat(rawText);
    } catch (_) {
      return rawText;
    }
  }

  void _startMatch() {
    if (_jsRuntime == null) return;
    setState(() {
      _rawLogs.clear();
      _p2TeamList.clear();
      _activeHp.clear();
      _activeNames.clear();
      _statusMessage = 'Starting Gen 9 Custom Double Battle...';
    });
    _announce('Starting Gen 9 Custom Double Battle.');

    final p1Raw = jsonEncode(_p1TeamController.text.trim());
    final p2Raw = jsonEncode(_p2TeamController.text.trim());

    final JsEvalResult result = _jsRuntime!.evaluate(
      "globalThis.startVGCBattle('gen9doublescustomgame', $p1Raw, $p2Raw);"
    );

    if (result.isError) {
      setState(() {
        _statusMessage = 'JS Evaluation Error: ${result.stringResult}';
      });
      _announce('Failed to start battle.');
    }
  }

  void _confirmTeamPreviewSelection() {
    if (_selectedPreviewSlots.length != 4 || _jsRuntime == null) return;
    final teamOrder = _selectedPreviewSlots.join('');
    _jsRuntime!.evaluate("globalThis.sendAction('>p1 team $teamOrder');");
    _jsRuntime!.evaluate("globalThis.sendAction('>p2 team 1234');");
    _announce('Submitted team selection. Entering battle turn 1.');
  }

  void _sendTurnCommands() {
    if (_jsRuntime == null || _currentRequest == null) return;

    final isForceSwitch = _currentRequest!.containsKey('forceSwitch');
    String p1Action = '>p1 ';

    if (isForceSwitch) {
      final forceList = _currentRequest!['forceSwitch'] as List<dynamic>;
      List<String> switchActions = [];
      for (int i = 0; i < forceList.length; i++) {
        if (forceList[i] == true) {
          final choice = (i == 0) ? _s1SwitchChoice : _s2SwitchChoice;
          switchActions.add('switch $choice');
        } else {
          switchActions.add('pass');
        }
      }
      p1Action += switchActions.join(', ');
    } else {
      List<String> slotActions = [];

      if (_s1IsSwitch) {
        slotActions.add('switch $_s1SwitchChoice');
      } else {
        String act = 'move $_s1MoveChoice $_s1Target';
        if (_s1Mega) act += ' mega';
        slotActions.add(act);
      }

      final activeList = _currentRequest!['active'] as List<dynamic>? ?? [];
      if (activeList.length > 1) {
        if (_s2IsSwitch) {
          slotActions.add('switch $_s2SwitchChoice');
        } else {
          String act = 'move $_s2MoveChoice $_s2Target';
          if (_s2Mega) act += ' mega';
          slotActions.add(act);
        }
      }
      p1Action += slotActions.join(', ');
    }

    _jsRuntime!.evaluate("globalThis.sendAction('$p1Action');");
    _jsRuntime!.evaluate("globalThis.sendAction('>p2 default');");

    _announce('Player actions submitted. Computer opponent executing turn.');
    setState(() => _currentRequest = null);
  }

  List<dynamic> _getAvailableSwitches() {
    if (_currentRequest == null || !_currentRequest!.containsKey('side')) return [];
    final pokemonList = _currentRequest!['side']['pokemon'] as List<dynamic>;
    List<Map<String, dynamic>> choices = [];
    for (int i = 0; i < pokemonList.length; i++) {
      final p = pokemonList[i];
      if (!(p['active'] ?? false) && !p['condition'].toString().startsWith('0')) {
        choices.add({
          'slot': i + 1,
          'name': p['details'].toString().split(',')[0],
          'condition': p['condition'],
        });
      }
    }
    return choices;
  }

  @override
  void dispose() {
    _logTimer?.cancel();
    _jsRuntime?.dispose();
    _p1TeamController.dispose();
    _p2TeamController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gen 9 PvC Double Battle'),
        actions: [
          if (_stage != BattleStage.setup)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'New Battle Setup',
              onPressed: () => setState(() => _stage = BattleStage.setup),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(12),
                    child: _buildStageContent(),
                  ),
                ),
                _buildLiveTerminal(),
                _buildStatusBar(),
              ],
            ),
    );
  }

  Widget _buildStageContent() {
    switch (_stage) {
      case BattleStage.setup:
        return _buildSetupStage();
      case BattleStage.teamPreview:
        return _buildTeamPreviewStage();
      case BattleStage.inBattle:
      case BattleStage.ended:
        return _buildInBattleStage();
    }
  }

  Widget _buildSetupStage() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: const Text('Setup PvC Gen 9 Teams', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ),
        const SizedBox(height: 12),
        const Text('Player 1 Team (Human)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.blueAccent)),
        const SizedBox(height: 4),
        Semantics(
          label: 'Player 1 Human Team Input Text Area',
          hint: 'Paste standard Pokémon Showdown export or packed team text for your team',
          child: TextField(
            controller: _p1TeamController,
            maxLines: 5,
            style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
            decoration: const InputDecoration(
              labelText: 'Player 1 Team Sheet',
              hintText: 'Paste standard Showdown team sheet here...',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        const SizedBox(height: 16),
        const Text('Player 2 Team (Computer AI)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.redAccent)),
        const SizedBox(height: 4),
        Semantics(
          label: 'Player 2 Computer AI Team Input Text Area',
          hint: 'Paste standard Pokémon Showdown export or packed team text for the computer opponent',
          child: TextField(
            controller: _p2TeamController,
            maxLines: 5,
            style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
            decoration: const InputDecoration(
              labelText: 'Computer Team Sheet',
              hintText: 'Paste standard Showdown team sheet here...',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Semantics(
          button: true,
          label: 'Start Player versus Computer Battle',
          hint: 'Begins team preview for player vs computer battle',
          child: SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              onPressed: _startMatch,
              style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurple),
              icon: const Icon(Icons.play_arrow, color: Colors.white),
              label: const Text('Start PvC Battle', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTeamPreviewStage() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: const Text('Team Preview (Choose 4)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ),
        const SizedBox(height: 8),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, childAspectRatio: 2.8, crossAxisSpacing: 8, mainAxisSpacing: 8),
          itemCount: _p1TeamList.length,
          itemBuilder: (context, index) {
            final slotIndex = index + 1;
            final monName = _p1TeamList[index]['details'].toString().split(',')[0];
            final selectedPos = _selectedPreviewSlots.indexOf(slotIndex);
            final String posText = selectedPos == -1
                ? 'Not selected'
                : (selectedPos < 2 ? 'Lead Position ${selectedPos + 1}' : 'Back Position ${selectedPos - 1}');

            return Semantics(
              button: true,
              label: '$monName. Status: $posText.',
              hint: 'Double tap to toggle selection for line-up.',
              child: InkWell(
                onTap: () {
                  setState(() {
                    if (selectedPos != -1) {
                      _selectedPreviewSlots.removeAt(selectedPos);
                    } else if (_selectedPreviewSlots.length < 4) {
                      _selectedPreviewSlots.add(slotIndex);
                    }
                  });
                },
                child: Container(
                  decoration: BoxDecoration(
                    color: selectedPos != -1 ? Colors.blue.withOpacity(0.3) : Colors.grey[850],
                    border: Border.all(color: selectedPos != -1 ? Colors.blue : Colors.grey),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  padding: const EdgeInsets.all(6),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(monName, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      if (selectedPos != -1) Text(posText, style: const TextStyle(fontSize: 10, color: Colors.amberAccent)),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 12),
        Semantics(
          button: true,
          enabled: _selectedPreviewSlots.length == 4,
          label: 'Confirm Lineup Selection',
          hint: 'Submits selected Pokémon and starts battle turn 1',
          child: SizedBox(
            width: double.infinity,
            height: 44,
            child: ElevatedButton(
              onPressed: _selectedPreviewSlots.length == 4 ? _confirmTeamPreviewSelection : null,
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green[700]),
              child: Text('Confirm Selection (${_selectedPreviewSlots.length}/4)'),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInBattleStage() {
    final activeList = (_currentRequest != null && _currentRequest!.containsKey('active')) ? _currentRequest!['active'] as List<dynamic> : [];
    final movesSlot1 = activeList.isNotEmpty ? (activeList[0]['moves'] as List<dynamic>? ?? []) : [];
    final movesSlot2 = activeList.length > 1 ? (activeList[1]['moves'] as List<dynamic>? ?? []) : [];
    final availableSwitches = _getAvailableSwitches();
    final isForceSwitch = _currentRequest != null && _currentRequest!.containsKey('forceSwitch');

    return Column(
      children: [
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              children: [
                _buildActiveSlotRow('Computer', ['p2a', 'p2b'], Colors.redAccent),
                const Divider(height: 10),
                _buildActiveSlotRow('Player', ['p1a', 'p1b'], Colors.blueAccent),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),

        if (_stage == BattleStage.inBattle && _currentRequest != null) ...[
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Semantics(
                    header: true,
                    child: Text(
                      isForceSwitch ? 'Select Replacement Pokémon' : 'Select Player Turn Actions',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ),
                  const SizedBox(height: 6),
                  _buildSlotActionControl(
                    slotTitle: 'Slot 1 (${_activeNames['p1a'] ?? 'Active 1'})',
                    moves: movesSlot1,
                    switches: availableSwitches,
                    isForceSwitch: isForceSwitch,
                    isSwitch: _s1IsSwitch,
                    selectedMove: _s1MoveChoice,
                    selectedTarget: _s1Target,
                    selectedSwitch: _s1SwitchChoice,
                    isMega: _s1Mega,
                    canMega: activeList.isNotEmpty && (activeList[0]['canMegaEvolve'] == true),
                    onToggleSwitch: (v) => setState(() => _s1IsSwitch = v),
                    onMoveChanged: (v) => setState(() => _s1MoveChoice = v!),
                    onTargetChanged: (v) => setState(() => _s1Target = v!),
                    onSwitchChanged: (v) => setState(() => _s1SwitchChoice = v!),
                    onMegaToggled: (v) => setState(() => _s1Mega = v!),
                  ),
                  if (!isForceSwitch && movesSlot2.isNotEmpty) ...[
                    const Divider(height: 16),
                    _buildSlotActionControl(
                      slotTitle: 'Slot 2 (${_activeNames['p1b'] ?? 'Active 2'})',
                      moves: movesSlot2,
                      switches: availableSwitches,
                      isForceSwitch: isForceSwitch,
                      isSwitch: _s2IsSwitch,
                      selectedMove: _s2MoveChoice,
                      selectedTarget: _s2Target,
                      selectedSwitch: _s2SwitchChoice,
                      isMega: _s2Mega,
                      canMega: activeList.length > 1 && (activeList[1]['canMegaEvolve'] == true),
                      onToggleSwitch: (v) => setState(() => _s2IsSwitch = v),
                      onMoveChanged: (v) => setState(() => _s2MoveChoice = v!),
                      onTargetChanged: (v) => setState(() => _s2Target = v!),
                      onSwitchChanged: (v) => setState(() => _s2SwitchChoice = v!),
                      onMegaToggled: (v) => setState(() => _s2Mega = v!),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Semantics(
                    button: true,
                    label: 'Submit Player Actions to Engine',
                    hint: 'Locks in player actions and triggers opponent turn selection',
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _sendTurnCommands,
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.green[700]),
                        child: const Text('Submit Actions (Trigger AI)', style: TextStyle(color: Colors.white)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildSlotActionControl({
    required String slotTitle,
    required List<dynamic> moves,
    required List<dynamic> switches,
    required bool isForceSwitch,
    required bool isSwitch,
    required int selectedMove,
    required int selectedTarget,
    required int selectedSwitch,
    required bool isMega,
    required bool canMega,
    required ValueChanged<bool> onToggleSwitch,
    required ValueChanged<int?> onMoveChanged,
    required ValueChanged<int?> onTargetChanged,
    required ValueChanged<int?> onSwitchChanged,
    required ValueChanged<bool> onMegaToggled,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(slotTitle, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
            if (!isForceSwitch && switches.isNotEmpty)
              Semantics(
                button: true,
                label: isSwitch ? 'Switch to Move selection' : 'Switch to Pokémon replacement',
                child: TextButton(
                  onPressed: () => onToggleSwitch(!isSwitch),
                  child: Text(isSwitch ? 'Use Move' : 'Switch Out', style: const TextStyle(fontSize: 11)),
                ),
              ),
          ],
        ),
        if (isSwitch || isForceSwitch) ...[
          Semantics(
            label: '$slotTitle Switch Pokémon Selection Dropdown',
            child: DropdownButton<int>(
              isExpanded: true,
              value: switches.isEmpty ? 1 : (selectedSwitch > switches.length ? switches.first['slot'] as int : selectedSwitch),
              items: switches.map((s) {
                return DropdownMenuItem<int>(
                  value: s['slot'] as int,
                  child: Text('Switch to: ${s['name']} (${s['condition']})', style: const TextStyle(fontSize: 11)),
                );
              }).toList(),
              onChanged: onSwitchChanged,
            ),
          ),
        ] else ...[
          Row(
            children: [
              Expanded(
                child: Semantics(
                  label: '$slotTitle Move Selection Dropdown',
                  child: DropdownButton<int>(
                    isExpanded: true,
                    value: moves.isEmpty ? 1 : (selectedMove > moves.length ? 1 : selectedMove),
                    items: List.generate(moves.length, (idx) {
                      final m = moves[idx];
                      return DropdownMenuItem<int>(
                        value: idx + 1,
                        child: Text(m['move'], style: const TextStyle(fontSize: 11)),
                      );
                    }),
                    onChanged: onMoveChanged,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Semantics(
                  label: '$slotTitle Opponent Target Selection Dropdown',
                  child: DropdownButton<int>(
                    isExpanded: true,
                    value: selectedTarget,
                    items: const [
                      DropdownMenuItem(value: 1, child: Text('Target: Computer 1 (p2a)', style: TextStyle(fontSize: 10))),
                      DropdownMenuItem(value: 2, child: Text('Target: Computer 2 (p2b)', style: TextStyle(fontSize: 10))),
                      DropdownMenuItem(value: -2, child: Text('Target: Ally Slot 2', style: TextStyle(fontSize: 10))),
                    ],
                    onChanged: onTargetChanged,
                  ),
                ),
              ),
            ],
          ),
          if (canMega)
            Semantics(
              label: 'Mega Evolution Toggle Checkbox',
              value: isMega ? 'Mega Evolution Enabled' : 'Mega Evolution Disabled',
              child: Row(
                children: [
                  Checkbox(value: isMega, onChanged: (v) => onMegaToggled(v ?? false)),
                  const Text('Mega Evolve', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.purpleAccent)),
                ],
              ),
            ),
        ],
      ],
    );
  }

  Widget _buildActiveSlotRow(String title, List<String> slots, Color color) {
    return Row(
      children: [
        SizedBox(width: 70, child: Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: color))),
        Expanded(
          child: Row(
            children: slots.map((slot) {
              final name = _activeNames[slot] ?? 'Empty';
              final hp = _activeHp[slot] ?? '100/100';
              return Expanded(
                child: Semantics(
                  container: true,
                  label: '$title slot $slot: $name, Health $hp',
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(color: Colors.grey[850], borderRadius: BorderRadius.circular(4)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                        Text('HP: $hp', style: const TextStyle(fontSize: 9, fontFamily: 'monospace')),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildLiveTerminal() {
    return Semantics(
      label: 'Live Battle Protocol Terminal Logs',
      child: Container(
        height: 100,
        width: double.infinity,
        margin: const EdgeInsets.all(8),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(6)),
        child: ListView.builder(
          itemCount: _rawLogs.length,
          itemBuilder: (context, index) {
            return Text(_rawLogs[index], style: const TextStyle(color: Colors.greenAccent, fontFamily: 'monospace', fontSize: 10));
          },
        ),
      ),
    );
  }

  Widget _buildStatusBar() {
    return Container(
      width: double.infinity,
      color: Colors.grey[900],
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      child: Text(_statusMessage, style: const TextStyle(color: Colors.grey, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
    );
  }
}
