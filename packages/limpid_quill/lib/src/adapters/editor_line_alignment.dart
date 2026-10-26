import 'dart:math' show min;

import 'package:flutter/foundation.dart';
import 'package:flutter_quill/quill_delta.dart' show Delta, Operation;

import 'delta_block_adapter.dart';
import 'scene_block.dart';

/// A line of the before-document, with its position in the flat document.
@immutable
class LimpidFlatLine {
  /// Creates the flat description of a line.
  const LimpidFlatLine({required this.start, required this.length});

  /// The offset of the first character of the line.
  final int start;

  /// The number of characters of the line, newline included.
  final int length;
}

/// Flattens a document into its lines, with their offsets.
List<LimpidFlatLine> flattenEditorLines(Delta document) {
  final List<LimpidEditorLine> lines = splitEditorLines(document);
  final bool endsWithNewline = _endsWithNewline(document);
  final List<LimpidFlatLine> flat = <LimpidFlatLine>[];
  int offset = 0;
  for (int i = 0; i < lines.length; i++) {
    final bool hasNewline = i < lines.length - 1 || endsWithNewline;
    final int length =
        deltaCharacterLength(lines[i].content) + (hasNewline ? 1 : 0);
    flat.add(LimpidFlatLine(start: offset, length: length));
    offset += length;
  }
  return flat;
}

bool _endsWithNewline(Delta document) {
  final List<Operation> ops = document.toList();
  if (ops.isEmpty) {
    return false;
  }
  final Object? data = ops.last.data;
  return data is String && data.endsWith('\n');
}

/// Aligns the lines of the after-document with the lines of the
/// before-document.
///
/// The returned list holds one entry per after-line: the index of the
/// before-line it comes from, or [kNewLineOrigin] when the change created
/// it.
///
/// A change does not always cover the whole document — `flutter_quill`
/// emits the operations of the edited region only — so the lines the walk
/// never reached keep their origin.
List<int> alignEditorLines(
  List<LimpidFlatLine> lines,
  Delta change,
  int afterLineCount,
) {
  final List<int> origins = <int>[];
  int lineIndex = 0;
  int currentOrigin = 0;
  int offset = 0;

  for (final Operation op in change.toList()) {
    if (op.isRetain) {
      int remaining = op.length ?? 0;
      while (remaining > 0 && lineIndex < lines.length) {
        final LimpidFlatLine line = lines[lineIndex];
        final int available = line.start + line.length - offset;
        final int taken = min(remaining, available);
        offset += taken;
        remaining -= taken;
        if (offset >= line.start + line.length) {
          origins.add(currentOrigin);
          lineIndex++;
          currentOrigin = lineIndex;
        }
      }
      continue;
    }
    if (op.isInsert) {
      final Object? data = op.data;
      if (data is! String) {
        continue;
      }
      final List<String> segments = data.split('\n');
      for (int i = 1; i < segments.length; i++) {
        origins.add(currentOrigin);
        currentOrigin = kNewLineOrigin;
      }
      continue;
    }
    if (op.isDelete) {
      int remaining = op.length ?? 0;
      while (remaining > 0 && lineIndex < lines.length) {
        final LimpidFlatLine line = lines[lineIndex];
        final int available = line.start + line.length - offset;
        final int taken = min(remaining, available);
        offset += taken;
        remaining -= taken;
        if (offset >= line.start + line.length) {
          lineIndex++;
        }
      }
    }
  }

  if (origins.length < afterLineCount) {
    origins.add(currentOrigin);
    for (int k = lineIndex + 1; origins.length < afterLineCount; k++) {
      origins.add(k);
    }
  }
  if (origins.length > afterLineCount) {
    origins.removeRange(afterLineCount, origins.length);
  }
  return origins;
}
