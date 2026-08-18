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

  /// Helper to check if runtime is ready
  bool get isReady => _isInitialized && _jsRuntime != null;

  /// Returns real held item names using Dex.items.all()
  Future<List<String>> getItemList() async {
    if (!isReady) return [];
    final script = '''
      (function() {
        if (!Dex || !Dex.items) return JSON.stringify([]);
        var items = Dex.items.all();
        var result = [];
        for (var i = 0; i < items.length; i++) {
          var item = items[i];
          if (item.exists && !item.isNonstandard) {
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

  /// Returns base species only (1 per Dex number), excluding Megas and Gmax
  Future<List<Map<String, dynamic>>> getBaseSpeciesList() async {
    if (!isReady) return [];
    final script = '''
      (function() {
        if (!Dex || !Dex.species) return JSON.stringify([]);
        var speciesList = Dex.species.all();
        var results = [];
        var seenNum = {};

        for (var i = 0; i < speciesList.length; i++) {
          var spec = speciesList[i];
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
    if (!isReady) return [];
    final sanitized = baseName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
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

  /// Fetches species data via Dex.species.get()
  Future<Map<String, dynamic>> getPokemon(String name) async {
    if (!isReady) throw Exception('JsEngineService is not initialized');
    final sanitized = name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    final result = _jsRuntime!.evaluate('JSON.stringify(Dex.species.get("$sanitized"))');
    if (result.isError) throw Exception('Failed to get species data for $name');
    return json.decode(result.stringResult) as Map<String, dynamic>;
  }

  /// Returns learnable moves for a species including pre-evolutions using Dex.moves.get()
  Future<List<Map<String, dynamic>>> getMovesForSpecies(String name) async {
    if (!isReady) return [];
    try {
      final sanitized = name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
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

  /// Returns formatted ability list for a given species name
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

  /// Returns female gender rate in 8ths (-1 = Genderless, 0 = 100% Male, 8 = 100% Female)
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

  /// Retrieves base stats for all Mega evolutions associated with a base species
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

  /// Fetches stat modifiers (+10% / -10%) using Dex.natures.get()
  Future<Map<String, String>> getNatureBoosts(String nature) async {
    if (!isReady) return {'plus': '', 'minus': ''};
    try {
      final sanitized = nature.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
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
