import '../models/team_member.dart';

class TeamTextCodec {
  /// Encodes a team into standard Pokémon Showdown multiline text format.
  static String encodeTeam(
    List<TeamMember> team, [
    Map<int, Map<String, int>>? baseStatsByIndex,
    Map<int, Map<String, int>?>? megaStatsByIndex,
    Map<int, String?>? megaFormNameByIndex,
    Map<int, String?>? megaAbilityByIndex,
  ]) {
    final buffer = StringBuffer();

    for (int i = 0; i < team.length; i++) {
      final m = team[i];

      // Header: Species @ Item
      if (m.heldItem != null && m.heldItem!.trim().isNotEmpty) {
        buffer.writeln('${m.name} @ ${_capitalize(m.heldItem!)}');
      } else {
        buffer.writeln(m.name);
      }

      // Ability
      if (m.ability != null && m.ability!.trim().isNotEmpty) {
        buffer.writeln('Ability: ${_capitalize(m.ability!)}');
      }

      // Level
      buffer.writeln('Level: ${m.level}');

      // Gender (Showdown format: Gender: M/F)
      if (m.gender == 'Male' || m.gender == 'M') {
        buffer.writeln('Gender: M');
      } else if (m.gender == 'Female' || m.gender == 'F') {
        buffer.writeln('Gender: F');
      }

      // EVs
      final evParts = <String>[];
      final statKeys = ['HP', 'Atk', 'Def', 'SpA', 'SpD', 'Spe'];
      for (final stat in statKeys) {
        final val = m.evs[stat] ?? 0;
        if (val > 0) evParts.add('$val $stat');
      }
      if (evParts.isNotEmpty) {
        buffer.writeln('EVs: ${evParts.join(' / ')}');
      }

      // Nature
      final cleanNature = _cleanNatureName(m.nature);
      buffer.writeln('$cleanNature Nature');

      // IVs
      final ivParts = <String>[];
      for (final stat in statKeys) {
        final val = m.ivs[stat] ?? 31;
        if (val < 31) ivParts.add('$val $stat');
      }
      if (ivParts.isNotEmpty) {
        buffer.writeln('IVs: ${ivParts.join(' / ')}');
      }

      // Moves
      for (final move in m.moves) {
        if (move != null && move.trim().isNotEmpty && move.toLowerCase() != 'none') {
          buffer.writeln('- ${_capitalize(move)}');
        }
      }

      if (i < team.length - 1) buffer.writeln();
    }

    return buffer.toString();
  }

  /// Encodes a team into Pokémon Showdown Packed format (`Mon1]Mon2]Mon3...`).
  static String encodePackedTeam(List<TeamMember> team) {
    return team.map((m) => _memberToPacked(m)).join(']');
  }

  /// Converts standard Showdown multiline text into Showdown Packed format.
  static String toPackedFormat(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return '';
    if (trimmed.contains(']')) return trimmed; // Already in packed format

    try {
      final members = decodeTeam(trimmed);
      return encodePackedTeam(members);
    } catch (_) {
      return '';
    }
  }

  static String _memberToPacked(TeamMember m) {
    final species = m.name.trim();
    final item = _cleanId(m.heldItem ?? '');
    final ability = _cleanId(m.ability ?? '');

    final validMoves = m.moves
        .where((move) => move != null && move.trim().isNotEmpty && move.toLowerCase() != 'none')
        .map((move) => _cleanId(move!))
        .join(',');

    final nature = _cleanNatureName(m.nature);

    final statKeys = ['HP', 'Atk', 'Def', 'SpA', 'SpD', 'Spe'];
    final evsList = statKeys.map((s) => (m.evs[s] ?? 0).toString()).join(',');
    final evsString = evsList == '0,0,0,0,0,0' ? '' : evsList;

    final gender = (m.gender == 'Female' || m.gender == 'F')
        ? 'F'
        : ((m.gender == 'Male' || m.gender == 'M') ? 'M' : '');

    final ivsList = statKeys.map((s) => (m.ivs[s] ?? 31).toString()).join(',');
    final ivsString = ivsList == '31,31,31,31,31,31' ? '' : ivsList;

    final level = m.level == 100 ? '' : m.level.toString();

    // Showdown packed structure: name|species|item|ability|moves|nature|evs|gender|ivs|shiny|level|happiness
    return '$species||$item|$ability|$validMoves|$nature|$evsString|$gender|$ivsString||$level|';
  }

  /// Parses Pokémon Showdown formatted text or packed strings into TeamMember instances.
  static List<TeamMember> decodeTeam(String text) {
    final List<TeamMember> result = [];
    final trimmed = text.trim();

    if (trimmed.isEmpty) {
      throw const FormatException('Team text is empty.');
    }

    if (trimmed.contains(']')) {
      final packedBlocks = trimmed.split(']');
      for (final block in packedBlocks) {
        if (block.trim().isEmpty) continue;
        final parts = block.split('|');
        if (parts.isEmpty) continue;

        final name = parts[0].trim();
        final species = (parts.length > 1 && parts[1].trim().isNotEmpty) ? parts[1].trim() : name;
        final item = parts.length > 2 ? parts[2].trim() : '';
        final ability = parts.length > 3 ? parts[3].trim() : '';
        final movesList = parts.length > 4 ? parts[4].split(',').map((m) => m.trim()).toList() : <String>[];
        final nature = (parts.length > 5 && parts[5].trim().isNotEmpty) ? _cleanNatureName(parts[5]) : 'Hardy';

        final Map<String, int> evs = {'HP': 0, 'Atk': 0, 'Def': 0, 'SpA': 0, 'SpD': 0, 'Spe': 0};
        if (parts.length > 6 && parts[6].trim().isNotEmpty) {
          final evVals = parts[6].split(',').map((e) => int.tryParse(e) ?? 0).toList();
          final keys = ['HP', 'Atk', 'Def', 'SpA', 'SpD', 'Spe'];
          for (int i = 0; i < keys.length && i < evVals.length; i++) {
            evs[keys[i]] = evVals[i];
          }
        }

        final genderRaw = parts.length > 7 ? parts[7].trim().toUpperCase() : '';
        final gender = genderRaw == 'F' ? 'Female' : (genderRaw == 'M' ? 'Male' : 'Genderless');

        int level = 100;
        if (parts.length > 10 && parts[10].trim().isNotEmpty) {
          level = int.tryParse(parts[10].trim()) ?? 100;
        }

        List<String?> moves = List.filled(4, null);
        for (int i = 0; i < 4 && i < movesList.length; i++) {
          if (movesList[i].isNotEmpty) moves[i] = movesList[i];
        }

        if (species.isNotEmpty) {
          result.add(TeamMember(
            name: species,
            pokedexNumber: 0,
            heldItem: item,
            ability: ability,
            level: level,
            gender: gender,
            nature: nature,
            moves: moves,
            evs: evs,
            ivs: {'HP': 31, 'Atk': 31, 'Def': 31, 'SpA': 31, 'SpD': 31, 'Spe': 31},
          ));
        }
      }

      if (result.isEmpty) {
        throw const FormatException('No valid Pokémon found in packed format.');
      }
      return result;
    }

    final blocks = trimmed.split(RegExp(r'\n\s*\n'));

    for (final block in blocks) {
      if (block.trim().isEmpty) continue;
      final lines = block.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();

      // Find the first non-move line to use as the header
      final headerIndex = lines.indexWhere((line) => !line.startsWith('-'));
      if (headerIndex == -1) continue; // Ignore blocks containing only moves

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

        if (i == headerIndex) {
          final headerData = _parseHeaderLine(line);
          species = headerData['species'];
          heldItem = headerData['item'];
          if (headerData['gender']!.isNotEmpty) {
            gender = headerData['gender']!;
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
          nature = _cleanNatureName(line);
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

      if (species != null && species.isNotEmpty && !species.startsWith('-')) {
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

  static Map<String, String> _parseHeaderLine(String line) {
    String remaining = line.trim();
    String item = '';
    String gender = '';
    String species = '';

    if (remaining.contains('@')) {
      final parts = remaining.split('@');
      remaining = parts[0].trim();
      item = parts.sublist(1).join('@').trim();
    }

    final genderMatch = RegExp(r'\s*\(([MF])\)$', caseSensitive: false).firstMatch(remaining);
    if (genderMatch != null) {
      final g = genderMatch.group(1)!.toUpperCase();
      gender = g == 'F' ? 'Female' : 'Male';
      remaining = remaining.substring(0, genderMatch.start).trim();
    }

    final speciesMatch = RegExp(r'^(.*?)\s*\(([^)]+)\)$').firstMatch(remaining);
    if (speciesMatch != null) {
      species = speciesMatch.group(2)!.trim();
    } else {
      species = remaining.trim();
    }

    return {
      'species': species,
      'item': item,
      'gender': gender,
    };
  }

  static String _cleanNatureName(String text) {
    String clean = text.replaceAll(RegExp(r'\s*Nature\s*', caseSensitive: false), '').trim();
    if (clean.isEmpty) return 'Hardy';
    return _capitalize(clean);
  }

  static String _cleanId(String text) {
    return text.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  static String _capitalize(String text) {
    if (text.isEmpty) return text;
    return text.split(RegExp(r'[\s-]')).map((s) => s.isEmpty ? '' : s[0].toUpperCase() + s.substring(1)).join(' ');
  }
}
