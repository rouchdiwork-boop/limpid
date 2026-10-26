import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:limpid_app/l10n/generated/app_localizations.dart';
import 'package:limpid_app/src/domain/providers.dart';
import 'package:limpid_app/src/features/onboarding/onboarding_screen.dart';
import 'package:limpid_app/src/features/onboarding/onboarding_widgets.dart';
import 'package:limpid_app/src/features/settings/settings_providers.dart';
import 'package:limpid_design_system/limpid_design_system.dart';

import 'fakes.dart';

void main() {
  /// Gives the test a viewport large enough for the desktop layout.
  void useSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(1440, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  /// Builds the wizard inside a router, so that the navigation works.
  Widget harness(Widget child) {
    final GoRouter router = GoRouter(
      initialLocation: '/onboarding',
      routes: <RouteBase>[
        GoRoute(
          path: '/onboarding',
          builder: (BuildContext context, GoRouterState state) => child,
        ),
        GoRoute(
          path: '/bureau',
          builder: (BuildContext context, GoRouterState state) =>
              const Scaffold(body: Text('Bureau')),
        ),
      ],
    );
    addTearDown(router.dispose);

    return MaterialApp.router(
      theme: LimpidTheme.of(LimpidThemeVariant.paper),
      routerConfig: router,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
    );
  }

  AppLocalizations stringsOf(WidgetTester tester) =>
      AppLocalizations.of(tester.element(find.byType(OnboardingScreen)));

  testWidgets(
    'the wizard creates the project with the chosen title and model',
    (tester) async {
      useSurface(tester);
      final FakeManuscriptRepository repository = FakeManuscriptRepository();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            manuscriptRepositoryProvider.overrideWithValue(repository),
          ],
          child: harness(const OnboardingScreen()),
        ),
      );
      await tester.pumpAndSettle();
      final AppLocalizations strings = stringsOf(tester);

      await tester.tap(find.text(strings.onboardingTemplateEssay));
      await tester.pumpAndSettle();

      await tester.tap(
        find.widgetWithText(LimpidButton, strings.onboardingNext),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Le livre des matins');
      await tester.pumpAndSettle();

      await tester.tap(
        find.widgetWithText(LimpidButton, strings.onboardingNext),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text(strings.onboardingGoalIntense));
      await tester.pumpAndSettle();

      await tester.tap(
        find.widgetWithText(LimpidButton, strings.onboardingNext),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.widgetWithText(LimpidButton, strings.onboardingCreateProject),
      );
      await tester.pumpAndSettle();

      expect(repository.createdProjects, hasLength(1));
      expect(repository.createdProjects.single.title, 'Le livre des matins');
      expect(
        repository.createdProjects.single.synopsis,
        contains(strings.onboardingTemplateEssay),
      );
    },
  );

  testWidgets('the wizard stores the rhythm the author chose', (tester) async {
    useSurface(tester);
    final FakeManuscriptRepository repository = FakeManuscriptRepository();

    // The container is owned by the test : the wizard leaves the screen when
    // it creates the project, and the goal is read after that.
    final ProviderContainer container = ProviderContainer(
      overrides: [manuscriptRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: harness(const OnboardingScreen()),
      ),
    );
    await tester.pumpAndSettle();
    final AppLocalizations strings = stringsOf(tester);

    await tester.tap(find.widgetWithText(LimpidButton, strings.onboardingNext));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Le livre des matins');
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(LimpidButton, strings.onboardingNext));
    await tester.pumpAndSettle();

    await tester.tap(find.text(strings.onboardingGoalLight));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(LimpidButton, strings.onboardingNext));
    await tester.pumpAndSettle();

    await tester.tap(
      find.widgetWithText(LimpidButton, strings.onboardingCreateProject),
    );
    await tester.pumpAndSettle();

    expect(container.read(dailyWordGoalProvider), lightDailyWordGoal);
  });

  testWidgets('the wizard is navigable with the keyboard', (tester) async {
    useSurface(tester);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          manuscriptRepositoryProvider.overrideWithValue(
            FakeManuscriptRepository(),
          ),
        ],
        child: harness(const OnboardingScreen()),
      ),
    );
    await tester.pumpAndSettle();
    final AppLocalizations strings = stringsOf(tester);

    // The first focus of the wizard is a model of book.
    for (
      var attempt = 0;
      attempt < 10 && _focusedTemplateTitle() == null;
      attempt++
    ) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    }
    expect(_focusedTemplateTitle(), strings.onboardingTemplateNovel);

    // The second model is reachable with the tab key.
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    expect(_focusedTemplateTitle(), strings.onboardingTemplateShort);

    // The focused model is chosen with the keyboard.
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    final OnboardingTemplateCard chosen = tester.widget<OnboardingTemplateCard>(
      find.byType(OnboardingTemplateCard).at(1),
    );
    expect(chosen.isSelected, isTrue);

    // The "next" button is reachable with the tab key, and it moves on.
    for (
      var attempt = 0;
      attempt < 20 && _focusedButtonLabel() != strings.onboardingNext;
      attempt++
    ) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    }
    expect(_focusedButtonLabel(), strings.onboardingNext);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(find.text(strings.onboardingProjectTitle), findsWidgets);
  });
}

/// The title of the model card that has the focus, `null` when the focus is
/// elsewhere.
String? _focusedTemplateTitle() {
  final BuildContext? context = FocusManager.instance.primaryFocus?.context;
  if (context == null) {
    return null;
  }
  String? title;
  context.visitAncestorElements((Element ancestor) {
    if (ancestor.widget is OnboardingTemplateCard) {
      title = (ancestor.widget as OnboardingTemplateCard).title;
      return false;
    }
    return true;
  });
  return title;
}

/// The label of the button that has the focus, `null` when the focus is
/// elsewhere.
String? _focusedButtonLabel() {
  final BuildContext? context = FocusManager.instance.primaryFocus?.context;
  if (context == null) {
    return null;
  }
  String? label;
  context.visitAncestorElements((Element ancestor) {
    if (ancestor.widget is LimpidButton) {
      label = (ancestor.widget as LimpidButton).label;
      return false;
    }
    return true;
  });
  return label;
}
