import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:limpid_app/l10n/generated/app_localizations.dart';
import 'package:limpid_app/src/auth/auth_repository.dart';
import 'package:limpid_app/src/auth/supabase_auth_repository.dart';
import 'package:limpid_app/src/features/auth/widgets/auth_form.dart';
import 'package:limpid_design_system/limpid_design_system.dart';

/// A repository whose every call fails with the same error.
final class _FailingRepository implements AuthRepository {
  _FailingRepository(this.error);

  final AuthException error;

  @override
  Stream<AuthSession?> watchSession() => const Stream<AuthSession?>.empty();

  @override
  Future<void> sendMagicLink(String email, {String? authorName}) async {
    throw error;
  }

  @override
  Future<void> signInWithPassword(String email, String password) async {
    throw error;
  }

  @override
  Future<void> signOut() async {}
}

void main() {
  Widget harness(AuthRepository repository) {
    return ProviderScope(
      overrides: [authRepositoryProvider.overrideWithValue(repository)],
      child: MaterialApp(
        theme: LimpidTheme.of(LimpidThemeVariant.paper),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: AuthForm(mode: AuthFormMode.signIn)),
      ),
    );
  }

  testWidgets('un service indisponible est signalé à l\'auteur', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(_FailingRepository(const AuthUnavailableException())),
    );
    await tester.pumpAndSettle();

    final strings = AppLocalizations.of(tester.element(find.byType(AuthForm)));

    await tester.enterText(
      find.byType(LimpidTextField),
      'camille@atelier-sable.fr',
    );
    await tester.tap(find.text(strings.actionSendLink));
    await tester.pumpAndSettle();

    expect(find.text(strings.errorGeneric), findsOneWidget);
    // Le bouton propose de recommencer.
    expect(find.text(strings.actionRetry), findsOneWidget);
  });

  testWidgets('un mot de passe refusé est signalé à l\'auteur', (tester) async {
    await tester.pumpWidget(
      harness(_FailingRepository(const AuthRejectedException())),
    );
    await tester.pumpAndSettle();

    final strings = AppLocalizations.of(tester.element(find.byType(AuthForm)));

    await tester.tap(find.text(strings.signInUsePassword));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byType(LimpidTextField).first,
      'camille@atelier-sable.fr',
    );
    await tester.enterText(
      find.byType(LimpidTextField).last,
      'un-mot-de-passe',
    );
    await tester.tap(find.text(strings.actionContinue));
    await tester.pumpAndSettle();

    expect(find.text(strings.errorGeneric), findsOneWidget);
  });
}
