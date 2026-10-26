import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill/quill_delta.dart' show Delta, Operation;
import 'package:limpid_core/limpid_core.dart';

import 'adapters/delta_block_adapter.dart';
import 'editor_span_builder.dart';
import 'slash_menu.dart';

/// Binds the slash menu to the document of an editor.
///
/// The binding detects the slash typed at the beginning of a line, keeps
/// the query of the menu up to date and applies the command the author
/// picked.
class LimpidSlashMenuBinding {
  /// Creates the binding.
  LimpidSlashMenuBinding({required this.controller, required this.menu});

  /// The controller of the editor.
  final QuillController controller;

  /// The controller of the slash menu.
  final LimpidSlashMenuController menu;

  int? _anchor;

  /// The offset of the slash that opened the menu.
  int? get anchor => _anchor;

  /// Handles a change of the document.
  ///
  /// The menu opens when a slash is typed at the beginning of a line; it
  /// follows the text typed after it and closes when the caret goes back
  /// before the slash.
  void onDocumentChanged(Delta change) {
    final int? slashOffset = _insertedSlashOffset(change);
    final (int, int)? range = slashOffset == null
        ? null
        : editorLineRangeAt(controller.document, slashOffset);
    if (slashOffset != null && range != null && range.$1 == slashOffset) {
      _anchor = slashOffset;
      menu.open();
      return;
    }
    if (!menu.isOpen || _anchor == null) {
      return;
    }
    final int caret = controller.selection.extentOffset;
    final int start = _anchor! + 1;
    if (caret < start) {
      dismiss();
      return;
    }
    menu.updateQuery(_textBetween(start, caret));
  }

  /// Closes the menu and removes the slash from the document.
  void dismiss() {
    menu.close();
    final int? anchor = _anchor;
    _anchor = null;
    if (anchor == null) {
      return;
    }
    final int length = _textBetween(
      anchor,
      controller.selection.extentOffset,
    ).length;
    controller.replaceText(
      anchor,
      length + 1,
      '',
      TextSelection.collapsed(offset: anchor),
    );
  }

  /// Turns the current line into a block of the given [type].
  void applyBlockType(BlockType type) {
    final int offset = controller.selection.extentOffset;
    for (final Attribute attribute in editorAttributesFor(type)) {
      controller.formatText(offset, 0, attribute);
    }
  }

  int? _insertedSlashOffset(Delta change) {
    int offset = 0;
    for (final Operation op in change.toList()) {
      if (op.isRetain || op.isDelete) {
        offset += op.length ?? 0;
        continue;
      }
      final Object? data = op.data;
      if (data is! String) {
        return null;
      }
      final int index = data.indexOf('/');
      if (index < 0) {
        return null;
      }
      return offset + index;
    }
    return null;
  }

  String _textBetween(int start, int end) {
    if (end <= start) {
      return '';
    }
    return controller.document.getPlainText(start, end - start);
  }
}

/// Returns the Quill attributes that turn a line into a block of [type].
///
/// A paragraph removes the attributes of the other kinds of block.
List<Attribute> editorAttributesFor(BlockType type) => switch (type) {
  BlockType.paragraph => <Attribute>[
    Attribute.clone(Attribute.h1, null),
    Attribute.clone(Attribute.ul, null),
    Attribute.clone(Attribute.blockQuote, null),
    Attribute.clone(Attribute.codeBlock, null),
  ],
  BlockType.heading1 => <Attribute>[Attribute.h1],
  BlockType.heading2 => <Attribute>[Attribute.h2],
  BlockType.heading3 => <Attribute>[Attribute.h3],
  BlockType.listItem => <Attribute>[Attribute.ul],
  BlockType.quote => <Attribute>[Attribute.blockQuote],
  BlockType.code => <Attribute>[Attribute.codeBlock],
  BlockType.footnote => <Attribute>[
    Attribute(kFootnoteAttribute, AttributeScope.block, true),
  ],
  BlockType.sceneBreak => <Attribute>[
    Attribute(kSceneBreakAttribute, AttributeScope.block, true),
  ],
  BlockType.image => const <Attribute>[],
};
