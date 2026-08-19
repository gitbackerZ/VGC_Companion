import 'package:flutter/material.dart';

class IvEditorPanel extends StatelessWidget {
  final Map<String, int> ivs;
  final bool isLocked;
  final ValueChanged<Map<String, int>> onChanged;

  const IvEditorPanel({
    super.key,
    required this.ivs,
    this.isLocked = false,
    required this.onChanged,
  });

  static const _statsOrder = ['HP', 'Atk', 'Def', 'SpA', 'SpD', 'Spe'];

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
              const Text('Individual Values (IVs)', style: TextStyle(fontWeight: FontWeight.bold)),
              if (isLocked)
                const Text(
                  'Locked to 31 (Champions VGC)',
                  style: TextStyle(fontSize: 10, color: Colors.orangeAccent, fontWeight: FontWeight.bold),
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
              final currentIv = isLocked ? 31 : (ivs[stat] ?? 31);

              return Semantics(
                label: 'Individual Value for $stat, current value $currentIv${isLocked ? ", locked" : ""}',
                textField: true,
                excludeSemantics: true,
                child: TextFormField(
                  initialValue: currentIv.toString(),
                  enabled: !isLocked,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: stat,
                    floatingLabelBehavior: FloatingLabelBehavior.always,
                    isDense: true,
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (val) {
                    if (isLocked) return;
                    final parsed = int.tryParse(val) ?? 31;
                    final updated = Map<String, int>.from(ivs);
                    updated[stat] = parsed.clamp(0, 31);
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
