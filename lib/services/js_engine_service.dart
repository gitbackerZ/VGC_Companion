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

  /// Evaluates JS code and safely decodes double-stringified JSON.
  dynamic _evalAndParse(String jsCode) {
    final result = _jsRuntime.evaluate(jsCode);

    if (result.isError) {
      throw Exception('JS Runtime Error: ${result.stringResult}');
    }

    var raw = result.stringResult;
    try {
      var decoded = jsonDecode(raw);
      // Handles cases where JS returns a stringified JSON string
      if (decoded is String) {
        decoded = jsonDecode(decoded);
      }
      return decoded;
    } catch (e) {
      throw Exception('Failed to parse JS output ($raw): $e');
    }
  }

  /// Fetches all species objects directly from getSpeciesList()
  Future<List<Map<String, dynamic>>> getAllSpeciesData() async {
    final decoded = _evalAndParse('getSpeciesList()');
    if (decoded is List) {
      return List<Map<String, dynamic>>.from(decoded);
    }
    return [];
  }

  /// Returns species names for search suggestions
  Future<List<String>> getSpeciesList() async {
    final speciesData = await getAllSpeciesData();
    return speciesData
        .map((s) => (s['name'] ?? s['id'] ?? '').toString())
        .where((n) => n.isNotEmpty)
        .toList();
  }

  /// Gets a full payload for a given Pokémon name or ID
  Future<Map<String, dynamic>> getPokemon(String name) async {
    final cleanTarget = name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    final allSpecies = await getAllSpeciesData();

    final match = allSpecies.firstWhere(
      (s) {
        final sName = (s['name'] ?? '').toString().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
        final sId = (s['id'] ?? '').toString().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
        return sName == cleanTarget || sId == cleanTarget;
      },
      orElse: () => {},
    );

    if (match.isNotEmpty) {
      final baseStats = Map<String, dynamic>.from(match['baseStats'] ?? {});
      
      // Provides both numeric ID and string ID, plus mapped stat keys for Dart model safety
      return {
        'id': match['id'] ?? cleanTarget,
        'num': 0, // Fallback if Dart model expects an int num
        'name': match['name'] ?? name,
        'species': match['name'] ?? name,
        'types': List<String>.from(match['types'] ?? ['Normal']),
        'abilities': List<String>.from(match['abilities'] ?? []),
        'baseStats': {
          'hp': baseStats['hp'] ?? 80,
          'atk': baseStats['atk'] ?? 80,
          'def': baseStats['def'] ?? 80,
          'spa': baseStats['spa'] ?? 80,
          'spd': baseStats['spd'] ?? 80,
          'spe': baseStats['spe'] ?? 80,
          'attack': baseStats['atk'] ?? 80,
          'defense': baseStats['def'] ?? 80,
          'specialAttack': baseStats['spa'] ?? 80,
          'specialDefense': baseStats['spd'] ?? 80,
          'speed': baseStats['spe'] ?? 80,
        },
      };
    }

    throw Exception('Species "$name" not found in Dex.');
  }

  /// Fetches competitive move list
  Future<List<Map<String, dynamic>>> getMoveList() async {
    final decoded = _evalAndParse('getMoveList()');
    if (decoded is List) {
      return List<Map<String, dynamic>>.from(decoded);
    }
    return [];
  }

  /// Fetches competitive item list
  Future<List<Map<String, dynamic>>> getItemList() async {
    final decoded = _evalAndParse('getItemList()');
    if (decoded is List) {
      return List<Map<String, dynamic>>.from(decoded);
    }
    return [];
  }
}
