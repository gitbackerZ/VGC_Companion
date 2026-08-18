import 'package:flutter/material.dart';
import '../models/team_member.dart';
import '../services/js_engine_service.dart';
import '../services/stat_calculator.dart';

class StatsDialog extends StatelessWidget {
  final TeamMember member;
  final Map<String, int> normalStats;
  final Map<String, int>? megaStats;
  final String? megaFormName;
  final String? megaAbility;
  final List<String> megaTypes;
  final String boosted;
  final String lowered;

  const StatsDialog({
    super.key,
    required this.member,
    required this.normalStats,
    this.megaStats,
    this.megaFormName,
    this.megaAbility,
    this.megaTypes = const [],
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

    Map<String, int>? megaStats;
    String? megaFormName;
    String? megaAbility;
    List<String> megaTypes = [];

    final activeMega = await _resolveActiveMega(member, service);
    if (activeMega != null) {
      megaFormName = activeMega.key;
      final megaData = await service.getPokemon(megaFormName);
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
        final abilities = await service.getAbilitiesForPokemon(megaFormName);
        if (abilities.isNotEmpty) {
          megaAbility = abilities.first['name'] as String;
        }
      } catch (_) {}
    }

    if (!context.mounted) return;

    await showDialog(
      context: context,
      builder: (context) => StatsDialog(
        member: member,
        normalStats: normalStats,
        megaStats: megaStats,
        megaFormName: megaFormName,
        megaAbility: megaAbility,
        megaTypes: megaTypes,
        boosted: boosted,
        lowered: lowered,
      ),
    );
  }

  static bool _isValidMegaItem(String heldItem, String formKey) {
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

  static Future<MapEntry<String, Map<String, int>>?> _resolveActiveMega(
    TeamMember member,
    JsEngineService service,
  ) async {
    final heldItem = (member.heldItem ?? '').toLowerCase().trim();
    if (heldItem.isEmpty) return null;

    final allMegaStats = await service.getAllMegaBaseStats(member.name);
    if (allMegaStats.isEmpty) return null;

    for (final entry in allMegaStats.entries) {
      if (_isValidMegaItem(heldItem, entry.key)) {
        return MapEntry(entry.key, entry.value);
      }
    }
    return null;
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
      return Semantics(
        label: '${e.key}: ${e.value}${isBoosted ? ", boosted" : ""}${isLowered ? ", lowered" : ""}',
        child: Text('${e.key}: ${e.value}$suffix'),
      );
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return AlertDialog(
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
            ..._buildStatRows(normalStats),
            if (megaStats != null) ...[
              const SizedBox(height: 16),
              Text('Mega Evolution: $megaFormName', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              Text('Mega Types: ${megaTypes.join("/")}', style: const TextStyle(fontSize: 13)),
              if (megaAbility != null) Text('Ability: $megaAbility', style: const TextStyle(fontStyle: FontStyle.italic)),
              const SizedBox(height: 4),
              ..._buildStatRows(megaStats!),
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
