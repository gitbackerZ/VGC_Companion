/// VGC-standard fixed values: every team member is always level 50 with
/// maximum (31) IVs in every stat. These are not user-configurable.
const int kFixedLevel = 50;
const Map<String, int> kFixedIvs = {
  'HP': 31,
  'Atk': 31,
  'Def': 31,
  'SpA': 31,
  'SpD': 31,
  'Spe': 31,
};

class TeamMember {
  String name;
  int pokedexNumber;
  List<String> types;
  String? heldItem;
  List<String?> moves;
  String nature;
  Map<String, int> evs;
  String? ability;
  String gender;
  int genderRate;

  /// Fixed at VGC standard; always level 50 with max IVs.
  int get level => kFixedLevel;
  Map<String, int> get ivs => kFixedIvs;

  TeamMember({
    required this.name,
    required this.pokedexNumber,
    List<String>? types,
    this.heldItem,
    List<String?>? moves,
    this.nature = 'Hardy',
    Map<String, int>? evs,
    this.ability,
    this.gender = 'Male',
    this.genderRate = 4,
  })  : types = types ?? [],
        moves = moves ?? List.filled(4, null),
        evs = evs ?? {'HP': 0, 'Atk': 0, 'Def': 0, 'SpA': 0, 'SpD': 0, 'Spe': 0};

  int get evTotal => evs.values.fold(0, (a, b) => a + b);

  Map<String, dynamic> toJson() => {
        'name': name,
        'pokedexNumber': pokedexNumber,
        'types': types,
        'heldItem': heldItem,
        'moves': moves,
        'nature': nature,
        'evs': evs,
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
        ability: json['ability'],
        gender: json['gender'] ?? 'Male',
        genderRate: json['genderRate'] ?? 4,
      );
}