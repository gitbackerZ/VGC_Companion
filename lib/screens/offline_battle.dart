import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_js/flutter_js.dart';

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

  List<dynamic> _p1TeamList = [];
  List<dynamic> _p2TeamList = [];
  final List<int> _selectedPreviewSlots = [];

  final Map<String, String> _activeHp = {};
  final Map<String, String> _activeNames = {};

  bool _s1IsSwitch = false;
  int _s1MoveChoice = 1;
  int _s1Target = 1;
  int _s1SwitchChoice = 1;
  bool _s1Mega = false;

  bool _s2IsSwitch = false;
  int _s2MoveChoice = 1;
  int _s2Target = 1;
  int _s2SwitchChoice = 1;
  bool _s2Mega = false;

  String _statusMessage = 'Engine initializing...';

  static const String _defaultP1Team = '''
Whimsicott @ Focus Sash
Ability: Prankster
Level: 50
EVs: 252 SpA / 4 SpD / 252 Spe
Timid Nature
- Energy Ball
- Tailwind
- Beat Up
- Protect

Urshifu-Rapid-Strike @ Choice Scarf
Ability: Unseen Fist
Level: 50
EVs: 252 Atk / 4 SpD / 252 Spe
Jolly Nature
- Surging Strikes
- Close Combat
- Aqua Jet
- U-turn''';

  static const String _defaultP2Team = '''
Raichu @ Life Orb
Ability: Lightning Rod
Level: 50
EVs: 4 HP / 252 SpA / 252 Spe
Timid Nature
- Thunderbolt
- Volt Switch
- Fake Out
- Protect

Gholdengo @ Choice Specs
Ability: Good as Gold
Level: 50
EVs: 252 SpA / 4 SpD / 252 Spe
Timid Nature
- Make It Rain
- Shadow Ball
- Focus Blast
- Trick''';

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
      final engineCode = await rootBundle.loadString('assets/engine.js');

      String learnsetsJson = '{}';
      try {
        learnsetsJson = await rootBundle.loadString('assets/js/learnsets.json');
      } catch (e) {
        debugPrint('learnsets.json asset load warning: $e');
      }

      const String polyfillsScript = '''
        globalThis.global = globalThis;
        globalThis.window = globalThis;
        globalThis.self = globalThis;
        globalThis.root = globalThis;
        globalThis.navigator = { userAgent: 'Node.js' };

        if (typeof globalThis.setImmediate === 'undefined') {
          globalThis.setImmediate = function(fn) {
            var args = Array.prototype.slice.call(arguments, 1);
            return setTimeout(function() { fn.apply(null, args); }, 0);
          };
        }

        if (typeof globalThis.clearImmediate === 'undefined') {
          globalThis.clearImmediate = function(id) { clearTimeout(id); };
        }

        if (typeof globalThis.queueMicrotask === 'undefined') {
          globalThis.queueMicrotask = function(cb) {
            Promise.resolve().then(cb).catch(function(e) {
              setTimeout(function() { throw e; }, 0);
            });
          };
        }

        if (!globalThis.process) {
          globalThis.process = {
            env: { NODE_ENV: 'production' },
            argv: [],
            nextTick: function(cb) { globalThis.setImmediate(cb); },
            cwd: function() { return ''; }
          };
        }

        if (!globalThis.performance) {
          globalThis.performance = { now: function() { return Date.now(); } };
        }

        if (!globalThis.crypto) {
          globalThis.crypto = {
            getRandomValues: function(buffer) {
              for (var i = 0; i < buffer.length; i++) {
                buffer[i] = Math.floor(Math.random() * 256);
              }
              return buffer;
            }
          };
        }

        if (typeof globalThis.TextEncoder === 'undefined') {
          globalThis.TextEncoder = function TextEncoder() {};
          globalThis.TextEncoder.prototype.encode = function(s) {
            var arr = new Uint8Array(s.length);
            for (var i = 0; i < s.length; i++) arr[i] = s.charCodeAt(i);
            return arr;
          };
        }

        if (typeof globalThis.TextDecoder === 'undefined') {
          globalThis.TextDecoder = function TextDecoder() {};
          globalThis.TextDecoder.prototype.decode = function(arr) {
            return String.fromCharCode.apply(null, arr);
          };
        }
if (typeof globalThis.TextDecoder === 'undefined') {
          globalThis.TextDecoder = function TextDecoder() {};
          globalThis.TextDecoder.prototype.decode = function(arr) {
            return String.fromCharCode.apply(null, arr);
          };
        }

        (function patchObjectEntries() {
          var origEntries = Object.entries;
          Object.entries = function(obj) {
            if (obj === undefined || obj === null) return [];
            return origEntries(obj);
          };
          var origKeys = Object.keys;
          Object.keys = function(obj) {
            if (obj === undefined || obj === null) return [];
            return origKeys(obj);
          };
          var origValues = Object.values;
          Object.values = function(obj) {
            if (obj === undefined || obj === null) return [];
            return origValues(obj);
          };
        })();

        var exp = {};
        globalThis.exports = exp;
        globalThis.module = { exports: exp };

        var dummyModules = {
          fs: {
            readFileSync: function() { return ''; },
            existsSync: function() { return false; },
            readdirSync: function() { return []; },
            statSync: function() { return { isDirectory: function() { return false; }, isFile: function() { return false; } }; }
          },
          path: { resolve: function() { return ''; }, join: function() { return ''; }, dirname: function() { return ''; } },
          util: { inspect: function(o) { return String(o); }, inherits: function() {} },
          os: { platform: function() { return 'browser'; }, homedir: function() { return ''; } },
          events: function EventEmitter() {},
          crypto: globalThis.crypto || {},
          buffer: { Buffer: { isBuffer: function() { return false; }, from: function() { return []; } } }
        };

        if (!globalThis.require) {
          globalThis.require = function(id) {
            if (dummyModules[id]) return dummyModules[id];
            if (globalThis[id]) return globalThis[id];
            var fallback = globalThis.module.exports || globalThis.exports || {};
            var knownArrays = ['Formats', 'Aliases', 'CompoundWordNames'];
            var knownObjects = ['Scripts', 'FormatsData', 'Learnsets', 'Aliases', 'Pokedex', 'Movedex', 'Moves', 'Abilities', 'Items', 'Natures', 'TypeChart', 'Conditions', 'PokemonGoData', 'Rulesets', 'Species', 'TextData', 'Text'];

            for (var i = 0; i < knownArrays.length; i++) {
              if (typeof fallback[knownArrays[i]] === 'undefined') {
                fallback[knownArrays[i]] = [];
              }
            }
            for (var i = 0; i < knownObjects.length; i++) {
              if (typeof fallback[knownObjects[i]] === 'undefined') {
                fallback[knownObjects[i]] = {};
              }
            }
            if (fallback.Scripts && typeof fallback.Scripts.gen === 'undefined') {
              fallback.Scripts.gen = 9;
            }
            return fallback;
          };
        }

        globalThis.__dirname = '';
        globalThis.__filename = 'engine.js';

        globalThis.logBuffer = [];
      ''';

      runtime.evaluate(polyfillsScript);

      final engineEval = runtime.evaluate(engineCode);
      if (engineEval.isError) {
        throw Exception('engine.js execution error: ${engineEval.stringResult}');
      }

      final String helperScript = '''
        (function resolveBattleConstructor() {
          function isValidCtor(fn) {
            if (typeof fn !== 'function') return false;
            try {
              if (fn.prototype) {
                var p = fn.prototype;
                if (typeof p.choose === 'function' || typeof p.makeChoices === 'function' || typeof p.start === 'function' || typeof p.init === 'function' || typeof p.setPlayer === 'function') {
                  return true;
                }
              }
            } catch (e) {}
            return false;
          }

          // Primary: PSSim bundle exposes Battle/Dex/Teams/PRNG directly
          if (globalThis.PSSim && isValidCtor(globalThis.PSSim.Battle)) {
            globalThis.Battle = globalThis.PSSim.Battle;
            if (globalThis.PSSim.Dex && !globalThis.Dex) {
              globalThis.Dex = globalThis.PSSim.Dex;
            }
            return;
          }

          // Fallback: old deep scan, in case bundle shape changes
          var candidates = [
            globalThis.Battle,
            globalThis.Sim ? globalThis.Sim.Battle : null,
            globalThis.Dex ? globalThis.Dex.Battle : null,
          ];
          for (var i = 0; i < candidates.length; i++) {
            if (isValidCtor(candidates[i])) {
              globalThis.Battle = candidates[i];
              return;
            }
          }
          for (var key in globalThis) {
            try {
              var obj = globalThis[key];
              if (isValidCtor(obj)) {
                globalThis.Battle = obj;
                return;
              }
            } catch (e) {}
          }
})();

        if (typeof Dex !== "undefined") {
          Dex.data = Dex.data || {};
          Dex.data.Learnsets = $learnsetsJson;
          Dex.data.Aliases = Dex.data.Aliases || [];
        }

        globalThis.toID = function(text) {
          if (text && text.id) return text.id;
          if (typeof text !== 'string' && typeof text !== 'number') return '';
          return ('' + text).toLowerCase().replace(/[^a-z0-9]/g, '');
        };

        globalThis.getLogs = function() {
          const logs = JSON.stringify(globalThis.logBuffer || []);
          globalThis.logBuffer = [];
          return logs;
        };

        globalThis.getDirectRequest = function() {
          if (!globalThis.battle) return "";
          try {
            var b = globalThis.battle;
            var p1 = b.p1 || (b.sides ? b.sides[0] : null);
            var req = null;
            if (p1) {
              if (typeof p1.getRequest === 'function') req = p1.getRequest();
              else if (p1.activeRequest) req = p1.activeRequest;
              else if (p1.currentRequest) req = p1.currentRequest;
            }
            if (!req && b.requests) req = b.requests[0];
            if (!req) return "";
            return (typeof req === 'string') ? req : JSON.stringify(req);
          } catch (e) {
            return "";
          }
        };

        globalThis.checkAndPushRequests = function() {
          if (!globalThis.battle) return;
          try {
            var reqStr = globalThis.getDirectRequest();
            if (reqStr && reqStr.length > 0) {
              globalThis.logBuffer.push('|request|' + reqStr);
            }
          } catch (e) {
            globalThis.logBuffer.push('|error| Request Exception: ' + (e.message || e));
          }
        };

        globalThis.sendAction = function(action) {
          if (!globalThis.battle) return;
          try {
            var b = globalThis.battle;
            var side = null;
            var cmd = action;

            if (typeof action === 'string' && action.startsWith('>')) {
              var spaceIdx = action.indexOf(' ');
              if (spaceIdx !== -1) {
                side = action.substring(1, spaceIdx);
                cmd = action.substring(spaceIdx + 1);
              }
            }

            if (typeof b.choose === 'function') {
              if (side) b.choose(side, cmd);
              else b.choose(cmd);
            } else if (typeof b.makeChoices === 'function') {
              b.makeChoices(cmd);
            } else if (typeof b.input === 'function') {
              b.input(action);
            } else if (typeof b.receive === 'function') {
              b.receive(action);
            }

            globalThis.checkAndPushRequests();
          } catch (err) {
            globalThis.logBuffer.push('|error| Action Exception: ' + (err.message || err));
          }
        };

        globalThis.parseTeam = function(teamData) {
          if (!teamData) teamData = '';
          let rawTeam = [];

          if (Array.isArray(teamData)) rawTeam = teamData;

          if (rawTeam.length === 0 && typeof teamData === 'string') {
            const blocks = teamData.split(/\\n\\s*\\n/);
            for (let b = 0; b < blocks.length; b++) {
              const lines = blocks[b].split('\\n').map(l => l.trim()).filter(Boolean);
              if (lines.length === 0) continue;

              let species = '';
              let item = '';
              let ability = '';
              let level = 50;
              let nature = 'Hardy';
              const moves = [];
              const evs = { hp: 0, atk: 0, def: 0, spa: 0, spd: 0, spe: 0 };

              for (let i = 0; i < lines.length; i++) {
                const line = lines[i];
                if (i === 0) {
                  let header = line;
                  if (header.includes('@')) {
                    const parts = header.split('@');
                    header = parts[0].trim();
                    item = parts[1].trim();
                  }
                  species = header.trim();
                } else if (line.startsWith('Ability:')) {
                  ability = line.replace('Ability:', '').trim();
                } else if (line.startsWith('Level:')) {
                  level = parseInt(line.replace('Level:', '').trim()) || 50;
                } else if (line.endsWith('Nature')) {
                  nature = line.replace(/Nature/i, '').trim() || 'Hardy';
                } else if (line.startsWith('-')) {
                  moves.push(line.substring(1).trim());
                }
              }

              if (species) {
                rawTeam.push({
                  name: species,
                  species: species,
                  item: item,
                  ability: ability,
                  moves: moves,
                  nature: nature,
                  evs: evs,
                  level: level
                });
              }
            }
          }

          const sanitized = [];
          for (let i = 0; i < rawTeam.length; i++) {
            const mon = rawTeam[i] || {};
            let moveIDs = Array.isArray(mon.moves) ? mon.moves.map(globalThis.toID).filter(Boolean) : [];
            if (moveIDs.length === 0) moveIDs = ['tackle', 'protect'];

            sanitized.push({
              name: mon.name || mon.species || 'Pikachu',
              species: mon.species || 'Pikachu',
              item: mon.item || '',
              ability: mon.ability || 'Static',
              moves: moveIDs,
              nature: mon.nature || 'Hardy',
              evs: mon.evs || { hp: 0, atk: 0, def: 0, spa: 0, spd: 0, spe: 0 },
              ivs: { hp: 31, atk: 31, def: 31, spa: 31, spd: 31, spe: 31 },
              level: parseInt(mon.level) || 50
            });
          }

          while (sanitized.length < 2) {
            sanitized.push({
              name: 'Pikachu ' + (sanitized.length + 1),
              species: 'Pikachu',
              item: '',
              ability: 'Static',
              moves: ['tackle', 'protect'],
              nature: 'Hardy',
              evs: { hp: 0, atk: 0, def: 0, spa: 0, spd: 0, spe: 0 },
              ivs: { hp: 31, atk: 31, def: 31, spa: 31, spd: 31, spe: 31 },
              level: 50
            });
          }

          return sanitized;
        };

        globalThis.startVGCBattle = function(formatId, p1TeamData, p2TeamData) {
          globalThis.logBuffer = [];
          try {
            const p1Team = globalThis.parseTeam(p1TeamData);
            const p2Team = globalThis.parseTeam(p2TeamData);

            let BattleCtor = globalThis.Battle;
            if (typeof BattleCtor !== 'function') {
              throw new Error('Battle constructor resolution failed. Available keys: ' + Object.keys(globalThis).join(', '));
            }

            var battleInstance = new BattleCtor({
              formatid: 'gen9championsdoublescustomgame',
              gameType: 'doubles',
              send: function(type, data) {
                if (Array.isArray(data)) {
                  globalThis.logBuffer.push(data.join('\\n'));
                } else if (data) {
                  globalThis.logBuffer.push(data);
                }
              }
            });

            globalThis.battle = battleInstance;

            if (typeof battleInstance.setPlayer === 'function') {
              battleInstance.setPlayer('p1', { name: 'Player 1', team: p1Team });
              battleInstance.setPlayer('p2', { name: 'Computer AI', team: p2Team });
            } else if (typeof battleInstance.join === 'function') {
              battleInstance.join('p1', 'Player 1', 1, p1Team);
              battleInstance.join('p2', 'Computer AI', 1, p2Team);
            }

            if (typeof battleInstance.start === 'function') {
              battleInstance.start();
            } else if (typeof battleInstance.init === 'function') {
              battleInstance.init();
            }

            globalThis.checkAndPushRequests();
            return "SUCCESS";
          } catch (err) {
            const errMsg = (err && err.message) ? err.message : String(err);
            const errStack = (err && err.stack) ? err.stack : 'no stack';
            globalThis.logBuffer.push('|error| Engine Crash: ' + errMsg + ' | STACK: ' + errStack);
            return "ERROR: " + errMsg;
          }
        };
      ''';

      final helperEval = runtime.evaluate(helperScript);
      if (helperEval.isError) {
        throw Exception('helperScript execution error: ${helperEval.stringResult}');
      }

      setState(() {
        _jsRuntime = runtime;
        _isLoading = false;
        _statusMessage = 'Engine ready. Gen 9 Custom Doubles Active.';
      });
      _announce('Engine initialized successfully.');
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
      if (result.isError) return;
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
      dynamic data = jsonDecode(jsonString);
      if (data is String) {
        data = jsonDecode(data);
      }
      if (data is! Map<String, dynamic>) return;

      setState(() {
        _currentRequest = Map<String, dynamic>.from(data);

        if (data.containsKey('teamPreview') && data['teamPreview'] == true) {
          _stage = BattleStage.teamPreview;
          _p1TeamList = data['side']['pokemon'] ?? [];
          _selectedPreviewSlots.clear();
          _statusMessage = 'Team preview active. Choose Pokémon.';
          _announce('Team preview started.');
        } else {
          _stage = BattleStage.inBattle;
          _s1IsSwitch = false;
          _s2IsSwitch = false;
          _s1Mega = false;
          _s2Mega = false;
          _s1MoveChoice = 1;
          _s2MoveChoice = 1;
          _statusMessage = 'Waiting for player actions...';
          _announce('New turn requested.');
        }
      });
    } catch (e) {
      debugPrint('Error parsing request JSON: $e');
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

    final p1Data = jsonEncode(_p1TeamController.text);
    final p2Data = jsonEncode(_p2TeamController.text);

    final JsEvalResult result = _jsRuntime!.evaluate(
      "globalThis.startVGCBattle('gen9championsdoublescustomgame', $p1Data, $p2Data);"
    );

    if (result.isError) {
      setState(() {
        _statusMessage = 'JS Evaluation Error: ${result.stringResult}';
      });
      _announce('Failed to start battle.');
      return;
    }

    _fetchLogs();

    final directReqRes = _jsRuntime!.evaluate("globalThis.getDirectRequest();");
    if (!directReqRes.isError && directReqRes.stringResult.isNotEmpty) {
      _parseRequest(directReqRes.stringResult);
    } else {
      // Direct UI stage fallback to advance off the setup screen
      final checkBattle = _jsRuntime!.evaluate("Boolean(globalThis.battle);");
      if (checkBattle.stringResult == 'true') {
        setState(() {
          if (_stage == BattleStage.setup) {
            _stage = BattleStage.inBattle;
            _statusMessage = 'Battle started. Select actions below.';
          }
        });
      }
    }
  }

  void _confirmTeamPreviewSelection() {
    if (_selectedPreviewSlots.length < 2 || _jsRuntime == null) return;
    final teamOrder = _selectedPreviewSlots.join('');
    _jsRuntime!.evaluate("globalThis.sendAction('>p1 team $teamOrder');");
    _jsRuntime!.evaluate("globalThis.sendAction('>p2 team 1234');");
    _fetchLogs();
    _announce('Submitted team selection. Entering battle turn 1.');
  }

  void _sendTurnCommands() {
    if (_jsRuntime == null) return;

    final isForceSwitch = _currentRequest != null && _currentRequest!.containsKey('forceSwitch');
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

      final activeList = _currentRequest != null ? (_currentRequest!['active'] as List<dynamic>? ?? []) : [];
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
    _fetchLogs();

    _announce('Player actions submitted.');
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
          child: TextField(
            controller: _p1TeamController,
            maxLines: 5,
            style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
            decoration: const InputDecoration(
              labelText: 'Player 1 Team Sheet',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        const SizedBox(height: 16),
        const Text('Player 2 Team (Computer AI)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.redAccent)),
        const SizedBox(height: 4),
        Semantics(
          label: 'Player 2 Computer AI Team Input Text Area',
          child: TextField(
            controller: _p2TeamController,
            maxLines: 5,
            style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
            decoration: const InputDecoration(
              labelText: 'Computer Team Sheet',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Semantics(
          button: true,
          label: 'Start Player versus Computer Battle',
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
          child: const Text('Team Preview (Choose Lineup)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
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
              child: InkWell(
                onTap: () {
                  setState(() {
                    if (selectedPos != -1) {
                      _selectedPreviewSlots.removeAt(selectedPos);
                    } else if (_selectedPreviewSlots.length < _p1TeamList.length) {
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
          enabled: _selectedPreviewSlots.length >= 2,
          child: SizedBox(
            width: double.infinity,
            height: 44,
            child: ElevatedButton(
              onPressed: _selectedPreviewSlots.length >= 2 ? _confirmTeamPreviewSelection : null,
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green[700]),
              child: Text('Confirm Selection (${_selectedPreviewSlots.length}/${_p1TeamList.length})'),
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
        if (_stage == BattleStage.inBattle) ...[
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
                  if (!isForceSwitch) ...[
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
                child: TextButton(
                  onPressed: () => onToggleSwitch(!isSwitch),
                  child: Text(isSwitch ? 'Use Move' : 'Switch Out', style: const TextStyle(fontSize: 11)),
                ),
              ),
          ],
        ),
        if (isSwitch || isForceSwitch) ...[
          DropdownButton<int>(
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
        ] else ...[
          Row(
            children: [
              Expanded(
                child: DropdownButton<int>(
                  isExpanded: true,
                  value: moves.isEmpty ? 1 : (selectedMove > moves.length ? 1 : selectedMove),
                  items: moves.isNotEmpty
                      ? List.generate(moves.length, (idx) {
                          final m = moves[idx];
                          return DropdownMenuItem<int>(
                            value: idx + 1,
                            child: Text(m['move'] ?? 'Move ${idx + 1}', style: const TextStyle(fontSize: 11)),
                          );
                        })
                      : const [
                          DropdownMenuItem(value: 1, child: Text('Move 1', style: TextStyle(fontSize: 11))),
                          DropdownMenuItem(value: 2, child: Text('Move 2', style: TextStyle(fontSize: 11))),
                          DropdownMenuItem(value: 3, child: Text('Move 3', style: TextStyle(fontSize: 11))),
                          DropdownMenuItem(value: 4, child: Text('Move 4', style: TextStyle(fontSize: 11))),
                        ],
                  onChanged: onMoveChanged,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
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
            ],
          ),
          if (canMega)
            Row(
              children: [
                Checkbox(value: isMega, onChanged: (v) => onMegaToggled(v ?? false)),
                const Text('Mega Evolve', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.purpleAccent)),
              ],
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
              final name = _activeNames[slot] ?? 'Active Mon';
              final hp = _activeHp[slot] ?? '100/100';
              return Expanded(
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
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildLiveTerminal() {
    return Container(
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