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
    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: List.generate(4, (index) {
          final currentMove = (index < moves.length) ? moves[index] : null;

          // Ensure current selected move is in items pool if non-null
          final dropdownItems = <String>{
            if (currentMove != null && currentMove.isNotEmpty) currentMove,
            ...availableMoves,
          }.toList();

          return Padding(
            padding: const EdgeInsets.only(bottom: 8.0),
            child: Semantics(
              label: 'Move slot ${index + 1} selector',
              child: DropdownButtonFormField<String?>(
                isExpanded: true,
                value: (currentMove != null && dropdownItems.contains(currentMove)) ? currentMove : null,
                decoration: InputDecoration(
                  labelText: 'Move ${index + 1}',
                  isDense: true,
                  border: const OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('(None)', style: TextStyle(color: Colors.grey)),
                  ),
                  ...dropdownItems.map((m) => DropdownMenuItem<String?>(
                        value: m,
                        child: Text(m),
                      )),
                ],
                onChanged: (newMove) {
                  final updated = List<String?>.from(moves);
                  while (updated.length < 4) {
                    updated.add(null);
                  }
                  updated[index] = newMove;
                  onChanged(updated);
                },
              ),
            ),
          );
        }),
      ),
    );
  }
}
