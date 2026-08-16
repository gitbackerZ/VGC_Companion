import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_js/flutter_js.dart';

class JsEngineService {
  static final JsEngineService _instance = JsEngineService._internal();
  factory JsEngineService() => _instance;
  JsEngineService._internal();

  late JavascriptRuntime _jsRuntime;
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;

    _jsRuntime = getJavascriptRuntime();

    // Environment polyfills for Node/CommonJS/Browser JS bundles
    _jsRuntime.evaluate('''
      var global = globalThis;
      var window = globalThis;
      var module = { exports: {} };
      var exports = module.exports;
    ''');

    final script = await rootBundle.loadString('assets/engine.js');
    final result = _jsRuntime.evaluate(script);

    if (result.isError) {
      throw Exception('Failed to evaluate assets/engine.js: ${result.stringResult}');
    }

    // Bind Dex to globalThis regardless of export pattern used by engine.js
    _jsRuntime.evaluate('''
      (function() {
        if (typeof globalThis.Dex === 'undefined') {
          if (typeof Dex !== 'undefined') {
            globalThis.Dex = Dex;
          } else if (typeof module !== 'undefined' && module.exports) {
            if (module.exports.Dex) {
              globalThis.Dex = module.exports.Dex;
            } else if (module.exports.default && module.exports.default.Dex) {
              globalThis.Dex = module.exports.default.Dex;
            } else if (module.exports.species || module.exports.data) {
              globalThis.Dex = module.exports;
            }
          }
        }
      })();
    ''');

    _initialized = true;
  }

  /// Safely evaluates JS code and decodes the JSON payload.
  dynamic _evalJson(String jsCode) {
    final result = _jsRuntime.evaluate(jsCode);

    if (result.isError) {
      throw Exception('JS Runtime Error: ${result.stringResult}');
    }

    final rawString = result.stringResult;
    try {
      return jsonDecode(rawString);
    } catch (e) {
      throw Exception('JS Engine output invalid JSON ($rawString): $e');
    }
  }

  Future<List<String>> getSpeciesList() async {
    final decoded = _evalJson('''
      (function() {
        var dexObj = typeof Dex !== 'undefined' ? Dex : (typeof globalThis.Dex !== 'undefined' ? globalThis.Dex : null);
        if (!dexObj) {
          var modKeys = (typeof module !== 'undefined' && module.exports) ? Object.keys(module.exports).join(', ') : 'none';
          return JSON.stringify({ error: "Dex object is undefined. module.exports keys: [" + modKeys + "]" });
        }
        var speciesMap = dexObj.species || dexObj.data?.Species || dexObj.data?.Pokedex;
        if (!speciesMap) {
          return JSON.stringify({ error: "Dex species repository is undefined on Dex object." });
        }
        
        var list = [];
        if (typeof speciesMap.all === 'function') {
          list = speciesMap.all().map(function(s) { return s.name; });
        } else if (typeof speciesMap === 'object') {
          list = Object.keys(speciesMap).map(function(k) { 
            return speciesMap[k].name || speciesMap[k].species || k; 
          });
        }
        return JSON.stringify(list);
      })()
    ''');

    if (decoded is Map && decoded.containsKey('error')) {
      throw Exception(decoded['error']);
    }

    return List<String>.from(decoded);
  }

  Future<Map<String, dynamic>> getPokemon(String name) async {
    final decoded = _evalJson('''
      (function() {
        var dexObj = typeof Dex !== 'undefined' ? Dex : globalThis.Dex;
        if (!dexObj) return JSON.stringify({ error: "Dex undefined" });
        var speciesMap = dexObj.species || dexObj.data?.Species || dexObj.data?.Pokedex;
        var p = typeof speciesMap.get === 'function' ? speciesMap.get('$name') : speciesMap['$name'];
        if (!p) return JSON.stringify({ error: "Pokémon not found: $name" });
        return JSON.stringify({
          id: p.num || p.pokedexNumber || 0,
          name: p.name || '$name'
        });
      })()
    ''');

    if (decoded is Map && decoded.containsKey('error')) {
      throw Exception(decoded['error']);
    }

    return Map<String, dynamic>.from(decoded);
  }

  Future<List<Map<String, dynamic>>> getAbilitiesForPokemon(String name) async {
    final decoded = _evalJson('''
      (function() {
        var dexObj = typeof Dex !== 'undefined' ? Dex : globalThis.Dex;
        if (!dexObj) return JSON.stringify([]);
        var speciesMap = dexObj.species || dexObj.data?.Species || dexObj.data?.Pokedex;
        var p = typeof speciesMap.get === 'function' ? speciesMap.get('$name') : speciesMap['$name'];
        if (!p || !p.abilities) return JSON.stringify([]);
        
        var abilities = [];
        var abs = p.abilities;
        if (Array.isArray(abs)) {
          abilities = abs.map(function(a) { return { name: a }; });
        } else if (typeof abs === 'object') {
          Object.keys(abs).forEach(function(key) {
            if (abs[key]) abilities.push({ name: abs[key] });
          });
        }
        return JSON.stringify(abilities);
      })()
    ''');

    return List<Map<String, dynamic>>.from(decoded);
  }

  Future<List<String>> getMovesForPokemon(String name) async {
    final decoded = _evalJson('''
      (function() {
        var dexObj = typeof Dex !== 'undefined' ? Dex : globalThis.Dex;
        if (!dexObj) return JSON.stringify([]);
        var movesMap = dexObj.moves || dexObj.data?.Moves;
        if (!movesMap) return JSON.stringify([]);
        
        var list = [];
        if (typeof movesMap.all === 'function') {
          list = movesMap.all().map(function(m) { return m.name; });
        } else if (typeof movesMap === 'object') {
          list = Object.keys(movesMap).map(function(k) { return movesMap[k].name || k; });
        }
        return JSON.stringify(list);
      })()
    ''');

    return List<String>.from(decoded);
  }

  Future<int> getGenderRate(String name) async {
    final decoded = _evalJson('''
      (function() {
        var dexObj = typeof Dex !== 'undefined' ? Dex : globalThis.Dex;
        if (!dexObj) return JSON.stringify(4);
        var speciesMap = dexObj.species || dexObj.data?.Species || dexObj.data?.Pokedex;
        var p = typeof speciesMap.get === 'function' ? speciesMap.get('$name') : speciesMap['$name'];
        if (!p) return JSON.stringify(4);
        if (p.gender === 'N') return JSON.stringify(-1);
        if (p.gender === 'M') return JSON.stringify(0);
        if (p.gender === 'F') return JSON.stringify(8);
        if (p.genderRatio) {
          if (p.genderRatio.M === 1) return JSON.stringify(0);
          if (p.genderRatio.F === 1) return JSON.stringify(8);
        }
        return JSON.stringify(4);
      })()
    ''');

    return (decoded as num).toInt();
  }

  Future<Map<String, dynamic>> getNatureBoosts(String nature) async {
    final decoded = _evalJson('''
      (function() {
        var dexObj = typeof Dex !== 'undefined' ? Dex : globalThis.Dex;
        if (!dexObj || !dexObj.natures) return JSON.stringify({ plus: null, minus: null });
        var n = typeof dexObj.natures.get === 'function' ? dexObj.natures.get('$nature') : dexObj.natures['$nature'];
        if (!n) return JSON.stringify({ plus: null, minus: null });
        return JSON.stringify({ plus: n.plus || null, minus: n.minus || null });
      })()
    ''');

    return Map<String, dynamic>.from(decoded);
  }

  Future<Map<String, int>> getBaseStats(String name) async {
    final decoded = _evalJson('''
      (function() {
        var dexObj = typeof Dex !== 'undefined' ? Dex : globalThis.Dex;
        if (!dexObj) return JSON.stringify({ hp: 0, atk: 0, def: 0, spa: 0, spd: 0, spe: 0 });
        var speciesMap = dexObj.species || dexObj.data?.Species || dexObj.data?.Pokedex;
        var p = typeof speciesMap.get === 'function' ? speciesMap.get('$name') : speciesMap['$name'];
        if (!p || !p.baseStats) return JSON.stringify({ hp: 0, atk: 0, def: 0, spa: 0, spd: 0, spe: 0 });
        return JSON.stringify(p.baseStats);
      })()
    ''');

    final map = Map<String, dynamic>.from(decoded);
    return map.map((k, v) => MapEntry(k, (v as num).toInt()));
  }

  Future<Map<String, Map<String, int>>> getAllMegaBaseStats(String name) async {
    final decoded = _evalJson('''
      (function() {
        var dexObj = typeof Dex !== 'undefined' ? Dex : globalThis.Dex;
        if (!dexObj) return JSON.stringify({});
        var speciesMap = dexObj.species || dexObj.data?.Species || dexObj.data?.Pokedex;
        var result = {};
        
        if (speciesMap && typeof speciesMap.all === 'function') {
          var all = speciesMap.all();
          all.forEach(function(s) {
            if (s.name.toLowerCase().indexOf('$name'.toLowerCase() + '-mega') === 0 && s.baseStats) {
              result[s.name] = s.baseStats;
            }
          });
        }
        return JSON.stringify(result);
      })()
    ''');

    final map = Map<String, dynamic>.from(decoded);
    return map.map((k, v) {
      final inner = Map<String, dynamic>.from(v);
      return MapEntry(k, inner.map((ik, iv) => MapEntry(ik, (iv as num).toInt())));
    });
  }
}
