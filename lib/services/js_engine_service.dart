import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_js/flutter_js.dart';

class JsEngineService {
  JavascriptRuntime? _jsRuntime;

  Future<void> init() async {
    if (_jsRuntime != null) return;
    _jsRuntime = getJavascriptRuntime();
    final engineCode = await rootBundle.loadString('assets/engine.js');
    _jsRuntime!.evaluate(engineCode);
  }

  dynamic _evalJson(String jsExpression) {
    if (_jsRuntime == null) throw Exception('Engine not initialized');
    final result = _jsRuntime!.evaluate("JSON.stringify($jsExpression)").stringResult;
    if (result == 'undefined' || result.isEmpty) return null;
    return jsonDecode(result);
  }

  Future<Map<String, dynamic>> getPokemon(String name) async {
    await init();
    final species = _evalJson("globalThis.Dex.species.get('$name')");
    if (species == null) throw Exception('Species $name not found in engine');
    return {
      'id': species['num'] ?? 0,
      'name': species['name'] ?? name,
    };
  }

  Future<List<Map<String, dynamic>>> getAbilitiesForPokemon(String name) async {
    await init();
    final species = _evalJson("globalThis.Dex.species.get('$name')");
    if (species == null || species['abilities'] == null) return [];
    
    final Map<String, dynamic> abilitiesMap = Map<String, dynamic>.from(species['abilities']);
    return abilitiesMap.values
        .map((abilityName) => {'name': abilityName.toString().toLowerCase()})
        .toList();
  }

  Future<List<String>> getMovesForPokemon(String name) async {
    await init();
    final learnset = _evalJson("globalThis.Dex.species.getLearnset('$name') || {}");
    if (learnset == null) return [];
    final Map<String, dynamic> map = Map<String, dynamic>.from(learnset);
    return map.keys.toList();
  }

  Future<int> getGenderRate(String name) async {
    await init();
    final species = _evalJson("globalThis.Dex.species.get('$name')");
    if (species == null) return 4;

    final gender = species['gender'];
    if (gender == 'N') return -1;
    if (gender == 'M') return 0;
    if (gender == 'F') return 8;

    if (species['genderRatio'] != null) {
      final fRatio = (species['genderRatio']['F'] as num?) ?? 0.5;
      return (fRatio * 8).round();
    }
    return 4;
  }

  Future<Map<String, int>> getBaseStats(String name) async {
    await init();
    final species = _evalJson("globalThis.Dex.species.get('$name')");
    if (species == null || species['baseStats'] == null) {
      return {'HP': 0, 'Atk': 0, 'Def': 0, 'SpA': 0, 'SpD': 0, 'Spe': 0};
    }

    final stats = species['baseStats'];
    return {
      'HP': (stats['hp'] as num).toInt(),
      'Atk': (stats['atk'] as num).toInt(),
      'Def': (stats['def'] as num).toInt(),
      'SpA': (stats['spa'] as num).toInt(),
      'SpD': (stats['spd'] as num).toInt(),
      'Spe': (stats['spe'] as num).toInt(),
    };
  }

  Future<Map<String, Map<String, int>>> getAllMegaBaseStats(String name) async {
    await init();
    final species = _evalJson("globalThis.Dex.species.get('$name')");
    if (species == null || species['otherFormes'] == null) return {};

    final List<dynamic> otherFormes = species['otherFormes'];
    final Map<String, Map<String, int>> megaStats = {};

    for (final formeName in otherFormes) {
      final formeStr = formeName.toString();
      if (formeStr.toLowerCase().contains('mega') || formeStr.toLowerCase().contains('primal')) {
        final keyName = formeStr.toLowerCase().replaceAll(' ', '');
        megaStats[keyName] = await getBaseStats(formeStr);
      }
    }
    return megaStats;
  }

  Future<List<dynamic>> getSpeciesList() async {
    await init();
    try {
      final jsonStr = _jsRuntime!.evaluate("globalThis.getSpeciesList();").stringResult;
      return jsonDecode(jsonStr);
    } catch (_) {
      return [];
    }
  }

  Future<List<dynamic>> getMoveList() async {
    await init();
    try {
      final jsonStr = _jsRuntime!.evaluate("globalThis.getMoveList();").stringResult;
      return jsonDecode(jsonStr);
    } catch (_) {
      return [];
    }
  }

  Future<List<dynamic>> getItemList() async {
    await init();
    try {
      final jsonStr = _jsRuntime!.evaluate("globalThis.getItemList();").stringResult;
      return jsonDecode(jsonStr);
    } catch (_) {
      return [];
    }
  }
}
