import 'package:flutter/material.dart';
import '../data/natures.dart';

class DetailsEditorPanel extends StatelessWidget {
  final String? heldItem;
  final String gender;
  final int genderRate;
  final String? ability;
  final List<Map<String, dynamic>>? abilities;
  final String nature;
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
    required this.onChanged,
  });

  List<String> _getGenderOptions() {
    if (genderRate == -1) return ['Genderless'];
    if (genderRate == 0) return ['Male'];
    if (genderRate == 8) return ['Female'];
    return ['Male', 'Female'];
  }

  /// De-duplicates ability entries by name, since some species data returns
  /// abilities as a Map (slot -> name) where multiple slots share the same
  /// ability name (e.g. hidden ability duplicating a normal slot). Duplicate
  /// values break DropdownButtonFormField, which requires each item's value
  /// to be unique - this is why the ability dropdown could load a default
  /// but not respond to selection.
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
        // 2x2 grid: Held Item / Gender on row one, Ability / Nature on row two.
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextFormField(
                initialValue: heldItem ?? '',
                decoration: const InputDecoration(
                  labelText: 'Held Item',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                onFieldSubmitted: (value) => onChanged(heldItem: value.trim()),
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