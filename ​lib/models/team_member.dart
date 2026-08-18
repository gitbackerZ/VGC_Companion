class TeamMember {
  String name;
  int pokedexNumber;
  List<String> types;
  String? heldItem;
  List<String?> moves;
  String nature;
  Map<String, int> evs;
  Map<String, int> ivs;
  int level;
  String? ability;
  String gender;
  int genderRate;

  TeamMember({
    required this.name,
    required this.pokedexNumber,
    List<String>? types,
    this.heldItem,
    List<String?>? moves,
    this.nature = 'Hardy',
    Map<String, int>? evs,
    Map<String, int>? ivs,
    this.level = 50,
    this.ability,
    this.gender = 'Male',
    this.genderRate = 4,
  })  : types = types ?? [],
        moves = moves ?? List.filled(4, null),
        evs = evs ?? {'HP': 0, 'Atk': 0, 'Def': 0, 'SpA': 0, 'SpD': 0, 'Spe': 0},
        ivs = ivs ?? {'HP': 31, 'Atk': 31, 'Def': 31, 'SpA': 31, 'SpD': 31, 'Spe': 31};

  int get evTotal => evs.values.fold(0, (a, b) => a + b);

  Map<String, dynamic> toJson() => {
        'name': name,
        'pokedexNumber': pokedexNumber,
        'types': types,
        'heldItem': heldItem,
        'moves': moves,
        'nature': nature,
        'evs': evs,
        'ivs': ivs,
        'level': level,
        'ability': ability,
        'gender': gender,
        'genderRate': genderRate,
      };

  factory TeamMember.fromJson(Map<String, dynamic> json) => TeamMember(
        name: json['name'],
        pokedexNumber: json['pokedexNumber'],
        types: List<String>.from(json['types'] ?? []),
        heldItem: json['heldItem'],
        moves: List<String?>.from(json['moves'] ?? List.filled(4, null)),
        nature: json['nature'] ?? 'Hardy',
        evs: Map<String, int>.from(json['evs'] ?? {'HP': 0, 'Atk': 0, 'Def': 0, 'SpA': 0, 'SpD': 0, 'Spe': 0}),
        ivs: Map<String, int>.from(json['ivs'] ?? {'HP': 31, 'Atk': 31, 'Def': 31, 'SpA': 31, 'SpD': 31, 'Spe': 31}),
        level: json['level'] ?? 50,
        ability: json['ability'],
        gender: json['gender'] ?? 'Male',
        genderRate: json['genderRate'] ?? 4,
      );
}
