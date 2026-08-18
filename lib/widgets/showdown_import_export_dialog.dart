import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/showdown_export_service.dart';

class ShowdownImportExportDialog extends StatefulWidget {
  final List<PokemonTeamMember> currentTeam;

  const ShowdownImportExportDialog({
    super.key,
    required this.currentTeam,
  });

  static Future<List<PokemonTeamMember>?> show(
    BuildContext context,
    List<PokemonTeamMember> currentTeam,
  ) {
    return showDialog<List<PokemonTeamMember>>(
      context: context,
      builder: (context) => ShowdownImportExportDialog(currentTeam: currentTeam),
    );
  }

  @override
  State<ShowdownImportExportDialog> createState() =>
      _ShowdownImportExportDialogState();
}

class _ShowdownImportExportDialogState
    extends State<ShowdownImportExportDialog> with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  late final TextEditingController _exportController;
  late final TextEditingController _importController;
  
  String? _errorMessage;
  bool _copied = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    
    // Generate Showdown export text from current team
    final exportText = ShowdownExportService.exportTeam(widget.currentTeam);
    _exportController = TextEditingController(text: exportText);
    _importController = TextEditingController();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _exportController.dispose();
    _importController.dispose();
    super.dispose();
  }

  Future<void> _copyToClipboard() async {
    if (_exportController.text.trim().isEmpty) return;
    
    await Clipboard.setData(ClipboardData(text: _exportController.text));
    setState(() => _copied = true);
    
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null) {
      setState(() {
        _importController.text = data!.text!;
        _errorMessage = null;
      });
    }
  }

  void _handleImport() {
    final rawText = _importController.text.trim();
    if (rawText.isEmpty) {
      setState(() => _errorMessage = 'Please enter or paste a team format string.');
      return;
    }

    try {
      final team = ShowdownExportService.importTeam(rawText);
      if (team.isEmpty) {
        setState(() => _errorMessage = 'No valid Pokémon sets were found in the text.');
        return;
      }

      // Return imported team to calling screen
      Navigator.of(context).pop(team);
    } catch (e) {
      setState(() => _errorMessage = 'Failed to parse team: ${e.toString()}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      titlePadding: EdgeInsets.zero,
      title: Column(
        children: [
          TabBar(
            controller: _tabController,
            labelColor: theme.colorScheme.primary,
            unselectedLabelColor: theme.colorScheme.onSurfaceVariant,
            tabs: const [
              Tab(icon: Icon(Icons.upload_rounded), text: 'Export Team'),
              Tab(icon: Icon(Icons.download_rounded), text: 'Import Team'),
            ],
          ),
        ],
      ),
      content: SizedBox(
        width: 500,
        height: 380,
        child: TabBarView(
          controller: _tabController,
          children: [
            // TAB 1: EXPORT
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 12),
                Expanded(
                  child: TextField(
                    controller: _exportController,
                    readOnly: true,
                    maxLines: null,
                    expands: true,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: 'Team is currently empty.',
                      contentPadding: EdgeInsets.all(12),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: widget.currentTeam.isEmpty ? null : _copyToClipboard,
                  icon: Icon(_copied ? Icons.check_rounded : Icons.copy_rounded),
                  label: Text(_copied ? 'Copied to Clipboard!' : 'Copy to Clipboard'),
                ),
              ],
            ),

            // TAB 2: IMPORT
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 12),
                Expanded(
                  child: TextField(
                    controller: _importController,
                    maxLines: null,
                    expands: true,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                    onChanged: (_) {
                      if (_errorMessage != null) {
                        setState(() => _errorMessage = null);
                      }
                    },
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      hintText: 'Paste Showdown team export format here...\n\nExample:\nDragapult @ Choice Specs\nAbility: Infiltrator\nEVs: 252 SpA / 4 SpD / 252 Spe\nTimid Nature\n- Shadow Ball\n- Draco Meteor',
                      contentPadding: const EdgeInsets.all(12),
                      errorText: _errorMessage,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _pasteFromClipboard,
                        icon: const Icon(Icons.paste_rounded),
                        label: const Text('Paste'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _handleImport,
                        icon: const Icon(Icons.file_download_done_rounded),
                        label: const Text('Import'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
