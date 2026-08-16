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
        if (typeof getPokemon === 'function') {
          var p = getPokemon('$name');
          if (p) return JSON.stringify(p);
        }
        if (typeof getSpeciesList === 'function') {
          var all = getSpeciesList();
          if (typeof all === 'string') {
            try { all = JSON.parse(all); } catch(e) {}
          }
          if (Array.isArray(all)) {
            var match = all.find(function(s) { 
              var sName = typeof s === 'string' ? s : (s.name || s.species);
              return sName && sName.toLowerCase() === '$name'.toLowerCase(); 
            });
            if (match) {
              return JSON.stringify(typeof match === 'string' ? { id: 0, name: match } : match);
            }
          }
        }
        return JSON.stringify({ error: "Pokémon not found: $name" });
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
        if (typeof getAbilities === 'function') {
          var res = getAbilities('$name');
          return typeof res === 'string' ? res : JSON.stringify(res);
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
          return typeof res === 'string' ? res : JSON.stringify(res);
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
        if (typeof getGenderRate === 'function') {
          return getGenderRate('$name');
        }
        return 4;
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
        if (typeof getBaseStats === 'function') {
          var res = getBaseStats('$name');
          return typeof res === 'string' ? res : JSON.stringify(res);
        }
        return JSON.stringify({ hp: 0, atk: 0, def: 0, spa: 0, spd: 0, spe: 0 });
      })()
    ''');

    final map = Map<String, dynamic>.from(decoded);
    return map.map((k, v) => MapEntry(k, (v as num).toInt()));
  }

  Future<Map<String, Map<String, int>>> getAllMegaBaseStats(String name) async {
    final decoded = _evalJson('''
      (function() {
        if (typeof getAllMegaBaseStats === 'function') {
          var res = getAllMegaBaseStats('$name');
          return typeof res === 'string' ? res : JSON.stringify(res);
        }
        return JSON.stringify({});
      })()
    ''');

    final map = Map<String, dynamic>.from(decoded);
    return map.map((k, v) {
      final inner = Map<String, dynamic>.from(v);
      return MapEntry(k, inner.map((ik, iv) => MapEntry(ik, (iv as num).toInt())));
    });
  }
}
