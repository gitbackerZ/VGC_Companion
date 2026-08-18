import 'dart:convert';

class PokemonTeamMember {
  final String species;
  final String? nickname;
  final String? item;
  final String? ability;
  final String? gender; // 'M', 'F', or null
  final int level;
  final bool isShiny;
  final String nature;
  final Map<String, int> evs; // {'HP': 252, 'Atk': 0, 'Def': 0, 'SpA': 0, 'SpD': 4, 'Spe': 252}
  final Map<String, int> ivs; // {'HP': 31, 'Atk': 31, 'Def': 31, 'SpA': 31, 'SpD': 31, 'Spe': 31}
  final List<String> moves;

  PokemonTeamMember({
    required this.species,
    this.nickname,
    this.item,
    this.ability,
    this.gender,
    this.level = 100,
    this.isShiny = false,
    required this.nature,
    required this.evs,
    required this.ivs,
    required this.moves,
  });
}

class ShowdownExportService {
  static const List<String> _statOrder = ['HP', 'Atk', 'Def', 'SpA', 'SpD', 'Spe'];

  /// Converts a single Pokémon into Showdown human-readable text format
  static String exportPokemon(PokemonTeamMember pokemon) {
    final buffer = StringBuffer();

    // Line 1: [Nickname] ([Species]) ([Gender]) @ [Item]
    String header = '';
    if (pokemon.nickname != null &&
        pokemon.nickname!.trim().isNotEmpty &&
        pokemon.nickname!.trim().toLowerCase() != pokemon.species.toLowerCase()) {
      header = '${pokemon.nickname!.trim()} (${pokemon.species})';
    } else {
      header = pokemon.species;
    }

    if (pokemon.gender == 'M' || pokemon.gender == 'F') {
      header += ' (${pokemon.gender})';
    }

    if (pokemon.item != null && pokemon.item!.trim().isNotEmpty) {
      header += ' @ ${pokemon.item!.trim()}';
    }
    buffer.writeln(header);

    // Ability
    if (pokemon.ability != null && pokemon.ability!.trim().isNotEmpty) {
      buffer.writeln('Ability: ${pokemon.ability!.trim()}');
    }

    // Level (omitted if default 100)
    if (pokemon.level != 100) {
      buffer.writeln('Level: ${pokemon.level}');
    }

    // Shiny
    if (pokemon.isShiny) {
      buffer.writeln('Shiny: Yes');
    }

    // EVs (only non-zero stats written)
    final evParts = <String>[];
    for (final stat in _statOrder) {
      final val = pokemon.evs[stat] ?? 0;
      if (val > 0) {
        evParts.add('$val $stat');
      }
    }
    if (evParts.isNotEmpty) {
      buffer.writeln('EVs: ${evParts.join(' / ')}');
    }

    // Nature
    if (pokemon.nature.trim().isNotEmpty) {
      final formattedNature = pokemon.nature.trim()[0].toUpperCase() +
          pokemon.nature.trim().substring(1).toLowerCase();
      buffer.writeln('$formattedNature Nature');
    }

    // IVs (only non-31 stats written)
    final ivParts = <String>[];
    for (final stat in _statOrder) {
      final val = pokemon.ivs[stat] ?? 31;
      if (val != 31) {
        ivParts.add('$val $stat');
      }
    }
    if (ivParts.isNotEmpty) {
      buffer.writeln('IVs: ${ivParts.join(' / ')}');
    }

    // Moves (- Move Name)
    for (final move in pokemon.moves) {
      final trimmed = move.trim();
      if (trimmed.isNotEmpty) {
        buffer.writeln('- $trimmed');
      }
    }

    return buffer.toString().trimRight();
  }

  /// Exports a full team (up to 6 Pokémon) separated by double line breaks
  static String exportTeam(List<PokemonTeamMember> team) {
    return team.map((p) => exportPokemon(p)).join('\n\n');
  }

  /// Parses a Showdown text export block back into structured team models
  static List<PokemonTeamMember> importTeam(String exportText) {
    final List<PokemonTeamMember> team = [];
    final blocks = exportText.split(RegExp(r'\n\s*\n'));

    for (final block in blocks) {
      if (block.trim().isEmpty) continue;

      String species = '';
      String? nickname;
      String? item;
      String? ability;
      String? gender;
      int level = 100;
      bool isShiny = false;
      String nature = 'Hardy';
      Map<String, int> evs = {'HP': 0, 'Atk': 0, 'Def': 0, 'SpA': 0, 'SpD': 0, 'Spe': 0};
      Map<String, int> ivs = {'HP': 31, 'Atk': 31, 'Def': 31, 'SpA': 31, 'SpD': 31, 'Spe': 31};
      List<String> moves = [];

      final lines = LineSplitter.split(block).map((l) => l.trim()).toList();

      for (int i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (line.isEmpty) continue;

        if (i == 0) {
          // Line 1 header parsing
          var remaining = line;
          if (remaining.contains('@')) {
            final parts = remaining.split('@');
            remaining = parts[0].trim();
            item = parts[1].trim();
          }

          if (remaining.endsWith('(M)') || remaining.endsWith('(F)')) {
            gender = remaining.substring(remaining.length - 2, remaining.length - 1);
            remaining = remaining.substring(0, remaining.length - 3).trim();
          }

          if (remaining.contains('(') && remaining.endsWith(')')) {
            final firstOpen = remaining.indexOf('(');
            nickname = remaining.substring(0, firstOpen).trim();
            species = remaining.substring(firstOpen + 1, remaining.length - 1).trim();
          } else {
            species = remaining;
          }
        } else if (line.startsWith('Ability:')) {
          ability = line.replaceFirst('Ability:', '').trim();
        } else if (line.startsWith('Level:')) {
          level = int.tryParse(line.replaceFirst('Level:', '').trim()) ?? 100;
        } else if (line.startsWith('Shiny:')) {
          isShiny = line.toLowerCase().contains('yes');
        } else if (line.endsWith('Nature')) {
          nature = line.replaceFirst('Nature', '').trim();
        } else if (line.startsWith('EVs:')) {
          final parts = line.replaceFirst('EVs:', '').trim().split('/');
          for (final part in parts) {
            final tokens = part.trim().split(' ');
            if (tokens.length >= 2) {
              final val = int.tryParse(tokens[0]) ?? 0;
              final stat = tokens[1];
              if (evs.containsKey(stat)) evs[stat] = val;
            }
          }
        } else if (line.startsWith('IVs:')) {
          final parts = line.replaceFirst('IVs:', '').trim().split('/');
          for (final part in parts) {
            final tokens = part.trim().split(' ');
            if (tokens.length >= 2) {
              final val = int.tryParse(tokens[0]) ?? 31;
              final stat = tokens[1];
              if (ivs.containsKey(stat)) ivs[stat] = val;
            }
          }
        } else if (line.startsWith('-')) {
          moves.add(line.replaceFirst('-', '').trim());
        }
      }

      if (species.isNotEmpty) {
        team.add(PokemonTeamMember(
          species: species,
          nickname: nickname,
          item: item,
          ability: ability,
          gender: gender,
          level: level,
          isShiny: isShiny,
          nature: nature,
          evs: evs,
          ivs: ivs,
          moves: moves,
        ));
      }
    }

    return team;
  }
}
