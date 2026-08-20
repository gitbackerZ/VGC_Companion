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

    try {
      final dexJs = await rootBundle.loadString('assets/js/dex.js');
      _jsRuntime!.evaluate(dexJs);

      final learnsetsJsonText = await rootBundle.loadString('assets/js/learnsets.json');
      final escapedJson = jsonEncode(learnsetsJsonText);
      _jsRuntime!.evaluate('Dex.data.Learnsets = JSON.parse($escapedJson);');
      
      _isInitialized = true;
    } catch (e, stack) {
      debugPrint('Error initializing JS Engine: $e\n$stack');
    }
  }

  bool get isReady => _isInitialized && _jsRuntime != null;

  String _toId(String text) => text.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  void dispose() {
    if (_jsRuntime != null) {
      _jsRuntime!.dispose();
      _jsRuntime = null;
      _isInitialized = false;
    }
  }

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
        var items = Dex.items.all();
        var result = [];
        for (var i = 0; i < items.length; i++) {
          var item = items[i];
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
