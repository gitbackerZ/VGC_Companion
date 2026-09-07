import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_js/flutter_js.dart';

class JsEngineService {
  static final JsEngineService _instance = JsEngineService._internal();
  factory JsEngineService() => _instance;
  JsEngineService._internal();

  JavascriptRuntime? _jsRuntime;
  bool _isInitialized = false;

  /// Holds the most recent diagnostic info from getBaseSpeciesList(), so it
  /// can be surfaced on-screen when testing directly on-device (no
  /// attached debug console to read debugPrint from).
  String? lastDiagnostics;

  /// Captures init()'s own failure reason, since debugPrint alone isn't
  /// visible when testing a standalone on-device build with no attached
  /// debug console.
  String? lastInitError;

  // Reference-counted lifecycle: multiple screens (Team Builder, Offline
  // Battle) share this one runtime. init() is idempotent and increments
  // the count; release() decrements it and only tears down the runtime
  // once nobody else is holding a reference.
  int _refCount = 0;

  /// Exposes the raw runtime for callers (e.g. OfflineBattleScreen) that
  /// need to evaluate battle-flow-specific scripts (starting a battle,
  /// sending actions, polling logs) not covered by this service's own
  /// higher-level Dex-lookup methods.
  JavascriptRuntime? get runtime => _jsRuntime;

  Future<void> init() async {
    _refCount++;
    if (_isInitialized) return;

    _jsRuntime = getJavascriptRuntime();

    try {
      final engineJs = await rootBundle.loadString('assets/engine.js');

      // Full polyfill set — merged from the offline battle screen's
      // requirements (setImmediate/queueMicrotask/TextEncoder/TextDecoder/
      // full dummyModules map for path/util/os/events/buffer) plus the
      // original lighter Team-Builder-oriented set. engine.js is shared by
      // both screens now, so it needs to satisfy whichever caller has the
      // heavier requirements (the battle simulator).
      const String polyfills = '''
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

      _jsRuntime!.evaluate(polyfills);

      final engineEval = _jsRuntime!.evaluate(engineJs);
      if (engineEval.isError) {
        throw Exception('engine.js execution error: ${engineEval.stringResult}');
      }

      // engine.js exposes globalThis.PSSim = { Battle, Dex, Teams, PRNG } —
      // not a bare global `Dex`. Bridge it so every script below (which
      // references a bare `Dex`) keeps working unmodified.
      final bridgeEval = _jsRuntime!.evaluate('''
        if (globalThis.PSSim && globalThis.PSSim.Dex && !globalThis.Dex) {
          globalThis.Dex = globalThis.PSSim.Dex;
        }
        if (globalThis.Dex && globalThis.PSStaticData && globalThis.PSStaticData.base) {
          globalThis.Dex.data = globalThis.Dex.data || {};
          if (!globalThis.Dex.data.Learnsets) {
            globalThis.Dex.data.Learnsets = globalThis.PSStaticData.base.learnsets || {};
          }
        }
        Boolean(globalThis.Dex);
      ''');
      if (bridgeEval.isError || bridgeEval.stringResult != 'true') {
        throw Exception('Failed to bridge PSSim.Dex to global Dex: ${bridgeEval.stringResult}');
      }

      _isInitialized = true;
      lastInitError = null;
    } catch (e, stack) {
      lastInitError = 'INIT FAILED: $e\nSTACK: $stack';
      debugPrint('Error initializing JS Engine: $e\n$stack');
    }
  }

  bool get isReady => _isInitialized && _jsRuntime != null;

  String _toId(String text) => text.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  /// Call this instead of holding onto the runtime forever. Decrements the
  /// reference count and only actually tears down the JS runtime once no
  /// screen is using it anymore.
  void release() {
    if (_refCount > 0) _refCount--;
    if (_refCount == 0 && _jsRuntime != null) {
      _jsRuntime!.dispose();
      _jsRuntime = null;
      _isInitialized = false;
    }
  }

  /// Deprecated alias — kept so existing call sites (dispose()) don't need
  /// an immediate rename; forwards to release().
  void dispose() => release();

  /// Direct Showdown lookup to find Mega or Primal form matching a held item
  Future<String?> getMegaFormForHeldItem(String speciesName, String heldItem) async {
    if (!isReady || heldItem.trim().isEmpty) return null;
    final sanitizedSpecies = _toId(speciesName);
    final sanitizedItem = _toId(heldItem);

    final script = '''
      (function() {
        var base = Dex.species.get("$sanitizedSpecies");
        if (!base || !base.exists) return null;
        if (base.isMega || (base.forme && base.forme.indexOf('Mega') !== -1)) {
          base = Dex.species.get(base.baseSpecies || "$sanitizedSpecies");
        }
        if (!base || !base.otherFormes) return null;

        for (var i = 0; i < base.otherFormes.length; i++) {
          var fSpec = Dex.species.get(base.otherFormes[i]);
          if (!fSpec || !fSpec.exists) continue;
          
          var reqItem = (fSpec.requiredItem || '').toLowerCase().replace(/[^a-z0-9]/g, '');
          var reqItems = (fSpec.requiredItems || []).map(function(x) {
            return x.toLowerCase().replace(/[^a-z0-9]/g, '');
          });
          
          if (reqItem === "$sanitizedItem" || reqItems.indexOf("$sanitizedItem") !== -1) {
            return fSpec.name;
          }
        }
        return null;
      })()
    ''';

    final result = _jsRuntime!.evaluate(script);
    if (result.isError || result.stringResult == 'null' || result.stringResult.isEmpty) return null;
    try {
      final decoded = json.decode(result.stringResult);
      return decoded?.toString();
    } catch (_) {
      return result.stringResult.replaceAll('"', '');
    }
  }

  Future<List<String>> getItemList() async {
    if (!isReady) return [];
    final script = '''
      (function() {
        if (!Dex || !Dex.items) return JSON.stringify([]);

        var itemKeys = (globalThis.PSStaticData && globalThis.PSStaticData.base && globalThis.PSStaticData.base.items)
          ? Object.keys(globalThis.PSStaticData.base.items)
          : [];

        var result = [];
        for (var i = 0; i < itemKeys.length; i++) {
          var item = Dex.items.get(itemKeys[i]);
          if (!item || !item.exists) continue;

          var isPastGen = item.isNonstandard === 'Past';
          var isMegaStone = !!item.megaStone || !!item.megaEvolves;
          var isStandard = !item.isNonstandard;

          if (isStandard || isPastGen || isMegaStone) {
            result.push(item.name);
          }
        }
        return JSON.stringify(result);
      })()
    ''';
    final result = _jsRuntime!.evaluate(script);
    if (result.isError) return [];
    final List<dynamic> list = json.decode(result.stringResult);
    return list.cast<String>();
  }

  Future<List<Map<String, dynamic>>> getBaseSpeciesList() async {
    if (!isReady) {
      lastDiagnostics = 'NOT READY. initError=${lastInitError ?? "(none captured — init() may not have been awaited/called yet)"}';
      return [];
    }
    final script = '''
      (function() {
        var diag = {};
        diag.dexExists = !!Dex;
        diag.dexSpeciesExists = !!(Dex && Dex.species);
        diag.psStaticDataExists = !!globalThis.PSStaticData;
        diag.baseExists = !!(globalThis.PSStaticData && globalThis.PSStaticData.base);
        diag.pokedexExists = !!(globalThis.PSStaticData && globalThis.PSStaticData.base && globalThis.PSStaticData.base.pokedex);

        if (!Dex || !Dex.species) return JSON.stringify({error: 'no-dex', diag: diag});

        var pokedexKeys = (globalThis.PSStaticData && globalThis.PSStaticData.base && globalThis.PSStaticData.base.pokedex)
          ? Object.keys(globalThis.PSStaticData.base.pokedex)
          : [];
        diag.pokedexKeyCount = pokedexKeys.length;
        diag.firstFewKeys = pokedexKeys.slice(0, 5);

        if (pokedexKeys.length === 0) {
          return JSON.stringify({error: 'no-keys', diag: diag});
        }

        // Try resolving the very first key and capture what happens.
        var testKey = pokedexKeys[0];
        var testSpec = null;
        var testError = null;
        try {
          testSpec = Dex.species.get(testKey);
        } catch (e) {
          testError = e && e.message ? e.message : String(e);
        }
        diag.testKey = testKey;
        diag.testSpecExists = !!(testSpec && testSpec.exists);
        diag.testSpecName = testSpec ? testSpec.name : null;
        diag.testError = testError;

        var results = [];
        var seenNum = {};

        for (var i = 0; i < pokedexKeys.length; i++) {
          var spec;
          try {
            spec = Dex.species.get(pokedexKeys[i]);
          } catch (e) {
            continue;
          }
          if (!spec || !spec.exists || spec.num <= 0) continue;

          var isMega = spec.forme && spec.forme.indexOf('Mega') !== -1;
          var isGmax = spec.forme && spec.forme.indexOf('Gmax') !== -1;
          if (isMega || isGmax) continue;

          if (!spec.forme && !seenNum[spec.num]) {
            seenNum[spec.num] = true;
            results.push({
              'name': spec.name,
              'num': spec.num,
              'types': spec.types || [],
              'hasFormes': !!(spec.otherFormes && spec.otherFormes.length > 0)
            });
          }
        }

        diag.resultCount = results.length;
        return JSON.stringify({results: results, diag: diag});
      })()
    ''';
    final result = _jsRuntime!.evaluate(script);
    if (result.isError) {
      lastDiagnostics = 'JS EVAL ERROR: ${result.stringResult}';
      return [];
    }

    try {
      final decoded = json.decode(result.stringResult);
      if (decoded is Map) {
        lastDiagnostics = decoded['diag']?.toString() ?? 'no diag';
        if (decoded['error'] != null) {
          lastDiagnostics = 'ERROR: ${decoded['error']} | diag: $lastDiagnostics';
          return [];
        }
        final List<dynamic> list = decoded['results'] as List<dynamic>? ?? [];
        return list.cast<Map<String, dynamic>>();
      }
      final List<dynamic> list = decoded as List<dynamic>;
      return list.cast<Map<String, dynamic>>();
    } catch (e) {
      lastDiagnostics = 'PARSE ERROR: $e | raw: ${result.stringResult}';
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getFormesForSpecies(String baseName) async {
    if (!isReady) return [];
    final sanitized = _toId(baseName);
    final script = '''
      (function() {
        var base = Dex.species.get("$sanitized");
        if (!base || !base.exists) return JSON.stringify([]);
        
        var list = [base];
        if (base.otherFormes) {
          for (var i = 0; i < base.otherFormes.length; i++) {
            var fName = base.otherFormes[i];
            if (fName.indexOf('Mega') !== -1 || fName.indexOf('Gmax') !== -1) continue;
            var fSpec = Dex.species.get(fName);
            if (fSpec && fSpec.exists) list.push(fSpec);
          }
        }
        return JSON.stringify(list.map(function(s) {
          return {
            'name': s.name,
            'num': s.num,
            'forme': s.forme || 'Base',
            'types': s.types || []
          };
        }));
      })()
    ''';
    final result = _jsRuntime!.evaluate(script);
    if (result.isError) return [];
    final List<dynamic> list = json.decode(result.stringResult);
    return list.cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> getMegaFormes(String speciesName) async {
    if (!isReady) return [];
    final sanitized = _toId(speciesName);
    final script = '''
      (function() {
        var base = Dex.species.get("$sanitized");
        if (!base || !base.exists) return JSON.stringify([]);
        
        if (base.isMega || (base.forme && base.forme.indexOf('Mega') !== -1)) {
          base = Dex.species.get(base.baseSpecies || "$sanitized");
        }
        
        var megas = [];
        if (base.otherFormes) {
          for (var i = 0; i < base.otherFormes.length; i++) {
            var fSpec = Dex.species.get(base.otherFormes[i]);
            if (fSpec && fSpec.exists && (fSpec.isMega || (fSpec.forme && fSpec.forme.indexOf('Mega') !== -1))) {
              megas.push({
                'name': fSpec.name,
                'num': fSpec.num,
                'types': fSpec.types || [],
                'requiredItem': fSpec.requiredItem || fSpec.requiredMove || ''
              });
            }
          }
        }
        return JSON.stringify(megas);
      })()
    ''';
    final result = _jsRuntime!.evaluate(script);
    if (result.isError) return [];
    final List<dynamic> list = json.decode(result.stringResult);
    return list.cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> getPokemon(String name) async {
    if (!isReady) throw Exception('JsEngineService is not initialized');
    final sanitized = _toId(name);
    final result = _jsRuntime!.evaluate('JSON.stringify(Dex.species.get("$sanitized"))');
    if (result.isError) throw Exception('Failed to get species data for $name');
    return json.decode(result.stringResult) as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> getMovesForSpecies(String name) async {
    if (!isReady) return [];
    try {
      final sanitized = _toId(name);
      final script = '''
        (function() {
          try {
            var species = Dex.species.get("$sanitized");
            if (!species || !species.exists) return JSON.stringify([]);

            var moveIdSet = {};
            var current = species;
            var seen = {};
            var guard = 0;

            while (current && guard < 10) {
              guard++;
              if (seen[current.id]) break;
              seen[current.id] = true;

              var learnsetData = Dex.data.Learnsets ? Dex.data.Learnsets[current.id] : null;
              if (learnsetData && learnsetData.learnset) {
                var ids = Object.keys(learnsetData.learnset);
                for (var i = 0; i < ids.length; i++) moveIdSet[ids[i]] = true;
              }

              if (current.prevo) {
                current = Dex.species.get(current.prevo);
              } else if (current.baseSpecies && current.baseSpecies !== current.name) {
                current = Dex.species.get(current.baseSpecies);
              } else {
                current = null;
              }
            }

            var moveIds = Object.keys(moveIdSet);
            var moves = moveIds
              .map(function(mid) { return Dex.moves.get(mid); })
              .filter(function(m) { return m && m.exists && !m.isNonstandard; });

            return JSON.stringify(moves);
          } catch (e) {
            return JSON.stringify([]);
          }
        })()
      ''';

      final result = _jsRuntime!.evaluate(script);
      if (result.isError) return [];
      final decoded = json.decode(result.stringResult);
      if (decoded is! List) return [];

      return decoded
          .whereType<Map>()
          .map((m) => m.cast<String, dynamic>())
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getAbilitiesForPokemon(String name) async {
    try {
      final data = await getPokemon(name);
      final raw = data['abilities'];
      if (raw is Map) {
        return raw.values.map((a) => {'name': a.toString()}).toList();
      }
      if (raw is List) {
        return raw.map((a) => {'name': a.toString()}).toList();
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  Future<int> getGenderRate(String name) async {
    try {
      final data = await getPokemon(name);
      if (data['gender'] == 'N') return -1;
      if (data['gender'] == 'M') return 0;
      if (data['gender'] == 'F') return 8;

      if (data.containsKey('genderRatio') && data['genderRatio'] is Map) {
        final ratioMap = data['genderRatio'] as Map<String, dynamic>;
        if (ratioMap.containsKey('F')) {
          final double f = (ratioMap['F'] as num).toDouble();
          return (f * 8).round();
        } else if (ratioMap.containsKey('M')) {
          final double m = (ratioMap['M'] as num).toDouble();
          return ((1.0 - m) * 8).round();
        }
      }
      return 4;
    } catch (_) {
      return 4;
    }
  }

  Future<Map<String, Map<String, int>>> getAllMegaBaseStats(String name) async {
    try {
      final cleanBaseName = _toId(name.split('-')[0]);
      final baseData = await getPokemon(cleanBaseName);
      final otherFormes = baseData['otherFormes'] as List? ?? [];

      Map<String, Map<String, int>> megaMap = {};
      for (final formName in otherFormes) {
        final formStr = formName.toString();
        if (formStr.contains('-mega')) {
          final formData = await getPokemon(formStr);
          if (formData['baseStats'] is Map) {
            final rawStats = formData['baseStats'] as Map<String, dynamic>;
            megaMap[formStr] = rawStats.map((k, v) => MapEntry(k, (v as num).toInt()));
          }
        }
      }
      return megaMap;
    } catch (_) {
      return {};
    }
  }

  Future<Map<String, String>> getNatureBoosts(String nature) async {
    if (!isReady) return {'plus': '', 'minus': ''};
    try {
      final sanitized = _toId(nature);
      final script = '''
        (function() {
          var statNames = {
            atk: 'Attack',
            def: 'Defense',
            spa: 'Sp. Atk',
            spd: 'Sp. Def',
            spe: 'Speed'
          };
          var n = Dex.natures.get("$sanitized");
          if (!n || !n.exists) return JSON.stringify({plus: '', minus: ''});
          return JSON.stringify({
            plus: statNames[n.plus] || '',
            minus: statNames[n.minus] || ''
          });
        })()
      ''';

      final result = _jsRuntime!.evaluate(script);
      if (result.isError) return {'plus': '', 'minus': ''};

      final decoded = json.decode(result.stringResult) as Map<String, dynamic>;
      return {
        'plus': decoded['plus']?.toString() ?? '',
        'minus': decoded['minus']?.toString() ?? '',
      };
    } catch (_) {
      return {'plus': '', 'minus': ''};
    }
  }
}
