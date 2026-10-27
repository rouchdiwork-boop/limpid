import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:limpid_app/l10n/generated/app_localizations.dart';
import 'package:limpid_app/src/app/router.dart';
import 'package:limpid_app/src/domain/ai_consent_repository.dart';
import 'package:limpid_app/src/features/settings/settings_privacy_section.dart';
import 'package:limpid_design_system/limpid_design_system.dart';

/// Un dépôt qui répond ce que le test lui demande.
final class _FakeConsentRepository implements AiConsentRepository {
  _FakeConsentRepository(this.current);

  /// L'etat lu par l'ecran.
  AiConsentState current;

  /// Les décisions prises, dans l'ordre.
  final List<bool> decisions = <bool>[];

  @override
  Future<AiConsentState> state() async => current;

  @override
  Future<AiConsentState> grant() async {
    decisions.add(true);
    current = AiConsentState(
      scope: current.scope,
      provider: current.provider,
      isGranted: true,
      requiresConsent: current.requiresConsent,
      grantedAt: DateTime(2026, 10, 26),
    );
    return current;
  }

  @override
  Future<AiConsentState> revoke() async {
    decisions.add(false);
    current = AiConsentState(
      scope: current.scope,
      provider: current.provider,
      isGranted: false,
      requiresConsent: current.requiresConsent,
      revokedAt: DateTime(2026, 10, 26),
    );
    return current;
  }
}

void main() {
  /// Donne au test une page assez haute pour voir toute la section.
  void useSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(1440, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  /// La section de la confidentialite, dans le theme du papier.
  Widget harness(_FakeConsentRepository repository) {
    final GoRouter router = GoRouter(
      initialLocation: AppRoutes.settings,
      routes: <RouteBase>[
        GoRoute(
          path: AppRoutes.settings,
          builder: (BuildContext context, GoRouterState state) =>
              const Scaffold(body: SettingsPrivacySection()),
        ),
      ],
    );
    addTearDown(router.dispose);

    return ProviderScope(
      overrides: [aiConsentRepositoryProvider.overrideWithValue(repository)],
      child: MaterialApp.router(
        theme: LimpidTheme.of(LimpidThemeVariant.paper),
        routerConfig: router,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('fr'),
      ),
    );
  }

  testWidgets('la section montre que l accord n est pas donne', (tester) async {
    useSurface(tester);
    final _FakeConsentRepository repository = _FakeConsentRepository(
      const AiConsentState(
        scope: 'text_to_third_party',
        provider: 'anthropic',
        isGranted: false,
        requiresConsent: true,
      ),
    );

    await tester.pumpWidget(harness(repository));
    await tester.pumpAndSettle();

    final AppLocalizations strings = AppLocalizations.of(
      tester.element(find.byType(SettingsPrivacySection)),
    );
    expect(find.text(strings.settingsAiConsentTitle), findsOneWidget);
    expect(find.text(strings.settingsAiConsentDisabled), findsOneWidget);
    // L'ecran dit ou part le texte : l'accord n'est pas une case sans
    // explication.
    expect(find.text(strings.settingsAiConsentSubtitle), findsOneWidget);
  });

  testWidgets('l interrupteur donne et retire l accord', (tester) async {
    useSurface(tester);
    final _FakeConsentRepository repository = _FakeConsentRepository(
      const AiConsentState(
        scope: 'text_to_third_party',
        provider: 'anthropic',
        isGranted: false,
        requiresConsent: true,
      ),
    );

    await tester.pumpWidget(harness(repository));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(LimpidSwitch));
    await tester.pumpAndSettle();
    expect(repository.decisions, <bool>[true]);

    final AppLocalizations strings = AppLocalizations.of(
      tester.element(find.byType(SettingsPrivacySection)),
    );
    expect(find.text(strings.settingsAiConsentEnabled), findsOneWidget);

    await tester.tap(find.byType(LimpidSwitch));
    await tester.pumpAndSettle();
    expect(repository.decisions, <bool>[true, false]);
  });

  testWidgets('un fournisseur local ne demande aucun accord', (tester) async {
    useSurface(tester);
    final _FakeConsentRepository repository = _FakeConsentRepository(
      const AiConsentState(
        scope: 'text_to_third_party',
        provider: 'ollama',
        isGranted: false,
        requiresConsent: false,
      ),
    );

    await tester.pumpWidget(harness(repository));
    await tester.pumpAndSettle();

    final AppLocalizations strings = AppLocalizations.of(
      tester.element(find.byType(SettingsPrivacySection)),
    );
    expect(find.text(strings.settingsAiConsentLocal), findsOneWidget);
    expect(find.byType(LimpidSwitch), findsNothing);
  });
}
