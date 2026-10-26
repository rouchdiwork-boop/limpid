import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:limpid_app/l10n/generated/app_localizations.dart';
import 'package:limpid_app/src/domain/share_repository.dart';
import 'package:limpid_app/src/features/project/share_section.dart';
import 'package:limpid_design_system/limpid_design_system.dart';

/// A share repository that remembers what the screen asked for.
///
/// The fake never reaches the network: it answers what the test wrote down,
/// and it counts the calls.
final class _FakeShareRepository implements ShareRepository {
  /// Creates the fake.
  _FakeShareRepository({List<Share> shares = const <Share>[]})
    : _shares = List<Share>.of(shares);

  final List<Share> _shares;

  /// The projects the screen asked to share.
  final List<String> created = <String>[];

  /// The shares the screen asked to revoke.
  final List<String> revoked = <String>[];

  @override
  Future<List<Share>> shares() async => List<Share>.unmodifiable(_shares);

  @override
  Future<CreatedShare> createShare({
    required String projectId,
    int? expiresInHours,
  }) async {
    created.add(projectId);
    return CreatedShare(
      share: Share(
        id: 'share-new',
        projectId: projectId,
        expiresAt: DateTime.utc(2026, 11, 8),
        isRevoked: false,
        createdAt: DateTime.utc(2026, 11, 1),
      ),
      token: 'ls.partage.jeton',
    );
  }

  @override
  Future<Share> revokeShare(String shareId) async {
    revoked.add(shareId);
    return Share(
      id: shareId,
      projectId: 'project-1',
      expiresAt: DateTime.utc(2026, 11, 8),
      isRevoked: true,
      createdAt: DateTime.utc(2026, 11, 1),
      revokedAt: DateTime.utc(2026, 11, 2),
    );
  }
}

/// Wraps the section in a provider scope holding the fake repository.
Widget _harness(_FakeShareRepository repository) {
  return ProviderScope(
    overrides: [shareRepositoryProvider.overrideWithValue(repository)],
    child: MaterialApp(
      theme: LimpidTheme.of(LimpidThemeVariant.paper),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      // Les textes du test sont francais : la locale est posee, sinon le
      // poste de test choisirait l'anglais.
      locale: const Locale('fr'),
      home: const Scaffold(body: ShareSection(projectId: 'project-1')),
    ),
  );
}

void main() {
  testWidgets('la section montre les partages du livre, et eux seuls', (
    WidgetTester tester,
  ) async {
    final _FakeShareRepository repository = _FakeShareRepository(
      shares: <Share>[
        Share(
          id: 'share-1',
          projectId: 'project-1',
          expiresAt: DateTime.utc(2026, 11, 8),
          isRevoked: false,
          createdAt: DateTime.utc(2026, 11, 1),
        ),
        Share(
          id: 'share-2',
          projectId: 'project-2',
          expiresAt: DateTime.utc(2026, 11, 9),
          isRevoked: false,
          createdAt: DateTime.utc(2026, 11, 1),
        ),
      ],
    );

    await tester.pumpWidget(_harness(repository));
    await tester.pumpAndSettle();

    // Le livre n'a qu'un partage : celui de l'autre livre ne doit pas
    // apparaitre ici.
    expect(find.text('Révoquer'), findsOneWidget);
  });

  testWidgets('la section dit quand le livre n’est pas partagé', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_harness(_FakeShareRepository()));
    await tester.pumpAndSettle();

    expect(find.text('Ce livre n’est pas partagé.'), findsOneWidget);
  });

  testWidgets('le bouton de partage crée le partage et montre le lien', (
    WidgetTester tester,
  ) async {
    final _FakeShareRepository repository = _FakeShareRepository();
    await tester.pumpWidget(_harness(repository));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Partager'));
    await tester.pumpAndSettle();

    expect(repository.created, <String>['project-1']);
    // Le lien est montré une fois : il est dans la fenêtre, il n'est pas
    // perdu dans un coin de l'interface.
    expect(find.textContaining('/v1/public/shares/'), findsOneWidget);
  });

  testWidgets('le bouton de révocation révoque le partage', (
    WidgetTester tester,
  ) async {
    final _FakeShareRepository repository = _FakeShareRepository(
      shares: <Share>[
        Share(
          id: 'share-1',
          projectId: 'project-1',
          expiresAt: DateTime.utc(2026, 11, 8),
          isRevoked: false,
          createdAt: DateTime.utc(2026, 11, 1),
        ),
      ],
    );
    await tester.pumpWidget(_harness(repository));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Révoquer'));
    await tester.pumpAndSettle();

    expect(repository.revoked, <String>['share-1']);
  });
}
