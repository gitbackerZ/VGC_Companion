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

  Future<List<String>> getSpeciesList() async {
    final decoded = _evalJson('''
      (function() {
        if (typeof getSpeciesList === 'function') {
          var res = getSpeciesList();
          var list = res;
          if (typeof res === 'string') {
            try { list = JSON.parse(res); } catch(e) {}
          }
          if (Array.isArray(list)) {
            var names = list.map(function(item) {
              if (typeof item === 'string') return item;
              if (typeof item === 'object' && item !== null) {
                return item.name || item.species || item.id || String(item);
              }
              return String(item);
            });
            return JSON.stringify(names);
          }
          return typeof res === 'string' ? res : JSON.stringify(res);
        }
        return JSON.stringify({ error: "getSpeciesList function is not defined globally." });
      })()
    ''');

    if (decoded is Map && decoded.containsKey('error')) {
      throw Exception(decoded['error']);
    }

    if (decoded is List) {
      return decoded.map((e) {
        if (e is String) return e;
        if (e is Map && e.containsKey('name')) return e['name'].toString();
        return e.toString();
      }).toList();
    }

    return List<String>.from(decoded);
  }

  Future<Map<String, dynamic>> getPokemon(String name) async {
    final decoded = _evalJson('''
      (function() {
        var nameClean = '$name'.toLowerCase().replace(/[^a-z0-9]/g, '');
        if (typeof getSpeciesList === 'function') {
          var all = getSpeciesList();
          if (typeof all === 'string') {
            try { all = JSON.parse(all); } catch(e) {}
          }
          if (Array.isArray(all)) {
            var match = all.find(function(s) { 
              var sName = typeof s === 'string' ? s : (s.name || s.species);
              return sName && sName.toLowerCase().replace(/[^a-z0-9]/g, '') === nameClean; 
            });
            if (match) {
              if (typeof match === 'string') return JSON.stringify({ id: 0, name: match });
              return JSON.stringify({
                id: match.num || match.id || match.pokedexNumber || 0,
                name: match.name || match.species || '$name'
              });
            }
          }
        }
        return JSON.stringify({ id: 0, name: '$name' });
      })()
    ''');

    return Map<String, dynamic>.from(decoded);
  }

  Future<List<Map<String, dynamic>>> getAbilitiesForPokemon(String name) async {
    final decoded = _evalJson('''
      (function() {
        var nameClean = '$name'.toLowerCase().replace(/[^a-z0-9]/g, '');
        if (typeof getSpeciesList === 'function') {
          var all = getSpeciesList();
          if (typeof all === 'string') {
            try { all = JSON.parse(all); } catch(e) {}
          }
          if (Array.isArray(all)) {
            var match = all.find(function(s) { 
              var sName = typeof s === 'string' ? s : (s.name || s.species);
              return sName && sName.toLowerCase().replace(/[^a-z0-9]/g, '') === nameClean; 
            });
            if (match && match.abilities) {
              var abs = match.abilities;
              var result = [];
              if (Array.isArray(abs)) {
                result = abs.map(function(a) { return { name: typeof a === 'string' ? a : (a.name || String(a)) }; });
              } else if (typeof abs === 'object') {
                Object.keys(abs).forEach(function(k) {
                  if (abs[k]) result.push({ name: typeof abs[k] === 'string' ? abs[k] : (abs[k].name || String(abs[k])) });
                });
              }
              return JSON.stringify(result);
            }
          }
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
      return decoded.map((e) {
        if (e is String) return e;
        if (e is Map && e.containsKey('name')) return e['name'].toString();
        return e.toString();
      }).toList();
    }

    return List<String>.from(decoded);
  }

  Future<int> getGenderRate(String name) async {
    final decoded = _evalJson('''
      (function() {
        var nameClean = '$name'.toLowerCase().replace(/[^a-z0-9]/g, '');
        if (typeof getSpeciesList === 'function') {
          var all = getSpeciesList();
          if (typeof all === 'string') { try { all = JSON.parse(all); } catch(e) {} }
          if (Array.isArray(all)) {
            var match = all.find(function(s) {
              var sName = typeof s === 'string' ? s : (s.name || s.species);
              return sName && sName.toLowerCase().replace(/[^a-z0-9]/g, '') === nameClean;
            });
            if (match) {
              if (match.gender === 'N') return JSON.stringify(-1);
              if (match.gender === 'M') return JSON.stringify(0);
              if (match.gender === 'F') return JSON.stringify(8);
              if (match.genderRatio) {
                if (match.genderRatio.M === 1) return JSON.stringify(0);
                if (match.genderRatio.F === 1) return JSON.stringify(8);
              }
            }
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
        var nameClean = '$name'.toLowerCase().replace(/[^a-z0-9]/g, '');
        if (typeof getSpeciesList === 'function') {
          var all = getSpeciesList();
          if (typeof all === 'string') { try { all = JSON.parse(all); } catch(e) {} }
          if (Array.isArray(all)) {
            var match = all.find(function(s) {
              var sName = typeof s === 'string' ? s : (s.name || s.species);
              return sName && sName.toLowerCase().replace(/[^a-z0-9]/g, '') === nameClean;
            });
            if (match && (match.baseStats || match.stats)) {
              return JSON.stringify(match.baseStats || match.stats);
            }
          }
        }
        return JSON.stringify({ hp: 45, atk: 45, def: 45, spa: 45, spd: 45, spe: 45 });
      })()
    ''');

    final map = Map<String, dynamic>.from(decoded);
    return map.map((k, v) => MapEntry(k.toString().toLowerCase(), (v as num).toInt()));
  }

  Future<Map<String, Map<String, int>>> getAllMegaBaseStats(String name) async {
    final decoded = _evalJson('''
      (function() {
        var nameClean = '$name'.toLowerCase().replace(/[^a-z0-9]/g, '');
        var result = {};
        if (typeof getSpeciesList === 'function') {
          var all = getSpeciesList();
          if (typeof all === 'string') { try { all = JSON.parse(all); } catch(e) {} }
          if (Array.isArray(all)) {
            all.forEach(function(s) {
              if (s && s.name && (s.baseStats || s.stats)) {
                var sClean = s.name.toLowerCase().replace(/[^a-z0-9]/g, '');
                if (sClean.indexOf(nameClean + 'mega') === 0) {
                  result[s.name] = s.baseStats || s.stats;
                }
              }
            });
          }
        }
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
