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

class TeamMember {
  String name;
  int pokedexNumber;
  String? heldItem;
  List<String?> moves;
  String nature;
  Map<String, int> evs;
  String? ability;
  String gender;
  int genderRate; // -1 genderless, 0 always male, 8 always female, else both possible

  TeamMember({
    required this.name,
    required this.pokedexNumber,
    this.heldItem,
    List<String?>? moves,
    this.nature = 'Hardy',
    Map<String, int>? evs,
    this.ability,
    this.gender = 'Male',
    this.genderRate = 4,
  })  : moves = moves ?? List.filled(4, null),
        evs = evs ?? {'HP': 0, 'Atk': 0, 'Def': 0, 'SpA': 0, 'SpD': 0, 'Spe': 0};

  int get evTotal => evs.values.fold(0, (a, b) => a + b);

  Map<String, dynamic> toJson() => {
        'name': name,
        'pokedexNumber': pokedexNumber,
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
        heldItem: json['heldItem'],
        moves: List<String?>.from(json['moves'] ?? List.filled(4, null)),
        nature: json['nature'] ?? 'Hardy',
        evs: Map<String, int>.from(json['evs'] ?? {'HP': 0, 'Atk': 0, 'Def': 0, 'SpA': 0, 'SpD': 0, 'Spe': 0}),
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

  List<String> _allSpecies = [];
  List<String> _filtered = [];
  List<TeamMember> _team = [];

  final Map<int, List<String>> _movesCache = {};
  final Map<int, List<Map<String, dynamic>>> _abilitiesCache = {};

  final Map<int, String?> _activePanels = {};
  final Set<int> _collapsedCards = {};

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

      final allowed = await _service.getSpeciesList();

      await _loadSavedTeam();

      setState(() {
        _allSpecies = allowed;
        _filtered = [];
        _loading = false;
        for (int i = 0; i < _team.length; i++) {
          _collapsedCards.add(i);
        }
      });
    } catch (e, stack) {
      debugPrint('Engine Initialization Error: $e');
      debugPrint(stack.toString());
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

  void _filter(String query) {
    final q = query.trim().toLowerCase();
    setState(() {
      if (q.isEmpty) {
        _filtered = [];
      } else {
        _filtered =
            _allSpecies.where((p) => p.toLowerCase().contains(q)).toList();
      }
    });
  }

  int _extractPokedexNumber(Map<String, dynamic> data) {
    if (data['num'] is int) return data['num'] as int;
    if (data['id'] is int) return data['id'] as int;
    return int.tryParse(data['id']?.toString() ?? '0') ?? 0;
  }

  Future<void> _addToTeam(String name) async {
    _unfocus();
    if (_team.length >= 6) {
      _announce('Team is full. Maximum of six Pokémon.');
      return;
    }

    try {
      final String selectedFormName = name;
      final data = await _service.getPokemon(selectedFormName);

      // Safe integer extraction for Dex Number
      final pokedexNumber = _extractPokedexNumber(data);

      if (_team.any((m) => m.name == selectedFormName)) {
        _announce('$selectedFormName is already on your team.');
        return;
      }

      List<String?> defaultMoves = List.filled(4, null);
      String? defaultAbility;

      // Check payload abilities first, fallback to service call
      if (data['abilities'] is List && (data['abilities'] as List).isNotEmpty) {
        defaultAbility = (data['abilities'] as List).first.toString();
      } else {
        try {
          final abilities = await _service.getAbilitiesForPokemon(selectedFormName);
          if (abilities.isNotEmpty) {
            defaultAbility = abilities.first['name'] as String;
          }
        } catch (_) {}
      }

      // Species-specific learnset lookup instead of the full move dex
      try {
        final movesData = await _service.getMovesForSpecies(selectedFormName);
        final moves = movesData.map((m) => m['name'].toString()).toList();
        for (int i = 0; i < 4 && i < moves.length; i++) {
          defaultMoves[i] = moves[i];
        }
      } catch (_) {}

      int genderRate = 4;
      try {
        genderRate = await _service.getGenderRate(selectedFormName);
      } catch (_) {}

      String defaultGender;
      if (genderRate == -1) {
        defaultGender = 'Genderless';
      } else if (selectedFormName.endsWith('-female')) {
        defaultGender = 'Female';
      } else {
        defaultGender = 'Male';
      }

      final newMember = TeamMember(
        name: selectedFormName,
        pokedexNumber: pokedexNumber,
        ability: defaultAbility,
        moves: defaultMoves,
        gender: defaultGender,
        genderRate: genderRate,
      );

      setState(() {
        _team.add(newMember);
        _collapsedCards.add(_team.length - 1);
        _searchController.clear();
        _filtered = [];
      });
      await _saveTeam();
      _announce('$selectedFormName added to your team.');
    } catch (e, stack) {
      debugPrint('Error adding $name: $e\n$stack');
      _announce('Could not add $name. Check the name and try again.');
    } finally {
      _unfocus();
    }
  }

  Future<void> _confirmRemoveFromTeam(int index) async {
    _unfocus();
    final name = _team[index].name;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Pokémon?'),
        content: Text('Remove $name from your team? This cannot be undone.'),
        actions: [
          TextButton(
            style: _inverseTextButtonStyle,
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: _inverseFilledButtonStyle,
            onPressed: () => Navigator.pop(context, true),
            child: Text('Remove $name'),
          ),
        ],
      ),
    );

    _unfocus();
    if (confirmed == true) {
      await _removeFromTeam(index);
    }
  }

  Future<void> _removeFromTeam(int index) async {
    final removed = _team[index].name;
    setState(() {
      _team.removeAt(index);
      _movesCache.clear();
      _abilitiesCache.clear();
      _activePanels.clear();
      _collapsedCards.clear();
      for (int i = 0; i < _team.length; i++) {
        _collapsedCards.add(i);
      }
    });
    await _saveTeam();
    _announce('$removed removed from team.');
  }

  void _toggleCardCollapsed(int index) {
    setState(() {
      if (_collapsedCards.contains(index)) {
        _collapsedCards.remove(index);
      } else {
        _collapsedCards.add(index);
        _activePanels[index] = null;
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
    _announce('${_team[index].name} is now holding ${cleanItem.isEmpty ? "no item" : cleanItem}.');
  }

  void _togglePanel(int index, String panelName) async {
    _unfocus();
    setState(() {
      if (_activePanels[index] == panelName) {
        _activePanels[index] = null;
      } else {
        _activePanels[index] = panelName;
      }
    });

    if (_activePanels[index] != null) {
      if (!_movesCache.containsKey(index)) {
        try {
          // Species-specific learnset lookup instead of the full move dex
          final movesData = await _service.getMovesForSpecies(_team[index].name);
          final moves = movesData.map((m) => m['name'].toString()).toList();
          setState(() => _movesCache[index] = moves);
        } catch (_) {}
      }
      if (!_abilitiesCache.containsKey(index)) {
        try {
          final data = await _service.getPokemon(_team[index].name);
          final abilities = (data['abilities'] as List? ?? [])
              .map((a) => {'name': a.toString()})
              .toList();
          setState(() => _abilitiesCache[index] = abilities);
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

  Future<void> _setEv(int index, String stat, int value) async {
    final member = _team[index];
    final clamped = value.clamp(0, 252);
    final otherTotal = member.evTotal - member.evs[stat]!;
    final maxAllowed = (510 - otherTotal).clamp(0, 252);
    final finalValue = clamped > maxAllowed ? maxAllowed : clamped;

    setState(() => member.evs[stat] = finalValue);
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
    if (allMegaStats.isEmpty) return null;

    for (final entry in allMegaStats.entries) {
      if (_isValidMegaItem(heldItem, entry.key)) {
        return MapEntry(entry.key, entry.value);
      }
    }
    return null;
  }

  Future<void> _showStats(int index) async {
    _unfocus();
    final member = _team[index];
    try {
      final natureInfo = await _service.getNatureBoosts(member.nature);
      final boosted = natureInfo['plus'] ?? '';
      final lowered = natureInfo['minus'] ?? '';

      final pokemonData = await _service.getPokemon(member.name);
      final rawStats = pokemonData['baseStats'] as Map<String, dynamic>;
      final normalBaseStats = rawStats.map((k, v) => MapEntry(k, (v as num).toInt()));

      final normalStats = StatCalculator.calculate(
        baseStats: normalBaseStats,
        evs: member.evs,
        natureBoosted: boosted,
        natureLowered: lowered,
      );

      Map<String, int>? megaStats;
      String? megaFormName;
      String? megaAbility;

      final activeMega = await _resolveActiveMega(member);
      if (activeMega != null) {
        megaFormName = activeMega.key;
        megaStats = StatCalculator.calculate(
          baseStats: activeMega.value,
          evs: member.evs,
          natureBoosted: boosted,
          natureLowered: lowered,
        );
        try {
          final abilities = await _service.getAbilitiesForPokemon(megaFormName);
          if (abilities.isNotEmpty) {
            megaAbility = abilities.first['name'] as String;
          }
        } catch (_) {}
      }

      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('${member.name.toUpperCase()} — Level 50 Stats'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Gender: ${member.gender} • Nature: ${member.nature}'),
                const SizedBox(height: 8),
                const Text('Assumes max IVs (31) at Level 50.', style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic)),
                const SizedBox(height: 12),
                const Text('Base Form', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ..._buildStatRows(normalStats, boosted, lowered),
                if (megaStats != null) ...[
                  const SizedBox(height: 16),
                  Text('Mega Evolution: $megaFormName', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  if (megaAbility != null) Text('Ability: $megaAbility', style: const TextStyle(fontStyle: FontStyle.italic)),
                  const SizedBox(height: 4),
                  ..._buildStatRows(megaStats, boosted, lowered),
                ] else ...[
                  const SizedBox(height: 16),
                  Text(
                    'No Mega Evolution active. Hold the correct Mega Stone to Mega Evolve.',
                    style: const TextStyle(color: Colors.orange, fontSize: 13, fontStyle: FontStyle.italic),
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
        final boosted = natureInfo['plus'] ?? '';
        final lowered = natureInfo['minus'] ?? '';

        final pokemonData = await _service.getPokemon(member.name);
        final rawStats = pokemonData['baseStats'] as Map<String, dynamic>;
        final baseStats = rawStats.map((k, v) => MapEntry(k, (v as num).toInt()));

        baseStatsByIndex[i] = StatCalculator.calculate(
          baseStats: baseStats,
          evs: member.evs,
          natureBoosted: boosted,
          natureLowered: lowered,
        );

        final activeMega = await _resolveActiveMega(member);
        if (activeMega != null) {
          megaFormNameByIndex[i] = activeMega.key;
          megaStatsByIndex[i] = StatCalculator.calculate(
            baseStats: activeMega.value,
            evs: member.evs,
            natureBoosted: boosted,
            natureLowered: lowered,
          );
          try {
            final abilities = await _service.getAbilitiesForPokemon(activeMega.key);
            if (abilities.isNotEmpty) {
              megaAbilityByIndex[i] = abilities.first['name'] as String;
            }
          } catch (_) {}
        }
      } catch (_) {}
    }

    if (!mounted) return;
    Navigator.pop(context);

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

    if (pastedText == null || pastedText.trim().isEmpty) {
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

    if (mode == null || mode == 'cancel') {
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
        member.pokedexNumber = _extractPokedexNumber(data);

        try {
          member.genderRate = await _service.getGenderRate(member.name);
        } catch (_) {
          member.genderRate = 4;
        }

        if (_team.any((m) => m.name == member.name) ||
            toAdd.any((m) => m.name == member.name)) {
          failed++;
          continue;
        }
        toAdd.add(member);
      } catch (e) {
        failed++;
      }
    }

    if (toAdd.isNotEmpty) {
      setState(() {
        final startIndex = _team.length;
        _team.addAll(toAdd);
        for (int i = 0; i < toAdd.length; i++) {
          _collapsedCards.add(startIndex + i);
        }
      });
    }

    await _saveTeam();
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
            Semantics(
              button: true,
              label: 'Export team as text',
              child: IconButton(
                icon: const Icon(Icons.upload_outlined),
                onPressed: _showExportDialog,
              ),
            ),
            Semantics(
              button: true,
              label: 'Import team from text',
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
                label: 'Search Pokémon by name',
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
                  decoration: _adaptiveInputDecoration('Search Pokémon').copyWith(
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
                          'Start typing above to search for Pokémon.',
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
                            final name = _filtered[index];
                            return Semantics(
                              button: true,
                              label: 'Add $name to team',
                              child: ListTile(
                                dense: true,
                                title: Text(name),
                                onTap: () => _addToTeam(name),
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
    final activePanel = _activePanels[index];
    final isCollapsed = _collapsedCards.contains(index);

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
                '${member.name}. Item: ${member.heldItem ?? "none"}. Gender: ${member.gender}. Ability: ${member.ability ?? "none"}. Nature: ${member.nature}. EVs: ${member.evTotal} of 510. Moves: $movesDisplay.',
            child: InkWell(
              onTap: () => _toggleCardCollapsed(index),
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
                      child: IconButton(
                        icon: Icon(isCollapsed ? Icons.expand_more : Icons.expand_less, size: 22),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                        onPressed: () => _toggleCardCollapsed(index),
                      ),
                    ),
                    Semantics(
                      button: true,
                      label: 'Remove ${member.name} from team',
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
                    onPressed: () => _togglePanel(index, 'details'),
                  ),
                  _buildToolbarToggle(
                    emoji: '⚔️',
                    label: 'Moves',
                    isActive: activePanel == 'moves',
                    semanticLabel: activePanel == 'moves'
                        ? 'Collapse moveset editor for ${member.name}'
                        : 'Expand moveset editor for ${member.name}',
                    onPressed: () => _togglePanel(index, 'moves'),
                  ),
                  _buildToolbarToggle(
                    emoji: '📈',
                    label: 'EVs',
                    isActive: activePanel == 'evs',
                    semanticLabel: activePanel == 'evs'
                        ? 'Collapse effort value editor for ${member.name}'
                        : 'Expand effort value editor for ${member.name}',
                    onPressed: () => _togglePanel(index, 'evs'),
                  ),
                  _buildToolbarToggle(
                    emoji: '📊',
                    label: 'Stats',
                    isActive: false,
                    semanticLabel: 'Show calculated stats for ${member.name}',
                    onPressed: () => _showStats(index),
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
      final moveOptions = _movesCache[index];
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
        abilities: _abilitiesCache[index],
        nature: member.nature,
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
        evs: member.evs,
        onChanged: (updatedEvs) async {
          setState(() => member.evs = updatedEvs);
          await _saveTeam();
        },
      );
    }

    return const SizedBox.shrink();
  }
}