import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/services.dart' show rootBundle;

class PokeApiService {
  static const String baseUrl = 'https://pokeapi.co/api/v2';
  List<String>? _cachedHeldItems;

  Future<Map<String, dynamic>> getPokemon(String name) async {
    final response = await http.get(
      Uri.parse('$baseUrl/pokemon/${name.toLowerCase().trim()}'),
    );
    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Pokémon not found: $name');
    }
  }

  Future<Map<String, dynamic>> getPokemonSpecies(String name) async {
    final response = await http.get(
      Uri.parse('$baseUrl/pokemon-species/${name.toLowerCase().trim()}'),
    );
    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Pokémon species not found: $name');
    }
  }

  Future<Map<String, dynamic>> getMove(String name) async {
    final formatted = name.toLowerCase().replaceAll(' ', '-');
    final response = await http.get(
      Uri.parse('$baseUrl/move/$formatted'),
    );
    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Move not found: $name');
    }
  }

  Future<List<String>> getAllSpeciesNames() async {
    final response = await http.get(
      Uri.parse('$baseUrl/pokemon-species?limit=2000'),
    );
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final results = data['results'] as List;
      return results.map((r) => r['name'] as String).toList();
    } else {
      throw Exception('Could not load species list');
    }
  }

  /// Returns gender_rate: -1 = genderless, 0 = always male, 8 = always female,
  /// otherwise a female-chance ratio out of 8 (both genders possible).
  Future<int> getGenderRate(String name) async {
    // Species-level data applies even to forms; strip common form suffixes first.
    String baseName = name.toLowerCase().trim();
    for (final suffix in [
      '-mega-x',
      '-mega-y',
      '-mega',
      '-gmax',
      '-female',
      '-male'
    ]) {
      if (baseName.endsWith(suffix)) {
        baseName = baseName.substring(0, baseName.length - suffix.length);
        break;
      }
    }
    try {
      final data = await getPokemonSpecies(baseName);
      return data['gender_rate'] as int;
    } catch (e) {
      return 4; // fallback: assume both genders possible
    }
  }

  Future<List<Map<String, dynamic>>> getVarieties(String speciesName) async {
    final speciesData = await getPokemonSpecies(speciesName);
    final List<dynamic> varieties = speciesData['varieties'] ?? [];
    return varieties.cast<Map<String, dynamic>>();
  }

  Future<Map<String, Map<String, int>>> getAllMegaBaseStats(String name) async {
    final Map<String, Map<String, int>> results = {};
    try {
      final varieties = await getVarieties(name);
      final megaVarieties = varieties.where((v) {
        final String formName = v['pokemon']['name'] ?? '';
        return formName.contains('-mega');
      });

      for (final variety in megaVarieties) {
        final String formName = variety['pokemon']['name'];
        final stats = await getBaseStats(formName);
        results[formName] = stats;
      }
    } catch (_) {
      // Species has no mega forms or request failed
    }
    return results;
  }

  Future<List<String>> getMovesForPokemon(String name) async {
    final data = await getPokemon(name);
    final moves = data['moves'] as List;
    return moves.map((m) => m['move']['name'] as String).toList()..sort();
  }

  Future<Map<String, int>> getBaseStats(String name) async {
    final data = await getPokemon(name);
    final stats = data['stats'] as List;
    final Map<String, int> result = {};
    for (final s in stats) {
      result[s['stat']['name']] = s['base_stat'];
    }
    return result;
  }

  Future<List<Map<String, dynamic>>> getAbilitiesForPokemon(String name) async {
    final data = await getPokemon(name);
    final abilities = data['abilities'] as List;
    return abilities
        .map((a) => {
              'name': a['ability']['name'] as String,
              'isHidden': a['is_hidden'] as bool,
            })
        .toList();
  }

  /// Champions held-item pool from local JSON (PokeAPI-compatible hyphens).
  /// Falls back to a broad PokéAPI category scrape only if the asset is missing.
  Future<List<String>> getHeldItemNames() async {
    if (_cachedHeldItems != null) return _cachedHeldItems!;

    // Preferred: curated Champions pool shipped with the app.
    try {
      final raw =
          await rootBundle.loadString('lib/data/champions_held_items.json');
      final decoded = json.decode(raw);
      final List<dynamic> list = decoded is Map
          ? (decoded['allowed_held_items'] as List? ?? const [])
          : (decoded as List);
      final items = list
          .map((e) => (e as String).toLowerCase().trim())
          .where((e) => e.isNotEmpty)
          .toSet()
          .toList()
        ..sort();
      if (items.isNotEmpty) {
        _cachedHeldItems = items;
        return _cachedHeldItems!;
      }
    } catch (_) {
      // Asset missing or malformed.
    }

    // Do not scrape PokéAPI categories here — that is many sequential HTTP
    // calls and makes Team Builder startup very slow. Prefer shipping
    // lib/data/champions_held_items.json as an asset.
    _cachedHeldItems = [];
    return _cachedHeldItems!;
  }
}
