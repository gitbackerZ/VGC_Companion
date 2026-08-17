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

  Future<void> init() async {
    if (_isInitialized) return;

    _jsRuntime = getJavascriptRuntime();

    final dexJs = await rootBundle.loadString('assets/js/dex.js');
    _jsRuntime!.evaluate(dexJs);

    try {
      final learnsetsJson = await rootBundle.loadString('assets/js/learnsets.json');
      _jsRuntime!.evaluate('Dex.data.Learnsets = $learnsetsJson;');
    } catch (e, stack) {
      debugPrint('Error loading learnsets.json: $e\n$stack');
    }

    _isInitialized = true;
  }

  /// Returns real held item names from Dex.data.Items
  Future<List<String>> getItemList() async {
    final script = '''
      (function() {
        if (!Dex.data.Items) return JSON.stringify([]);
        var items = Object.values(Dex.data.Items)
          .filter(function(i) { return i.exists && !i.isNonstandard; })
          .map(function(i) { return i.name; });
        return JSON.stringify(items);
      })()
    ''';
    final result = _jsRuntime!.evaluate(script);
    if (result.isError) return [];
    final List<dynamic> list = json.decode(result.stringResult);
    return list.cast<String>();
  }

  /// Returns base species only (1 per Dex number), excluding Megas and Gmax
  Future<List<Map<String, dynamic>>> getBaseSpeciesList() async {
    final script = '''
      (function() {
        var results = [];
        var seenNum = {};
        var keys = Object.keys(Dex.data.Species);
        for (var i = 0; i < keys.length; i++) {
          var spec = Dex.species.get(keys[i]);
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
              'hasFormes': (spec.otherFormes && spec.otherFormes.length > 0)
            });
          }
        }
        return JSON.stringify(results);
      })()
    ''';
    final result = _jsRuntime!.evaluate(script);
    if (result.isError) return [];
    final List<dynamic> list = json.decode(result.stringResult);
    return list.cast<Map<String, dynamic>>();
  }

  /// Gets non-Mega, non-Gmax varieties for a base species
  Future<List<Map<String, dynamic>>> getFormesForSpecies(String baseName) async {
    final script = '''
      (function() {
        var base = Dex.species.get("$baseName");
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

  Future<Map<String, dynamic>> getPokemon(String name) async {
    final sanitized = name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    final result = _jsRuntime!.evaluate('JSON.stringify(Dex.species.get("$sanitized"))');
    if (result.isError) throw Exception('Failed to get species data for $name');
    return json.decode(result.stringResult) as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> getMovesForSpecies(String name) async {
    try {
      final sanitized = name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
      final script = '''
        (function() {
          try {
            var species = Dex.species.get("$sanitized");
            if (!species || !species.exists) return JSON.stringify([]);
            if (!Dex.data.Learnsets) return JSON.stringify([]);

            var moveIdSet = {};
            var current = species;
            var seen = {};
            var guard = 0;

            while (current && guard < 10) {
              guard++;
              if (seen[current.id]) break;
              seen[current.id] = true;

              var learnsetData = Dex.data.Learnsets[current.id];
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
              .map(function(mid) { return Dex.data.Moves[mid]; })
              .filter(function(m) { return m; });

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
