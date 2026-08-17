import '../screens/team_builder.dart' show TeamMember;

class TeamTextCodec {
  static String encodeTeam(
    List<TeamMember> team,
    Map<int, Map<String, int>> baseStatsByIndex,
    Map<int, Map<String, int>?> megaStatsByIndex,
    Map<int, String?> megaFormNameByIndex,
    Map<int, String?> megaAbilityByIndex,
  ) {
    final buffer = StringBuffer();
    for (int i = 0; i < team.length; i++) {
      final m = team[i];
      buffer.writeln('=== POKEMON ${i + 1} ===');
      buffer.writeln('Species: ${m.name}');
      buffer.writeln('Level: ${m.level}');
      buffer.writeln('Gender: ${m.gender}');
      buffer.writeln('Held Item: ${m.heldItem ?? "None"}');
      buffer.writeln('Ability: ${m.ability ?? "None"}');
      buffer.writeln('Nature: ${m.nature}');
      final moveList = m.moves.map((mv) => mv ?? 'None').join(', ');
      buffer.writeln('Moves: $moveList');
      final evList = m.evs.entries.map((e) => '${e.key}=${e.value}').join(', ');
      buffer.writeln('EVs: $evList');
      final ivList = m.ivs.entries.map((e) => '${e.key}=${e.value}').join(', ');
      buffer.writeln('IVs: $ivList');

      final baseStats = baseStatsByIndex[i];
      if (baseStats != null) {
        final statList = baseStats.entries.map((e) => '${e.key}=${e.value}').join(', ');
        buffer.writeln('Final Stats (Base Form): $statList');
      }

      final megaStats = megaStatsByIndex[i];
      if (megaStats != null) {
        final megaFormName = megaFormNameByIndex[i] ?? '${m.name}-mega';
        final megaAbility = megaAbilityByIndex[i];
        buffer.writeln('Mega Form Name: $megaFormName');
        if (megaAbility != null) {
          buffer.writeln('Mega Form Ability: $megaAbility');
        }
        final megaStatList = megaStats.entries.map((e) => '${e.key}=${e.value}').join(', ');
        buffer.writeln('Final Stats (Mega Form): $megaStatList');
      }

      buffer.writeln('=== END ===');
      if (i < team.length - 1) buffer.writeln();
    }
    return buffer.toString();
  }

  /// Parses pasted text back into a list of TeamMember objects.
  /// Note: "Final Stats" and "Mega Form" lines are informational only on import
  /// (they are recalculated live in-app) and are safely ignored by the parser.
  static List<TeamMember> decodeTeam(String text) {
    final List<TeamMember> result = [];
    final blocks = text.split(RegExp(r'===\s*POKEMON\s+\d+\s*==='));

    for (final rawBlock in blocks) {
      final block = rawBlock.trim();
      if (block.isEmpty) continue;

      final lines = block.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();

      String? species;
      int level = 50;
      String gender = 'Male';
      String? heldItem;
      String? ability;
      String nature = 'Hardy';
      List<String?> moves = List.filled(4, null);
      Map<String, int> evs = {'HP': 0, 'Atk': 0, 'Def': 0, 'SpA': 0, 'SpD': 0, 'Spe': 0};
      Map<String, int> ivs = {'HP': 31, 'Atk': 31, 'Def': 31, 'SpA': 31, 'SpD': 31, 'Spe': 31};

      for (final line in lines) {
        if (line.startsWith('===')) continue;
        if (line.startsWith('Final Stats')) continue; // informational only
        if (line.startsWith('Mega Form')) continue; // informational only

        if (line.startsWith('Species:')) {
          species = line.substring('Species:'.length).trim();
        } else if (line.startsWith('Level:')) {
          final parsed = int.tryParse(line.substring('Level:'.length).trim());
          if (parsed != null) level = parsed.clamp(1, 100);
        } else if (line.startsWith('Gender:')) {
          gender = line.substring('Gender:'.length).trim();
        } else if (line.startsWith('Held Item:')) {
          final val = line.substring('Held Item:'.length).trim();
          heldItem = (val.toLowerCase() == 'none' || val.isEmpty) ? null : val.toLowerCase();
        } else if (line.startsWith('Ability:')) {
          final val = line.substring('Ability:'.length).trim();
          ability = (val.toLowerCase() == 'none' || val.isEmpty) ? null : val;
        } else if (line.startsWith('Nature:')) {
          nature = line.substring('Nature:'.length).trim();
        } else if (line.startsWith('Moves:')) {
          final val = line.substring('Moves:'.length).trim();
          final parts = val.split(',').map((p) => p.trim()).toList();
          for (int i = 0; i < 4; i++) {
            if (i < parts.length && parts[i].toLowerCase() != 'none' && parts[i].isNotEmpty) {
              moves[i] = parts[i];
            }
          }
        } else if (line.startsWith('EVs:')) {
          final val = line.substring('EVs:'.length).trim();
          final parts = val.split(',');
          for (final part in parts) {
            final kv = part.split('=');
            if (kv.length == 2) {
              final key = kv[0].trim();
              final value = int.tryParse(kv[1].trim()) ?? 0;
              if (evs.containsKey(key)) {
                evs[key] = value.clamp(0, 252);
              }
            }
          }
        } else if (line.startsWith('IVs:')) {
          final val = line.substring('IVs:'.length).trim();
          final parts = val.split(',');
          for (final part in parts) {
            final kv = part.split('=');
            if (kv.length == 2) {
              final key = kv[0].trim();
              final value = int.tryParse(kv[1].trim()) ?? 31;
              if (ivs.containsKey(key)) {
                ivs[key] = value.clamp(0, 31);
              }
            }
          }
        }
      }

      if (species == null || species.isEmpty) {
        throw FormatException('A Pokémon block is missing a "Species:" line.');
      }

      result.add(TeamMember(
        name: species,
        pokedexNumber: 0,
        heldItem: heldItem,
        moves: moves,
        nature: nature,
        evs: evs,
        ivs: ivs,
        level: level,
        ability: ability,
        gender: gender,
      ));
    }

    if (result.isEmpty) {
      throw const FormatException('No valid Pokémon blocks found in the pasted text.');
    }
    if (result.length > 6) {
      throw const FormatException('Pasted text contains more than 6 Pokémon.');
    }

    return result;
  }
}