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
import '../services/stat_calculator.dart';

// =============================================================================
// Inlined: DetailsEditorPanel (was ../widgets/details_editor_panel.dart)
// =============================================================================

class DetailsEditorPanel extends StatelessWidget {
  final String? heldItem;
  final String gender;
  final int genderRate;
  final String? ability;
  final List<Map<String, dynamic>>? abilities;
  final String nature;
  final List<String> itemList;
  final List<Map<String, dynamic>> natures;
  final Function({
    String? heldItem,
    String? gender,
    String? ability,
    String? nature,
  }) onChanged;

  const DetailsEditorPanel({
    super.key,
    this.heldItem,
    required this.gender,
    required this.genderRate,
    this.ability,
    this.abilities,
    required this.nature,
    this.itemList = const [],
    this.natures = const [],
    required this.onChanged,
  });

  List<String> _getGenderOptions() {
    if (genderRate == -1) return ['Genderless'];
    if (genderRate == 0) return ['Male'];
    if (genderRate == 8) return ['Female'];
    return ['Male', 'Female'];
  }

  List<Map<String, dynamic>> _getUniqueAbilities() {
    final seen = <String>{};
    final result = <Map<String, dynamic>>[];
    for (final a in abilities ?? const []) {
      final name = a['name'] as String?;
      if (name != null && name.isNotEmpty && seen.add(name)) {
        result.add(a);
      }
    }
    return result;
  }

  static InputDecoration _fieldDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(fontSize: 13, color: Color(0xFFCFCFCF)),
      isDense: true,
      filled: true,
      fillColor: const Color(0xFF2A2A2E),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: Color(0xFF757575))),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: Color(0xFF9E9E9E))),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: Colors.lightBlueAccent, width: 2)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
    );
  }

  static const _fieldTextStyle = TextStyle(fontSize: 15, color: Colors.white);

  @override
  Widget build(BuildContext context) {
    final genderOptions = _getGenderOptions();
    final abilityOptions = _getUniqueAbilities();
    final abilityNames = abilityOptions.map((a) => a['name'] as String).toSet();
    final safeAbilityValue = abilityNames.contains(ability) ? ability : null;
    final natureNames = natures.map((n) => n['name'] as String).toSet();
    final safeNatureValue = natureNames.contains(nature) ? nature : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Customize Details',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
        ),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _HeldItemField(
                key: const ValueKey('held_item_field'),
                initialValue: heldItem ?? '',
                itemList: itemList,
                onChanged: (val) => onChanged(heldItem: val),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: DropdownButtonFormField<String>(
                key: const ValueKey('gender_dropdown'),
                value: genderOptions.contains(gender) ? gender : genderOptions.first,
                style: _fieldTextStyle,
                dropdownColor: const Color(0xFF2A2A2E),
                decoration: _fieldDecoration('Gender'),
                items: genderOptions
                    .map((g) => DropdownMenuItem(value: g, child: Text(g, style: _fieldTextStyle)))
                    .toList(),
                onChanged: (val) {
                  if (val != null) onChanged(gender: val);
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                key: const ValueKey('ability_dropdown'),
                value: safeAbilityValue,
                isExpanded: true,
                style: _fieldTextStyle,
                dropdownColor: const Color(0xFF2A2A2E),
                decoration: _fieldDecoration('Ability'),
                selectedItemBuilder: (context) {
                  return abilityOptions.map((a) {
                    return Align(
                      alignment: Alignment.centerLeft,
                      child: Text(a['name'] as String, style: _fieldTextStyle, overflow: TextOverflow.ellipsis),
                    );
                  }).toList();
                },
                items: abilityOptions.map((a) {
                  final name = a['name'] as String;
                  final desc = a['shortDesc'] as String? ?? '';
                  return DropdownMenuItem(
                    value: name,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(name, style: _fieldTextStyle),
                          if (desc.isNotEmpty)
                            Text(
                              desc,
                              style: const TextStyle(fontSize: 11, color: Color(0xFFB0B0B0)),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
                onChanged: (val) {
                  if (val != null) onChanged(ability: val);
                },
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: DropdownButtonFormField<String>(
                key: const ValueKey('nature_dropdown'),
                value: safeNatureValue,
                style: _fieldTextStyle,
                dropdownColor: const Color(0xFF2A2A2E),
                decoration: _fieldDecoration('Nature'),
                selectedItemBuilder: (context) {
                  return natures.map((n) {
                    return Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        n['name'] as String,
                        style: _fieldTextStyle,
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  }).toList();
                },
                items: natures.map((n) {
                  final boosted = n['boosted'] as String?;
                  final lowered = n['lowered'] as String?;
                  final String boostText = (boosted != null && lowered != null)
                      ? ' (+$boosted, -$lowered)'
                      : ' (neutral)';
                  return DropdownMenuItem(
                    value: n['name'] as String,
                    child: Text(
                      '${n['name']}$boostText',
                      style: const TextStyle(fontSize: 14, color: Colors.white),
                    ),
                  );
                }).toList(),
                onChanged: (val) {
                  if (val != null) onChanged(nature: val);
                },
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// =============================================================================
// Held item field with proper focus-listener lifecycle management
// =============================================================================

class _HeldItemField extends StatefulWidget {
  final String initialValue;
  final List<Map<String, dynamic>> itemList;
  final ValueChanged<String> onChanged;

  const _HeldItemField({
    required this.initialValue,
    required this.itemList,
    required this.onChanged,
  });

  @override
  State<_HeldItemField> createState() => _HeldItemFieldState();
}

class _HeldItemFieldState extends State<_HeldItemField> {
  FocusNode? _attachedFocusNode;
  VoidCallback? _focusListener;
  TextEditingController? _attachedController;

  void _handleFocusChange() {
    if (_attachedFocusNode != null &&
        !_attachedFocusNode!.hasFocus &&
        _attachedController != null) {
      widget.onChanged(_attachedController!.text.trim());
    }
  }

  @override
  void dispose() {
    if (_attachedFocusNode != null && _focusListener != null) {
      _attachedFocusNode!.removeListener(_focusListener!);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Autocomplete<Map<String, dynamic>>(
      initialValue: TextEditingValue(text: widget.initialValue),
      displayStringForOption: (item) => item['name'] as String,
      optionsBuilder: (TextEditingValue value) {
        if (value.text.isEmpty || widget.itemList.isEmpty) {
          return const Iterable<Map<String, dynamic>>.empty();
        }
        final query = value.text.toLowerCase();
        return widget.itemList
            .where((item) => (item['name'] as String? ?? '').toLowerCase().contains(query))
            .take(8);
      },
      optionsViewBuilder: (context, onSelected, options) {
        final list = options.toList();
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            color: const Color(0xFF2A2A2E),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 260, maxWidth: 320),
              child: ListView.builder(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: list.length,
                itemBuilder: (context, index) {
                  final item = list[index];
                  final name = item['name'] as String? ?? '';
                  final desc = item['shortDesc'] as String? ?? '';
                  return InkWell(
                    onTap: () => onSelected(item),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(name, style: const TextStyle(fontSize: 15, color: Colors.white, fontWeight: FontWeight.bold)),
                          if (desc.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(desc, style: const TextStyle(fontSize: 12, color: Color(0xFFCFCFCF))),
                          ],
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
      onSelected: (selected) => widget.onChanged(selected['name'] as String),
      fieldViewBuilder: (context, controller, focusNode, onEditingComplete) {
        // Attach the listener only once per focusNode instance, and keep a
        // reference to the exact closure so dispose() can remove it correctly.
        if (_attachedFocusNode != focusNode) {
          if (_attachedFocusNode != null && _focusListener != null) {
            _attachedFocusNode!.removeListener(_focusListener!);
          }
          _attachedFocusNode = focusNode;
          _attachedController = controller;
          _focusListener = _handleFocusChange;
          focusNode.addListener(_focusListener!);
        }

        return TextField(
          controller: controller,
          focusNode: focusNode,
          style: const TextStyle(fontSize: 15, color: Colors.white),
          onEditingComplete: () {
            onEditingComplete();
            widget.onChanged(controller.text.trim());
          },
          decoration: InputDecoration(
            labelText: 'Held Item',
            labelStyle: const TextStyle(fontSize: 13, color: Color(0xFFCFCFCF)),
            isDense: true,
            filled: true,
            fillColor: const Color(0xFF2A2A2E),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: Color(0xFF9E9E9E))),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: Colors.lightBlueAccent, width: 2)),
            suffixIcon: controller.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear, size: 20, color: Colors.white70),
                    onPressed: () {
                      controller.clear();
                      widget.onChanged('');
                    },
                  )
                : null,
          ),
          onChanged: (val) {
            if (val.trim().isEmpty) widget.onChanged('');
          },
        );
      },
    );
  }
}

// =============================================================================
// Inlined: EvEditorPanel (was ../widgets/ev_editor_panel.dart)
// =============================================================================

class EvEditorPanel extends StatelessWidget {
  final Map<String, int> evs;
  final ValueChanged<Map<String, int>> onChanged;

  const EvEditorPanel({
    super.key,
    required this.evs,
    required this.onChanged,
  });

  static const _statsOrder = ['HP', 'Atk', 'Def', 'SpA', 'SpD', 'Spe'];

  int get totalEvs => evs.values.fold(0, (a, b) => a + b);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('EV Allocation', style: TextStyle(fontWeight: FontWeight.bold)),
              Semantics(
                label: 'Total EVs allocated: $totalEvs out of 510 maximum',
                child: Text(
                  'Total: $totalEvs / 510',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: totalEvs > 510 ? Colors.red : Colors.green,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              childAspectRatio: 1.7,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
            ),
            itemCount: _statsOrder.length,
            itemBuilder: (context, index) {
              final stat = _statsOrder[index];
              final currentEv = evs[stat] ?? 0;

              return Semantics(
                label: 'Effort Value for $stat, current value $currentEv',
                textField: true,
                excludeSemantics: true,
                child: TextFormField(
                  key: ValueKey('ev_field_$stat'),
                  initialValue: currentEv.toString(),
                  keyboardType: TextInputType.number,
                  style: const TextStyle(fontSize: 16, color: Colors.white),
                  decoration: InputDecoration(
                    labelText: stat,
                    labelStyle: const TextStyle(fontSize: 13, color: Color(0xFFCFCFCF)),
                    floatingLabelBehavior: FloatingLabelBehavior.always,
                    isDense: true,
                    filled: true,
                    fillColor: const Color(0xFF2A2A2E),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: Color(0xFF9E9E9E))),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: Colors.lightBlueAccent, width: 2)),
                  ),
                  onChanged: (val) {
                    final parsed = int.tryParse(val) ?? 0;
                    final updated = Map<String, int>.from(evs);
                    final otherTotal = totalEvs - currentEv;
                    final maxAllowed = (510 - otherTotal).clamp(0, 252);
                    updated[stat] = parsed.clamp(0, maxAllowed);
                    onChanged(updated);
                  },
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Inlined: MoveEditorPanel (was ../widgets/move_editor_panel.dart)
// =============================================================================

class MoveEditorPanel extends StatelessWidget {
  final List<String?> moves;
  final List<Map<String, dynamic>> availableMoves;
  final ValueChanged<List<String?>> onChanged;

  const MoveEditorPanel({
    super.key,
    required this.moves,
    required this.availableMoves,
    required this.onChanged,
  });

  Map<String, dynamic>? _dataForMove(String? name) {
    if (name == null) return null;
    for (final m in availableMoves) {
      if (m['name'] == name) return m;
    }
    return null;
  }

  void _showMoveInfo(BuildContext context, Map<String, dynamic> moveData) {
    final type = moveData['type'] as String? ?? '?';
    final category = moveData['category'] as String? ?? '?';
    final power = moveData['basePower'];
    final accuracy = moveData['accuracy'];
    final powerStr = (power == null || power == 0) ? '—' : power.toString();
    final accStr = (accuracy == true) ? '—' : (accuracy?.toString() ?? '?');
    final desc = (moveData['shortDesc'] as String?)?.isNotEmpty == true
        ? moveData['shortDesc'] as String
        : (moveData['desc'] as String? ?? 'No description available.');

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(moveData['name'] as String? ?? 'Move', style: const TextStyle(fontSize: 15)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Type: $type   |   Category: $category', style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 4),
            Text('Power: $powerStr   |   Accuracy: $accStr', style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 10),
            Text(desc, style: const TextStyle(fontSize: 13)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(6.0),
      color: Colors.black87,
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: _buildMoveDropdown(context, 0)),
              const SizedBox(width: 6),
              Expanded(child: _buildMoveDropdown(context, 1)),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(child: _buildMoveDropdown(context, 2)),
              const SizedBox(width: 6),
              Expanded(child: _buildMoveDropdown(context, 3)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMoveDropdown(BuildContext context, int slotIndex) {
    final currentMove = moves.length > slotIndex ? moves[slotIndex] : null;
    final availableMoveNames = availableMoves.map((m) => m['name'] as String).toList();
    final currentMoveData = _dataForMove(currentMove);

    return Semantics(
      label: 'Move slot ${slotIndex + 1}',
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: DropdownButtonFormField<String>(
              key: ValueKey('move_dropdown_$slotIndex'),
              value: availableMoveNames.contains(currentMove) ? currentMove : null,
              isDense: true,
              isExpanded: true,
              style: const TextStyle(fontSize: 14, color: Colors.white),
              dropdownColor: Colors.grey[900],
              decoration: InputDecoration(
                labelText: 'Move ${slotIndex + 1}',
                labelStyle: const TextStyle(color: Colors.white70, fontSize: 12),
                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: Color(0xFF9E9E9E))),
              ),
              items: [
                const DropdownMenuItem<String>(
                  value: null,
                  child: Text('(None)', style: TextStyle(fontSize: 13, color: Colors.white54)),
                ),
                ...availableMoves.map((m) {
                  final name = m['name'] as String;
                  final type = m['type'] as String? ?? '';
                  final power = m['basePower'];
                  final powerStr = (power == null || power == 0) ? '—' : power.toString();
                  return DropdownMenuItem<String>(
                    value: name,
                    child: Text(
                      '$name  ($type, $powerStr BP)',
                      style: const TextStyle(fontSize: 13, color: Colors.white),
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                }),
              ],
              onChanged: (selected) {
                if (selected != null) {
                  final duplicateSlot = moves.indexWhere(
                    (m) => m != null && m == selected,
                  );
                  if (duplicateSlot != -1 && duplicateSlot != slotIndex) {
                    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                      SnackBar(content: Text('$selected is already selected in another slot.')),
                    );
                    return;
                  }
                }

                final updated = List<String?>.from(moves);
                while (updated.length < 4) {
                  updated.add(null);
                }
                updated[slotIndex] = selected;
                onChanged(updated);
              },
            ),
          ),
          Semantics(
            label: currentMoveData != null ? 'Show details for $currentMove' : 'No move selected for slot ${slotIndex + 1}',
            button: true,
            excludeSemantics: true,
            child: IconButton(
              icon: const Icon(Icons.info_outline, size: 18, color: Colors.white70),
              onPressed: currentMoveData != null ? () => _showMoveInfo(context, currentMoveData) : null,
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Inlined: StatsDialog (was ../widgets/stats_dialog.dart)
// =============================================================================

class StatsDialog extends StatelessWidget {
  final TeamMember member;
  final Map<String, int> normalStats;
  final String boosted;
  final String lowered;

  const StatsDialog({
    super.key,
    required this.member,
    required this.normalStats,
    required this.boosted,
    required this.lowered,
  });

  static Future<void> show(BuildContext context, TeamMember member, JsEngineService service) async {
    final natureInfo = await service.getNatureBoosts(member.nature);
    final boosted = natureInfo['plus'] ?? '';
    final lowered = natureInfo['minus'] ?? '';

    final pokemonData = await service.getPokemon(member.name);
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

    if (!context.mounted) return;

    await showDialog(
      context: context,
      builder: (context) => StatsDialog(
        member: member,
        normalStats: normalStats,
        boosted: boosted,
        lowered: lowered,
      ),
    );
  }

  List<Widget> _buildStatRows(Map<String, int> stats) {
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
      final semantic = '${e.key}: ${e.value}${isBoosted ? ", boosted" : ""}${isLowered ? ", lowered" : ""}';
      return Text(
        '${e.key}: ${e.value}$suffix',
        semanticsLabel: semantic,
      );
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ivStr = member.ivs.entries.map((e) => '${e.key} ${e.value}').join(', ');
    final evStr = member.evs.entries.map((e) => '${e.key} ${e.value}').join(', ');

    return AlertDialog(
      title: Text('${member.name.toUpperCase()} — Level ${member.level} Stats'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Nature: ${member.nature}'),
            const SizedBox(height: 6),
            Text(
              'IVs: $ivStr',
              style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
            ),
            Text(
              'EVs: $evStr',
              style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
            ),
            const SizedBox(height: 12),
            const Text('Calculated Stats', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 4),
            ..._buildStatRows(normalStats),
          ],
        ),
      ),
      actions: [
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: cs.primaryContainer.withValues(alpha: 0.85),
            foregroundColor: cs.onPrimaryContainer,
          ),
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

// =============================================================================
// Original TeamBuilderScreen
// =============================================================================

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
  final _teamScrollController = ScrollController();
  static const _storageKey = 'saved_team';

  List<Map<String, dynamic>> _baseSpeciesList = [];
  List<Map<String, dynamic>> _filtered = [];
  List<Map<String, dynamic>> _itemList = [];
  List<Map<String, dynamic>> _natures = [];
  List<TeamMember> _team = [];

  final Map<TeamMember, List<Map<String, dynamic>>> _movesCache = {};
  final Map<TeamMember, List<Map<String, dynamic>>> _abilitiesCache = {};
  final Map<TeamMember, Map<String, dynamic>> _speciesDataCache = {};
  final Set<TeamMember> _collapsedCards = {};

  final Map<TeamMember, Map<String, int>> _initialEvs = {};

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
    _teamScrollController.dispose();
    _service.dispose();
    super.dispose();
  }

  void _unfocus() {
    _searchFocusNode.unfocus();
    FocusManager.instance.primaryFocus?.unfocus();
    FocusScope.of(context).unfocus();
  }

  void _unfocusAfterFrame() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _unfocus();
      }
    });
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
    }
  }

  void _evictMemberCaches(TeamMember member) {
    _movesCache.remove(member);
    _abilitiesCache.remove(member);
    _speciesDataCache.remove(member);
    _initialEvs.remove(member);
    _collapsedCards.remove(member);
  }

  Future<void> _ensureSpeciesData(TeamMember member) async {
    if (_speciesDataCache.containsKey(member)) return;
    try {
      final data = await _service.getPokemon(member.name);
      if (!mounted) return;
      setState(() => _speciesDataCache[member] = data);
    } catch (_) {}
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
          ..heldItem = m.heldItem
          ..nature = m.nature
          ..evs = Map<String, int>.from(m.evs);
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
          ..heldItem = m.heldItem
          ..nature = m.nature
          ..evs = Map<String, int>.from(m.evs);
        result.add(copy);
      }
    }
    return result;
  }

  List<Map<String, dynamic>> _filterBattleItems(List<Map<String, dynamic>> rawItems) {
    final megaAndOrbPattern = RegExp(
      r'ite($|[\s\-_]*[xy]|\b)|red[\s\-_]*orb|blue[\s\-_]*orb',
      caseSensitive: false,
    );
    final junkPattern = RegExp(
      r'^(tm\d+|hm\d+|tr\d+|key-|mail|letter|old-rod|good-rod|super-rod|bicycle|bike|ticket|pass|card|parcel|pokedex|journal|map|case|pouch)',
      caseSensitive: false,
    );

    return rawItems.where((item) {
      final trimmed = (item['name'] as String? ?? '').trim();
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
      final natures = await _service.getAllNatures();
      await _loadSavedTeam();

      if (!mounted) return;

      setState(() {
        _baseSpeciesList = baseList;
        _itemList = _filterBattleItems(items);
        _natures = natures;
        _filtered = [];
        _loading = false;
        for (final member in _team) {
          _collapsedCards.add(member);
        }
        if (baseList.isEmpty) {
          _statusMessage = 'DIAG: ${_service.lastDiagnostics ?? "no diagnostics captured"}';
        } else if (natures.isEmpty) {
          _statusMessage = 'DIAG: Nature list failed to load from engine (Dex.data.Natures empty or unreachable).';
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
      _unfocus();
      _unfocusAfterFrame();
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
    _unfocus();
    _unfocusAfterFrame();
  }

  Future<void> _confirmRemoveAllTeamMembers() async {
    _flushPendingPanelUpdates();
    _unfocus();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove All Pokémon?', style: TextStyle(fontSize: 14)),
        content: const Text(
          'This will clear your entire team. This cannot be undone.',
          style: TextStyle(fontSize: 12),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove All', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() {
      for (final member in List<TeamMember>.from(_team)) {
        _evictMemberCaches(member);
      }
      _team.clear();
    });
    await _saveTeam();
    if (!mounted) return;
    _announce('All Pokémon removed from team');
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
    _unfocus();
    _unfocusAfterFrame();
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
    FocusNode? focusNode,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fillColor = isDark ? Colors.grey[850] : Colors.grey[200];
    final textColor = isDark ? Colors.white : Colors.black;

    return TextField(
      controller: controller,
      focusNode: focusNode,
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
          title: const Text('Champions Team Builder', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
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
            Semantics(
              label: 'Remove all Pokémon from team',
              button: true,
              container: true,
              excludeSemantics: true,
              child: IconButton(
                icon: const Text('🧹', style: TextStyle(fontSize: 16)),
                onPressed: _team.isEmpty ? null : _confirmRemoveAllTeamMembers,
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
                focusNode: _searchFocusNode,
                labelText: 'Search Base Pokémon...',
                onChanged: _filter,
              ),
            ),
            if (_team.isNotEmpty)
              Expanded(
                flex: 5,
                child: ListView.builder(
                  controller: _teamScrollController,
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
              GestureDetector(
                onTap: () {
                  if (_statusMessage.startsWith('DIAG:')) {
                    showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Diagnostics'),
                        content: SizedBox(
                          width: double.maxFinite,
                          child: SingleChildScrollView(
                            child: SelectableText(_statusMessage, style: const TextStyle(fontSize: 12, fontFamily: 'monospace')),
                          ),
                        ),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
                        ],
                      ),
                    );
                  }
                },
                child: Container(
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
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTeamCard(int index) {
    final member = _team[index];
    final isCollapsed = _collapsedCards.contains(member);

    final typesStr = member.types.join('/');
    final itemStr = (member.heldItem != null && member.heldItem!.isNotEmpty) ? member.heldItem! : 'None';
    final abilityStr = member.ability ?? 'None';
    final movesStr = member.moves.where((m) => m != null && m.isNotEmpty).join(' / ');
    final int totalEvs = member.evTotal;
    final speciesData = _speciesDataCache[member];
    final heightStr = speciesData != null ? '${speciesData['heightm'] ?? '?'} m' : null;
    final weightStr = speciesData != null ? '${speciesData['weightkg'] ?? '?'} kg' : null;

    final semanticSummary = '${member.name}, Types: $typesStr, Item: $itemStr, Level: ${member.level}, Ability: $abilityStr, Nature: ${member.nature}, Gender: ${member.gender}, Moves: ${movesStr.isNotEmpty ? movesStr : "None"}, Total EVs: $totalEvs';

    return Semantics(
      key: ValueKey('member_card_${member.pokedexNumber}_$index'),
      label: semanticSummary,
      container: true,
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        child: InkWell(
          onTap: () {
            _flushPendingPanelUpdates(member);
            final willExpand = isCollapsed;
            setState(() {
              if (isCollapsed) {
                _collapsedCards.remove(member);
              } else {
                _collapsedCards.add(member);
              }
            });
            if (willExpand) _ensureSpeciesData(member);
          },
          child: Padding(
            padding: const EdgeInsets.all(10.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${member.name.toUpperCase()}  $typesStr',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
                const SizedBox(height: 3),
                Text(
                  '@$itemStr  ✦$abilityStr',
                  style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildEmojiButton(
                      emoji: 'Ⓜ️',
                      semanticLabel: 'Toggle Mega form based on held item for ${member.name}',
                      onPressed: () => _toggleMegaForm(index),
                    ),
                    _buildEmojiButton(
                      emoji: '📝',
                      semanticLabel: 'Edit details, moves, and EVs for ${member.name}',
                      onPressed: () => _openEditDialog(member),
                    ),
                    _buildEmojiButton(
                      emoji: '📊',
                      semanticLabel: 'Show stats dialog for ${member.name}',
                      onPressed: () => _showStats(member),
                    ),
                    _buildEmojiButton(
                      emoji: '🗑️',
                      semanticLabel: 'Remove ${member.name} from team',
                      onPressed: () async {
                        _flushPendingPanelUpdates(member);
                        final name = member.name;
                        setState(() {
                          _team.removeAt(index);
                          _evictMemberCaches(member);
                        });
                        await _saveTeam();
                        _announce('$name removed from team');
                      },
                    ),
                  ],
                ),
                if (!isCollapsed) ...[
                  const Divider(height: 14),
                  Text('Gender: ${member.gender} | Nature: ${member.nature}', style: const TextStyle(fontSize: 13)),
                  if (heightStr != null && weightStr != null)
                    Text('Height: $heightStr | Weight: $weightStr', style: const TextStyle(fontSize: 13)),
                  const SizedBox(height: 2),
                  Text('Moves: ${movesStr.isNotEmpty ? movesStr : "None"}', style: const TextStyle(fontSize: 13)),
                  const SizedBox(height: 2),
                  Text('Total EVs: $totalEvs / 510', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                ],
              ],
            ),
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
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Text(emoji, style: const TextStyle(fontSize: 24)),
        ),
      ),
    );
  }

  Future<void> _openEditDialog(TeamMember member) async {
    _unfocus();
    _flushPendingPanelUpdates(member);

    // Track EVs at dialog-open time so we can announce a change once the
    // dialog closes, same as the old EV-only panel did.
    _initialEvs[member] = Map<String, int>.from(member.evs);

    if (!_movesCache.containsKey(member)) {
      try {
        final movesData = await _service.getMovesForSpecies(member.name);
        if (!mounted) return;
        setState(() => _movesCache[member] = movesData);
      } catch (_) {}
    }
    if (!_abilitiesCache.containsKey(member)) {
      try {
        final abilities = await _service.getAbilitiesForPokemon(member.name);
        if (!mounted) return;
        setState(() => _abilitiesCache[member] = abilities);
      } catch (_) {}
    }

    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          // Prevents the dialog from resizing when the on-screen keyboard
          // opens/closes. That resize is what triggers the layout +
          // semantics-tree rebuild that drops TalkBack's accessibility
          // focus off the active field. Ignoring viewInsets here keeps the
          // dialog's layout stable across keyboard show/hide.
          return MediaQuery(
            data: MediaQuery.of(dialogContext).removeViewInsets(removeBottom: true),
            child: AlertDialog(
            title: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(child: Text('Edit ${member.name}', style: const TextStyle(fontSize: 14))),
                _buildCloseDialogButton(dialogContext),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DetailsEditorPanel(
                    key: const ValueKey('details_panel'),
                    heldItem: member.heldItem,
                    gender: member.gender,
                    genderRate: member.genderRate,
                    ability: member.ability,
                    abilities: _abilitiesCache[member],
                    nature: member.nature,
                    itemList: _itemList,
                    natures: _natures,
                    onChanged: ({heldItem, gender, ability, nature}) async {
                      if (heldItem != null) {
                        final trimmed = heldItem.trim();
                        if (trimmed.isNotEmpty) {
                          final isDuplicate = _team.any((m) => m != member && (m.heldItem ?? '').toLowerCase().trim() == trimmed.toLowerCase());
                          if (isDuplicate) {
                            _announce('Item Clause: $trimmed is already held by another Pokémon.');
                            return;
                          }
                        }
                        setState(() => member.heldItem = trimmed);
                        setDialogState(() {});
                        _announce('${member.name} is now holding ${trimmed.isEmpty ? "no item" : trimmed}');
                      }
                      if (gender != null) {
                        setState(() => member.gender = gender);
                        setDialogState(() {});
                        _announce('${member.name} gender set to $gender');
                      }
                      if (ability != null) {
                        setState(() => member.ability = ability);
                        setDialogState(() {});
                        _announce('${member.name} ability change to $ability');
                      }
                      if (nature != null) {
                        setState(() => member.nature = nature);
                        setDialogState(() {});
                        _announce('${member.name} nature set to $nature');
                      }
                      await _saveTeam();
                    },
                  ),
                  const SizedBox(height: 14),
                  const Divider(),
                  const SizedBox(height: 8),
                  const Text('Moves', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  const SizedBox(height: 8),
                  MoveEditorPanel(
                    key: const ValueKey('moves_panel'),
                    moves: member.moves,
                    availableMoves: _movesCache[member] ?? [],
                    onChanged: (moves) async {
                      setState(() => member.moves = moves);
                      setDialogState(() {});
                      await _saveTeam();
                      _announce('${member.name} moveset updated');
                    },
                  ),
                  const SizedBox(height: 14),
                  const Divider(),
                  EvEditorPanel(
                    key: const ValueKey('evs_panel'),
                    evs: member.evs,
                    onChanged: (evs) async {
                      setState(() => member.evs = evs);
                      setDialogState(() {});
                      await _saveTeam();
                    },
                  ),
                ],
              ),
            ),
            ),
          );
        },
      ),
    );

    // Flush after dialog closes (for EV change announcements)
    _flushPendingPanelUpdates(member);
    _unfocus();
    _unfocusAfterFrame();
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
    _unfocus();
    _unfocusAfterFrame();
  }
}