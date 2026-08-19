import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/team_member.dart';
import '../services/js_engine_service.dart';
import '../services/stat_calculator.dart';
import '../services/team_text_codec.dart';
import '../widgets/details_editor_panel.dart';
import '../widgets/ev_editor_panel.dart';
import '../widgets/iv_editor_panel.dart';
import '../widgets/move_editor_panel.dart';
import '../widgets/stats_dialog.dart';

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

  /// Clean item pool to include Mega Stones/Orbs and filter non-battle junk.
  List<String> _filterBattleItems(List<String> rawItems) {
    final junkPattern = RegExp(
      r'^(tm\d+|hm\d+|tr\d+|key-|mail|letter|old-rod|good-rod|super-rod|bicycle|bike|ticket|pass|card|parcel|pokedex|journal|map|case|pouch)',
      caseSensitive: false,
    );

    return rawItems.where((item) {
      final l = item.toLowerCase().trim();
      if (l.isEmpty) return false;

      // Always explicitly retain Mega Stones and Primal Orbs
      if (l.endsWith('ite') ||
          l.endsWith('ite-x') ||
          l.endsWith('ite-y') ||
          l == 'red-orb' ||
          l == 'blue-orb' ||
          l == 'red orb' ||
          l == 'blue orb') {
        return true;
      }

      // Exclude junk items
      if (junkPattern.hasMatch(l)) return false;

      return true;
    }).toList();
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
        _itemList = _filterBattleItems(items);
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
        _statusMessage = 'Error loading roster: $e';
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
      _filtered = q.isEmpty
          ? []
          : _baseSpeciesList
              .where((p) => p['name'].toString().toLowerCase().contains(q))
              .toList();
    });
  }

  Future<void> _handleSpeciesTap(Map<String, dynamic> baseEntry) async {
    _unfocus();
    final int pokedexNumber = baseEntry['num'] as int;

    if (_team.any((m) => m.pokedexNumber == pokedexNumber)) {
      _announce('Species Clause: Pokédex #$pokedexNumber is already on your team.');
      return;
    }

    if (_team.length >= 6) {
      _announce('Team is full (6 max).');
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
        content: Text('Remove ${member.name} from your team?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
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
        _announce('Item Clause: ${duplicateMember.name.toUpperCase()} is holding $cleanItem.');
        return;
      }
    }

    setState(() => _team[index].heldItem = cleanItem.isEmpty ? null : cleanItem);
    await _saveTeam();
    if (!mounted) return;
    _announce('${_team[index].name} item updated.');
  }

  void _togglePanel(TeamMember member, String panelName) async {
    _unfocus();
    setState(() {
      _activePanels[member] = _activePanels[member] == panelName ? null : panelName;
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

  Future<void> _showStats(TeamMember member) async {
    _unfocus();
    try {
      await StatsDialog.show(context, member, _service);
    } catch (_) {
      if (!mounted) return;
      _announce('Could not load stats.');
    } finally {
      _unfocus();
    }
  }

  Future<void> _showExportDialog() async {
    _unfocus();
    if (_team.isEmpty) {
      _announce('Your team is empty.');
      return;
    }

    final text = TeamTextCodec.encodeTeam(_team, {}, {}, {}, {});

    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Export Team (Showdown Format)'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Semantics(
              label: 'Showdown team sheet export text',
              child: SelectableText(text, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
            ),
          ),
        ),
        actions: [
          FilledButton(
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
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
    _unfocus();
  }

  void _announce(String message) {
    setState(() => _statusMessage = message);
  }

  /// Generates visual Showdown style summary text block for member cards.
  String _buildShowdownSummary(TeamMember m) {
    final header = m.heldItem != null && m.heldItem!.isNotEmpty ? '${m.name} @ ${m.heldItem}' : m.name;
    final ability = 'Ability: ${m.ability ?? "None"} | Level: ${m.level}';

    final evsList = <String>[];
    m.evs.forEach((k, v) {
      if (v > 0) evsList.add('$v $k');
    });
    final evStr = evsList.isNotEmpty ? 'EVs: ${evsList.join(' / ')}' : 'EVs: None';

    final movesList = m.moves.where((mv) => mv != null && mv.isNotEmpty).join(' / ');
    final movesStr = movesList.isNotEmpty ? 'Moves: $movesList' : 'Moves: None';

    return '$header\n$ability\n$evStr | ${m.nature} Nature\n$movesStr';
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
              label: 'Apply VGC Preset to set all members to level 50 and 31 IVs',
              button: true,
              child: TextButton.icon(
                onPressed: _applyVgcPreset,
                icon: const Icon(Icons.flash_on, size: 18),
                label: const Text('VGC Preset', style: TextStyle(fontSize: 12)),
              ),
            ),
            Semantics(
              label: 'Export Team in Showdown format',
              button: true,
              child: IconButton(
                icon: const Icon(Icons.upload_outlined),
                tooltip: 'Export Team',
                onPressed: _showExportDialog,
              ),
            ),
          ],
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: TextField(
                controller: _searchController,
                focusNode: _searchFocusNode,
                decoration: InputDecoration(
                  labelText: 'Search Base Pokémon',
                  isDense: true,
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _searchController.clear();
                            _filter('');
                          },
                        )
                      : null,
                ),
                onChanged: _filter,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12.0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Your team: ${_team.length} of 6 slots filled',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ),
            ),
            if (_statusMessage.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 2.0),
                child: Text(_statusMessage, style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
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
                  ? const Center(child: Text('Start typing above to search for Pokémon species.'))
                  : ListView.builder(
                      itemCount: _filtered.length,
                      itemBuilder: (context, index) {
                        final entry = _filtered[index];
                        final types = List<String>.from(entry['types'] ?? []);
                        return ListTile(
                          dense: true,
                          title: Text(entry['name']),
                          subtitle: Text('Types: ${types.join("/")}'),
                          onTap: () => _handleSpeciesTap(entry),
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

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Column(
        children: [
          ListTile(
            title: Text('${member.name.toUpperCase()} #${member.pokedexNumber}'),
            subtitle: Text(
              _buildShowdownSummary(member),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Semantics(
                  label: isCollapsed ? 'Expand ${member.name} options' : 'Collapse ${member.name} options',
                  button: true,
                  child: IconButton(
                    icon: Icon(isCollapsed ? Icons.expand_more : Icons.expand_less),
                    onPressed: () => _toggleCardCollapsed(member),
                  ),
                ),
                Semantics(
                  label: 'Remove ${member.name} from team',
                  button: true,
                  child: IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                    onPressed: () => _confirmRemoveFromTeam(index),
                  ),
                ),
              ],
            ),
          ),
          if (!isCollapsed) ...[
            Container(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              padding: const EdgeInsets.symmetric(vertical: 4.0),
              child: Column(
                children: [
                  // Level Quick Control Bar (Bug 4)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 2.0),
                    child: Row(
                      children: [
                        const Text('Level:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                        Expanded(
                          child: Semantics(
                            label: 'Level slider for ${member.name}, current level ${member.level}',
                            child: Slider(
                              value: member.level.toDouble(),
                              min: 1,
                              max: 100,
                              divisions: 99,
                              label: '${member.level}',
                              onChanged: (val) async {
                                setState(() => member.level = val.toInt());
                                await _saveTeam();
                              },
                            ),
                          ),
                        ),
                        Text('Lvl ${member.level}', style: const TextStyle(fontSize: 12)),
                      ],
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildToolbarToggle('⚙️', 'Details', 'Open details editor for ${member.name}', activePanel == 'details', () => _togglePanel(member, 'details')),
                      _buildToolbarToggle('⚔️', 'Moves', 'Open move editor for ${member.name}', activePanel == 'moves', () => _togglePanel(member, 'moves')),
                      _buildToolbarToggle('📈', 'EVs', 'Open EV allocation for ${member.name}', activePanel == 'evs', () => _togglePanel(member, 'evs')),
                      _buildToolbarToggle('🎚️', 'IVs', 'Open IV allocation for ${member.name}', activePanel == 'ivs', () => _togglePanel(member, 'ivs')),
                      _buildToolbarToggle('📊', 'Stats', 'Show stats dialog for ${member.name}', false, () => _showStats(member)),
                    ],
                  ),
                ],
              ),
            ),
            if (activePanel != null) _buildPanelContent(index, activePanel),
          ],
        ],
      ),
    );
  }

  Widget _buildToolbarToggle(String emoji, String label, String semanticLabel, bool isActive, VoidCallback onPressed) {
    return Semantics(
      label: semanticLabel,
      button: true,
      child: IconButton(
        icon: Text(emoji, style: const TextStyle(fontSize: 20)),
        color: isActive ? Theme.of(context).colorScheme.primary : null,
        onPressed: onPressed,
      ),
    );
  }

  Widget _buildPanelContent(int index, String panelName) {
    final member = _team[index];

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
          if (gender != null) setState(() => member.gender = gender);
          if (ability != null) setState(() => member.ability = ability);
          if (nature != null) setState(() => member.nature = nature);
          await _saveTeam();
        },
      );
    }

    if (panelName == 'moves') {
      return MoveEditorPanel(
        moves: member.moves,
        availableMoves: _movesCache[member] ?? [],
        onChanged: (moves) async {
          setState(() => member.moves = moves);
          await _saveTeam();
        },
      );
    }

    if (panelName == 'evs') {
      return EvEditorPanel(
        evs: member.evs,
        onChanged: (evs) async {
          setState(() => member.evs = evs);
          await _saveTeam();
        },
      );
    }

    if (panelName == 'ivs') {
      return IvEditorPanel(
        ivs: member.ivs,
        onChanged: (ivs) async {
          setState(() => member.ivs = ivs);
          await _saveTeam();
        },
      );
    }

    return const SizedBox.shrink();
  }
}
