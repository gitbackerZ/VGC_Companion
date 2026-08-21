import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/team_member.dart';
import '../services/js_engine_service.dart';
import '../services/team_text_codec.dart';
import '../widgets/details_editor_panel.dart';
import '../widgets/ev_editor_panel.dart';
import '../widgets/iv_editor_panel.dart';
import '../widgets/move_editor_panel.dart';
import '../widgets/stats_dialog.dart';

enum TeamPreset { championsVgc, freeform }

class TeamBuilderScreen extends StatefulWidget {
  const TeamBuilderScreen({super.key});

  @override
  State<TeamBuilderScreen> createState() => _TeamBuilderScreenState();
}

class _TeamBuilderScreenState extends State<TeamBuilderScreen> {
  final _service = JsEngineService();
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  final _importController = TextEditingController();
  static const _storageKey = 'saved_team';

  TeamPreset _activePreset = TeamPreset.championsVgc;

  List<Map<String, dynamic>> _baseSpeciesList = [];
  List<Map<String, dynamic>> _filtered = [];
  List<String> _itemList = [];
  List<TeamMember> _team = [];

  final Map<TeamMember, List<String>> _movesCache = {};
  final Map<TeamMember, List<Map<String, dynamic>>> _abilitiesCache = {};
  final Map<TeamMember, String?> _activePanels = {};
  final Set<TeamMember> _collapsedCards = {};

  final Map<TeamMember, Map<String, int>> _initialEvs = {};
  final Map<TeamMember, Map<String, int>> _initialIvs = {};

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
    _importController.dispose();
    _service.dispose();
    super.dispose();
  }

  void _unfocus() {
    _searchFocusNode.unfocus();
    FocusScope.of(context).unfocus();
  }

  void _announce(String message) {
    if (message.isEmpty) return;
    setState(() => _statusMessage = message);
    SemanticsService.announce(message, TextDirection.ltr);
  }

  void _flushPendingPanelUpdates([TeamMember? targetMember]) {
    final membersToFlush = targetMember != null ? [targetMember] : List<TeamMember>.from(_team);
    for (final member in membersToFlush) {
      final initialEv = _initialEvs[member];
      if (initialEv != null) {
        if (!_mapsEqual(initialEv, member.evs)) {
          _announce('${member.name} ev values updated');
        }
        _initialEvs.remove(member);
      }

      final initialIv = _initialIvs[member];
      if (initialIv != null) {
        if (!_mapsEqual(initialIv, member.ivs)) {
          _announce('${member.name} iv values updated');
        }
        _initialIvs.remove(member);
      }
    }
  }

  bool _mapsEqual(Map<String, int> m1, Map<String, int> m2) {
    if (m1.length != m2.length) return false;
    for (final key in m1.keys) {
      if (m1[key] != m2[key]) return false;
    }
    return true;
  }

  Future<List<TeamMember>> _teamAsBaseForms() async {
    final result = <TeamMember>[];
    for (final m in _team) {
      if (!m.name.contains('-Mega') && !m.name.contains('-Primal')) {
        result.add(m);
        continue;
      }
      try {
        final data = await _service.getPokemon(m.name);
        final baseName = data['baseSpecies'] as String? ?? m.name.split('-')[0];
        final baseData = await _service.getPokemon(baseName);
        final baseTypes = List<String>.from(baseData['types'] ?? m.types);

        final baseAbilities = await _service.getAbilitiesForPokemon(baseName);
        String baseAbility = m.ability ?? '';
        if (baseAbilities.isNotEmpty) {
          final baseAbilityNames = baseAbilities.map((a) => a['name'].toString()).toList();
          if (!baseAbilityNames.contains(baseAbility)) {
            baseAbility = baseAbilityNames.first;
          }
        }

        final baseMember = TeamMember(
          name: baseName,
          pokedexNumber: m.pokedexNumber,
          types: baseTypes,
          ability: baseAbility,
          moves: List<String?>.from(m.moves),
          gender: m.gender,
          genderRate: m.genderRate,
        )
          ..level = m.level
          ..heldItem = m.heldItem
          ..nature = m.nature
          ..evs = Map<String, int>.from(m.evs)
          ..ivs = Map<String, int>.from(m.ivs);
        result.add(baseMember);
      } catch (_) {
        final fallback = m.name.split('-Mega').first.split('-Primal').first;
        final copy = TeamMember(
          name: fallback,
          pokedexNumber: m.pokedexNumber,
          types: m.types,
          ability: m.ability,
          moves: List<String?>.from(m.moves),
          gender: m.gender,
          genderRate: m.genderRate,
        )
          ..level = m.level
          ..heldItem = m.heldItem
          ..nature = m.nature
          ..evs = Map<String, int>.from(m.evs)
          ..ivs = Map<String, int>.from(m.ivs);
        result.add(copy);
      }
    }
    return result;
  }

  List<String> _filterBattleItems(List<String> rawItems) {
    final megaAndOrbPattern = RegExp(
      r'ite($|[\s\-_]*[xy]|\b)|red[\s\-_]*orb|blue[\s\-_]*orb',
      caseSensitive: false,
    );
    final junkPattern = RegExp(
      r'^(tm\d+|hm\d+|tr\d+|key-|mail|letter|old-rod|good-rod|super-rod|bicycle|bike|ticket|pass|card|parcel|pokedex|journal|map|case|pouch)',
      caseSensitive: false,
    );

    return rawItems.where((item) {
      final trimmed = item.trim();
      if (trimmed.isEmpty) return false;
      if (megaAndOrbPattern.hasMatch(trimmed)) return true;
      if (junkPattern.hasMatch(trimmed.toLowerCase())) return false;
      return true;
    }).toList();
  }

  Future<void> _loadData() async {
    try {
      await _service.init();
      if (!mounted) return;

      final baseList = await _service.getBaseSpeciesList();
      final items = await _service.getItemList();
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

      if (_activePreset == TeamPreset.championsVgc) {
        _enforceVgcPreset();
      }
    } catch (e, stack) {
      debugPrint('Initialization Error: $e\n$stack');
      if (!mounted) return;
      setState(() {
        _statusMessage = 'Error loading roster: $e';
        _loading = false;
      });
    }
  }

  void _enforceVgcPreset() {
    for (final member in _team) {
      member.level = 50;
      member.ivs = {'HP': 31, 'Atk': 31, 'Def': 31, 'SpA': 31, 'SpD': 31, 'Spe': 31};
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

  void _applyPreset(TeamPreset preset) async {
    _flushPendingPanelUpdates();
    setState(() {
      _activePreset = preset;
      if (_activePreset == TeamPreset.championsVgc) {
        _enforceVgcPreset();
      }
    });
    await _saveTeam();
    if (_activePreset == TeamPreset.championsVgc) {
      _announce('Preset changed to Champions VGC. Levels set to 50, IVs set to 31.');
    } else {
      _announce('Preset changed to Freeform. Level and IV restrictions removed.');
    }
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
    _flushPendingPanelUpdates();
    _unfocus();
    final int pokedexNumber = baseEntry['num'] as int;

    if (_activePreset == TeamPreset.championsVgc) {
      if (_team.any((m) => m.pokedexNumber == pokedexNumber)) {
        _announce('Species Clause: Pokédex #$pokedexNumber is already on your team.');
        return;
      }
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
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Select Form for ${baseEntry['name']}', style: const TextStyle(fontSize: 14)),
              _buildCloseDialogButton(context),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: formes.map((f) {
                final String fName = f['name'];
                final List<String> fTypes = List<String>.from(f['types'] ?? []);
                return ListTile(
                  dense: true,
                  title: Text(fName, style: const TextStyle(fontSize: 12)),
                  subtitle: Text('Types: ${fTypes.join('/')}', style: const TextStyle(fontSize: 10)),
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

      if (_activePreset == TeamPreset.championsVgc) {
        newMember.level = 50;
        newMember.ivs = {'HP': 31, 'Atk': 31, 'Def': 31, 'SpA': 31, 'SpD': 31, 'Spe': 31};
      }

      setState(() {
        _team.add(newMember);
        _collapsedCards.add(newMember);
        _searchController.clear();
        _filtered = [];
      });
      await _saveTeam();
      if (!mounted) return;
      _announce('$formName added to your team.');
    } catch (e) {
      if (!mounted) return;
      _announce('Could not add $formName.');
    } finally {
      _unfocus();
    }
  }

  Future<void> _toggleMegaForm(int index) async {
    _flushPendingPanelUpdates();
    final member = _team[index];
    try {
      String targetFormName;

      if (member.name.contains('-Mega') || member.name.contains('-Primal')) {
        final baseData = await _service.getPokemon(member.name);
        targetFormName = baseData['baseSpecies'] ?? member.name.split('-')[0];
      } else {
        final heldItem = member.heldItem ?? '';
        if (heldItem.isEmpty) {
          _announce('Hold the correct Mega Stone or Orb on ${member.name} to Mega Evolve.');
          return;
        }
        final megaForm = await _service.getMegaFormForHeldItem(member.name, heldItem);
        if (megaForm == null) {
          _announce('Hold the correct Mega Stone or Orb on ${member.name} to Mega Evolve.');
          return;
        }
        targetFormName = megaForm;
      }

      final data = await _service.getPokemon(targetFormName);
      if (!mounted) return;

      final newTypes = List<String>.from(data['types'] ?? []);
      final abilities = await _service.getAbilitiesForPokemon(targetFormName);
      final newAbility = abilities.isNotEmpty ? abilities.first['name'] : member.ability;

      setState(() {
        member.name = data['name'] ?? targetFormName;
        member.types = newTypes;
        if (newAbility != null) member.ability = newAbility;
        _movesCache.remove(member);
        _abilitiesCache.remove(member);
      });

      await _saveTeam();
      if (!mounted) return;
      _announce('Switched to ${member.name}.');
    } catch (e) {
      if (!mounted) return;
      _announce('Could not toggle Mega form.');
    }
  }

  Future<void> _showLevelDialog(TeamMember member) async {
    _flushPendingPanelUpdates();

    if (_activePreset == TeamPreset.championsVgc) {
      _announce('Levels are fixed at 50 in Champions VGC mode.');
      return;
    }

    final controller = TextEditingController(text: member.level.toString());
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Set Level for ${member.name}', style: const TextStyle(fontSize: 14)),
            _buildCloseDialogButton(context),
          ],
        ),
        content: _buildLightGrayTextField(
          controller: controller,
          labelText: 'Level (1 - 100)',
          keyboardType: TextInputType.number,
        ),
        actions: [
          _buildLightGrayButton(
            label: 'Save',
            onPressed: () async {
              final parsed = int.tryParse(controller.text);
              if (parsed != null && parsed >= 1 && parsed <= 100) {
                setState(() => member.level = parsed);
                await _saveTeam();
                _announce('${member.name} level change to $parsed');
              }
              if (context.mounted) Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }

  Future<void> _showImportDialog() async {
    _flushPendingPanelUpdates();
    _unfocus();
    _importController.clear();

    final docDir = await getApplicationDocumentsDirectory();

    List<FileSystemEntity> availableFiles = [];
    try {
      if (await docDir.exists()) {
        availableFiles = docDir
            .listSync()
            .where((entity) => entity.path.endsWith('.txt'))
            .toList();
      }
    } catch (_) {}

    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Import Showdown Team', style: TextStyle(fontSize: 14)),
                _buildCloseDialogButton(context),
              ],
            ),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildLightGrayTextField(
                      controller: _importController,
                      labelText: 'Paste Showdown Team Text',
                      maxLines: 5,
                    ),
                    if (availableFiles.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      const Divider(),
                      const SizedBox(height: 4),
                      const Text(
                        'load from file:',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      SizedBox(
                        height: 100,
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: availableFiles.length,
                          itemBuilder: (context, idx) {
                            final file = availableFiles[idx];
                            final name = file.path.split(Platform.pathSeparator).last;
                            return ListTile(
                              dense: true,
                              visualDensity: VisualDensity.compact,
                              title: Text(name, style: const TextStyle(fontSize: 11)),
                              onTap: () async {
                                try {
                                  final content = await File(file.path).readAsString();
                                  setDialogState(() {
                                    _importController.text = content;
                                  });
                                  _announce('Team sheet loaded from $name');
                                } catch (e) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('Could not read file: $e')),
                                    );
                                  }
                                }
                              },
                            );
                          },
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              _buildLightGrayButton(
                label: 'Add to Team',
                onPressed: () async {
                  Navigator.pop(context);
                  await _processImport(replace: false);
                },
              ),
              _buildLightGrayButton(
                label: 'Replace Team',
                onPressed: () async {
                  Navigator.pop(context);
                  await _processImport(replace: true);
                },
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _processImport({required bool replace}) async {
    final text = _importController.text.trim();
    if (text.isEmpty) return;

    try {
      final importedMembers = TeamTextCodec.decodeTeam(text);
      if (importedMembers.isEmpty) {
        _announce('No valid Pokémon found in import text.');
        return;
      }

      setState(() {
        if (replace) {
          _team.clear();
        }
        for (final m in importedMembers) {
          if (_team.length < 6) {
            if (_activePreset == TeamPreset.championsVgc) {
              m.level = 50;
              m.ivs = {'HP': 31, 'Atk': 31, 'Def': 31, 'SpA': 31, 'SpD': 31, 'Spe': 31};
            }
            _team.add(m);
            _collapsedCards.add(m);
          }
        }
      });

      await _saveTeam();
      if (!mounted) return;
      _announce('Imported ${importedMembers.length} Pokémon successfully.');
    } catch (e) {
      _announce('Error importing team sheet.');
    }
  }

  Future<void> _showExportDialog() async {
    _flushPendingPanelUpdates();
    _unfocus();
    if (_team.isEmpty) {
      _announce('Your team is empty.');
      return;
    }

    final baseTeam = await _teamAsBaseForms();
    final text = TeamTextCodec.encodeTeam(baseTeam, {}, {}, {}, {});

    final fileNameController = TextEditingController(text: 'Team');

    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Export Team Sheet', style: TextStyle(fontSize: 14)),
            _buildCloseDialogButton(context),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText(
                  text,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                ),
                const SizedBox(height: 10),
                const Divider(),
                const SizedBox(height: 6),
                _buildLightGrayTextField(
                  controller: fileNameController,
                  labelText: 'File Name',
                ),
              ],
            ),
          ),
        ),
        actions: [
          _buildLightGrayButton(
            label: 'Copy',
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: text));
              _announce('Team sheet copied to clipboard');
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Copied to clipboard')),
                );
                Navigator.pop(context);
              }
            },
          ),
          _buildLightGrayButton(
            label: 'Save File',
            onPressed: () async {
              try {
                String rawName = fileNameController.text.trim();
                if (rawName.isEmpty) rawName = 'Team';
                final fileName = rawName.toLowerCase().endsWith('.txt') ? rawName : '$rawName.txt';

                final docDir = await getApplicationDocumentsDirectory();
                final file = File('${docDir.path}/$fileName');
                await file.writeAsString(text);

                _announce('Team sheet saved as $fileName');
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Saved to ${file.path}')),
                  );
                  Navigator.pop(context);
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Could not save file: $e')),
                  );
                }
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCloseDialogButton(BuildContext context) {
    return Semantics(
      label: 'Close dialog',
      button: true,
      container: true,
      excludeSemantics: true,
      child: IconButton(
        icon: const Text('❌', style: TextStyle(fontSize: 14)),
        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        padding: EdgeInsets.zero,
        onPressed: () => Navigator.pop(context),
      ),
    );
  }

  Widget _buildLightGrayButton({required String label, required VoidCallback onPressed}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Semantics(
      label: label,
      button: true,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: isDark ? Colors.grey[800] : Colors.grey[300],
          foregroundColor: isDark ? Colors.white : Colors.black,
          minimumSize: const Size(60, 32),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        ),
        onPressed: onPressed,
        child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
      ),
    );
  }

  Widget _buildLightGrayTextField({
    required TextEditingController controller,
    required String labelText,
    int maxLines = 1,
    TextInputType keyboardType = TextInputType.text,
    Function(String)? onChanged,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fillColor = isDark ? Colors.grey[850] : Colors.grey[200];
    final textColor = isDark ? Colors.white : Colors.black;

    return TextField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      style: TextStyle(color: textColor, fontSize: 12),
      decoration: InputDecoration(
        labelText: labelText,
        labelStyle: TextStyle(color: textColor.withOpacity(0.7), fontSize: 11),
        filled: true,
        fillColor: fillColor,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
      ),
      onChanged: onChanged,
    );
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
      onTap: () {
        _flushPendingPanelUpdates();
        _unfocus();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Semantics(
            label: 'Select the battle format for team building',
            child: DropdownButtonHideUnderline(
              child: DropdownButton<TeamPreset>(
                value: _activePreset,
                isDense: true,
                icon: const Icon(Icons.arrow_drop_down, size: 22),
                items: const [
                  DropdownMenuItem(
                    value: TeamPreset.championsVgc,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Team Builder Preset', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                        Text('Champions VGC', style: TextStyle(fontSize: 11, color: Colors.grey)),
                      ],
                    ),
                  ),
                  DropdownMenuItem(
                    value: TeamPreset.freeform,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Team Builder Preset', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                        Text('Freeform', style: TextStyle(fontSize: 11, color: Colors.grey)),
                      ],
                    ),
                  ),
                ],
                onChanged: (preset) {
                  if (preset != null && preset != _activePreset) {
                    _applyPreset(preset);
                  }
                },
              ),
            ),
          ),
          actions: [
            Semantics(
              label: 'Import team',
              button: true,
              container: true,
              excludeSemantics: true,
              child: IconButton(
                icon: const Text('📥', style: TextStyle(fontSize: 16)),
                onPressed: _showImportDialog,
              ),
            ),
            Semantics(
              label: 'Export team',
              button: true,
              container: true,
              excludeSemantics: true,
              child: IconButton(
                icon: const Text('📤', style: TextStyle(fontSize: 16)),
                onPressed: _showExportDialog,
              ),
            ),
          ],
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
              child: _buildLightGrayTextField(
                controller: _searchController,
                labelText: 'Search Base Pokémon...',
                onChanged: _filter,
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
                  ? const Center(child: Text('Search species to add to team', style: TextStyle(fontSize: 11)))
                  : ListView.builder(
                      itemCount: _filtered.length,
                      itemBuilder: (context, index) {
                        final entry = _filtered[index];
                        final types = List<String>.from(entry['types'] ?? []);
                        return ListTile(
                          dense: true,
                          visualDensity: VisualDensity.compact,
                          title: Text(entry['name'], style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                          subtitle: Text('Types: ${types.join("/")}', style: const TextStyle(fontSize: 10)),
                          onTap: () => _handleSpeciesTap(entry),
                        );
                      },
                    ),
            ),
            if (_statusMessage.isNotEmpty)
              Container(
                width: double.infinity,
                color: Theme.of(context).brightness == Brightness.dark ? Colors.black26 : Colors.grey[200],
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                child: Text(
                  _statusMessage,
                  style: TextStyle(
                    color: Theme.of(context).brightness == Brightness.dark ? Colors.grey[400] : Colors.grey[700],
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
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

    final typesStr = member.types.join('/');
    final itemStr = (member.heldItem != null && member.heldItem!.isNotEmpty) ? member.heldItem! : 'None';
    final movesStr = member.moves.where((m) => m != null && m.isNotEmpty).join(' / ');
    final int totalEvs = member.evs.values.fold(0, (sum, val) => sum + val);

    final semanticSummary = '${member.name}, Types: $typesStr, Item: $itemStr, Level: ${member.level}, Ability: ${member.ability ?? "None"}, Nature: ${member.nature}, Gender: ${member.gender}, Moves: ${movesStr.isNotEmpty ? movesStr : "None"}, Total EVs: $totalEvs';

    return Semantics(
      key: ValueKey('member_card_${member.pokedexNumber}_$index'),
      label: semanticSummary,
      container: true,
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${member.name.toUpperCase()}  $typesStr',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '@$itemStr  lvl.${member.level}',
                          style: const TextStyle(fontSize: 10, fontFamily: 'monospace'),
                        ),
                      ],
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildEmojiButton(
                        emoji: '🔼',
                        semanticLabel: 'Change level for ${member.name}',
                        onPressed: () => _showLevelDialog(member),
                      ),
                      _buildEmojiButton(
                        emoji: 'Ⓜ️',
                        semanticLabel: 'Toggle Mega form based on held item for ${member.name}',
                        onPressed: () => _toggleMegaForm(index),
                      ),
                      _buildEmojiButton(
                        emoji: isCollapsed ? '⬇️' : '⬆️',
                        semanticLabel: isCollapsed ? 'Expand ${member.name} details' : 'Collapse ${member.name} details',
                        onPressed: () {
                          _flushPendingPanelUpdates(member);
                          setState(() {
                            if (isCollapsed) {
                              _collapsedCards.remove(member);
                            } else {
                              _collapsedCards.add(member);
                              _activePanels[member] = null;
                            }
                          });
                        },
                      ),
                      _buildEmojiButton(
                        emoji: '🗑️',
                        semanticLabel: 'Remove ${member.name} from team',
                        onPressed: () async {
                          _flushPendingPanelUpdates(member);
                          final name = member.name;
                          setState(() => _team.removeAt(index));
                          await _saveTeam();
                          _announce('$name removed from team');
                        },
                      ),
                    ],
                  ),
                ],
              ),

              if (!isCollapsed) ...[
                const Divider(height: 12),
                Text('Ability: ${member.ability ?? "None"} | Gender: ${member.gender} | Nature: ${member.nature}', style: const TextStyle(fontSize: 10)),
                Text('Moves: ${movesStr.isNotEmpty ? movesStr : "None"}', style: const TextStyle(fontSize: 10)),
                Text('Total EVs: $totalEvs / 510', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildPanelToggle('⚙️', 'Details', 'Open details editor for ${member.name}', activePanel == 'details', () => _togglePanel(member, 'details')),
                    _buildPanelToggle('⚔️', 'Moves', 'Open move editor for ${member.name}', activePanel == 'moves', () => _togglePanel(member, 'moves')),
                    _buildPanelToggle('📈', 'EVs', 'Open EV allocation for ${member.name}', activePanel == 'evs', () => _togglePanel(member, 'evs')),
                    _buildPanelToggle('🎚️', 'IVs', 'Open IV allocation for ${member.name}', activePanel == 'ivs', () => _togglePanel(member, 'ivs')),
                    _buildPanelToggle('📊', 'Stats', 'Show stats dialog for ${member.name}', false, () => _showStats(member)),
                  ],
                ),
                if (activePanel != null) _buildPanelContent(index, activePanel),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmojiButton({required String emoji, required String semanticLabel, required VoidCallback onPressed}) {
    return Semantics(
      label: semanticLabel,
      button: true,
      container: true,
      excludeSemantics: true,
      child: InkWell(
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Text(emoji, style: const TextStyle(fontSize: 21)),
        ),
      ),
    );
  }

  Widget _buildPanelToggle(String emoji, String label, String semanticLabel, bool isActive, VoidCallback onPressed) {
    return Semantics(
      label: semanticLabel,
      button: true,
      container: true,
      excludeSemantics: true,
      child: TextButton(
        style: TextButton.styleFrom(
          minimumSize: const Size(32, 24),
          padding: EdgeInsets.zero,
          backgroundColor: isActive ? Theme.of(context).colorScheme.primaryContainer : Colors.transparent,
        ),
        onPressed: onPressed,
        child: Text(emoji, style: const TextStyle(fontSize: 13)),
      ),
    );
  }

  void _togglePanel(TeamMember member, String panelName) async {
    _unfocus();
    _flushPendingPanelUpdates(member);

    final isOpening = _activePanels[member] != panelName;

    setState(() {
      _activePanels[member] = isOpening ? panelName : null;
    });

    if (isOpening) {
      if (panelName == 'evs') {
        _initialEvs[member] = Map<String, int>.from(member.evs);
      } else if (panelName == 'ivs') {
        _initialIvs[member] = Map<String, int>.from(member.ivs);
      }

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
    _flushPendingPanelUpdates(member);
    _unfocus();
    try {
      await StatsDialog.show(context, member, _service);
    } catch (_) {
      if (!mounted) return;
      _announce('Could not load stats.');
    }
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
          if (heldItem != null) {
            final trimmed = heldItem.trim();
            if (_activePreset == TeamPreset.championsVgc && trimmed.isNotEmpty) {
              final isDuplicate = _team.any((m) => m != member && (m.heldItem ?? '').toLowerCase().trim() == trimmed.toLowerCase());
              if (isDuplicate) {
                _announce('Item Clause: $trimmed is already held by another Pokémon.');
                return;
              }
            }
            setState(() => member.heldItem = trimmed);
            _announce('${member.name} is now holding ${trimmed.isEmpty ? "no item" : trimmed}');
          }
          if (gender != null) {
            setState(() => member.gender = gender);
            _announce('${member.name} gender set to $gender');
          }
          if (ability != null) {
            setState(() => member.ability = ability);
            _announce('${member.name} ability change to $ability');
          }
          if (nature != null) {
            setState(() => member.nature = nature);
            _announce('${member.name} nature set to $nature');
          }
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
          _announce('${member.name} moveset updated');
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
        isLocked: _activePreset == TeamPreset.championsVgc,
        onChanged: (ivs) async {
          if (_activePreset == TeamPreset.championsVgc) return;
          setState(() => member.ivs = ivs);
          await _saveTeam();
        },
      );
    }

    return const SizedBox.shrink();
  }
}
