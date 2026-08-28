import 'package:flutter/material.dart';

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
              childAspectRatio: 2.2,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
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
                  initialValue: currentEv.toString(),
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: stat,
                    floatingLabelBehavior: FloatingLabelBehavior.always,
                    isDense: true,
                    border: const OutlineInputBorder(),
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
