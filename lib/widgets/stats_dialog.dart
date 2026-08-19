import 'package:flutter/material.dart';
import '../models/team_member.dart';
import '../services/js_engine_service.dart';
import '../services/stat_calculator.dart';

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
