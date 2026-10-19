import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../domain/todo.dart';

class TodoRow extends StatefulWidget {
  const TodoRow({
    required this.todo,
    required this.isExpanded,
    required this.onToggleExpand,
    required this.onToggleArchive,
    required this.onEdit,
    required this.onDelete,
    this.enabled = true,
    super.key,
  });

  final Todo todo;
  final bool isExpanded;
  final VoidCallback onToggleExpand;
  final VoidCallback onToggleArchive;
  final void Function(String newText) onEdit;
  final VoidCallback onDelete;

  /// False while offline, when v1 refuses writes.
  final bool enabled;

  @override
  State<TodoRow> createState() => _TodoRowState();
}

class _TodoRowState extends State<TodoRow> {
  late final TextEditingController _editController;
  late final FocusNode _editFocus;
  bool _isEditing = false;

  @override
  void initState() {
    super.initState();
    _editController = TextEditingController(text: widget.todo.text);
    _editFocus = FocusNode();
  }

  @override
  void didUpdateWidget(TodoRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.todo.id != widget.todo.id) {
      _editController.text = widget.todo.text;
      _isEditing = false;
    }
  }

  @override
  void dispose() {
    _editController.dispose();
    _editFocus.dispose();
    super.dispose();
  }

  void _startEdit() {
    setState(() {
      _isEditing = true;
      _editController.text = widget.todo.text;
    });
  }

  void _cancelEdit() {
    setState(() {
      _isEditing = false;
      _editController.text = widget.todo.text;
    });
  }

  void _saveEdit() {
    final text = _editController.text.trim();
    if (text.isNotEmpty && text != widget.todo.text) {
      widget.onEdit(text);
    }
    setState(() => _isEditing = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final row = Card(
      color: widget.isExpanded
          ? theme.colorScheme.primaryContainer.withValues(alpha: 0.22)
          : null,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        hoverColor: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.6,
        ),
        onTap: widget.onToggleExpand,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Checkbox(
                    value: widget.todo.isArchived,
                    onChanged: widget.enabled
                        ? (_) => widget.onToggleArchive()
                        : null,
                  ),
                  Expanded(
                    child: _isEditing
                        ? _buildEditor(theme)
                        : Text(
                            widget.todo.text,
                            maxLines: widget.isExpanded ? null : 2,
                            overflow: widget.isExpanded
                                ? null
                                : TextOverflow.ellipsis,
                          ),
                  ),
                  AnimatedRotation(
                    turns: widget.isExpanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(Icons.expand_more),
                  ),
                ],
              ),
              if (widget.isExpanded && !_isEditing) _buildActions(theme),
            ],
          ),
        ),
      ),
    );

    return MouseRegion(cursor: SystemMouseCursors.click, child: row);
  }

  Widget _buildEditor(ThemeData theme) {
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): _cancelEdit},
      child: TextField(
        controller: _editController,
        focusNode: _editFocus,
        autofocus: true,
        maxLines: null,
        onSubmitted: (_) => _saveEdit(),
        decoration: InputDecoration(
          isDense: true,
          border: InputBorder.none,
          suffixIcon: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.check),
                onPressed: _saveEdit,
                tooltip: 'Save',
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: _cancelEdit,
                tooltip: 'Cancel',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActions(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 48),
      child: Row(
        children: [
          TextButton.icon(
            onPressed: widget.enabled ? _startEdit : null,
            icon: const Icon(Icons.edit, size: 16),
            label: const Text('Edit'),
          ),
          const SizedBox(width: 8),
          TextButton.icon(
            onPressed: widget.enabled ? widget.onDelete : null,
            icon: Icon(Icons.delete, size: 16, color: theme.colorScheme.error),
            label: Text(
              'Delete',
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ),
        ],
      ),
    );
  }
}
