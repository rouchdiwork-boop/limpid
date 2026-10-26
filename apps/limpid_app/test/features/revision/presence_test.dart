import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:limpid_app/l10n/generated/app_localizations.dart';
import 'package:limpid_app/src/features/revision/presence_bar.dart';
import 'package:limpid_app/src/features/revision/presence_models.dart';
import 'package:limpid_design_system/limpid_design_system.dart';

/// Wraps the bar in the theme and the strings of the application.
Widget harness(List<PresencePeerView> peers) {
  return MaterialApp(
    theme: LimpidTheme.of(LimpidThemeVariant.paper),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: PresenceBar(peers: peers)),
  );
}

void main() {
  testWidgets('the bar shows the avatar of every peer', (tester) async {
    await tester.pumpWidget(
      harness(<PresencePeerView>[
        const PresencePeerView(
          userId: 'auteur-2',
          displayName: 'Ines Barreau',
          paragraph: 3,
        ),
      ]),
    );
    await tester.pumpAndSettle();

    expect(find.byType(LimpidAvatar), findsOneWidget);
    expect(find.text('IB'), findsOneWidget);
    // La position du curseur distant est affichée avec le paragraphe.
    expect(find.text('¶ 3'), findsOneWidget);
  });

  testWidgets('the bar shows nothing when the author writes alone', (
    tester,
  ) async {
    await tester.pumpWidget(harness(const <PresencePeerView>[]));
    await tester.pumpAndSettle();

    expect(find.byType(LimpidAvatar), findsNothing);
    expect(find.byType(LimpidBadge), findsNothing);
  });

  testWidgets('the bar names the peers it shows', (tester) async {
    await tester.pumpWidget(
      harness(<PresencePeerView>[
        const PresencePeerView(userId: 'auteur-2', displayName: 'Ines Barreau'),
        const PresencePeerView(
          userId: 'auteur-3',
          displayName: 'Thomas Derval',
          paragraph: 7,
        ),
      ]),
    );
    await tester.pumpAndSettle();

    expect(find.byType(LimpidAvatar), findsNWidgets(2));
    expect(find.text('IB'), findsOneWidget);
    expect(find.text('TD'), findsOneWidget);
    expect(find.text('¶ 7'), findsOneWidget);
  });
}
