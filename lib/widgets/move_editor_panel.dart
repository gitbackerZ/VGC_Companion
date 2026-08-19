import 'package:flutter/material.dart';

class MoveEditorPanel extends StatelessWidget {
  final List<String?> moves;
  final List<String> availableMoves;
  final ValueChanged<List<String?>> onChanged;

  const MoveEditorPanel({
    super.key,
    required this.moves,
    required this.availableMoves,
    required this.onChanged,
  });

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

    return Semantics(
      label: 'Move slot ${slotIndex + 1}',
      child: DropdownButtonFormField<String>(
        value: availableMoves.contains(currentMove) ? currentMove : null,
        isDense: true,
        style: const TextStyle(fontSize: 10, color: Colors.white),
        dropdownColor: Colors.grey[900],
        decoration: InputDecoration(
          labelText: 'Move ${slotIndex + 1}',
          labelStyle: const TextStyle(color: Colors.white70, fontSize: 10),
          contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          border: const OutlineInputBorder(),
        ),
        items: [
          const DropdownMenuItem<String>(
            value: null,
            child: Text('(None)', style: TextStyle(fontSize: 10, color: Colors.white54)),
          ),
          ...availableMoves.map(
            (m) => DropdownMenuItem<String>(
              value: m,
              child: Text(m, style: const TextStyle(fontSize: 10, color: Colors.white)),
            ),
          ),
        ],
        onChanged: (selected) {
          final updated = List<String?>.from(moves);
          while (updated.length < 4) {
            updated.add(null);
          }
          updated[slotIndex] = selected;
          onChanged(updated);
        },
      ),
    );
  }
}
