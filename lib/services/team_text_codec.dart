import '../models/team_member.dart';

class TeamTextCodec {
  /// Encodes a team into standard Pokémon Showdown format.
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

      // Header: Species @ Item
      if (m.heldItem != null && m.heldItem!.isNotEmpty) {
        buffer.writeln('${m.name} @ ${_capitalize(m.heldItem!)}');
      } else {
        buffer.writeln(m.name);
      }

      // Ability
      if (m.ability != null && m.ability!.isNotEmpty) {
        buffer.writeln('Ability: ${m.ability}');
      }

      // Level
      buffer.writeln('Level: ${m.level}');

      // Gender (Showdown format: Gender: M/F)
      if (m.gender == 'Male') {
        buffer.writeln('Gender: M');
      } else if (m.gender == 'Female') {
        buffer.writeln('Gender: F');
      }

      // EVs (only non-zero EVs)
      final evParts = <String>[];
      m.evs.forEach((stat, val) {
        if (val > 0) evParts.add('$val $stat');
      });
      if (evParts.isNotEmpty) {
        buffer.writeln('EVs: ${evParts.join(' / ')}');
      }

      // Nature
      buffer.writeln('${m.nature} Nature');

      // IVs (only non-31 IVs in Showdown style)
      final ivParts = <String>[];
      m.ivs.forEach((stat, val) {
        if (val < 31) ivParts.add('$val $stat');
      });
      if (ivParts.isNotEmpty) {
        buffer.writeln('IVs: ${ivParts.join(' / ')}');
      }

      // Moves
      for (final move in m.moves) {
        if (move != null && move.isNotEmpty && move.toLowerCase() != 'none') {
          buffer.writeln('- $move');
        }
      }

      if (i < team.length - 1) buffer.writeln();
    }

    return buffer.toString();
  }

  /// Parses Pokémon Showdown formatted text back into TeamMember instances.
  static List<TeamMember> decodeTeam(String text) {
    final List<TeamMember> result = [];
    final blocks = text.trim().split(RegExp(r'\n\s*\n'));

    for (final block in blocks) {
      if (block.trim().isEmpty) continue;
      final lines = block.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();

      String? species;
      String? heldItem;
      String? ability;
      int level = 50;
      String gender = 'Male';
      String nature = 'Hardy';
      List<String?> moves = List.filled(4, null);
      int moveIdx = 0;
      Map<String, int> evs = {'HP': 0, 'Atk': 0, 'Def': 0, 'SpA': 0, 'SpD': 0, 'Spe': 0};
      Map<String, int> ivs = {'HP': 31, 'Atk': 31, 'Def': 31, 'SpA': 31, 'SpD': 31, 'Spe': 31};

      for (int i = 0; i < lines.length; i++) {
        final line = lines[i];

        // First line: Species @ Item
        if (i == 0) {
          if (line.contains('@')) {
            final parts = line.split('@');
            species = parts[0].trim();
            heldItem = parts[1].trim().toLowerCase();
          } else {
            species = line.trim();
          }
          continue;
        }

        if (line.startsWith('Ability:')) {
          ability = line.substring('Ability:'.length).trim();
        } else if (line.startsWith('Level:')) {
          final parsed = int.tryParse(line.substring('Level:'.length).trim());
          if (parsed != null) level = parsed.clamp(1, 100);
        } else if (line.startsWith('Gender:')) {
          final g = line.substring('Gender:'.length).trim().toUpperCase();
          gender = g == 'F' ? 'Female' : (g == 'M' ? 'Male' : 'Genderless');
        } else if (line.endsWith('Nature')) {
          nature = line.replaceAll('Nature', '').trim();
        } else if (line.startsWith('EVs:')) {
          final raw = line.substring('EVs:'.length).trim();
          final parts = raw.split('/');
          for (final part in parts) {
            final tokens = part.trim().split(' ');
            if (tokens.length == 2) {
              final val = int.tryParse(tokens[0]) ?? 0;
              final stat = tokens[1].trim();
              if (evs.containsKey(stat)) evs[stat] = val.clamp(0, 252);
            }
          }
        } else if (line.startsWith('IVs:')) {
          final raw = line.substring('IVs:'.length).trim();
          final parts = raw.split('/');
          for (final part in parts) {
            final tokens = part.trim().split(' ');
            if (tokens.length == 2) {
              final val = int.tryParse(tokens[0]) ?? 31;
              final stat = tokens[1].trim();
              if (ivs.containsKey(stat)) ivs[stat] = val.clamp(0, 31);
            }
          }
        } else if (line.startsWith('-')) {
          if (moveIdx < 4) {
            moves[moveIdx] = line.substring(1).trim();
            moveIdx++;
          }
        }
      }

      if (species != null && species.isNotEmpty) {
        result.add(TeamMember(
          name: species,
          pokedexNumber: 0,
          heldItem: heldItem,
          ability: ability,
          level: level,
          gender: gender,
          nature: nature,
          moves: moves,
          evs: evs,
          ivs: ivs,
        ));
      }
    }

    if (result.isEmpty) {
      throw const FormatException('No valid Pokémon Showdown team blocks found.');
    }
    return result;
  }

  static String _capitalize(String text) {
    if (text.isEmpty) return text;
    return text.split('-').map((s) => s.isEmpty ? '' : s[0].toUpperCase() + s.substring(1)).join(' ');
  }
}
