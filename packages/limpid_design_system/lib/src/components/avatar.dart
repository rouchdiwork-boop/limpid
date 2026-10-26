import 'package:flutter/material.dart';
import 'package:limpid_design_system/src/theme/limpid_theme.dart';

/// The sizes of a [LimpidAvatar].
enum LimpidAvatarSize {
  /// A 24 pixel avatar.
  small,

  /// A 32 pixel avatar.
  medium,

  /// A 48 pixel avatar.
  large,
}

/// The avatar of the Limpid design system.
///
/// It displays an image when one is provided, and falls back on the
/// initials of the person otherwise.
class LimpidAvatar extends StatelessWidget {
  /// Creates an avatar.
  const LimpidAvatar({
    super.key,
    this.label,
    this.initials,
    this.image,
    this.size = LimpidAvatarSize.medium,
    this.backgroundColor,
    this.semanticLabel,
  });

  /// The full name of the person, used to compute the initials.
  final String? label;

  /// The initials displayed when no image is provided.
  final String? initials;

  /// The image of the person.
  final ImageProvider? image;

  /// The size of the avatar.
  final LimpidAvatarSize size;

  /// An optional background color.
  final Color? backgroundColor;

  /// The label announced by screen readers.
  final String? semanticLabel;

  double get _diameter => switch (size) {
    LimpidAvatarSize.small => 24,
    LimpidAvatarSize.medium => 32,
    LimpidAvatarSize.large => 48,
  };

  String get _resolvedInitials {
    final String? explicit = initials;
    if (explicit != null && explicit.isNotEmpty) {
      return explicit;
    }
    final List<String> parts = (label ?? '')
        .split(' ')
        .where((String part) => part.isNotEmpty)
        .toList(growable: false);
    if (parts.isEmpty) {
      return '';
    }
    if (parts.length == 1) {
      return _firstLetter(parts.first);
    }
    return _firstLetter(parts.first) + _firstLetter(parts.last);
  }

  static String _firstLetter(String value) {
    if (value.isEmpty) {
      return '';
    }
    return String.fromCharCode(value.runes.first).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final LimpidThemeScope tokens = context.limpid;
    final double diameter = _diameter;

    final Widget content = image != null
        ? ClipOval(
            child: Image(
              image: image!,
              width: diameter,
              height: diameter,
              fit: BoxFit.cover,
            ),
          )
        : Container(
            width: diameter,
            height: diameter,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: backgroundColor ?? tokens.colors.accentSubtle,
              shape: BoxShape.circle,
              border: Border.all(color: tokens.colors.accentBorder),
            ),
            child: Text(
              _resolvedInitials,
              style: TextStyle(
                fontSize: diameter * 0.4,
                fontWeight: FontWeight.w600,
                color: tokens.colors.accent,
              ),
            ),
          );

    return Semantics(
      label: semanticLabel ?? label,
      image: image != null,
      child: SizedBox.square(dimension: diameter, child: content),
    );
  }
}
