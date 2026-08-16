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

    _jsRuntime.evaluate('''
      var global = globalThis;
      var window = globalThis;
      var self = globalThis;
      var module = { exports: {} };
      var exports = module.exports;
    ''');

    final script = await rootBundle.loadString('assets/engine.js');
    final result = _jsRuntime.evaluate(script);

    if (result.isError) {
      throw Exception('Failed to evaluate assets/engine.js: ${result.stringResult}');
    }

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

  static const String _jsHelperCode = '''
    function _cleanStr(s) {
      return String(s || '').toLowerCase().replace(/[^a-z0-9]/g, '');
    }

    function _getAllSpecies() {
      if (typeof getSpeciesList !== 'function') return [];
      var res = getSpeciesList();
      if (typeof res === 'string') {
        try { res = JSON.parse(res); } catch(e) { return []; }
      }
      return Array.isArray(res) ? res : [];
    }

    function _findSpeciesObj(targetName) {
      var targetClean = _cleanStr(targetName);
      var all = _getAllSpecies();
      for (var i = 0; i < all.length; i++) {
        var item = all[i];
        var itemName = typeof item === 'string' ? item : (item.name || item.species || item.id);
        if (_cleanStr(itemName) === targetClean) {
          return item;
        }
      }
      return null;
    }

    function _extractStatsMap(item) {
      var defStats = { hp: 80, atk: 80, def: 80, spa: 80, spd: 80, spe: 80 };
      if (!item || typeof item === 'string') return defStats;
      var s = item.baseStats || item.stats || item.base_stats || item;
      
      var hp = s.hp || s.HP || 80;
      var atk = s.atk || s.attack || s.Atk || s.ATTACK || 80;
      var def = s.def || s.defense || s.Def || s.DEFENSE || 80;
      var spa = s.spa || s.spAtk || s.spatk || s.specialAttack || s.special_attack || s.SpA || 80;
      var spd = s.spd || s.spDef || s.spdef || s.specialDefense || s.special_defense || s.SpD || 80;
      var spe = s.spe || s.speed || s.Spe || s.SPEED || 80;

      return {
        hp: Number(hp) || 80,
        atk: Number(atk) || 80,
        def: Number(def) || 80,
        spa: Number(spa) || 80,
        spd: Number(spd) || 80,
        spe: Number(spe) || 80,
        attack: Number(atk) || 80,
        defense: Number(def) || 80,
        specialAttack: Number(spa) || 80,
        specialDefense: Number(spd) || 80,
        speed: Number(spe) || 80
      };
    }
  ''';

  Future<List<String>> getSpeciesList() async {
    final decoded = _evalJson('''
      (function() {
        $_jsHelperCode
        var all = _getAllSpecies();
        var names = all.map(function(item) {
          if (typeof item === 'string') return item;
          if (typeof item === 'object' && item !== null) {
            return item.name || item.species || item.id || String(item);
          }
          return String(item);
        });
        return JSON.stringify(names);
      })()
    ''');

    if (decoded is List) {
      return decoded.map((e) => e.toString()).toList();
    }
    return List<String>.from(decoded);
  }

  Future<Map<String, dynamic>> getPokemon(String name) async {
    final decoded = _evalJson('''
      (function() {
        $_jsHelperCode
        var match = _findSpeciesObj('$name');
        if (match && typeof match === 'object') {
          var stats = _extractStatsMap(match);
          var abs = match.abilities || [];
          if (typeof abs === 'object' && !Array.isArray(abs)) {
            abs = Object.keys(abs).map(function(k) { return abs[k]; });
          }
          return JSON.stringify({
            id: match.num || match.id || match.pokedexNumber || 1,
            name: match.name || match.species || '$name',
            species: match.name || match.species || '$name',
            types: match.types || match.type || ["Normal"],
            baseStats: stats,
            stats: stats,
            abilities: abs
          });
        }
        return JSON.stringify({
          id: 1,
          name: '$name',
          species: '$name',
          types: ["Normal"],
          baseStats: { hp: 80, atk: 80, def: 80, spa: 80, spd: 80, spe: 80 },
          stats: { hp: 80, atk: 80, def: 80, spa: 80, spd: 80, spe: 80 },
          abilities: []
        });
      })()
    ''');

    return Map<String, dynamic>.from(decoded);
  }

  Future<List<Map<String, dynamic>>> getAbilitiesForPokemon(String name) async {
    final decoded = _evalJson('''
      (function() {
        $_jsHelperCode
        var match = _findSpeciesObj('$name');
        if (match && typeof match === 'object' && match.abilities) {
          var abs = match.abilities;
          var result = [];
          if (Array.isArray(abs)) {
            result = abs.map(function(a) { 
              return { name: typeof a === 'string' ? a : (a.name || String(a)) }; 
            });
          } else if (typeof abs === 'object') {
            Object.keys(abs).forEach(function(k) {
              if (abs[k]) {
                result.push({ name: typeof abs[k] === 'string' ? abs[k] : (abs[k].name || String(abs[k])) });
              }
            });
          }
          return JSON.stringify(result);
        }
        return JSON.stringify([]);
      })()
    ''');

    return List<Map<String, dynamic>>.from(decoded);
  }

  Future<List<String>> getMovesForPokemon(String name) async {
    final decoded = _evalJson('''
      (function() {
        if (typeof getMoveList === 'function') {
          var res = getMoveList('$name');
          if (!res || res.length === 0) res = getMoveList();
          var list = res;
          if (typeof res === 'string') {
            try { list = JSON.parse(res); } catch(e) {}
          }
          if (Array.isArray(list)) {
            var names = list.map(function(item) {
              if (typeof item === 'string') return item;
              if (typeof item === 'object' && item !== null) {
                return item.name || item.move || String(item);
              }
              return String(item);
            });
            return JSON.stringify(names);
          }
        }
        return JSON.stringify([]);
      })()
    ''');

    if (decoded is List) {
      return decoded.map((e) => e.toString()).toList();
    }
    return List<String>.from(decoded);
  }

  Future<int> getGenderRate(String name) async {
    final decoded = _evalJson('''
      (function() {
        $_jsHelperCode
        var match = _findSpeciesObj('$name');
        if (match && typeof match === 'object') {
          if (match.gender === 'N') return JSON.stringify(-1);
          if (match.gender === 'M') return JSON.stringify(0);
          if (match.gender === 'F') return JSON.stringify(8);
          if (match.genderRatio) {
            if (match.genderRatio.M === 1) return JSON.stringify(0);
            if (match.genderRatio.F === 1) return JSON.stringify(8);
          }
        }
        return JSON.stringify(4);
      })()
    ''');

    return (decoded as num).toInt();
  }

  Future<Map<String, dynamic>> getNatureBoosts(String nature) async {
    final decoded = _evalJson('''
      (function() {
        if (typeof getNatureBoosts === 'function') {
          var res = getNatureBoosts('$nature');
          return typeof res === 'string' ? res : JSON.stringify(res);
        }
        return JSON.stringify({ plus: null, minus: null });
      })()
    ''');

    return Map<String, dynamic>.from(decoded);
  }

  Future<Map<String, int>> getBaseStats(String name) async {
    final decoded = _evalJson('''
      (function() {
        $_jsHelperCode
        var match = _findSpeciesObj('$name');
        var stats = _extractStatsMap(match);
        return JSON.stringify(stats);
      })()
    ''');

    final map = Map<String, dynamic>.from(decoded);
    return map.map((k, v) => MapEntry(k.toString().toLowerCase(), (v as num).toInt()));
  }

  Future<Map<String, Map<String, int>>> getAllMegaBaseStats(String name) async {
    final decoded = _evalJson('''
      (function() {
        $_jsHelperCode
        var nameClean = _cleanStr('$name');
        var result = {};
        var all = _getAllSpecies();
        all.forEach(function(s) {
          if (s && s.name) {
            var sClean = _cleanStr(s.name);
            if (sClean.indexOf(nameClean + 'mega') === 0) {
              result[s.name] = _extractStatsMap(s);
            }
          }
        });
        return JSON.stringify(result);
      })()
    ''');

    final map = Map<String, dynamic>.from(decoded);
    return map.map((k, v) {
      final inner = Map<String, dynamic>.from(v);
      return MapEntry(k, inner.map((ik, iv) => MapEntry(ik.toString().toLowerCase(), (iv as num).toInt())));
    });
  }
}
