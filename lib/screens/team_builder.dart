import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle, Clipboard, ClipboardData, FilteringTextInputFormatter;
import 'package:shared_preferences/shared_preferences.dart';
import '../services/pokeapi_service.dart';
import '../services/stat_calculator.dart';
import '../services/team_text_codec.dart';
import '../data/natures.dart';

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
  final _service = PokeApiService();
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  static const _storageKey = 'saved_team';

  List<String> _allSpecies = [];
  List<String> _excludedPokemon = [];
  List<String> _filtered = [];
  List<TeamMember> _team = [];

  /// Top search field mode: species (add to team) or held-item (assign to a member).
  String _searchMode = 'species'; // 'species' | 'heldItem'
  int? _heldItemTargetIndex; // which team slot receives the chosen item
  final Map<int, List<String>> _movesCache = {};
  final Map<int, List<Map<String, dynamic>>> _abilitiesCache = {};

  final Map<int, String?> _activePanels = {};
  final Set<int> _collapsedCards = {}; // cards that are collapsed (summary only)

  // Stable EV editors: controllers are created when the EV panel opens and
  // only write back to the model when the field loses focus / editing completes.
  final Map<int, Map<String, TextEditingController>> _evControllers = {};
  final Map<int, Map<String, FocusNode>> _evFocusNodes = {};

  // Held-item text fields (one per team member), committed on focus loss.
  final Map<int, TextEditingController> _itemControllers = {};
  final Map<int, FocusNode> _itemFocusNodes = {};
  List<String>? _cachedValidItems;

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
    _disposeAllEvControllers();
    super.dispose();
  }

  void _disposeAllEvControllers() {
    for (final map in _evControllers.values) {
      for (final c in map.values) {
        c.dispose();
      }
    }
    _evControllers.clear();
    for (final map in _evFocusNodes.values) {
      for (final n in map.values) {
        n.dispose();
      }
    }
    _evFocusNodes.clear();
    for (final c in _itemControllers.values) {
      c.dispose();
    }
    _itemControllers.clear();
    for (final n in _itemFocusNodes.values) {
      n.dispose();
    }
    _itemFocusNodes.clear();
  }

  void _disposeEvControllersForIndex(int index) {
    final controllers = _evControllers.remove(index);
    if (controllers != null) {
      for (final c in controllers.values) {
        c.dispose();
      }
    }
    final nodes = _evFocusNodes.remove(index);
    if (nodes != null) {
      for (final n in nodes.values) {
        n.dispose();
      }
    }
    _itemControllers.remove(index)?.dispose();
    _itemFocusNodes.remove(index)?.dispose();
  }

  /// Ensure controllers exist for this team member and are in sync with model values.
  void _ensureEvControllers(int index) {
    final member = _team[index];
    final existing = _evControllers[index];
    if (existing != null) {
      // Keep text in sync if the model changed externally (e.g. import)
      for (final stat in member.evs.keys) {
        final c = existing[stat];
        if (c != null && c.text != member.evs[stat].toString()) {
          c.text = member.evs[stat].toString();
        }
      }
      return;
    }

    final controllers = <String, TextEditingController>{};
    final nodes = <String, FocusNode>{};
    for (final stat in member.evs.keys) {
      final controller = TextEditingController(text: member.evs[stat].toString());
      final focusNode = FocusNode();
      focusNode.addListener(() {
        if (!focusNode.hasFocus) {
          _commitEv(index, stat);
        }
      });
      controllers[stat] = controller;
      nodes[stat] = focusNode;
    }
    _evControllers[index] = controllers;
    _evFocusNodes[index] = nodes;
  }

  /// Parse the controller text, clamp, enforce 510 total, call _setEv, and
  /// rewrite the controller so it shows the final accepted value.
  void _commitEv(int index, String stat) {
    final controllers = _evControllers[index];
    if (controllers == null) return;
    final controller = controllers[stat];
    if (controller == null) return;

    final parsed = int.tryParse(controller.text.trim()) ?? 0;
    _setEv(index, stat, parsed);

    // Reflect the clamped value back into the field without fighting the cursor
    // while the user is still typing (we only get here on focus loss).
    final accepted = _team[index].evs[stat]!.toString();
    if (controller.text != accepted) {
      controller.text = accepted;
      controller.selection = TextSelection.collapsed(offset: accepted.length);
    }
  }

  void _ensureItemController(int index) {
    if (_itemControllers.containsKey(index)) {
      final current = _team[index].heldItem ?? '';
      if (_itemControllers[index]!.text != current) {
        _itemControllers[index]!.text = current;
      }
      return;
    }
    final controller =
        TextEditingController(text: _team[index].heldItem ?? '');
    final focusNode = FocusNode();
    focusNode.addListener(() {
      if (!focusNode.hasFocus) {
        _commitHeldItem(index);
      }
    });
    _itemControllers[index] = controller;
    _itemFocusNodes[index] = focusNode;
  }

  Future<void> _commitHeldItem(int index) async {
    final controller = _itemControllers[index];
    if (controller == null) return;
    final raw = controller.text.trim().toLowerCase();

    if (raw.isEmpty) {
      await _setHeldItem(index, '');
      return;
    }

    try {
      _cachedValidItems ??= await _service.getHeldItemNames();
      final normalizedSlug = raw.replaceAll(' ', '-');
      final normalizedSpace = raw.replaceAll('-', ' ');

      // Resolve to the canonical name from the Champions pool (hyphenated slug).
      String? canonical;
      for (final item in _cachedValidItems!) {
        final clean = item.toLowerCase();
        if (clean == raw ||
            clean == normalizedSlug ||
            clean == normalizedSpace ||
            clean.replaceAll('-', ' ') == normalizedSpace) {
          canonical = clean;
          break;
        }
      }

      if (canonical != null) {
        await _setHeldItem(index, canonical);
        controller.text = _team[index].heldItem ?? '';
      } else {
        _announce('Not a recognized Champions held item.');
        controller.text = _team[index].heldItem ?? '';
      }
    } catch (_) {
      _announce('Could not validate held item.');
      controller.text = _team[index].heldItem ?? '';
    }
  }

  void _unfocus() {
    _searchFocusNode.unfocus();
    FocusScope.of(context).unfocus();
  }

  Future<void> _loadData() async {
    try {
      final rosterJson =
          await rootBundle.loadString('lib/data/champions_roster.json');
      final roster = json.decode(rosterJson);
      final List<String> allowed =
          List<String>.from(roster['allowed_pokemon']);

      // Prefetch Champions held-item pool (curated JSON via PokeApiService).
      try {
        _cachedValidItems = await _service.getHeldItemNames();
      } catch (_) {
        _cachedValidItems = [];
      }

      await _loadSavedTeam();

      setState(() {
        _allSpecies = allowed;
        _filtered = [];
        _loading = false;
        // Start all cards collapsed for max space efficiency
        for (int i = 0; i < _team.length; i++) {
          _collapsedCards.add(i);
        }
      });
    } catch (e) {
      setState(() {
        _statusMessage = 'Error loading Pokémon roster.';
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
        return;
      }
      if (_searchMode == 'heldItem') {
        final pool = _cachedValidItems ?? const <String>[];
        _filtered = pool.where((item) => item.toLowerCase().contains(q)).toList();
      } else {
        _filtered =
            _allSpecies.where((p) => p.toLowerCase().contains(q)).toList();
      }
    });
  }

  void _enterHeldItemSearch(int teamIndex) {
    _ensureItemController(teamIndex);
    setState(() {
      _searchMode = 'heldItem';
      _heldItemTargetIndex = teamIndex;
    });
    // Filter from whatever is already in the held-item field
    final existing = _itemControllers[teamIndex]?.text ?? '';
    _filterHeldItems(existing);
  }

  void _exitHeldItemSearch() {
    setState(() {
      _searchMode = 'species';
      _heldItemTargetIndex = null;
      final q = _searchController.text.trim().toLowerCase();
      _filtered = q.isEmpty
          ? []
          : _allSpecies.where((p) => p.toLowerCase().contains(q)).toList();
    });
  }

  /// Filter held-item pool on every keystroke (same contains-match as species).
  void _filterHeldItems(String query) {
    final q = query.trim().toLowerCase();
    setState(() {
      _searchMode = 'heldItem';
      if (q.isEmpty) {
        _filtered = [];
      } else {
        final pool = _cachedValidItems ?? const <String>[];
        _filtered =
            pool.where((item) => item.toLowerCase().contains(q)).toList();
      }
    });
  }

  Future<void> _pickHeldItemFromSearch(String itemName) async {
    final index = _heldItemTargetIndex;
    if (index == null || index < 0 || index >= _team.length) {
      _exitHeldItemSearch();
      return;
    }
    await _setHeldItem(index, itemName);
    if (_itemControllers.containsKey(index)) {
      _itemControllers[index]!.text = _team[index].heldItem ?? '';
    }
    setState(() {
      _searchMode = 'species';
      _heldItemTargetIndex = null;
      _filtered = [];
    });
    _unfocus();
  }

  Future<void> _addToTeam(String name) async {
    _unfocus();
    if (_team.length >= 6) {
      _announce('Team is full. Maximum of six Pokémon.');
      return;
    }

    try {
      // The roster already contains the exact form name (e.g. "raichu-alola").
      // Use it directly — no need to query varieties.
      final String selectedFormName = name;

      final data = await _service.getPokemon(selectedFormName);
      final pokedexNumber = data['id'] as int;

      if (_team.any((m) => m.pokedexNumber == pokedexNumber)) {
        _announce(
            '$selectedFormName shares a Pokédex number with a Pokémon already on your team.');
        return;
      }

      List<String?> defaultMoves = List.filled(4, null);
      String? defaultAbility;

      try {
        final abilities =
            await _service.getAbilitiesForPokemon(selectedFormName);
        if (abilities.isNotEmpty) {
          defaultAbility = abilities.first['name'] as String;
        }
      } catch (_) {}

      try {
        final moves = await _service.getMovesForPokemon(selectedFormName);
        for (int i = 0; i < 4 && i < moves.length; i++) {
          defaultMoves[i] = moves[i];
        }
      } catch (_) {}

      final genderRate = await _service.getGenderRate(selectedFormName);
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
    } catch (e) {
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
      _movesCache.remove(index);
      _abilitiesCache.remove(index);
      _activePanels.remove(index);
      _collapsedCards.remove(index);
      _disposeEvControllersForIndex(index);

      // Re-key maps that are keyed by team index
      final newCollapsed = <int>{};
      for (final i in _collapsedCards) {
        newCollapsed.add(i > index ? i - 1 : i);
      }
      _collapsedCards
        ..clear()
        ..addAll(newCollapsed);

      // Re-key EV controllers / focus nodes
      final newEvControllers = <int, Map<String, TextEditingController>>{};
      final newEvFocusNodes = <int, Map<String, FocusNode>>{};
      for (final entry in _evControllers.entries) {
        final i = entry.key;
        if (i == index) continue; // already disposed
        final newKey = i > index ? i - 1 : i;
        newEvControllers[newKey] = entry.value;
      }
      for (final entry in _evFocusNodes.entries) {
        final i = entry.key;
        if (i == index) continue;
        final newKey = i > index ? i - 1 : i;
        newEvFocusNodes[newKey] = entry.value;
      }
      _evControllers
        ..clear()
        ..addAll(newEvControllers);
      _evFocusNodes
        ..clear()
        ..addAll(newEvFocusNodes);

      final newItemControllers = <int, TextEditingController>{};
      final newItemFocusNodes = <int, FocusNode>{};
      for (final entry in _itemControllers.entries) {
        final i = entry.key;
        if (i == index) continue;
        final newKey = i > index ? i - 1 : i;
        newItemControllers[newKey] = entry.value;
      }
      for (final entry in _itemFocusNodes.entries) {
        final i = entry.key;
        if (i == index) continue;
        final newKey = i > index ? i - 1 : i;
        newItemFocusNodes[newKey] = entry.value;
      }
      _itemControllers
        ..clear()
        ..addAll(newItemControllers);
      _itemFocusNodes
        ..clear()
        ..addAll(newItemFocusNodes);
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
        _activePanels[index] = null; // also close any open sub-panel
      }
    });
  }

  Future<void> _setHeldItem(int index, String item) async {
    final cleanItem = item.trim().toLowerCase();

    if (cleanItem.isNotEmpty) {
      // Check if another member on the team is already holding this item
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
      if (panelName == 'evs') {
        _ensureEvControllers(index);
      }
      if (panelName == 'details') {
        _ensureItemController(index);
        // Prefetch held-item pool for autocomplete suggestions
        if (_cachedValidItems == null) {
          try {
            _cachedValidItems = await _service.getHeldItemNames();
          } catch (_) {}
        }
      }
      if (!_movesCache.containsKey(index)) {
        try {
          final moves = await _service.getMovesForPokemon(_team[index].name);
          setState(() => _movesCache[index] = moves);
        } catch (_) {}
      }
      if (!_abilitiesCache.containsKey(index)) {
        try {
          final abilities =
              await _service.getAbilitiesForPokemon(_team[index].name);
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

    // Guard against non-Mega item ending in 'ite'
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

  /// Determines the active Mega form (if any) based purely on held item.
  /// Returns (formName, baseStats) or null if not currently Mega Evolved.
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
      final nature = allNatures.firstWhere((n) => n.name == member.nature);

      final normalBaseStats = await _service.getBaseStats(member.name);
      final normalStats = StatCalculator.calculate(
        baseStats: normalBaseStats,
        evs: member.evs,
        natureBoosted: nature.boosted ?? '',
        natureLowered: nature.lowered ?? '',
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
          natureBoosted: nature.boosted ?? '',
          natureLowered: nature.lowered ?? '',
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
                ..._buildStatRows(normalStats, nature),
                if (megaStats != null) ...[
                  const SizedBox(height: 16),
                  Text('Mega Evolution: $megaFormName', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  if (megaAbility != null) Text('Ability: $megaAbility', style: const TextStyle(fontStyle: FontStyle.italic)),
                  const SizedBox(height: 4),
                  ..._buildStatRows(megaStats, nature),
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

  List<Widget> _buildStatRows(Map<String, int> stats, Nature nature) {
    return stats.entries.map((e) {
      final isBoosted = (e.key == 'Atk' && nature.boosted == 'Attack') ||
          (e.key == 'Def' && nature.boosted == 'Defense') ||
          (e.key == 'SpA' && nature.boosted == 'Sp. Atk') ||
          (e.key == 'SpD' && nature.boosted == 'Sp. Def') ||
          (e.key == 'Spe' && nature.boosted == 'Speed');
      final isLowered = (e.key == 'Atk' && nature.lowered == 'Attack') ||
          (e.key == 'Def' && nature.lowered == 'Defense') ||
          (e.key == 'SpA' && nature.lowered == 'Sp. Atk') ||
          (e.key == 'SpD' && nature.lowered == 'Sp. Def') ||
          (e.key == 'Spe' && nature.lowered == 'Speed');
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
        final nature = allNatures.firstWhere((n) => n.name == member.nature);
        final baseStats = await _service.getBaseStats(member.name);
        baseStatsByIndex[i] = StatCalculator.calculate(
          baseStats: baseStats,
          evs: member.evs,
          natureBoosted: nature.boosted ?? '',
          natureLowered: nature.lowered ?? '',
        );

        final activeMega = await _resolveActiveMega(member);
        if (activeMega != null) {
          megaFormNameByIndex[i] = activeMega.key;
          megaStatsByIndex[i] = StatCalculator.calculate(
            baseStats: activeMega.value,
            evs: member.evs,
            natureBoosted: nature.boosted ?? '',
            natureLowered: nature.lowered ?? '',
          );
          try {
            final abilities = await _service.getAbilitiesForPokemon(activeMega.key);
            if (abilities.isNotEmpty) {
              megaAbilityByIndex[i] = abilities.first['name'] as String;
            }
          } catch (_) {}
        }
      } catch (_) {
        // Skip stats for this member if fetch fails; export continues without them.
      }
    }

    if (!mounted) return;
    Navigator.pop(context); // close loading dialog

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

    int added = 0;
    int failed = 0;
    for (final member in parsed) {
      if (_team.length >= 6) break;
      try {
        final data = await _service.getPokemon(member.name);
        member.pokedexNumber = data['id'] as int;
        member.genderRate = await _service.getGenderRate(member.name);
        if (_team.any((m) => m.pokedexNumber == member.pokedexNumber)) {
          failed++;
          continue;
        }
        setState(() {
          _team.add(member);
          _collapsedCards.add(_team.length - 1);
        });
        added++;
      } catch (e) {
        failed++;
      }
    }

    await _saveTeam();
    _announce('Import complete. $added Pokémon added${failed > 0 ? ", $failed failed or skipped" : ""}.');
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
                label: _searchMode == 'heldItem'
                    ? 'Search held items by name'
                    : 'Search Pokémon by name',
                child: TextField(
                  controller: _searchController,
                  focusNode: _searchFocusNode,
                  autofocus: false,
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.92)),
                  cursorColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.85),
                      color: Theme.of(context).colorScheme.onInverseSurface),
                  cursorColor: Theme.of(context).colorScheme.inversePrimary,

                  decoration: _adaptiveInputDecoration(
                    _searchMode == 'heldItem'
                        ? (_heldItemTargetIndex != null
                            ? 'Held item for ${_team[_heldItemTargetIndex!].name}'
                            : 'Search held items')
                        : 'Search Pokémon',
                  ).copyWith(
                    prefixIcon: Icon(
                      _searchMode == 'heldItem'
                          ? Icons.inventory_2_outlined
                          : Icons.search,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.75)
                          .withValues(alpha: 0.75),
                    ),
                    suffixIcon: _searchMode == 'heldItem'
                        ? IconButton(
                            tooltip: 'Cancel item search',
                            onPressed: _exitHeldItemSearch,
                            icon: Icon(
                              Icons.close,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withValues(alpha: 0.75),
                                  .onInverseSurface,

                            ),
                          )
                        : (_searchController.text.isNotEmpty
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
                                      .onInverseSurface,

                                ),
                              )
                            : null),
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
                  child: Text(_statusMessage, style: const TextStyle(color: Colors.blue, fontSize: 12)),
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
              child: Builder(builder: (context) {
                // Species search uses the top field; held-item search uses the
                // Details "Held Item" field — not _searchController.
                final activeQuery = _searchMode == 'heldItem'
                    ? (_heldItemTargetIndex != null
                        ? (_itemControllers[_heldItemTargetIndex!]?.text ?? '')
                        : '')
                    : _searchController.text;

                if (activeQuery.trim().isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Text(
                        _searchMode == 'heldItem'
                            ? 'Type in the Held Item field to search Champions items.'
                            : 'Start typing above to search for Pokémon.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  );
                }

                if (_filtered.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Text(
                        _searchMode == 'heldItem'
                            ? 'No held items match "$activeQuery".'
                            : 'No Pokémon match "$activeQuery".',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 13),
                      ),
              child: _searchController.text.trim().isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Text(
                          _searchMode == 'heldItem'
                              ? 'Type above to search Champions held items.'
                              : 'Start typing above to search for Pokémon.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _filtered.length,
                      itemBuilder: (context, index) {
                        final name = _filtered[index];
                        final isItem = _searchMode == 'heldItem';
                        return Semantics(
                          button: true,
                          label: isItem
                              ? 'Set held item to $name'
                              : 'Add $name to team',
                          child: ListTile(
                            dense: true,
                            title: Text(name),
                            onTap: () {
                              if (isItem) {
                                _pickHeldItemFromSearch(name);
                              } else {
                                _addToTeam(name);
                              }
                            },
                          ),
                        );
                      },

                    ),
                  );
                }

                return ListView.builder(
                  itemCount: _filtered.length,
                  itemBuilder: (context, index) {
                    final name = _filtered[index];
                    final isItem = _searchMode == 'heldItem';
                    return Semantics(
                      button: true,
                      label: isItem
                          ? 'Set held item to $name'
                          : 'Add $name to team',
                      child: ListTile(
                        dense: true,
                        title: Text(name),
                        onTap: () {
                          if (isItem) {
                            _pickHeldItemFromSearch(name);
                          } else {
                            _addToTeam(name);
                          }
                        },
                      ),
                    );
                  },
                );
              }),
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
          // COMPACT HEADER: name, collapse toggle, remove toggle — always visible
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
                  // Details first, then Moves (interchanged)
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
    // Adaptive highlight; emoji follows onSurface so it stays readable in light & dark.
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

  /// Soft high-contrast fields: muted gray/white fills, readable but not glaring.
  InputDecoration _adaptiveInputDecoration(String labelText) {
    final cs = Theme.of(context).colorScheme;
    // Light wash of onSurface over surface → soft gray in both themes
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

  /// Dropdown menu: soft elevated surface, not full inverse white/black.
  Color get _dropdownMenuColor {
    final cs = Theme.of(context).colorScheme;
    return Color.alphaBlend(
      cs.onSurface.withValues(alpha: 0.08),
      cs.surfaceContainerHigh,
    );
  }

  /// Body text inside fields / dropdowns.
  Color get _fieldTextColor =>
      Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.92);

  /// Primary actions — soft filled (primaryContainer), easier on the eyes.
  ButtonStyle get _inverseFilledButtonStyle {
    final cs = Theme.of(context).colorScheme;
    return FilledButton.styleFrom(
      backgroundColor: cs.primaryContainer.withValues(alpha: 0.85),
      foregroundColor: cs.onPrimaryContainer,
      disabledBackgroundColor: cs.surfaceContainerHighest.withValues(alpha: 0.5),
      disabledForegroundColor: cs.onSurface.withValues(alpha: 0.38),
    );
  }

  /// Secondary / cancel — muted primary, not neon inverse.
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
          else
            // 2 columns × 2 rows → at most 2 visual rows of fields
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
                              initialValue: member.moves[slot],
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
      final abilityOptions = _abilitiesCache[index];

      List<DropdownMenuItem<String>> genderItems;
      final itemStyle = TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.92));
      if (member.genderRate == -1) {
        genderItems = [
          DropdownMenuItem(
              value: 'Genderless',
              child: Text('Genderless', style: itemStyle))
        ];
      } else if (member.genderRate == 0) {
        genderItems = [
          DropdownMenuItem(
              value: 'Male', child: Text('Male', style: itemStyle))
        ];
      } else if (member.genderRate == 8) {
        genderItems = [
          DropdownMenuItem(
              value: 'Female', child: Text('Female', style: itemStyle))
        ];
      } else {
        genderItems = [
          DropdownMenuItem(
              value: 'Male', child: Text('Male', style: itemStyle)),
          DropdownMenuItem(
              value: 'Female', child: Text('Female', style: itemStyle)),
        ];
      }

      Widget abilityField;
      if (abilityOptions == null) {
        abilityField = const Center(child: CircularProgressIndicator());
      } else {
        abilityField = Semantics(
          label:
              'Ability for ${member.name}, currently ${member.ability ?? "none"}',
          child: DropdownButtonFormField<String>(
            initialValue: member.ability,
            isExpanded: true,
            dropdownColor: _dropdownMenuColor,
            style: TextStyle(color: _fieldTextColor, fontSize: 14),
            decoration: _adaptiveInputDecoration('Ability'),
            items: abilityOptions.map((a) {
              final label =
                  a['isHidden'] ? '${a['name']} (Hidden)' : a['name'];
              return DropdownMenuItem<String>(
                value: a['name'] as String,
                child: Text(label,
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.92))),
              );
            }).toList(),
            onChanged: (value) {
              if (value != null) _setAbility(index, value);
            },
          ),
        );
      }

      final genderField = Semantics(
        label: 'Gender for ${member.name}, currently ${member.gender}',
        child: DropdownButtonFormField<String>(
          initialValue: member.gender,
          isExpanded: true,
          dropdownColor: _dropdownMenuColor,
          style: TextStyle(color: _fieldTextColor, fontSize: 14),
          decoration: _adaptiveInputDecoration('Gender'),
          items: genderItems,
          onChanged: genderItems.length > 1
              ? (value) {
                  if (value != null) _setGender(index, value);
                }
              : null,
        ),
      );

      final natureField = Semantics(
        label: 'Nature for ${member.name}, currently ${member.nature}',
        child: DropdownButtonFormField<String>(
          initialValue: member.nature,
          isExpanded: true,
          dropdownColor: _dropdownMenuColor,
          style: TextStyle(color: _fieldTextColor, fontSize: 14),
          decoration: _adaptiveInputDecoration('Nature'),
          items: allNatures.map((n) {
            final desc = n.boosted == null
                ? '${n.name} (neutral)'
                : '${n.name} (+${n.boosted}, -${n.lowered})';
            return DropdownMenuItem(
              value: n.name,
              child:
                  Text(desc, style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.92))),
            );
          }).toList(),
          onChanged: (value) {
            if (value != null) _setNature(index, value);
          },
        ),
      );

      // Ensure controller exists before building the field
      _ensureItemController(index);
      final itemController = _itemControllers[index]!;
      final itemFocus = _itemFocusNodes[index]!;

      final itemField = Semantics(
        label:
            'Held item for ${member.name}, currently ${member.heldItem ?? "none"}. Type to search.',
        textField: true,
        child: TextField(
          controller: itemController,
          focusNode: itemFocus,
          style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.92)),
          cursorColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.85),
              color: Theme.of(context).colorScheme.onInverseSurface),
          cursorColor: Theme.of(context).colorScheme.inversePrimary,

          decoration: _adaptiveInputDecoration('Held Item').copyWith(
            hintText: 'Type to search items…',
            hintStyle: TextStyle(
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.55)
                  .onInverseSurface

                  .withValues(alpha: 0.5),
            ),
            suffixIcon: itemController.text.isNotEmpty
                ? IconButton(
                    tooltip: 'Clear held item',
                    onPressed: () async {
                      itemController.clear();
                      await _setHeldItem(index, '');
                      _filterHeldItems('');
                    },
                    icon: Icon(
                      Icons.clear,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.75),
                      color:
                          Theme.of(context).colorScheme.onInverseSurface,

                    ),
                  )
                : Icon(
                    Icons.search,
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.92),
                    color: Theme.of(context).colorScheme.onInverseSurface,

                  ),
          ),
          onTap: () => _enterHeldItemSearch(index),
          onChanged: (value) {
            // Same keystroke behavior as species search: filter the shared list
            if (_heldItemTargetIndex != index) {
              _heldItemTargetIndex = index;
            }
            _filterHeldItems(value);
          },
          onEditingComplete: () {
            _commitHeldItem(index);
            itemFocus.unfocus();
          },
          onSubmitted: (_) => _commitHeldItem(index),
        ),
      );

      // 2 columns × 2 rows: Item | Gender / Ability | Nature
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Held Item, Gender, Ability & Nature',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: itemField),
                const SizedBox(width: 8),
                Expanded(child: genderField),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: abilityField),
                const SizedBox(width: 8),
                Expanded(child: natureField),
              ],
            ),
          ),
        ],
      );
    }

    if (panelName == 'evs') {
      // Controllers are created when the panel is opened (_togglePanel).
      final controllers = _evControllers[index];
      final focusNodes = _evFocusNodes[index];
      if (controllers == null || focusNodes == null) {
        return const Center(child: CircularProgressIndicator());
      }

      final stats = member.evs.keys.toList(); // HP Atk Def SpA SpD Spe

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Effort Values (EVs)',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              Semantics(
                liveRegion: true,
                child: Text(
                  '${member.evTotal}/510 total',
                  style: TextStyle(
                    fontSize: 13,
                    color: member.evTotal > 510
                        ? Colors.red
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // 2 columns × 3 rows → at most 3 visual rows of fields
          ...List.generate(3, (row) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  for (int col = 0; col < 2; col++) ...[
                    if (col > 0) const SizedBox(width: 8),
                    Expanded(
                      child: Builder(builder: (_) {
                        final statIndex = row * 2 + col;
                        if (statIndex >= stats.length) {
                          return const SizedBox.shrink();
                        }
                        final stat = stats[statIndex];
                        return Semantics(
                          label:
                              '$stat effort values, currently ${member.evs[stat]} out of 252',
                          textField: true,
                          child: TextField(
                            controller: controllers[stat],
                            focusNode: focusNodes[stat],
                            keyboardType: TextInputType.number,
                            style: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurface
                                    .withValues(alpha: 0.92)),
                            cursorColor: Theme.of(context)
                                .colorScheme
                                .primary
                                .withValues(alpha: 0.85),
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            decoration: _adaptiveInputDecoration(
                                '$stat EVs (0-252)'),
                            onEditingComplete: () {
                              _commitEv(index, stat);
                              focusNodes[stat]?.unfocus();
                            },
                            onSubmitted: (_) {
                              _commitEv(index, stat);
                            },
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

    return const SizedBox.shrink();
  }

}