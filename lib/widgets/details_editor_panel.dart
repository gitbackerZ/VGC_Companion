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

  @override
  Widget build(BuildContext context) {
    final genderOptions = _getGenderOptions();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Customize Details',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
        const SizedBox(height: 8),
        TextFormField(
          initialValue: heldItem ?? '',
          decoration: const InputDecoration(
            labelText: 'Held Item',
            isDense: true,
            border: OutlineInputBorder(),
          ),
          onFieldSubmitted: (value) => onChanged(heldItem: value.trim()),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
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
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: ability,
          decoration: const InputDecoration(
            labelText: 'Ability',
            isDense: true,
            border: OutlineInputBorder(),
          ),
          items: abilities?.map((a) {
                final name = a['name'] as String;
                return DropdownMenuItem(value: name, child: Text(name));
              }).toList() ??
              [],
          onChanged: (val) {
            if (val != null) onChanged(ability: val);
          },
        ),
      ],
    );
  }
}
