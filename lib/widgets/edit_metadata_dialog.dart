// edit_metadata_dialog.dart
import 'package:flutter/material.dart';
import '../core/constants/app_colors.dart';
import '../core/constants/app_radius.dart';
import '../core/constants/app_typography.dart';
import '../models/track.dart';
import '../services/metadata_editor_service.dart';

/// Modal dialog for editing track metadata with SQLite synchronization and physical tag reporting.
class EditMetadataDialog extends StatefulWidget {
  final Track track;
  final Color accentColor;

  const EditMetadataDialog({
    super.key,
    required this.track,
    this.accentColor = AppColors.abyssAccent,
  });

  static Future<MetadataEditResult?> show(BuildContext context, Track track, {Color? accentColor}) {
    return showDialog<MetadataEditResult>(
      context: context,
      builder: (ctx) => EditMetadataDialog(
        track: track,
        accentColor: accentColor ?? Theme.of(context).colorScheme.primary,
      ),
    );
  }

  @override
  State<EditMetadataDialog> createState() => _EditMetadataDialogState();
}

class _EditMetadataDialogState extends State<EditMetadataDialog> {
  late final TextEditingController _titleController;
  late final TextEditingController _artistController;
  late final TextEditingController _albumController;
  late final TextEditingController _genreController;
  late final TextEditingController _yearController;
  late final TextEditingController _trackNumController;
  late final TextEditingController _albumArtistController;

  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.track.title);
    _artistController = TextEditingController(text: widget.track.artist);
    _albumController = TextEditingController(text: widget.track.album ?? '');
    _genreController = TextEditingController(text: widget.track.genre ?? '');
    _yearController = TextEditingController(text: widget.track.year?.toString() ?? '');
    _trackNumController = TextEditingController(text: widget.track.trackNumber?.toString() ?? '');
    _albumArtistController = TextEditingController(text: widget.track.albumArtist ?? '');
  }

  @override
  void dispose() {
    _titleController.dispose();
    _artistController.dispose();
    _albumController.dispose();
    _genreController.dispose();
    _yearController.dispose();
    _trackNumController.dispose();
    _albumArtistController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);

    final params = EditMetadataParams(
      title: _titleController.text,
      artist: _artistController.text,
      album: _albumController.text,
      genre: _genreController.text,
      year: int.tryParse(_yearController.text),
      trackNumber: int.tryParse(_trackNumController.text),
      albumArtist: _albumArtistController.text,
    );

    final result = await MetadataEditorService.instance.updateMetadata(
      track: widget.track,
      params: params,
    );

    if (mounted) {
      Navigator.of(context).pop(result);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.isPhysicalFileUpdated
                ? 'Metadata updated in database and physical file!'
                : 'Metadata updated in database. (${result.physicalStatusMessage})',
          ),
          backgroundColor: AppColors.voidOverlay,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryTextColor = isDark ? Colors.white : Colors.black87;
    final secondaryTextColor = isDark ? Colors.white54 : Colors.black54;
    final dialogBg = isDark ? const Color(0xFF0D1527) : Colors.white;
    final borderCol = isDark ? Colors.white.withValues(alpha: 0.12) : Colors.black.withValues(alpha: 0.1);

    return Dialog(
      backgroundColor: dialogBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: BorderSide(color: borderCol),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.edit_note_rounded, color: widget.accentColor, size: 24),
                  const SizedBox(width: 8),
                  Text(
                    'Edit Metadata',
                    style: TextStyle(
                      color: primaryTextColor,
                      fontSize: 18,
                      fontFamily: AppTypography.displayFont,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _buildField('Title', _titleController, isDark: isDark),
              _buildField('Artist', _artistController, isDark: isDark),
              _buildField('Album', _albumController, isDark: isDark),
              _buildField('Album Artist', _albumArtistController, isDark: isDark),
              _buildField('Genre', _genreController, isDark: isDark),
              Row(
                children: [
                  Expanded(child: _buildField('Year', _yearController, isNumber: true, isDark: isDark)),
                  const SizedBox(width: 12),
                  Expanded(child: _buildField('Track #', _trackNumController, isNumber: true, isDark: isDark)),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _isSaving ? null : () => Navigator.pop(context),
                    child: Text('Cancel', style: TextStyle(color: secondaryTextColor)),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: widget.accentColor,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: _isSaving ? null : _save,
                    child: _isSaving
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Save Changes', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildField(String label, TextEditingController controller, {bool isNumber = false, bool isDark = true}) {
    final inputColor = isDark ? Colors.white : Colors.black87;
    final labelColor = isDark ? Colors.white54 : Colors.black54;
    final borderColor = isDark ? Colors.white.withValues(alpha: 0.15) : Colors.black.withValues(alpha: 0.15);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        keyboardType: isNumber ? TextInputType.number : TextInputType.text,
        style: TextStyle(color: inputColor, fontSize: 13, fontFamily: AppTypography.bodyFont),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: labelColor, fontSize: 12),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: borderColor),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: widget.accentColor),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          isDense: true,
        ),
      ),
    );
  }
}
