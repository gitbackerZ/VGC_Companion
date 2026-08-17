import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class IvLevelEditorPanel extends StatefulWidget {
  final int level;
  final Map<String, int> ivs;
  final ValueChanged<int> onLevelChanged;
  final ValueChanged<Map<String, int>> onIvsChanged;

  const IvLevelEditorPanel({
    super.key,
    required this.level,
    required this.ivs,
    required this.onLevelChanged,
    required this.onIvsChanged,
  });

  @override
  State<IvLevelEditorPanel> createState() => _IvLevelEditorPanelState();
}

class _IvLevelEditorPanelState extends State<IvLevelEditorPanel> {
  late final TextEditingController _levelController;
  late final Map<String, TextEditingController> _ivControllers;
  late final Map<String, FocusNode> _ivNodes;
  late final FocusNode _levelNode;

  @override
  void initState() {
    super.initState();
    _levelController = TextEditingController(text: widget.level.toString());
    _levelNode = FocusNode()..addListener(() {
      if (!_levelNode.hasFocus) _commitLevel();
    });
    _ivControllers = widget.ivs.map(
      (stat, val) => MapEntry(stat, TextEditingController(text: val.toString())),
    );
    _ivNodes = widget.ivs.map((stat, _) {
      final node = FocusNode();
      node.addListener(() {
        if (!node.hasFocus) _commitIv(stat);
      });
      return MapEntry(stat, node);
    });
  }

  void _commitLevel() {
    final parsed = int.tryParse(_levelController.text.trim()) ?? 50;
    final clamped = parsed.clamp(1, 100);
    _levelController.text = clamped.toString();
    widget.onLevelChanged(clamped);
  }

  void _commitIv(String stat) {
    final parsed = int.tryParse(_ivControllers[stat]!.text.trim()) ?? 0;
    final clamped = parsed.clamp(0, 31);
    _ivControllers[stat]!.text = clamped.toString();

    final updated = Map<String, int>.from(widget.ivs);
    updated[stat] = clamped;
    widget.onIvsChanged(updated);
  }

  void _applyVgcDefaults() {
    setState(() {
      _levelController.text = '50';
      for (final stat in _ivControllers.keys) {
        _ivControllers[stat]!.text = '31';
      }
    });
    widget.onLevelChanged(50);
    widget.onIvsChanged({for (final stat in widget.ivs.keys) stat: 31});
  }

  @override
  void dispose() {
    _levelController.dispose();
    _levelNode.dispose();
    for (final c in _ivControllers.values) {
      c.dispose();
    }
    for (final n in _ivNodes.values) {
      n.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Level & IVs', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            TextButton(
              onPressed: _applyVgcDefaults,
              child: const Text('VGC Defaults (Lv.50, 31 IV)', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: 120,
          child: TextField(
            controller: _levelController,
            focusNode: _levelNode,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: 'Level (1-100)',
              isDense: true,
              border: OutlineInputBorder(),
            ),
            onEditingComplete: () {
              _commitLevel();
              _levelNode.unfocus();
            },
          ),
        ),
        const SizedBox(height: 12),
        GridView.count(
          crossAxisCount: 2,
          childAspectRatio: 3.2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 6,
          crossAxisSpacing: 8,
          children: widget.ivs.keys.map((stat) {
            return TextField(
              controller: _ivControllers[stat],
              focusNode: _ivNodes[stat],
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: '$stat IV (0-31)',
                isDense: true,
                border: const OutlineInputBorder(),
              ),
              onEditingComplete: () {
                _commitIv(stat);
                _ivNodes[stat]?.unfocus();
              },
            );
          }).toList(),
        ),
      ],
    );
  }
}