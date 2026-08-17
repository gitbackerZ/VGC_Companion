import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class EvEditorPanel extends StatefulWidget {
  final Map<String, int> evs;
  final ValueChanged<Map<String, int>> onChanged;

  const EvEditorPanel({
    super.key,
    required this.evs,
    required this.onChanged,
  });

  @override
  State<EvEditorPanel> createState() => _EvEditorPanelState();
}

class _EvEditorPanelState extends State<EvEditorPanel> {
  late final Map<String, TextEditingController> _controllers;
  late final Map<String, FocusNode> _nodes;

  @override
  void initState() {
    super.initState();
    _controllers = widget.evs.map(
      (stat, val) => MapEntry(stat, TextEditingController(text: val.toString())),
    );
    _nodes = widget.evs.map((stat, _) {
      final node = FocusNode();
      node.addListener(() {
        if (!node.hasFocus) _commitStat(stat);
      });
      return MapEntry(stat, node);
    });
  }

  void _commitStat(String stat) {
    final parsed = int.tryParse(_controllers[stat]!.text.trim()) ?? 0;
    final statClamped = parsed.clamp(0, 252);

    // Enforce the shared 510 EV budget across all stats, not just the
    // per-stat 0-252 cap - previously any stat could be set up to 252
    // regardless of what the other five stats already totaled, allowing
    // an illegal total well past 510.
    final otherTotal = widget.evs.entries
        .where((e) => e.key != stat)
        .fold(0, (sum, e) => sum + e.value);
    final maxAllowed = (510 - otherTotal).clamp(0, 252);
    final finalValue = statClamped > maxAllowed ? maxAllowed : statClamped;

    final updated = Map<String, int>.from(widget.evs);
    updated[stat] = finalValue;

    widget.onChanged(updated);
    _controllers[stat]!.text = finalValue.toString();
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    for (final n in _nodes.values) {
      n.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.evs.values.fold(0, (a, b) => a + b);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Effort Values (EVs)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            Text(
              '$total/510 total',
              style: TextStyle(
                fontSize: 13,
                color: total > 510 ? Colors.red : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        GridView.count(
          crossAxisCount: 2,
          childAspectRatio: 3.2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 6,
          crossAxisSpacing: 8,
          children: widget.evs.keys.map((stat) {
            return TextField(
              controller: _controllers[stat],
              focusNode: _nodes[stat],
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: '$stat EVs (0-252)',
                isDense: true,
                border: const OutlineInputBorder(),
              ),
              onEditingComplete: () {
                _commitStat(stat);
                _nodes[stat]?.unfocus();
              },
            );
          }).toList(),
        ),
      ],
    );
  }
}