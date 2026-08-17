import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:shared_preferences/shared_preferences.dart';
import '../services/js_engine_service.dart';
import '../services/stat_calculator.dart';
import '../services/team_text_codec.dart';
import '../widgets/ev_editor_panel.dart';
import '../widgets/details_editor_panel.dart';
import '../widgets/iv_level_editor_panel.dart';

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

class TeamBuilderScreen extends StatefulWidget {
  const TeamBuilderScreen({super.key});

  @override
  State<TeamBuilderScreen> createState() => _TeamBuilderScreenState();
}

class _TeamBuilderScreenState extends State<TeamBuilderScreen> {
  final _service = JsEngineService();
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  static const _storageKey = 'saved_team';

  List<Map<String, dynamic>> _baseSpeciesList = [];
  List<Map<String, dynamic>> _filtered = [];
  List<String> _itemList = [];
  List<TeamMember> _team = [];

  // Key caches and UI state by TeamMember reference for stability across list re-orders
  final Map<TeamMember, List<String>> _movesCache = {};
  final Map<TeamMember, List<Map<String, dynamic>>> _abilitiesCache = {};
  final Map<TeamMember, String?> _activePanels = {};
  final Set<TeamMember> _collapsedCards = {};

  bool _loading = true;
  String _statusMessage = '';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _unfocus() {
    _searchFocusNode.unfocus();
    FocusScope.of(context).unfocus();
  }

  Future<void> _loadData() async {
    try {
      await _service.init();
      if (!mounted) return;

      final baseList = await _service.getBaseSpeciesList();
      if (!mounted) return;

      final items = await _service.getItemList();
      if (!mounted) return;

      await _loadSavedTeam();
      if (!mounted) return;

      setState(() {
        _baseSpeciesList = baseList;
        _itemList = items;
        _filtered = [];
        _loading = false;
        for (final member in _team) {
          _collapsedCards.add(member);
        }
      });
    } catch (e, stack) {
      debugPrint('Initialization Error: $e\n$stack');
      if (!mounted) return;
      setState(() {
        _statusMessage = 'Error loading Pokémon roster: $e';
        _loading = false;
      });
    }
  }

  Future<void> _loadSavedTeam() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_storageKey);
    if (saved != null) {
      final List<dynamic> decoded = json.decode(saved);
      _team = decoded.map((m) => TeamMember.fromJson(m)).toList();
    }
  }

  Future<void> _saveTeam() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = json.encode(_team.map((m) => m.toJson()).toList());
    await prefs.setString(_storageKey, encoded);
  }

  void _applyVgcPreset() async {
    _unfocus();
    setState(() {
      for (final m in _team) {
        m.level = 50;
        m.ivs = {'HP': 31, 'Atk': 31, 'Def': 31, 'SpA': 31, 'SpD': 31, 'Spe': 31};
      }
    });
    await _saveTeam();
    if (!mounted) return;
    _announce('Applied VGC Preset: All members set to Level 50 with 31 IVs.');
  }

  void _filter(String query) {
    final q = query.trim().toLowerCase();
    setState(() {
      if (q.isEmpty) {
        _filtered = [];
      } else {
        _filtered = _baseSpeciesList
            .where((p) => p['name'].toString().toLowerCase().contains(q))
            .toList();
      }
    });
  }

  Future<void> _handleSpeciesTap(Map<String, dynamic> baseEntry) async {
    _unfocus();
    final int pokedexNumber = baseEntry['num'] as int;

    // Species Clause Check
    if (_team.any((m) => m.pokedexNumber == pokedexNumber)) {
      _announce('Species Clause Violation: Pokédex #$pokedexNumber is already on your team.');
      return;
    }

    if (_team.length >= 6) {
      _announce('Team is full. Maximum of 6 Pokémon allowed.');
      return;
    }

    final formes = await _service.getFormesForSpecies(baseEntry['name']);
    if (!mounted) return;

    String selectedForm = baseEntry['name'];

    if (formes.length > 1) {
      final chosen = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Select Form for ${baseEntry['name']}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: formes.map((f) {
                final String fName = f['name'];
                final List<String> fTypes = List<String>.from(f['types'] ?? []);
                return ListTile(
                  title: Text(fName),
                  subtitle: Text('Types: ${fTypes.join('/')}'),
                  onTap: () => Navigator.pop(context, fName),
                );
              }).toList(),
            ),
          ),
        ),
      );
      if (!mounted || chosen == null) return;
      selectedForm = chosen;
    }

    await _addToTeam(selectedForm, pokedexNumber);
  }

  Future<void> _addToTeam(String formName, int pokedexNumber) async {
    try {
      final data = await _service.getPokemon(formName);
      if (!mounted) return;
      final types = List<String>.from(data['types'] ?? []);

      List<String?> defaultMoves = List.filled(4, null);
      String? defaultAbility;

      final abilities = await _service.getAbilitiesForPokemon(formName);
      if (!mounted) return;
      if (abilities.isNotEmpty) defaultAbility = abilities.first['name'];

      try {
        final movesData = await _service.getMovesForSpecies(formName);
        if (mounted) {
          for (int i = 0; i < 4 && i < movesData.length; i++) {
            defaultMoves[i] = movesData[i]['name'].toString();
          }
        }
      } catch (_) {}

      int genderRate = 4;
      try {
        genderRate = await _service.getGenderRate(formName);
      } catch (_) {}

      if (!mounted) return;

      String defaultGender = (genderRate == -1) ? 'Genderless' : ((genderRate == 8) ? 'Female' : 'Male');

      final newMember = TeamMember(
        name: formName,
        pokedexNumber: pokedexNumber,
        types: types,
        ability: defaultAbility,
        moves: defaultMoves,
        gender: defaultGender,
        genderRate: genderRate,
      );

      setState(() {
        _team.add(newMember);
        _collapsedCards.add(newMember);
        _searchController.clear();
        _filtered = [];
      });
      await _saveTeam();
      if (!mounted) return;
      _announce('$formName added to your team.');
    } catch (e, stack) {
      debugPrint('Error adding $formName: $e\n$stack');
      if (!mounted) return;
      _announce('Could not add $formName.');
    } finally {
      _unfocus();
    }
  }

  Future<void> _confirmRemoveFromTeam(int index) async {
    _unfocus();
    final member = _team[index];
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Pokémon?'),
        content: Text('Remove ${member.name} from your team? This cannot be undone.'),
        actions: [
          TextButton(
            style: _inverseTextButtonStyle,
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: _inverseFilledButtonStyle,
            onPressed: () => Navigator.pop(context, true),
            child: Text('Remove ${member.name}'),
          ),
        ],
      ),
    );

    _unfocus();
    if (mounted && confirmed == true) {
      await _removeFromTeam(index);
    }
  }

  Future<void> _removeFromTeam(int index) async {
    final member = _team[index];
    final removed = member.name;
    setState(() {
      _team.removeAt(index);
      _movesCache.remove(member);
      _abilitiesCache.remove(member);
      _activePanels.remove(member);
      _collapsedCards.remove(member);
    });
    await _saveTeam();
    if (!mounted) return;
    _announce('$removed removed from team.');
  }

  void _toggleCardCollapsed(TeamMember member) {
    setState(() {
      if (_collapsedCards.contains(member)) {
        _collapsedCards.remove(member);
      } else {
        _collapsedCards.add(member);
        _activePanels[member] = null;
      }
    });
  }

  Future<void> _setHeldItem(int index, String item) async {
    final cleanItem = item.trim().toLowerCase();

    if (cleanItem.isNotEmpty) {
      final duplicateMember = _team.firstWhere(
        (m) => m.heldItem?.trim().toLowerCase() == cleanItem && _team.indexOf(m) != index,
        orElse: () => TeamMember(name: '', pokedexNumber: -1),
      );

      if (duplicateMember.pokedexNumber != -1) {
        _announce('Item Clause Violation: ${duplicateMember.name.toUpperCase()} is already holding $cleanItem.');
        return;
      }
    }

    setState(() => _team[index].heldItem = cleanItem.isEmpty ? null : cleanItem);
    await _saveTeam();
    if (!mounted) return;
    _announce('${_team[index].name} is now holding ${cleanItem.isEmpty ? "no item" : cleanItem}.');
  }

  void _togglePanel(TeamMember member, String panelName) async {
    _unfocus();
    setState(() {
      if (_activePanels[member] == panelName) {
        _activePanels[member] = null;
      } else {
        _activePanels[member] = panelName;
      }
    });

    if (_activePanels[member] != null) {
      if (!_movesCache.containsKey(member)) {
        try {
          final movesData = await _service.getMovesForSpecies(member.name);
          if (!mounted) return;
          final moves = movesData.map((m) => m['name'].toString()).toList();
          setState(() => _movesCache[member] = moves);
        } catch (_) {}
      }
      if (!_abilitiesCache.containsKey(member)) {
        try {
          final abilities = await _service.getAbilitiesForPokemon(member.name);
          if (!mounted) return;
          setState(() => _abilitiesCache[member] = abilities);
        } catch (_) {}
      }
    }
  }

  Future<void> _setMove(int teamIndex, int moveSlot, String? move) async {
    setState(() => _team[teamIndex].moves[moveSlot] = move);
    await _saveTeam();
  }

  Future<void> _setNature(int index, String nature) async {
    setState(() => _team[index].nature = nature);
    await _saveTeam();
  }

  Future<void> _setAbility(int index, String ability) async {
    setState(() => _team[index].ability = ability);
    await _saveTeam();
  }

  Future<void> _setGender(int index, String gender) async {
    setState(() => _team[index].gender = gender);
    await _saveTeam();
  }

  Future<void> _setLevel(int index, int level) async {
    setState(() => _team[index].level = level);
    await _saveTeam();
  }

  Future<void> _setIvs(int index, Map<String, int> ivs) async {
    setState(() => _team[index].ivs = ivs);
    await _saveTeam();
  }

  bool _isValidMegaItem(String heldItem, String formKey) {
    if (heldItem.isEmpty) return false;
    final item = heldItem.toLowerCase().trim();

    if (item == 'eviolite') return false;

    if (formKey.contains('-mega-x')) {
      return item.endsWith('x') && item.contains('ite');
    } else if (formKey.contains('-mega-y')) {
      return item.endsWith('y') && item.contains('ite');
    } else {
      return item.endsWith('ite') ||
          item == 'red-orb' ||
          item == 'blue-orb' ||
          item == 'red orb' ||
          item == 'blue orb';
    }
  }

  Future<MapEntry<String, Map<String, int>>?> _resolveActiveMega(TeamMember member) async {
    final heldItem = (member.heldItem ?? '').toLowerCase().trim();
    if (heldItem.isEmpty) return null;

    final allMegaStats = await _service.getAllMegaBaseStats(member.name);
    if (!mounted || allMegaStats.isEmpty) return null;

    for (final entry in allMegaStats.entries) {
      if (_isValidMegaItem(heldItem, entry.key)) {
        return MapEntry(entry.key, entry.value);
      }
    }
    return null;
  }

  Future<void> _showStats(TeamMember member) async {
    _unfocus();
    try {
      final natureInfo = await _service.getNatureBoosts(member.nature);
      if (!mounted) return;
      final boosted = natureInfo['plus'] ?? '';
      final lowered = natureInfo['minus'] ?? '';

      final pokemonData = await _service.getPokemon(member.name);
      if (!mounted) return;
      final rawStats = pokemonData['baseStats'] as Map<String, dynamic>;
      final normalBaseStats = rawStats.map((k, v) => MapEntry(k, (v as num).toInt()));

      final normalStats = StatCalculator.calculate(
        baseStats: normalBaseStats,
        evs: member.evs,
        ivs: member.ivs,
        level: member.level,
        natureBoosted: boosted,
        natureLowered: lowered,
      );

      Map<String, int>? megaStats;
      String? megaFormName;
      String? megaAbility;
      List<String> megaTypes = [];

      final activeMega = await _resolveActiveMega(member);
      if (!mounted) return;
      if (activeMega != null) {
        megaFormName = activeMega.key;
        final megaData = await _service.getPokemon(megaFormName);
        if (!mounted) return;
        megaTypes = List<String>.from(megaData['types'] ?? []);
        megaStats = StatCalculator.calculate(
          baseStats: activeMega.value,
          evs: member.evs,
          ivs: member.ivs,
          level: member.level,
          natureBoosted: boosted,
          natureLowered: lowered,
        );
        try {
          final abilities = await _service.getAbilitiesForPokemon(megaFormName);
          if (mounted && abilities.isNotEmpty) {
            megaAbility = abilities.first['name'] as String;
          }
        } catch (_) {}
      }

      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('${member.name.toUpperCase()} — Level ${member.level} Stats'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Types: ${member.types.join("/")}'),
                Text('Gender: ${member.gender} • Nature: ${member.nature}'),
                const SizedBox(height: 8),
                Text(
                  'IVs: ${member.ivs.entries.map((e) => "${e.key} ${e.value}").join(", ")}',
                  style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
                ),
                const SizedBox(height: 12),
                const Text('Base Form', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ..._buildStatRows(normalStats, boosted, lowered),
                if (megaStats != null) ...[
                  const SizedBox(height: 16),
                  Text('Mega Evolution: $megaFormName', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  Text('Mega Types: ${megaTypes.join("/")}', style: const TextStyle(fontSize: 13)),
                  if (megaAbility != null) Text('Ability: $megaAbility', style: const TextStyle(fontStyle: FontStyle.italic)),
                  const SizedBox(height: 4),
                  ..._buildStatRows(megaStats, boosted, lowered),
                ] else ...[
                  const SizedBox(height: 16),
                  const Text(
                    'No Mega Evolution active. Hold the correct Mega Stone to Mega Evolve.',
                    style: TextStyle(color: Colors.orange, fontSize: 13, fontStyle: FontStyle.italic),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            FilledButton(
              style: _inverseFilledButtonStyle,
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      _announce('Could not load stats for ${member.name}.');
    } finally {
      _unfocus();
    }
  }

  List<Widget> _buildStatRows(Map<String, int> stats, String boosted, String lowered) {
    return stats.entries.map((e) {
      final isBoosted = (e.key == 'Atk' && boosted == 'Attack') ||
          (e.key == 'Def' && boosted == 'Defense') ||
          (e.key == 'SpA' && boosted == 'Sp. Atk') ||
          (e.key == 'SpD' && boosted == 'Sp. Def') ||
          (e.key == 'Spe' && boosted == 'Speed');
      final isLowered = (e.key == 'Atk' && lowered == 'Attack') ||
          (e.key == 'Def' && lowered == 'Defense') ||
          (e.key == 'SpA' && lowered == 'Sp. Atk') ||
          (e.key == 'SpD' && lowered == 'Sp. Def') ||
          (e.key == 'Spe' && lowered == 'Speed');
      final suffix = isBoosted ? ' (+)' : (isLowered ? ' (-)' : '');
      return Semantics(
        label: '${e.key}: ${e.value}${isBoosted ? ", boosted" : ""}${isLowered ? ", lowered" : ""}',
        child: Text('${e.key}: ${e.value}$suffix'),
      );
    }).toList();
  }

  Future<void> _showExportDialog() async {
    _unfocus();
    if (_team.isEmpty) {
      _announce('Your team is empty. Add Pokémon before exporting.');
      return;
    }

    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text('Calculating stats...'),
          ],
        ),
      ),
    );

    final Map<int, Map<String, int>> baseStatsByIndex = {};
    final Map<int, Map<String, int>?> megaStatsByIndex = {};
    final Map<int, String?> megaFormNameByIndex = {};
    final Map<int, String?> megaAbilityByIndex = {};

    for (int i = 0; i < _team.length; i++) {
      final member = _team[i];
      try {
        final natureInfo = await _service.getNatureBoosts(member.nature);
        if (!mounted) return;
        final boosted = natureInfo['plus'] ?? '';
        final lowered = natureInfo['minus'] ?? '';

        final pokemonData = await _service.getPokemon(member.name);
        if (!mounted) return;
        final rawStats = pokemonData['baseStats'] as Map<String, dynamic>;
        final baseStats = rawStats.map((k, v) => MapEntry(k, (v as num).toInt()));

        baseStatsByIndex[i] = StatCalculator.calculate(
          baseStats: baseStats,
          evs: member.evs,
          ivs: member.ivs,
          level: member.level,
          natureBoosted: boosted,
          natureLowered: lowered,
        );

        final activeMega = await _resolveActiveMega(member);
        if (!mounted) return;
        if (activeMega != null) {
          megaFormNameByIndex[i] = activeMega.key;
          megaStatsByIndex[i] = StatCalculator.calculate(
            baseStats: activeMega.value,
            evs: member.evs,
            ivs: member.ivs,
            level: member.level,
            natureBoosted: boosted,
            natureLowered: lowered,
          );
          try {
            final abilities = await _service.getAbilitiesForPokemon(activeMega.key);
            if (mounted && abilities.isNotEmpty) {
              megaAbilityByIndex[i] = abilities.first['name'] as String;
            }
          } catch (_) {}
        }
      } catch (_) {}
    }

    if (!mounted) return;
    Navigator.pop(context); // Dismiss progress dialog

    final text = TeamTextCodec.encodeTeam(
      _team,
      baseStatsByIndex,
      megaStatsByIndex,
      megaFormNameByIndex,
      megaAbilityByIndex,
    );

    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Export Team'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Semantics(
              label: 'Team export text',
              child: SelectableText(text, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
            ),
          ),
        ),
        actions: [
          FilledButton(
            style: _inverseFilledButtonStyle,
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: text));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Copied to clipboard')),
                );
              }
            },
            child: const Text('Copy'),
          ),
          TextButton(
            style: _inverseTextButtonStyle,
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
    _unfocus();
  }

  Future<void> _showImportDialog() async {
    _unfocus();
    final controller = TextEditingController();
    final pastedText = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Import Team'),
        content: Semantics(
          label: 'Paste team text here',
          textField: true,
          child: TextField(
            controller: controller,
            maxLines: 10,
            style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.92)),
            cursorColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.85),
            decoration: _adaptiveInputDecoration('').copyWith(
              hintText: 'Paste exported team text here',
              hintStyle: TextStyle(
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.45),
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            style: _inverseTextButtonStyle,
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: _inverseFilledButtonStyle,
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Parse'),
          ),
        ],
      ),
    );

    if (!mounted || pastedText == null || pastedText.trim().isEmpty) {
      _unfocus();
      return;
    }

    List<TeamMember> parsed;
    try {
      parsed = TeamTextCodec.decodeTeam(pastedText);
    } catch (e) {
      _announce('Could not parse pasted text: ${e.toString()}');
      _unfocus();
      return;
    }

    if (!mounted) return;
    final mode = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Import Mode'),
        content: Text('Found ${parsed.length} Pokémon in the pasted text. How should this be applied?'),
        actions: [
          TextButton(
            style: _inverseTextButtonStyle,
            onPressed: () => Navigator.pop(context, 'cancel'),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: _inverseFilledButtonStyle,
            onPressed: () => Navigator.pop(context, 'add'),
            child: const Text('Add to Team'),
          ),
          FilledButton(
            style: _inverseFilledButtonStyle,
            onPressed: () => Navigator.pop(context, 'replace'),
            child: const Text('Replace Team'),
          ),
        ],
      ),
    );

    if (!mounted || mode == null || mode == 'cancel') {
      _unfocus();
      return;
    }

    if (mode == 'replace') {
      setState(() {
        _team.clear();
        _movesCache.clear();
        _abilitiesCache.clear();
        _activePanels.clear();
        _collapsedCards.clear();
      });
    }

    int failed = 0;
    final List<TeamMember> toAdd = [];

    for (final member in parsed) {
      if (_team.length + toAdd.length >= 6) break;
      try {
        final data = await _service.getPokemon(member.name);
        if (!mounted) return;

        member.pokedexNumber = (data['num'] is int)
            ? data['num'] as int
            : int.tryParse(data['id']?.toString() ?? '0') ?? 0;
        member.types = List<String>.from(data['types'] ?? []);

        try {
          member.genderRate = await _service.getGenderRate(member.name);
        } catch (_) {
          member.genderRate = 4;
        }

        // Species Clause enforcement
        if (_team.any((m) => m.pokedexNumber == member.pokedexNumber) ||
            toAdd.any((m) => m.pokedexNumber == member.pokedexNumber)) {
          failed++;
          continue;
        }
        toAdd.add(member);
      } catch (e) {
        failed++;
      }
    }

    if (!mounted) return;

    if (toAdd.isNotEmpty) {
      setState(() {
        _team.addAll(toAdd);
        for (final member in toAdd) {
          _collapsedCards.add(member);
        }
      });
    }

    await _saveTeam();
    if (!mounted) return;
    _announce('Import complete. ${toAdd.length} Pokémon added${failed > 0 ? ", $failed failed or skipped" : ""}.');
    _unfocus();
  }

  void _announce(String message) {
    setState(() => _statusMessage = message);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Team Builder')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return GestureDetector(
      onTap: _unfocus,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Team Builder'),
          actions: [
            TextButton.icon(
              onPressed: _applyVgcPreset,
              icon: const Icon(Icons.flash_on, size: 18),
              label: const Text('VGC Preset', style: TextStyle(fontSize: 12)),
            ),
            Semantics(
              button: true,
              label: 'Export team as text',
              excludeSemantics: true,
              child: IconButton(
                icon: const Icon(Icons.upload_outlined),
                onPressed: _showExportDialog,
              ),
            ),
            Semantics(
              button: true,
              label: 'Import team from text',
              excludeSemantics: true,
              child: IconButton(
                icon: const Icon(Icons.download_outlined),
                onPressed: _showImportDialog,
              ),
            ),
          ],
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: Semantics(
                label: 'Search Pokémon by base species',
                child: TextField(
                  controller: _searchController,
                  focusNode: _searchFocusNode,
                  autofocus: false,
                  style: TextStyle(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.92)),
                  cursorColor: Theme.of(context)
                      .colorScheme
                      .primary
                      .withValues(alpha: 0.85),
                  decoration: _adaptiveInputDecoration('Search Base Pokémon').copyWith(
                    prefixIcon: Icon(
                      Icons.search,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.75),
                    ),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            tooltip: 'Clear search',
                            onPressed: () {
                              _searchController.clear();
                              _filter('');
                            },
                            icon: Icon(
                              Icons.clear,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withValues(alpha: 0.75),
                            ),
                          )
                        : null,
                  ),
                  onChanged: _filter,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12.0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    'Your team: ${_team.length} of 6 slots filled',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
              ),
            ),
            if (_statusMessage.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 2.0),
                child: Semantics(
                  liveRegion: true,
                  child: Text(_statusMessage, style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
                ),
              ),
            if (_team.isNotEmpty)
              Expanded(
                flex: 5,
                child: ListView.builder(
                  itemCount: _team.length,
                  itemBuilder: (context, index) => _buildTeamCard(index),
                ),
              ),
            const Divider(height: 1),
            Expanded(
              flex: 2,
              child: _searchController.text.trim().isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(16.0),
                        child: Text(
                          'Start typing above to search for Pokémon species.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 13),
                        ),
                      ),
                    )
                  : _filtered.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Text(
                              'No Pokémon match "${_searchController.text.trim()}".',
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                        )
                      : ListView.builder(
                          itemCount: _filtered.length,
                          itemBuilder: (context, index) {
                            final entry = _filtered[index];
                            final types = List<String>.from(entry['types'] ?? []);
                            return Semantics(
                              button: true,
                              label: 'Add ${entry['name']} to team',
                              child: ListTile(
                                dense: true,
                                title: Text(entry['name']),
                                subtitle: Text('Types: ${types.join("/")}'),
                                onTap: () => _handleSpeciesTap(entry),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTeamCard(int index) {
    final member = _team[index];
    final activePanel = _activePanels[member];
    final isCollapsed = _collapsedCards.contains(member);

    final nonNullMoves = member.moves.where((m) => m != null && m.isNotEmpty).join(', ');
    final movesDisplay = nonNullMoves.isEmpty ? 'None set' : nonNullMoves;

    final theme = Theme.of(context);
    final secondaryTextColor = theme.textTheme.bodySmall?.color ?? Colors.grey;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      elevation: 1,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            label:
                '${member.name}. Types: ${member.types.join("/")}. Level ${member.level}. Item: ${member.heldItem ?? "none"}. Gender: ${member.gender}. Ability: ${member.ability ?? "none"}. Nature: ${member.nature}. EVs: ${member.evTotal} of 510. Moves: $movesDisplay.',
            child: InkWell(
              onTap: () => _toggleCardCollapsed(member),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${member.name.toUpperCase()}  #${member.pokedexNumber}',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Semantics(
                      button: true,
                      label: isCollapsed ? 'Expand ${member.name} details' : 'Collapse ${member.name} details',
                      excludeSemantics: true,
                      child: IconButton(
                        icon: Icon(isCollapsed ? Icons.expand_more : Icons.expand_less, size: 22),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                        onPressed: () => _toggleCardCollapsed(member),
                      ),
                    ),
                    Semantics(
                      button: true,
                      label: 'Remove ${member.name} from team',
                      excludeSemantics: true,
                      child: IconButton(
                        icon: const Icon(Icons.delete_outline, size: 20, color: Colors.redAccent),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                        onPressed: () => _confirmRemoveFromTeam(index),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          if (!isCollapsed) ...[
            Divider(height: 1, color: theme.dividerColor),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
              child: Wrap(
                spacing: 10,
                runSpacing: 2,
                children: [
                  Text('Types: ${member.types.join("/")}', style: const TextStyle(fontSize: 12)),
                  Text('Level: ${member.level}', style: const TextStyle(fontSize: 12)),
                  Text('Item: ${member.heldItem ?? "None"}', style: const TextStyle(fontSize: 12)),
                  Text('Gender: ${member.gender}', style: const TextStyle(fontSize: 12)),
                  Text('Ability: ${member.ability ?? "None"}', style: const TextStyle(fontSize: 12)),
                  Text('Nature: ${member.nature}', style: const TextStyle(fontSize: 12)),
                  Text('EVs: ${member.evTotal}/510', style: const TextStyle(fontSize: 12)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 6),
              child: Text(
                'Moves: $movesDisplay',
                style: TextStyle(fontSize: 12, color: secondaryTextColor, fontStyle: FontStyle.italic),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Divider(height: 1, color: theme.dividerColor),
            Container(
              color: theme.colorScheme.surfaceContainerHighest,
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildToolbarToggle(
                    emoji: '⚙️',
                    label: 'Details',
                    isActive: activePanel == 'details',
                    semanticLabel: activePanel == 'details'
                        ? 'Collapse held item, gender, ability, and nature editor for ${member.name}'
                        : 'Expand held item, gender, ability, and nature editor for ${member.name}',
                    onPressed: () => _togglePanel(member, 'details'),
                  ),
                  _buildToolbarToggle(
                    emoji: '⚔️',
                    label: 'Moves',
                    isActive: activePanel == 'moves',
                    semanticLabel: activePanel == 'moves'
                        ? 'Collapse moveset editor for ${member.name}'
                        : 'Expand moveset editor for ${member.name}',
                    onPressed: () => _togglePanel(member, 'moves'),
                  ),
                  _buildToolbarToggle(
                    emoji: '📈',
                    label: 'EVs',
                    isActive: activePanel == 'evs',
                    semanticLabel: activePanel == 'evs'
                        ? 'Collapse effort value editor for ${member.name}'
                        : 'Expand effort value editor for ${member.name}',
                    onPressed: () => _togglePanel(member, 'evs'),
                  ),
                  _buildToolbarToggle(
                    emoji: '🎚️',
                    label: 'IVs',
                    isActive: activePanel == 'ivlevel',
                    semanticLabel: activePanel == 'ivlevel'
                        ? 'Collapse level and individual value editor for ${member.name}'
                        : 'Expand level and individual value editor for ${member.name}',
                    onPressed: () => _togglePanel(member, 'ivlevel'),
                  ),
                  _buildToolbarToggle(
                    emoji: '📊',
                    label: 'Stats',
                    isActive: false,
                    semanticLabel: 'Show calculated stats for ${member.name}',
                    onPressed: () => _showStats(member),
                  ),
                ],
              ),
            ),
            if (activePanel != null) ...[
              Divider(height: 1, color: theme.dividerColor),
              Container(
                color: theme.colorScheme.surfaceContainerHigh,
                width: double.infinity,
                padding: const EdgeInsets.all(10.0),
                child: DefaultTextStyle(
                  style: TextStyle(color: theme.colorScheme.onSurface),
                  child: _buildPanelContent(index, activePanel),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildToolbarToggle({
    required String emoji,
    required String label,
    required bool isActive,
    Color? activeColor,
    required VoidCallback onPressed,
    String? semanticLabel,
  }) {
    final cs = Theme.of(context).colorScheme;
    final Color bg =
        isActive ? cs.primary.withValues(alpha: 0.25) : Colors.transparent;
    final Color emojiColor = isActive ? cs.primary : cs.onSurface;

    return Semantics(
      button: true,
      label: semanticLabel ?? label,
      selected: isActive,
      excludeSemantics: true,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(8),
          ),
          child: ExcludeSemantics(
            child: Text(
              emoji,
              style: TextStyle(
                fontSize: 22,
                color: emojiColor,
                height: 1.0,
              ),
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _adaptiveInputDecoration(String labelText) {
    final cs = Theme.of(context).colorScheme;
    final softFill = Color.alphaBlend(
      cs.onSurface.withValues(alpha: 0.10),
      cs.surfaceContainerHighest,
    );
    final border = OutlineInputBorder(
      borderSide: BorderSide(color: cs.outline.withValues(alpha: 0.45)),
    );
    return InputDecoration(
      labelText: labelText,
      labelStyle: TextStyle(
        color: cs.onSurfaceVariant.withValues(alpha: 0.90),
        fontSize: 13,
      ),
      floatingLabelStyle: TextStyle(
        color: cs.primary.withValues(alpha: 0.90),
      ),
      filled: true,
      fillColor: softFill,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      isDense: true,
      border: border,
      enabledBorder: border,
      focusedBorder: OutlineInputBorder(
        borderSide: BorderSide(
          color: cs.primary.withValues(alpha: 0.75),
          width: 1.5,
        ),
      ),
      errorStyle: TextStyle(color: cs.error),
    );
  }

  Color get _dropdownMenuColor {
    final cs = Theme.of(context).colorScheme;
    return Color.alphaBlend(
      cs.onSurface.withValues(alpha: 0.08),
      cs.surfaceContainerHigh,
    );
  }

  Color get _fieldTextColor =>
      Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.92);

  ButtonStyle get _inverseFilledButtonStyle {
    final cs = Theme.of(context).colorScheme;
    return FilledButton.styleFrom(
      backgroundColor: cs.primaryContainer.withValues(alpha: 0.85),
      foregroundColor: cs.onPrimaryContainer,
      disabledBackgroundColor: cs.surfaceContainerHighest.withValues(alpha: 0.5),
      disabledForegroundColor: cs.onSurface.withValues(alpha: 0.38),
    );
  }

  ButtonStyle get _inverseTextButtonStyle {
    final cs = Theme.of(context).colorScheme;
    return TextButton.styleFrom(
      foregroundColor: cs.primary.withValues(alpha: 0.90),
    );
  }

  Widget _buildPanelContent(int index, String panelName) {
    final member = _team[index];

    if (panelName == 'moves') {
      final moveOptions = _movesCache[member];
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Configure Moveset',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(height: 6),
          if (moveOptions == null)
            const Center(child: CircularProgressIndicator())
          else if (moveOptions.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8.0),
              child: Text(
                'No learnable moves found for this Pokémon.',
                style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
              ),
            )
          else
            ...List.generate(2, (row) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    for (int col = 0; col < 2; col++) ...[
                      if (col > 0) const SizedBox(width: 8),
                      Expanded(
                        child: Builder(builder: (_) {
                          final slot = row * 2 + col;
                          return Semantics(
                            label:
                                'Move slot ${slot + 1} for ${member.name}',
                            child: DropdownButtonFormField<String>(
                              value: member.moves[slot],
                              isExpanded: true,
                              dropdownColor: _dropdownMenuColor,
                              style: TextStyle(
                                  color: _fieldTextColor, fontSize: 14),
                              decoration: _adaptiveInputDecoration(
                                  'Move ${slot + 1}'),
                              items: [
                                DropdownMenuItem(
                                  value: null,
                                  child: Text('None',
                                      style: TextStyle(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurface
                                              .withValues(alpha: 0.70))),
                                ),
                                ...moveOptions.map((m) => DropdownMenuItem(
                                      value: m,
                                      child: Text(m,
                                          style: TextStyle(
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .onSurface
                                                  .withValues(alpha: 0.92))),
                                    )),
                              ],
                              onChanged: (value) =>
                                  _setMove(index, slot, value),
                            ),
                          );
                        }),
                      ),
                    ],
                  ],
                ),
              );
            }),
        ],
      );
    }

    if (panelName == 'details') {
      return DetailsEditorPanel(
        heldItem: member.heldItem,
        gender: member.gender,
        genderRate: member.genderRate,
        ability: member.ability,
        abilities: _abilitiesCache[member],
        nature: member.nature,
        itemList: _itemList,
        onChanged: ({heldItem, gender, ability, nature}) async {
          if (heldItem != null) await _setHeldItem(index, heldItem);
          if (gender != null) await _setGender(index, gender);
          if (ability != null) await _setAbility(index, ability);
          if (nature != null) await _setNature(index, nature);
        },
      );
    }

    if (panelName == 'evs') {
      return EvEditorPanel(
        key: ValueKey('evs-${member.name}-$index'),
        evs: member.evs,
        onChanged: (updatedEvs) async {
          setState(() => member.evs = updatedEvs);
          await _saveTeam();
        },
      );
    }

    if (panelName == 'ivlevel') {
      return IvLevelEditorPanel(
        key: ValueKey('ivlevel-${member.name}-$index'),
        level: member.level,
        ivs: member.ivs,
        onLevelChanged: (level) => _setLevel(index, level),
        onIvsChanged: (ivs) => _setIvs(index, ivs),
      );
    }

    return const SizedBox.shrink();
  }
}
