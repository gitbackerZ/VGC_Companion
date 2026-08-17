class StatCalculator {
  /// Calculates final competitive stats at Level 50, IV 31, given EVs and nature.
  /// baseStats keys must match Showdown/@pkmn Dex format: hp, atk, def, spa, spd, spe
  static Map<String, int> calculate({
    required Map<String, int> baseStats,
    required Map<String, int> evs, // keys: HP, Atk, Def, SpA, SpD, Spe
    required String natureBoosted,
    required String natureLowered,
  }) {
    const level = 50;
    const iv = 31;

    int calcHp(int base, int ev) {
      return ((2 * base + iv + (ev / 4).floor()) * level / 100).floor() + level + 10;
    }

    int calcOther(int base, int ev, double natureMultiplier) {
      final raw = ((2 * base + iv + (ev / 4).floor()) * level / 100).floor() + 5;
      return (raw * natureMultiplier).floor();
    }

    double multiplierFor(String statLabel) {
      if (statLabel == natureBoosted) return 1.1;
      if (statLabel == natureLowered) return 0.9;
      return 1.0;
    }

    return {
      'HP': calcHp(baseStats['hp'] ?? 0, evs['HP'] ?? 0),
      'Atk': calcOther(baseStats['atk'] ?? 0, evs['Atk'] ?? 0, multiplierFor('Attack')),
      'Def': calcOther(baseStats['def'] ?? 0, evs['Def'] ?? 0, multiplierFor('Defense')),
      'SpA': calcOther(baseStats['spa'] ?? 0, evs['SpA'] ?? 0, multiplierFor('Sp. Atk')),
      'SpD': calcOther(baseStats['spd'] ?? 0, evs['SpD'] ?? 0, multiplierFor('Sp. Def')),
      'Spe': calcOther(baseStats['spe'] ?? 0, evs['Spe'] ?? 0, multiplierFor('Speed')),
    };
  }
}