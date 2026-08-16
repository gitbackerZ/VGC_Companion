import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_js/flutter_js.dart';

class JsEngineService {
  static final JsEngineService _instance = JsEngineService._internal();
  factory JsEngineService() => _instance;
  JsEngineService._internal();

  JavascriptRuntime? _jsRuntime;
  bool _isInitialized = false;

  Future<void> init() async {
    if (_isInitialized) return;

    _jsRuntime = getJavascriptRuntime();

    final dexJs = await rootBundle.loadString('assets/js/dex.js');
    _jsRuntime!.evaluate(dexJs);

    _isInitialized = true;
  }

  Future<List<String>> getSpeciesList() async {
    final result = _jsRuntime!.evaluate('JSON.stringify(Object.keys(Dex.data.Species))');
    if (result.isError) return [];
    final List<dynamic> list = json.decode(result.stringResult);
    return list.cast<String>();
  }

  Future<Map<String, dynamic>> getPokemon(String name) async {
    final sanitized = name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    final result = _jsRuntime!.evaluate('JSON.stringify(Dex.species.get("$sanitized"))');
    if (result.isError) throw Exception('Failed to get species data for $name');
    return json.decode(result.stringResult) as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> getMoveList() async {
    final result = _jsRuntime!.evaluate('JSON.stringify(Object.values(Dex.data.Moves))');
    if (result.isError) return [];
    final List<dynamic> list = json.decode(result.stringResult);
    return list.cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> getAbilitiesForPokemon(String name) async {
    try {
      final data = await getPokemon(name);
      if (data['abilities'] is List) {
        return (data['abilities'] as List)
            .map((a) => {'name': a.toString()})
            .toList();
      }
      if (data['abilities'] is Map) {
        final abilitiesMap = data['abilities'] as Map<String, dynamic>;
        return abilitiesMap.values
            .map((a) => {'name': a.toString()})
            .toList();
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
        final double m = (data['genderRatio']['M'] as num?)?.toDouble() ?? 0.5;
        if (m == 0.0) return 8;
        if (m == 1.0) return 0;
      }
      return 4;
    } catch (_) {
      return 4;
    }
  }

  Future<Map<String, Map<String, int>>> getAllMegaBaseStats(String name) async {
    try {
      final cleanBaseName = name.toLowerCase().split('-')[0];
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
    const natures = {
      'adamant': {'plus': 'Attack', 'minus': 'Sp. Atk'},
      'bashful': {'plus': '', 'minus': ''},
      'bold': {'plus': 'Defense', 'minus': 'Attack'},
      'brave': {'plus': 'Attack', 'minus': 'Speed'},
      'calm': {'plus': 'Sp. Def', 'minus': 'Attack'},
      'careful': {'plus': 'Sp. Def', 'minus': 'Sp. Atk'},
      'docile': {'plus': '', 'minus': ''},
      'gentle': {'plus': 'Sp. Def', 'minus': 'Defense'},
      'hardy': {'plus': '', 'minus': ''},
      'hasty': {'plus': 'Speed', 'minus': 'Defense'},
      'impish': {'plus': 'Defense', 'minus': 'Sp. Atk'},
      'jolly': {'plus': 'Speed', 'minus': 'Sp. Atk'},
      'lax': {'plus': 'Defense', 'minus': 'Sp. Def'},
      'lonely': {'plus': 'Attack', 'minus': 'Defense'},
      'mild': {'plus': 'Sp. Atk', 'minus': 'Defense'},
      'modest': {'plus': 'Sp. Atk', 'minus': 'Attack'},
      'naive': {'plus': 'Speed', 'minus': 'Sp. Def'},
      'naughty': {'plus': 'Attack', 'minus': 'Sp. Def'},
      'quiet': {'plus': 'Sp. Atk', 'minus': 'Speed'},
      'quirky': {'plus': '', 'minus': ''},
      'rash': {'plus': 'Sp. Atk', 'minus': 'Sp. Def'},
      'relaxed': {'plus': 'Defense', 'minus': 'Speed'},
      'sassy': {'plus': 'Sp. Def', 'minus': 'Speed'},
      'serious': {'plus': '', 'minus': ''},
      'timid': {'plus': 'Speed', 'minus': 'Attack'},
    };
    return natures[nature.toLowerCase()] ?? {'plus': '', 'minus': ''};
  }
}
