import 'package:flutter/material.dart';
import '../data/natures.dart';

class DetailsEditorPanel extends StatelessWidget {
  final String? heldItem;
  final String gender;
  final int genderRate;
  final String? ability;
  final List<Map<String, dynamic>>? abilities;
  final String nature;
  final List<String> itemList;
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
    required this.itemList,
    required this.onChanged,
  });

  List<String> _getGenderOptions() {
    if (genderRate == -1) return ['Genderless'];
    if (genderRate == 0) return ['Male'];
    if (genderRate == 8) return ['Female'];
    return ['Male', 'Female'];
  }

  List<String> _getUniqueAbilityNames() {
    final seen = <String>{};
    final result = <String>[];
    for (final a in abilities ?? const []) {
      final name = a['name'] as String?;
      if (name != null && name.isNotEmpty && seen.add(name)) {
        result.add(name);
      }
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final genderOptions = _getGenderOptions();
    final abilityOptions = _getUniqueAbilityNames();
    final safeAbilityValue = abilityOptions.contains(ability) ? ability : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Customize Details',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Held Item with Autocomplete
            Expanded(
              child: Autocomplete<String>(
                initialValue: TextEditingValue(text: heldItem ?? ''),
                optionsBuilder: (TextEditingValue value) {
                  if (value.text.isEmpty) return const Iterable<String>.empty();
                  final query = value.text.toLowerCase();
                  return itemList
                      .where((item) => item.toLowerCase().contains(query))
                      .take(8);
                },
                onSelected: (selected) => onChanged(heldItem: selected),
                fieldViewBuilder: (context, controller, focusNode, onEditingComplete) {
                  return TextField(
                    controller: controller,
                    focusNode: focusNode,
                    onEditingComplete: onEditingComplete,
                    decoration: InputDecoration(
                      labelText: 'Held Item',
                      isDense: true,
                      border: const OutlineInputBorder(),
                      suffixIcon: controller.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () {
                                controller.clear();
                                onChanged(heldItem: '');
                              },
                            )
                          : null,
                    ),
                    onChanged: (val) {
                      if (val.trim().isEmpty) onChanged(heldItem: '');
                    },
                  );
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: DropdownButtonFormField<String>(
                value: genderOptions.contains(gender) ? gender : genderOptions.first,
                decoration: const InputDecoration(
                  labelText: 'Gender',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                items: genderOptions
                    .map((g) => DropdownMenuItem(value: g, child: Text(g)))
                    .toList(),
                onChanged: (val) {
                  if (val != null) onChanged(gender: val);
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                value: safeAbilityValue,
                decoration: const InputDecoration(
                  labelText: 'Ability',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                items: abilityOptions
                    .map((name) => DropdownMenuItem(value: name, child: Text(name)))
                    .toList(),
                onChanged: (val) {
                  if (val != null) onChanged(ability: val);
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: DropdownButtonFormField<String>(
                value: nature,
                decoration: const InputDecoration(
                  labelText: 'Nature',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                items: allNatures
                    .map((n) => DropdownMenuItem(value: n.name, child: Text(n.name)))
                    .toList(),
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
