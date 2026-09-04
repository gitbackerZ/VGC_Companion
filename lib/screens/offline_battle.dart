import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
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
  bool _isLoading = false;
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
  final Map<String, List<String>> _activeTypes = {};
  final Map<String, String> _activeStatus = {};

  void _refreshActiveMonInfo() {
    if (_jsRuntime == null) return;
    for (final entry in {'p1a': 'p1,a', 'p1b': 'p1,b', 'p2a': 'p2,a', 'p2b': 'p2,b'}.entries) {
      final args = entry.value.split(',');
      final result = _jsRuntime!.evaluate("globalThis.getPokemonInfo('${args[0]}', '${args[1]}');");
      if (result.isError) continue;
      try {
        final data = jsonDecode(result.stringResult);
        if (data is Map) {
          final types = (data['types'] as List<dynamic>?)?.map((t) => t.toString()).toList() ?? [];
          if (types.isNotEmpty) _activeTypes[entry.key] = types;
          final status = data['status']?.toString() ?? '';
          _activeStatus[entry.key] = status;
        }
      } catch (_) {}
    }
  }

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

  String _statusMessage = 'Enter both team sheets to begin.';
  bool _engineInitialized = false;
  bool _isWaiting = false;

  @override
  void initState() {
    super.initState();
    // Engine no longer initializes automatically.
    // It starts only after the player submits both team sheets.
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

        var fsStub = {
          readFileSync: function() { return ''; },
          existsSync: function(filePath) {
            if (typeof filePath === 'string' && (filePath.includes('champions') || filePath.includes('championsregma'))) {
              return true; 
            }
            return false;
          },
          readdirSync: function(dirPath, options) {
            if (typeof dirPath === 'string' && (dirPath.includes('mods') || dirPath.endsWith('mods'))) {
              return ['champions', 'championsregma'];
            }
            return [];
          },
          statSync: function() { return { isDirectory: function() { return true; }, isFile: function() { return false; } }; }
        };

        var dummyModules = {
          fs: fsStub,
          'node:fs': fsStub,
          path: { resolve: function() { return ''; }, join: function() { return ''; }, dirname: function() { return ''; }, basename: function() { return ''; }, extname: function() { return ''; } },
          'node:path': { resolve: function() { return ''; }, join: function() { return ''; }, dirname: function() { return ''; }, basename: function() { return ''; }, extname: function() { return ''; } },
          util: { inspect: function(o) { return String(o); }, inherits: function() {} },
          'node:util': { inspect: function(o) { return String(o); }, inherits: function() {} },
          os: { platform: function() { return 'browser'; }, homedir: function() { return ''; } },
          'node:os': { platform: function() { return 'browser'; }, homedir: function() { return ''; } },
          events: function EventEmitter() {},
          crypto: globalThis.crypto || {},
          buffer: { Buffer: { isBuffer: function() { return false; }, from: function() { return []; } } }
        };

        globalThis.fs2 = fsStub;

        if (!globalThis.require) {
          globalThis.require = function(id) {
            if (dummyModules[id]) return dummyModules[id];
            if (globalThis[id]) return globalThis[id];

            if (globalThis.PSStaticData) {
              var dataKeyMap = {
                abilities: 'Abilities',
                rulesets: 'Rulesets',
                'formats-data': 'FormatsData',
                items: 'Items',
                learnsets: 'Learnsets',
                moves: 'Moves',
                natures: 'Natures',
                pokedex: 'Pokedex',
                scripts: 'Scripts',
                conditions: 'Conditions',
                typechart: 'TypeChart',
                aliases: 'Aliases',
              };
              var safetyArrays = ['Formats', 'Aliases', 'CompoundWordNames'];
              var safetyObjects = ['Scripts', 'FormatsData', 'Learnsets', 'Pokedex', 'Moves', 'Abilities', 'Items', 'Natures', 'TypeChart', 'Conditions', 'PokemonGoData', 'Rulesets'];

              function withSafetyDefaults(result) {
                for (var a = 0; a < safetyArrays.length; a++) {
                  if (typeof result[safetyArrays[a]] === 'undefined') {
                    result[safetyArrays[a]] = [];
                  }
                }
                for (var o = 0; o < safetyObjects.length; o++) {
                  if (typeof result[safetyObjects[o]] === 'undefined') {
                    result[safetyObjects[o]] = {};
                  }
                }
                if (result.Scripts && typeof result.Scripts.gen === 'undefined') {
                  result.Scripts.gen = 9;
                }
                return result;
              }

              var lowerId = String(id).toLowerCase();
              for (var fileKey in dataKeyMap) {
                if (lowerId.indexOf(fileKey) !== -1 && lowerId.indexOf('mods/champions') === -1 && lowerId.indexOf('mods/championsregma') === -1) {
                  var exportName = dataKeyMap[fileKey];
                  var result = {};
                  result[exportName] = globalThis.PSStaticData.base[fileKey] || {};
                  return withSafetyDefaults(result);
                }
              }
              if (lowerId.indexOf('championsregma') !== -1) {
                for (var fileKey2 in dataKeyMap) {
                  if (lowerId.indexOf(fileKey2) !== -1) {
                    var exportName2 = dataKeyMap[fileKey2];
                    var result2 = {};
                    result2[exportName2] = (globalThis.PSStaticData.mods.championsregma && globalThis.PSStaticData.mods.championsregma[fileKey2]) || {};
                    return withSafetyDefaults(result2);
                  }
                }
              }
              if (lowerId.indexOf('champions') !== -1) {
                for (var fileKey3 in dataKeyMap) {
                  if (lowerId.indexOf(fileKey3) !== -1) {
                    var exportName3 = dataKeyMap[fileKey3];
                    var result3 = {};
                    result3[exportName3] = (globalThis.PSStaticData.mods.champions && globalThis.PSStaticData.mods.champions[fileKey3]) || {};
                    return withSafetyDefaults(result3);
                  }
                }
              }

              if (lowerId.indexOf('custom-formats') !== -1) {
                return { Formats: [] };
              }
              if (lowerId.indexOf('config/formats') !== -1) {
                return { Formats: globalThis.PSStaticData.configFormats || [] };
              }
            }

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

          if (globalThis.PSSim && isValidCtor(globalThis.PSSim.Battle)) {
            globalThis.Battle = globalThis.PSSim.Battle;
            if (globalThis.PSSim.Dex && !globalThis.Dex) {
              globalThis.Dex = globalThis.PSSim.Dex;
            }
            return;
          }

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

        try {
          var _Dex = (globalThis.PSSim && globalThis.PSSim.Dex) ? globalThis.PSSim.Dex : globalThis.Dex;
          if (_Dex) {
            if (!_Dex.dexes) _Dex.dexes = Object.create(null);
            if (!_Dex.dexes.base) _Dex.dexes.base = _Dex;

            var ModdedDexCtor = _Dex.ModdedDex || _Dex.constructor;
            if (!_Dex.dexes.champions) {
              _Dex.dexes.champions = new ModdedDexCtor('champions');
            }
            if (!_Dex.dexes.championsregma) {
              _Dex.dexes.championsregma = new ModdedDexCtor('championsregma');
            }

            _Dex.modsLoaded = true;
            if (_Dex.dexes.base) _Dex.dexes.base.modsLoaded = true;
          }
        } catch (e) {}

        if (typeof Dex !== "undefined") {
          Dex.data = Dex.data || {};
          Dex.data.Learnsets = $learnsetsJson;
          Dex.data.Aliases = Dex.data.Aliases || [];
        }

        globalThis.toID = function(text) {
          if (text && text.id) return text.id;
          if (typeof text !== 'string' && typeof text !== 'number') return '';
          return ('' + text).toLowerCase().replace(new RegExp('[^a-z0-9]', 'g'), '');
        };

        globalThis.getLogs = function() {
          const logs = JSON.stringify(globalThis.logBuffer || []);
          globalThis.logBuffer = [];
          return logs;
        };

        globalThis.getPokemonInfo = function(side, slotLetter) {
          try {
            var b = globalThis.battle;
            if (!b) return "{}";
            var sideObj = (side === 'p1') ? b.p1 : b.p2;
            if (!sideObj || !sideObj.active) return "{}";
            var slotIdx = slotLetter === 'a' ? 0 : 1;
            var mon = sideObj.active[slotIdx];
            if (!mon) return "{}";
            var types = mon.types || (mon.getTypes ? mon.getTypes() : []);
            var status = mon.status || '';
            return JSON.stringify({ types: types, status: status, name: mon.name || '' });
          } catch (e) {
            return "{}";
          }
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
            var b = globalThis.battle;
            var p1Done = b.p1 && typeof b.p1.isChoiceDone === 'function' ? b.p1.isChoiceDone() : 'n/a';
            var p2Done = b.p2 && typeof b.p2.isChoiceDone === 'function' ? b.p2.isChoiceDone() : 'n/a';
            var requestState = b.requestState || 'n/a';
            globalThis.logBuffer.push('|debug-state| requestState=' + requestState + ' p1Done=' + p1Done + ' p2Done=' + p2Done);

            var reqStr = globalThis.getDirectRequest();
            if (reqStr && reqStr.length > 0) {
              globalThis.logBuffer.push('|request|' + reqStr);
            }
          } catch (e) {
            globalThis.logBuffer.push('|debug-state-error| ' + (e && e.message ? e.message : String(e)));
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

            var targetSide = null;
            if (side === 'p1' && b.p1) targetSide = b.p1;
            else if (side === 'p2' && b.p2) targetSide = b.p2;
            else if (b.sides && b.sides.length > 0) targetSide = b.sides[0];

            var result = 'no-op';
            if (targetSide && typeof targetSide.choose === 'function') {
              result = targetSide.choose(cmd);
            } else if (typeof b.choose === 'function') {
              if (side) result = b.choose(side, cmd);
              else result = b.choose(cmd);
            } else if (typeof b.makeChoices === 'function') {
              result = b.makeChoices(cmd);
            }

            globalThis.logBuffer.push('|debug-choose| action="' + action + '" cmd="' + cmd + '" side=' + side + ' result=' + result);

            // If both sides have finished choosing, explicitly advance the battle.
            try {
              var p1Ready = b.p1 && typeof b.p1.isChoiceDone === 'function' ? b.p1.isChoiceDone() : false;
              var p2Ready = b.p2 && typeof b.p2.isChoiceDone === 'function' ? b.p2.isChoiceDone() : false;
              if (p1Ready && p2Ready) {
                if (typeof b.commitChoices === 'function') {
                  b.commitChoices();
                  globalThis.logBuffer.push('|debug-commit| commitChoices() called, requestState now=' + b.requestState);

                  if (typeof b.sendUpdates === 'function') {
                    b.sendUpdates();
                    globalThis.logBuffer.push('|debug-flush| sendUpdates() called');
                  } else {
                    globalThis.logBuffer.push('|debug-flush| sendUpdates not found on battle object');
                  }
                } else {
                  globalThis.logBuffer.push('|debug-commit| commitChoices not found on battle object');
                }
              }
            } catch (commitErr) {
              globalThis.logBuffer.push('|debug-commit-error| ' + (commitErr && commitErr.message ? commitErr.message : String(commitErr)));
            }

            globalThis.checkAndPushRequests();
          } catch (err) {
            globalThis.logBuffer.push('|debug-choose-error| ' + (err && err.message ? err.message : String(err)));
          }
        };

        globalThis.parseTeam = function(teamData) {
          if (!teamData) teamData = '';
          let rawTeam = [];

          if (Array.isArray(teamData)) rawTeam = teamData;

          if (rawTeam.length === 0 && typeof teamData === 'string') {
            const blocks = teamData.split(new RegExp('\\n\\s*\\n'));
            for (let b = 0; b < blocks.length; b++) {
              const lines = blocks[b].split(new RegExp('\\n')).map(l => l.trim()).filter(Boolean);
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
                  nature = line.replace(new RegExp('Nature', 'i'), '').trim() || 'Hardy';
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
              throw new Error('Battle constructor resolution failed.');
            }

            if (BattleCtor.prototype && typeof BattleCtor.prototype.start === 'function' && !BattleCtor.prototype._patchedStart) {
              var origStart = BattleCtor.prototype.start;
              BattleCtor.prototype.start = function() {
                if (this.started) return;
                return origStart.apply(this, arguments);
              };
              BattleCtor.prototype._patchedStart = true;
            }

            var battleInstance = new BattleCtor({
              formatid: formatId,
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
            globalThis.logBuffer.push('|error| Engine Crash: ' + errMsg);
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
        _statusMessage = 'Engine ready. Format active.';
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

  String _humanizeLogLine(String line) {
    final parts = line.split('|');
    if (parts.length < 2) return line;
    final cmd = parts[1];

    String nameOf(String raw) {
      final idx = raw.indexOf(':');
      return idx != -1 ? raw.substring(idx + 1).trim() : raw;
    }

    switch (cmd) {
      case 'move':
        if (parts.length < 4) return line;
        return '${nameOf(parts[2])} used ${parts[3]}!';
      case '-damage':
        if (parts.length < 4) return line;
        final hp = parts[3].split(' ')[0];
        return '${nameOf(parts[2])} took damage → $hp HP';
      case '-heal':
        if (parts.length < 4) return line;
        final hp = parts[3].split(' ')[0];
        return '${nameOf(parts[2])} healed → $hp HP';
      case 'faint':
        if (parts.length < 3) return line;
        return '${nameOf(parts[2])} fainted!';
      case 'switch':
      case 'drag':
        if (parts.length < 4) return line;
        return '${nameOf(parts[3])} was sent out';
      case '-supereffective':
        return "It's super effective!";
      case '-resisted':
        return "It's not very effective...";
      case '-immune':
        if (parts.length < 3) return line;
        return "It doesn't affect ${nameOf(parts[2])}...";
      case '-boost':
        if (parts.length < 5) return line;
        return '${nameOf(parts[2])}\'s ${parts[3]} rose!';
      case '-unboost':
        if (parts.length < 5) return line;
        return '${nameOf(parts[2])}\'s ${parts[3]} fell!';
      case '-status':
        if (parts.length < 4) return line;
        return '${nameOf(parts[2])} was afflicted with ${parts[3]}!';
      case '-curestatus':
        if (parts.length < 3) return line;
        return '${nameOf(parts[2])} recovered from its status!';
      case '-weather':
        if (parts.length < 3) return line;
        if (parts[2] == 'none') return 'The weather cleared.';
        return 'The weather is ${parts[2]}.';
      case '-ability':
        if (parts.length < 4) return line;
        return "${nameOf(parts[2])}'s ${parts[3]} activated";
      case '-start':
        if (parts.length < 4) return line;
        return '${nameOf(parts[2])} started ${parts[3]}';
      case '-end':
        if (parts.length < 4) return line;
        return '${nameOf(parts[2])}\'s ${parts[3]} ended';
      case '-sidestart':
        if (parts.length < 4) return line;
        return '${parts[3].replaceAll('move: ', '')} started for ${parts[2]}';
      case 'turn':
        if (parts.length < 3) return line;
        return '── Turn ${parts[2]} ──';
      case 'cant':
        if (parts.length < 4) return line;
        return "${nameOf(parts[2])} couldn't move (${parts[3]})";
      case '-crit':
        return 'A critical hit!';
      case '-fail':
        return 'But it failed!';
      case '-miss':
        return 'The attack missed!';
      default:
        return line; // fall back to raw for anything not covered
    }
  }

  void _announce(String message) {
    if (message.isEmpty) return;
    SemanticsService.announce(message, TextDirection.ltr);
  }

  void _startLogPolling() {
    _logTimer = Timer.periodic(const Duration(milliseconds: 250), (_) => _fetchLogs());
  }

  String _pendingRequestSide = 'p1';
  Map<String, dynamic>? _lastP2Request;
  final math.Random _rng = math.Random();
  bool _p1HasMegaEvolved = false;
  bool _p2HasMegaEvolved = false;

  final List<Map<String, dynamic>> _turnHistory = []; // {turn: int, lines: List<String>}
  int _currentTurnNumber = 0;

  void _fetchLogs() {
    if (_jsRuntime == null) return;
    try {
      final JsEvalResult result = _jsRuntime!.evaluate("globalThis.getLogs();");
      if (result.isError) return;
      final String rawJson = result.stringResult;
      final List<dynamic> parsed = jsonDecode(rawJson);
      if (parsed.isNotEmpty) {
        setState(() {
          _refreshActiveMonInfo();
          for (var chunk in parsed) {
            for (var line in chunk.toString().split('\n')) {
              final trimmed = line.trim();
              if (trimmed.isEmpty) continue;

              // Track which side the next |request| line belongs to
              if (trimmed == 'p1' || trimmed == 'p2') {
                _pendingRequestSide = trimmed;
                continue;
              }

              if (trimmed.startsWith('|poke|')) {
                _rawLogs.add('|debug-raw-poke| $trimmed');
              }

              // Track per-turn log segments for turn-by-turn browsing.
              if (trimmed.startsWith('|turn|')) {
                final parts = trimmed.split('|');
                final turnNum = parts.length > 2 ? int.tryParse(parts[2]) ?? (_currentTurnNumber + 1) : (_currentTurnNumber + 1);
                _currentTurnNumber = turnNum;
                _turnHistory.add({'turn': turnNum, 'lines': <String>[]});
              }
              if (_turnHistory.isNotEmpty) {
                (_turnHistory.last['lines'] as List<String>).add(trimmed);
              }

              // Track p2's own request by inspecting side.id directly — do NOT rely on
              // the preceding bare "p1"/"p2" marker line, since the very first move
              // request of a battle can arrive without one.
              if (trimmed.startsWith('|request|')) {
                try {
                  dynamic reqData = jsonDecode(trimmed.substring(9));
                  if (reqData is String) reqData = jsonDecode(reqData);
                  if (reqData is Map) {
                    final sideId = reqData['side']?['id']?.toString();
                    if (sideId == 'p2') {
                      if (reqData.containsKey('forceSwitch')) {
                        _rawLogs.add('|debug-p2-forceswitch| auto-sending default switch');
                        _jsRuntime?.evaluate("globalThis.sendAction('>p2 default');");
                      } else if (reqData.containsKey('active')) {
                        _lastP2Request = Map<String, dynamic>.from(reqData);
                      }
                    }
                  }
                } catch (_) {}
              }

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
        final slotParts = parts[2].split(':');
        final slot = slotParts.first.trim();
        final name = slotParts.length > 1 ? slotParts.sublist(1).join(':').trim() : slot;
        final hp = parts.length > 4 ? parts[4] : '';
        _activeNames[slot] = name;
        _activeHp[slot] = hp;
        _announce('$name entered battle on $slot.');
        break;
      case '-damage':
        final slotParts = parts[2].split(':');
        final slot = slotParts.first.trim();
        final name = slotParts.length > 1 ? slotParts.sublist(1).join(':').trim() : slot;
        if (parts.length > 3) _activeHp[slot] = parts[3];
        _announce('$name took damage. Health is now ${parts[3]}.');
        break;
      case 'faint':
        final slotParts = parts[2].split(':');
        final slot = slotParts.first.trim();
        final name = slotParts.length > 1 ? slotParts.sublist(1).join(':').trim() : slot;
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

      // Only track the player's (p1) request — ignore the computer's (p2) own request block.
      // Check the request's own side.id rather than a preceding marker line, since the
      // marker line can be absent (e.g. the very first request after committing choices).
      final sideId = data['side']?['id']?.toString();
      if (sideId == 'p2') return;

      setState(() {
        if (data.containsKey('teamPreview') && data['teamPreview'] == true) {
          _currentRequest = Map<String, dynamic>.from(data);
          _stage = BattleStage.teamPreview;
          _p1TeamList = data['side']?['pokemon'] ?? [];
          _selectedPreviewSlots.clear();
          _statusMessage = 'Team preview active. Choose Pokémon.';
          _announce('Team preview started.');
        } else if (data.containsKey('wait') && data['wait'] == true) {
          // Genuinely don't touch _currentRequest here — keep whatever move/active
          // data we already had, so the UI doesn't go blank while waiting.
          _isWaiting = true;
          _stage = BattleStage.inBattle;
          _statusMessage = 'Waiting for the computer to send out a replacement...';
          _announce('Waiting for opponent.');
        } else {
          _isWaiting = false;
          _currentRequest = Map<String, dynamic>.from(data);
          _stage = BattleStage.inBattle;
          _s1IsSwitch = false;
          _s2IsSwitch = false;
          _s1Mega = false;
          _s2Mega = false;
          _s1MoveChoice = 1;
          _s2MoveChoice = 1;
          _statusMessage = 'Waiting for player actions...';
          _announce('New turn requested.');

          final activeCheck = data['active'] as List<dynamic>?;
          _rawLogs.add('|debug-request-applied| activeSlots=${activeCheck?.length ?? 'null'} slot1Moves=${activeCheck != null && activeCheck.isNotEmpty ? (activeCheck[0]['moves'] as List<dynamic>?)?.length : 'n/a'}');
        }
      });
    } catch (e, st) {
      debugPrint('Error parsing request JSON: $e');
      setState(() {
        _rawLogs.add('|debug-parse-error| $e');
        _rawLogs.add('|debug-parse-stack| ${st.toString().split('\n').take(3).join(' | ')}');
      });
    }
  }

  bool _looksLikeValidTeamSheet(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return false;
    final blocks = trimmed.split(RegExp(r'\n\s*\n'));
    int validBlocks = 0;
    for (final block in blocks) {
      final lines = block.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
      if (lines.isEmpty) continue;
      final hasMove = lines.any((l) => l.startsWith('-'));
      if (lines.first.isNotEmpty && hasMove) {
        validBlocks++;
      }
    }
    return validBlocks > 0;
  }

  Future<void> _handleTeamSubmission() async {
    final p1Text = _p1TeamController.text;
    final p2Text = _p2TeamController.text;

    if (!_looksLikeValidTeamSheet(p1Text)) {
      setState(() => _statusMessage = 'Player 1 team sheet is missing or invalid. Add at least one Pokémon with moves.');
      _announce('Player 1 team sheet is invalid.');
      return;
    }
    if (!_looksLikeValidTeamSheet(p2Text)) {
      setState(() => _statusMessage = 'Computer team sheet is missing or invalid. Add at least one Pokémon with moves.');
      _announce('Computer team sheet is invalid.');
      return;
    }

    if (!_engineInitialized) {
      setState(() {
        _isLoading = true;
        _statusMessage = 'Loading engine...';
      });
      await _initEngine();
      _engineInitialized = true;
    }

    _startMatch();
  }

  void _startMatch() {
    if (_jsRuntime == null) return;
    setState(() {
      _rawLogs.clear();
      _p2TeamList.clear();
      _activeHp.clear();
      _activeNames.clear();
      _statusMessage = 'Starting Battle...';
      _p1HasMegaEvolved = false;
      _p2HasMegaEvolved = false;
      _turnHistory.clear();
      _currentTurnNumber = 0;
      _isWaiting = false;
    });
    _announce('Starting Battle.');

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

    List<int> fullOrder = List.from(_selectedPreviewSlots);
    for (int i = 1; i <= _p1TeamList.length; i++) {
      if (!fullOrder.contains(i)) {
        fullOrder.add(i);
      }
    }
    final p1Order = fullOrder.join('');

    // Build a randomized, non-repeating permutation for p2 sized to its actual typed team sheet
    final p2SheetBlocks = _p2TeamController.text
        .trim()
        .split(RegExp(r'\n\s*\n'))
        .where((b) => b.trim().isNotEmpty)
        .toList();
    final p2Count = p2SheetBlocks.isNotEmpty ? p2SheetBlocks.length : 2;
    final p2Digits = List.generate(p2Count, (i) => i + 1);
    p2Digits.shuffle();
    final p2Order = p2Digits.join('');

    // Safely route through sendAction helper
    _jsRuntime!.evaluate("globalThis.sendAction('>p1 team $p1Order');");
    _jsRuntime!.evaluate("globalThis.sendAction('>p2 team $p2Order');");

    _fetchLogs();
    _announce('Submitted team selection. Entering battle turn 1.');
  }

  bool _moveNeedsTarget(List<dynamic> activeList, int slotIndex, int moveChoice) {
    if (activeList.length <= slotIndex) return true;
    final moves = activeList[slotIndex]['moves'] as List<dynamic>? ?? [];
    if (moveChoice < 1 || moveChoice > moves.length) return true;
    final moveData = moves[moveChoice - 1];
    final target = moveData is Map ? moveData['target']?.toString() : null;
    // Target types that Showdown resolves automatically — no explicit target index needed.
    const noTargetTypes = {
      'allySide',        // e.g. Tailwind, Wide Guard, Light Screen
      'self',            // e.g. Protect, Substitute
      'all',             // e.g. Perish Song
      'allyTeam',        // team-wide heal/buff moves
      'foeSide',         // e.g. Toxic Spikes, Stealth Rock
      'allAdjacent',     // e.g. Parabolic Charge, Earthquake — hits everyone nearby automatically
      'allAdjacentFoes', // e.g. Rock Slide, Muddy Water — hits all adjacent foes automatically
    };
    return !(target != null && noTargetTypes.contains(target));
  }

  void _sendTurnCommands() {
    if (_jsRuntime == null) return;

    final isForceSwitch = _currentRequest != null && _currentRequest!.containsKey('forceSwitch');
    final activeList = _currentRequest != null ? (_currentRequest!['active'] as List<dynamic>? ?? []) : [];
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
        String act = 'move $_s1MoveChoice';
        if (_moveNeedsTarget(activeList, 0, _s1MoveChoice)) act += ' $_s1Target';
        if (_s1Mega) act += ' mega';
        slotActions.add(act);
      }

      if (activeList.length > 1) {
        if (_s2IsSwitch) {
          slotActions.add('switch $_s2SwitchChoice');
        } else {
          String act = 'move $_s2MoveChoice';
          if (_moveNeedsTarget(activeList, 1, _s2MoveChoice)) act += ' $_s2Target';
          if (_s2Mega) act += ' mega';
          slotActions.add(act);
        }
      }
      p1Action += slotActions.join(', ');
    }

    if (!isForceSwitch) {
      if (_s1Mega || _s2Mega) _p1HasMegaEvolved = true;
    }

    _jsRuntime!.evaluate("globalThis.sendAction('$p1Action');");
    _jsRuntime!.evaluate("globalThis.sendAction('${_buildP2MoveAction()}');");
    _fetchLogs();

    _announce('Player actions submitted.');
    // Do NOT null out _currentRequest here — _fetchLogs() above already parsed
    // and applied the next turn's real request (or a "wait" state). Wiping it
    // afterward discards that data and permanently freezes the UI.
  }

  String _buildP2MoveAction() {
    if (_lastP2Request == null || !_lastP2Request!.containsKey('active')) {
      return '>p2 default';
    }
    final active = _lastP2Request!['active'] as List<dynamic>? ?? [];
    if (active.isEmpty) return '>p2 default';

    // Cross-check against p2's actual living Pokémon count from the same
    // cached request. If the number of active move-slots doesn't match the
    // number of currently-active (non-fainted) Pokémon, this cached request
    // is stale (e.g. a partner fainted since it was captured) — fall back
    // to 'default' rather than submitting a mismatched choice count.
    final pokemonList = _lastP2Request!['side']?['pokemon'] as List<dynamic>? ?? [];
    final livingActiveCount = pokemonList.where((p) {
      final isActive = p is Map && (p['active'] == true);
      final condition = p is Map ? p['condition']?.toString() ?? '' : '';
      final fainted = condition.startsWith('0') || condition.contains('fnt');
      return isActive && !fainted;
    }).length;
    if (livingActiveCount != active.length) {
      return '>p2 default';
    }

    List<String> slotActions = [];
    for (int slot = 0; slot < active.length; slot++) {
      final moves = active[slot]['moves'] as List<dynamic>? ?? [];
      final usable = <int>[];
      for (int i = 0; i < moves.length; i++) {
        final m = moves[i];
        final disabled = m is Map && (m['disabled'] == true);
        if (!disabled) usable.add(i + 1);
      }
      if (usable.isEmpty) {
        slotActions.add('pass');
        continue;
      }
      final moveIdx = usable[_rng.nextInt(usable.length)];
      final moveData = moves[moveIdx - 1];
      final targetType = moveData is Map ? moveData['target']?.toString() : null;
      const noTargetTypes = {
        'allySide', 'self', 'all', 'allyTeam', 'foeSide', 'allAdjacent', 'allAdjacentFoes',
      };
      String act = 'move $moveIdx';
      if (!(targetType != null && noTargetTypes.contains(targetType))) {
        // Random valid target: p1a or p1b (opposing slots), rarely -2 (ally) if relevant.
        final targets = ['1', '2'];
        act += ' ${targets[_rng.nextInt(targets.length)]}';
      }
      final canMega = active[slot] is Map && (active[slot]['canMegaEvo'] == true);
      bool willMega = false;
      if (canMega && !_p2HasMegaEvolved && _rng.nextDouble() < 0.75) {
        act += ' mega';
        willMega = true;
      }
      slotActions.add(act);
      if (willMega) {
        _p2HasMegaEvolved = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          setState(() {
            _rawLogs.add('|debug-p2-action| slot $slot chose to Mega Evolve');
          });
        });
      }
    }
    return '>p2 ${slotActions.join(', ')}';
  }

  List<dynamic> _getAvailableSwitches() {
    if (_currentRequest == null || !_currentRequest!.containsKey('side')) return [];
    final pokemonList = _currentRequest!['side']?['pokemon'] as List<dynamic>? ?? [];
    List<Map<String, dynamic>> choices = [];
    for (int i = 0; i < pokemonList.length; i++) {
      final p = pokemonList[i];
      if (!(p['active'] ?? false) && !(p['condition']?.toString().startsWith('0') ?? false)) {
        choices.add({
          'slot': i + 1,
          'name': p['details']?.toString().split(',')[0] ?? 'Unknown',
          'condition': p['condition'] ?? '',
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
        TextField(
          controller: _p1TeamController,
          maxLines: 5,
          style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
          decoration: const InputDecoration(
            labelText: 'Player 1 Team Sheet',
            hintText: 'Species @ Item\nAbility: X\nLevel: 50\nNature\n- Move 1\n- Move 2',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        const Text('Player 2 Team (Computer AI)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.redAccent)),
        const SizedBox(height: 4),
        TextField(
          controller: _p2TeamController,
          maxLines: 5,
          style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
          decoration: const InputDecoration(
            labelText: 'Computer Team Sheet',
            hintText: 'Species @ Item\nAbility: X\nLevel: 50\nNature\n- Move 1\n- Move 2',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton.icon(
            onPressed: _handleTeamSubmission,
            style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurple),
            icon: const Icon(Icons.play_arrow, color: Colors.white),
            label: const Text('Start PvC Battle', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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
            final monData = _p1TeamList[index];
            final monName = monData is Map ? (monData['details']?.toString().split(',')[0] ?? 'Pokémon $slotIndex') : 'Pokémon $slotIndex';
            final selectedPos = _selectedPreviewSlots.indexOf(slotIndex);
            final String posText = selectedPos == -1
                ? 'Not selected'
                : (selectedPos < 2 ? 'Lead Position ${selectedPos + 1}' : 'Back Position ${selectedPos - 1}');

            return InkWell(
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
            );
          },
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          height: 44,
          child: ElevatedButton(
            onPressed: _selectedPreviewSlots.length >= 2 ? _confirmTeamPreviewSelection : null,
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green[700]),
            child: Text('Confirm Selection (${_selectedPreviewSlots.length}/${_p1TeamList.length})'),
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
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 6,
          mainAxisSpacing: 6,
          childAspectRatio: 2.6,
          children: [
            _buildMonPanel('p2a', 'Computer 1', Colors.redAccent),
            _buildMonPanel('p2b', 'Computer 2', Colors.redAccent),
            _buildMonPanel('p1a', 'Player 1', Colors.blueAccent),
            _buildMonPanel('p1b', 'Player 2', Colors.blueAccent),
          ],
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
                  Text(
                    isForceSwitch ? 'Select Replacement Pokémon' : 'Select Player Turn Actions',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  Builder(builder: (context) {
                    // DEBUG: verify mega eligibility inputs, visible in-app
                    if (activeList.isNotEmpty && (_rawLogs.isEmpty || !_rawLogs.last.startsWith('|debug-mega-check|'))) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        setState(() {
                          _rawLogs.add('|debug-mega-check| p1HasMegaEvolved=$_p1HasMegaEvolved canMegaEvoSlot0=${activeList[0]['canMegaEvo']} canMegaEvoSlot1=${activeList.length > 1 ? activeList[1]['canMegaEvo'] : 'n/a'}');
                        });
                      });
                    }
                    final forceList = (isForceSwitch && _currentRequest != null)
                        ? (_currentRequest!['forceSwitch'] as List<dynamic>? ?? [])
                        : [];
                    final slot1NeedsSwitch = !isForceSwitch || (forceList.isNotEmpty && forceList[0] == true);
                    final slot2NeedsSwitch = isForceSwitch && forceList.length > 1 && forceList[1] == true;
                    final slot2Exists = activeList.length > 1 || (isForceSwitch && forceList.length > 1);

                    return Column(
                      children: [
                        if (slot1NeedsSwitch)
                          _buildSlotActionControl(
                            slotNumber: 1,
                            slotTitle: 'Slot 1 (${_activeNames['p1a'] ?? 'Active 1'})',
                            moves: movesSlot1,
                            switches: availableSwitches,
                            isForceSwitch: isForceSwitch,
                            isSwitch: _s1IsSwitch,
                            selectedMove: _s1MoveChoice,
                            selectedTarget: _s1Target,
                            selectedSwitch: _s1SwitchChoice,
                            isMega: _s1Mega,
                            canMega: !_p1HasMegaEvolved && activeList.isNotEmpty && (activeList[0]['canMegaEvo'] == true),
                            onToggleSwitch: (v) => setState(() => _s1IsSwitch = v),
                            onMoveChanged: (v) => setState(() => _s1MoveChoice = v ?? 1),
                            onTargetChanged: (v) => setState(() => _s1Target = v ?? 1),
                            onSwitchChanged: (v) => setState(() => _s1SwitchChoice = v ?? 1),
                            onMegaToggled: (v) => setState(() => _s1Mega = v),
                          ),
                        if (slot2Exists && (!isForceSwitch || slot2NeedsSwitch)) ...[
                          const Divider(height: 16),
                          _buildSlotActionControl(
                            slotNumber: 2,
                            slotTitle: 'Slot 2 (${_activeNames['p1b'] ?? 'Active 2'})',
                            moves: movesSlot2,
                            switches: availableSwitches,
                            isForceSwitch: isForceSwitch,
                            isSwitch: _s2IsSwitch,
                            selectedMove: _s2MoveChoice,
                            selectedTarget: _s2Target,
                            selectedSwitch: _s2SwitchChoice,
                            isMega: _s2Mega,
                            canMega: !_p1HasMegaEvolved && activeList.length > 1 && (activeList[1]['canMegaEvo'] == true),
                            onToggleSwitch: (v) => setState(() => _s2IsSwitch = v),
                            onMoveChanged: (v) => setState(() => _s2MoveChoice = v ?? 1),
                            onTargetChanged: (v) => setState(() => _s2Target = v ?? 1),
                            onSwitchChanged: (v) => setState(() => _s2SwitchChoice = v ?? 1),
                            onMegaToggled: (v) => setState(() => _s2Mega = v),
                          ),
                        ],
                      ],
                    );
                  }),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isWaiting ? null : _sendTurnCommands,
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.green[700]),
                      child: const Text('Submit Actions (Trigger AI)', style: TextStyle(color: Colors.white)),
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
    required int slotNumber, // 1 or 2, used to route the target overlay
  }) {
    if (isForceSwitch) {
      // Forced switches get their own dedicated overlay — see _showForcedSwitchOverlay.
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Expanded(child: Text('$slotTitle needs a replacement', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold))),
            ElevatedButton(
              onPressed: () => _showForcedSwitchOverlay(
                slotNumber: slotNumber,
                switches: switches,
                onSwitchChanged: onSwitchChanged,
              ),
              child: Text(selectedSwitch > 0 ? 'Switching to #$selectedSwitch' : 'Choose Switch-In'),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(slotTitle, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
        const SizedBox(height: 6),

        if (isSwitch) ...[
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: switches.map((s) {
              final slot = s['slot'] as int;
              final selected = slot == selectedSwitch;
              return ElevatedButton(
                onPressed: () => onSwitchChanged(slot),
                style: ElevatedButton.styleFrom(
                  backgroundColor: selected ? Colors.blue[700] : Colors.grey[800],
                ),
                child: Text('${s['name']} (${s['condition']})', style: const TextStyle(fontSize: 11)),
              );
            }).toList(),
          ),
          const SizedBox(height: 6),
          TextButton(
            onPressed: () => onToggleSwitch(false),
            child: const Text('Use a Move Instead', style: TextStyle(fontSize: 11)),
          ),
        ] else if (moves.isEmpty) ...[
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('Waiting for move data...', style: TextStyle(fontSize: 11, color: Colors.grey)),
          ),
        ] else ...[
          _buildCompactMoveGrid(
            moves: moves,
            selectedMove: selectedMove,
            slotNumber: slotNumber,
            canMega: canMega,
            isMega: isMega,
            canSwitch: switches.isNotEmpty,
            onMoveChanged: onMoveChanged,
            onTargetChanged: onTargetChanged,
            selectedTarget: selectedTarget,
            onMegaToggled: onMegaToggled,
            onToggleSwitch: onToggleSwitch,
          ),
          if (moves.isNotEmpty && selectedMove > 0 && selectedMove <= moves.length && _moveNeedsTargetForOverlay(moves[selectedMove - 1]))
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Semantics(
                label: 'Selected target: ${_targetLabel(selectedTarget)}',
                child: Text(
                  'Target: ${_targetLabel(selectedTarget)}',
                  style: const TextStyle(fontSize: 11, color: Colors.amberAccent),
                ),
              ),
            ),
        ],
      ],
    );
  }

  // Compact 2-row, 3-column grid: [Move1] [Move2] [Mega/blank]
  //                                [Move3] [Move4] [Switch/blank]
  Widget _buildCompactMoveGrid({
    required List<dynamic> moves,
    required int selectedMove,
    required int slotNumber,
    required bool canMega,
    required bool isMega,
    required bool canSwitch,
    required ValueChanged<int?> onMoveChanged,
    required ValueChanged<int?> onTargetChanged,
    required int selectedTarget,
    required ValueChanged<bool> onMegaToggled,
    required ValueChanged<bool> onToggleSwitch,
  }) {
    Widget buildMoveCell(int idx) {
      if (idx >= moves.length) return const SizedBox.shrink();
      final m = moves[idx];
      final moveNum = idx + 1;
      final moveName = m is Map ? (m['move'] ?? 'Move $moveNum') : 'Move $moveNum';
      final disabled = m is Map && (m['disabled'] == true);
      final selected = moveNum == selectedMove;
      return Semantics(
        button: true,
        label: disabled ? '$moveName, disabled' : (selected ? '$moveName, selected' : moveName),
        child: ElevatedButton(
          onPressed: disabled
              ? null
              : () {
                  onMoveChanged(moveNum);
                  if (_moveNeedsTargetForOverlay(m)) {
                    _showTargetOverlay(
                      slotNumber: slotNumber,
                      moveIdx: moveNum,
                      onTargetChanged: onTargetChanged,
                      currentTarget: selectedTarget,
                    );
                  } else {
                    onTargetChanged(null);
                  }
                },
          style: ElevatedButton.styleFrom(
            backgroundColor: disabled ? Colors.grey[900] : (selected ? Colors.green[700] : Colors.grey[800]),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
            minimumSize: const Size(0, 40),
          ),
          child: Text(
            disabled ? '$moveName ✕' : moveName,
            style: TextStyle(fontSize: 11, color: disabled ? Colors.grey : null),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      );
    }

    Widget megaCell() {
      if (!canMega) return const SizedBox.shrink();
      return Semantics(
        button: true,
        checked: isMega,
        label: isMega ? 'Mega Evolve, enabled' : 'Mega Evolve, disabled. Double tap to toggle.',
        child: InkWell(
          onTap: () => onMegaToggled(!isMega),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
            decoration: BoxDecoration(
              color: isMega ? Colors.purple.withOpacity(0.35) : Colors.purple.withOpacity(0.1),
              border: Border.all(color: Colors.purpleAccent, width: 1.5),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(isMega ? Icons.check_box : Icons.check_box_outline_blank, size: 16, color: Colors.purpleAccent),
                const SizedBox(width: 3),
                const Flexible(
                  child: Text('MEGA', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.purpleAccent), overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
          ),
        ),
      );
    }

    Widget switchCell() {
      if (!canSwitch) return const SizedBox.shrink();
      return Semantics(
        button: true,
        label: 'Switch Out instead of using a move',
        child: OutlinedButton(
          onPressed: () => onToggleSwitch(true),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
            minimumSize: const Size(0, 40),
          ),
          child: const Text('SWITCH', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
        ),
      );
    }

    return Table(
      columnWidths: const {
        0: FlexColumnWidth(1),
        1: FlexColumnWidth(1),
        2: FlexColumnWidth(1),
      },
      children: [
        TableRow(children: [
          Padding(padding: const EdgeInsets.all(3), child: buildMoveCell(0)),
          Padding(padding: const EdgeInsets.all(3), child: buildMoveCell(1)),
          Padding(padding: const EdgeInsets.all(3), child: megaCell()),
        ]),
        TableRow(children: [
          Padding(padding: const EdgeInsets.all(3), child: buildMoveCell(2)),
          Padding(padding: const EdgeInsets.all(3), child: buildMoveCell(3)),
          Padding(padding: const EdgeInsets.all(3), child: switchCell()),
        ]),
      ],
    );
  }

  String _targetLabel(int target) {
    final p2aName = _activeNames['p2a'] ?? 'Opponent 1';
    final p2bName = _activeNames['p2b'] ?? 'Opponent 2';
    switch (target) {
      case 1: return '$p2aName (Opponent)';
      case 2: return '$p2bName (Opponent)';
      case -2: return 'Ally';
      default: return 'Unset';
    }
  }

  bool _moveNeedsTargetForOverlay(dynamic moveData) {
    final target = moveData is Map ? moveData['target']?.toString() : null;
    const noTargetTypes = {
      'allySide', 'self', 'all', 'allyTeam', 'foeSide', 'allAdjacent', 'allAdjacentFoes',
    };
    return !(target != null && noTargetTypes.contains(target));
  }

  void _showTargetOverlay({
    required int slotNumber,
    required int moveIdx,
    required ValueChanged<int?> onTargetChanged,
    required int currentTarget,
  }) {
    // Build labeled options using real Pokémon names where available.
    final p2aName = _activeNames['p2a'] ?? 'Opponent 1';
    final p2bName = _activeNames['p2b'] ?? 'Opponent 2';
    final allyName = slotNumber == 1
        ? (_activeNames['p1b'] ?? 'Ally')
        : (_activeNames['p1a'] ?? 'Ally');

    final options = <Map<String, dynamic>>[
      {'label': '$p2aName (Opponent)', 'value': 1},
      {'label': '$p2bName (Opponent)', 'value': 2},
      {'label': '$allyName (Ally)', 'value': -2},
    ];

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Choose Target — Slot $slotNumber', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 12),
              ...options.map((opt) {
                final val = opt['value'] as int;
                final selected = currentTarget == val;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Semantics(
                    button: true,
                    label: selected ? '${opt['label']}, currently selected' : opt['label'] as String,
                    child: ElevatedButton(
                      onPressed: () {
                        onTargetChanged(val);
                        Navigator.of(context).pop();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: selected ? Colors.green[700] : Colors.grey[800],
                        minimumSize: const Size(double.infinity, 44),
                      ),
                      child: Text(opt['label'] as String),
                    ),
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }

  void _showForcedSwitchOverlay({
    required int slotNumber,
    required List<dynamic> switches,
    required ValueChanged<int?> onSwitchChanged,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      isScrollControlled: true,
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Forced Switch — Slot $slotNumber', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 4),
              const Text('Your Pokémon fainted or was forced out. Choose a replacement.',
                  style: TextStyle(fontSize: 11, color: Colors.grey)),
              const SizedBox(height: 12),
              ...switches.map((s) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: ElevatedButton(
                    onPressed: () {
                      onSwitchChanged(s['slot'] as int);
                      Navigator.of(context).pop();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.grey[800],
                      minimumSize: const Size(double.infinity, 44),
                    ),
                    child: Text('${s['name']} (${s['condition']})'),
                  ),
                );
              }),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Return (no selection)'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
  static const Map<String, Color> _typeColors = {
    'Normal': Color(0xFFA8A878), 'Fire': Color(0xFFF08030), 'Water': Color(0xFF6890F0),
    'Electric': Color(0xFFF8D030), 'Grass': Color(0xFF78C850), 'Ice': Color(0xFF98D8D8),
    'Fighting': Color(0xFFC03028), 'Poison': Color(0xFFA040A0), 'Ground': Color(0xFFE0C068),
    'Flying': Color(0xFFA890F0), 'Psychic': Color(0xFFF85888), 'Bug': Color(0xFFA8B820),
    'Rock': Color(0xFFB8A038), 'Ghost': Color(0xFF705898), 'Dragon': Color(0xFF7038F8),
    'Dark': Color(0xFF705848), 'Steel': Color(0xFFB8B8D0), 'Fairy': Color(0xFFEE99AC),
  };

  static const Map<String, Color> _statusColors = {
    'brn': Colors.deepOrange, 'par': Colors.amber, 'psn': Colors.purple,
    'tox': Colors.purple, 'slp': Colors.indigo, 'frz': Colors.cyan,
  };

  static const Map<String, String> _statusLabels = {
    'brn': 'BRN', 'par': 'PAR', 'psn': 'PSN', 'tox': 'TOX', 'slp': 'SLP', 'frz': 'FRZ',
  };

  Widget _buildMonPanel(String slotKey, String sideLabel, Color color) {
    final name = _activeNames[slotKey] ?? 'Active Mon';
    final hp = _activeHp[slotKey] ?? '100/100';
    final types = _activeTypes[slotKey] ?? [];
    final status = _activeStatus[slotKey] ?? '';

    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Colors.grey[850],
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.4), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(sideLabel, style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: color)),
          Row(
            children: [
              Expanded(child: Text(name, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
              if (status.isNotEmpty && _statusLabels.containsKey(status))
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                  margin: const EdgeInsets.only(left: 3),
                  decoration: BoxDecoration(
                    color: _statusColors[status] ?? Colors.grey,
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(_statusLabels[status]!, style: const TextStyle(fontSize: 7, color: Colors.white, fontWeight: FontWeight.bold)),
                ),
            ],
          ),
          Text('HP: $hp', style: const TextStyle(fontSize: 9, fontFamily: 'monospace')),
          if (types.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Wrap(
                spacing: 2,
                runSpacing: 2,
                children: types.map((t) {
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: _typeColors[t] ?? Colors.grey,
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text(t, style: const TextStyle(fontSize: 7, color: Colors.white, fontWeight: FontWeight.bold)),
                  );
                }).toList(),
              ),
            ),
        ],
      ),
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
              final types = _activeTypes[slot] ?? [];
              final status = _activeStatus[slot] ?? '';
              return Expanded(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(color: Colors.grey[850], borderRadius: BorderRadius.circular(6)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(child: Text(name, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold))),
                          if (status.isNotEmpty && _statusLabels.containsKey(status))
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                              margin: const EdgeInsets.only(left: 4),
                              decoration: BoxDecoration(
                                color: _statusColors[status] ?? Colors.grey,
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: Text(_statusLabels[status]!, style: const TextStyle(fontSize: 8, color: Colors.white, fontWeight: FontWeight.bold)),
                            ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text('HP: $hp', style: const TextStyle(fontSize: 9, fontFamily: 'monospace')),
                      if (types.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Wrap(
                          spacing: 3,
                          children: types.map((t) {
                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: _typeColors[t] ?? Colors.grey,
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: Text(t, style: const TextStyle(fontSize: 8, color: Colors.white, fontWeight: FontWeight.bold)),
                            );
                          }).toList(),
                        ),
                      ],
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
      child: Column(
        children: [
          Expanded(
            child: ListView.builder(
              itemCount: _rawLogs.length,
              itemBuilder: (context, index) {
                return Text(_rawLogs[index], style: const TextStyle(color: Colors.greenAccent, fontFamily: 'monospace', fontSize: 10));
              },
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton(
                onPressed: _showTurnHistoryDialog,
                child: const Text('View Turn History', style: TextStyle(fontSize: 10)),
              ),
              TextButton(
                onPressed: _showFullLogDialog,
                child: const Text('View Full Log', style: TextStyle(fontSize: 10)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showTurnHistoryDialog() {
    if (_turnHistory.isNotEmpty) {
      // Jump straight to the most recently completed turn instead of
      // making the person tap through the list every time.
      _showTurnDetailDialog(_turnHistory.last, showBackToList: true);
      return;
    }
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Turn History'),
        content: const SizedBox(
          width: double.maxFinite,
          height: 100,
          child: Text('No turns recorded yet.'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showTurnListDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Turn History'),
        content: SizedBox(
          width: double.maxFinite,
          height: 400,
          child: ListView.builder(
            itemCount: _turnHistory.length,
            itemBuilder: (context, index) {
              final entry = _turnHistory[index];
              return ListTile(
                title: Text('Turn ${entry['turn']}'),
                onTap: () {
                  Navigator.of(context).pop();
                  _showTurnDetailDialog(entry, showBackToList: true);
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showTurnDetailDialog(Map<String, dynamic> entry, {bool showBackToList = false}) {
    final rawLines = entry['lines'] as List<String>;
    final humanLinesRaw = rawLines
        .where((l) =>
            l.isNotEmpty &&
            !l.startsWith('|debug') &&
            !l.startsWith('|request') &&
            !l.startsWith('|t:') &&
            !l.startsWith('|error|'))
        .map(_humanizeLogLine)
        .where((l) => l.trim().isNotEmpty)
        .toList();

    // Showdown's |split| protocol directive sends the following line twice
    // (once per viewer perspective) — collapse immediate consecutive
    // duplicates so switch-ins / HP updates don't appear twice in the UI.
    final humanLines = <String>[];
    for (final line in humanLinesRaw) {
      if (humanLines.isEmpty || humanLines.last != line) {
        humanLines.add(line);
      }
    }
    final lines = humanLines.join('\n');
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Turn ${entry['turn']} Log'),
        content: SizedBox(
          width: double.maxFinite,
          height: 500,
          child: SingleChildScrollView(
            child: SelectableText(lines, style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
          ),
        ),
        actions: [
          if (showBackToList)
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _showTurnListDialog();
              },
              child: const Text('Browse All Turns'),
            ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showFullLogDialog() {
    final fullLog = _rawLogs.join('\n');
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Full Battle Log'),
        content: SizedBox(
          width: double.maxFinite,
          height: 500,
          child: SingleChildScrollView(
            child: SelectableText(
              fullLog,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
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
