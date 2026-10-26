import 'package:flutter/material.dart';
import 'package:limpid_app/l10n/generated/app_localizations.dart';
import 'package:limpid_design_system/limpid_design_system.dart';

/// The banner telling the author the device is offline.
///
/// The operations are written on the device and wait in the durable queue:
/// the manuscript never stops being editable.
class WritingOfflineBanner extends StatelessWidget {
  /// Creates the offline banner.
  const WritingOfflineBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final AppLocalizations strings = AppLocalizations.of(context);
    final LimpidThemeScope scope = context.limpid;

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: scope.spacing.space16,
        vertical: scope.spacing.space8,
      ),
      child: LimpidBanner(
        variant: LimpidStatusVariant.warning,
        title: strings.editorOffline,
      ),
    );
  }
}
