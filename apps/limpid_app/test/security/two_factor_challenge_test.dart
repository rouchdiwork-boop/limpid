import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:limpid_app/l10n/generated/app_localizations.dart';
import 'package:limpid_app/src/auth/auth_repository.dart';
import 'package:limpid_app/src/auth/session_stream.dart';
import 'package:limpid_app/src/auth/supabase_auth_repository.dart';
import 'package:limpid_app/src/auth/two_factor_proof_holder.dart';
import 'package:limpid_app/src/data/api_client.dart';
import 'package:limpid_app/src/domain/errors.dart';
import 'package:limpid_app/src/domain/two_factor_repository.dart';
import 'package:limpid_app/src/features/security/security_providers.dart';
import 'package:limpid_app/src/features/security/two_factor_challenge.dart';
import 'package:limpid_design_system/limpid_design_system.dart';

import 'fakes.dart';

void main() {
  setUp(TwoFactorProofHolder.reset);
  tearDown(TwoFactorProofHolder.reset);

  group('l’en-tête de la preuve', () {
    test('porte la preuve du second facteur', () async {
      TwoFactorProofHolder.set(fakeTwoFactorProof);
      String? header;
      final ApiClient client = _clientOf((http.Request request) async {
        header = request.headers['x-limpid-2fa'];
        return _ok(<String, Object?>{});
      });

      await client.get('/v1/me/plan');

      expect(header, 'preuve-1');
    });

    test('ne porte aucune preuve quand la session n’en a plus', () async {
      TwoFactorProofHolder.set(fakeTwoFactorProof);
      TwoFactorProofHolder.clear();
      String? header;
      final ApiClient client = _clientOf((http.Request request) async {
        header = request.headers['x-limpid-2fa'];
        return _ok(<String, Object?>{});
      });

      await client.get('/v1/me/plan');

      expect(header, isNull);
    });

    test('ne porte aucune preuve quand la preuve a expiré', () async {
      TwoFactorProofHolder.useClock(() => DateTime.utc(2100));
      TwoFactorProofHolder.set(fakeTwoFactorProof);
      String? header;
      final ApiClient client = _clientOf((http.Request request) async {
        header = request.headers['x-limpid-2fa'];
        return _ok(<String, Object?>{});
      });

      await client.get('/v1/me/plan');

      expect(header, isNull);
    });
  });

  group('le refus du serveur', () {
    test('un compte sans second facteur a une session invalide', () async {
      final TwoFactorRefusal refusal = await classifyRefusal(
        repository: FakeTwoFactorRepository(state: fakeTwoFactorOff),
        proof: null,
        statusCode: 401,
      );

      expect(refusal, TwoFactorRefusal.session);
    });

    test('un compte au second facteur actif doit fournir une preuve', () async {
      final TwoFactorRefusal refusal = await classifyRefusal(
        repository: FakeTwoFactorRepository(state: fakeTwoFactorOn),
        proof: null,
        statusCode: 401,
      );

      expect(refusal, TwoFactorRefusal.secondFactor);
    });

    test(
      'une preuve portée par l’application est un refus du second facteur',
      () async {
        final TwoFactorRefusal refusal = await classifyRefusal(
          repository: FakeTwoFactorRepository(state: fakeTwoFactorOff),
          proof: fakeTwoFactorProof,
          statusCode: 401,
        );

        expect(refusal, TwoFactorRefusal.secondFactor);
      },
    );

    test('une preuve expirée ne compte plus', () async {
      final TwoFactorRefusal refusal = await classifyRefusal(
        repository: FakeTwoFactorRepository(state: fakeTwoFactorOff),
        proof: fakeTwoFactorProof,
        statusCode: 401,
        now: DateTime.utc(2100),
      );

      expect(refusal, TwoFactorRefusal.session);
    });

    test('la formule qui exige le second facteur est nommée', () async {
      final TwoFactorRefusal refusal = await classifyRefusal(
        repository: FakeTwoFactorRepository(state: fakeTwoFactorRequired),
        proof: null,
        statusCode: 403,
      );

      expect(refusal, TwoFactorRefusal.required);
    });
  });

  group('la fenêtre du second facteur', () {
    testWidgets('un 401 ouvre la fenêtre et répète la requête', (tester) async {
      final List<http.Request> requests = <http.Request>[];
      final ApiClient client = _clientOf((http.Request request) async {
        requests.add(request);
        if (requests.length == 1) return _unauthorized();
        return _ok(<String, Object?>{'plan': 'pro'});
      });
      final FakeTwoFactorRepository repository = FakeTwoFactorRepository(
        state: fakeTwoFactorOn,
      );

      await tester.pumpWidget(
        challengeHarness(repository: repository, client: client),
      );
      await tester.pumpAndSettle();

      final AppLocalizations strings = stringsOf(tester);
      await tester.tap(find.text('envoyer'));
      await tester.pumpAndSettle();

      // La fenêtre demande le code du second facteur.
      expect(find.text(strings.twoFactorProofMissing), findsOneWidget);

      await tester.enterText(find.byType(LimpidTextField), '123456');
      await tester.tap(find.text(strings.twoFactorVerify));
      await tester.pumpAndSettle();

      // La requête est répétée, et elle porte la preuve.
      expect(repository.verified, <String>['123456']);
      expect(requests, hasLength(2));
      expect(requests.first.headers['x-limpid-2fa'], isNull);
      expect(requests.last.headers['x-limpid-2fa'], 'preuve-1');
      expect(find.text('accepté'), findsOneWidget);
    });

    testWidgets('un 401 de session n’ouvre pas la fenêtre du code', (
      tester,
    ) async {
      final List<http.Request> requests = <http.Request>[];
      final ApiClient client = _clientOf((http.Request request) async {
        requests.add(request);
        return _unauthorized();
      });
      final FakeTwoFactorRepository repository = FakeTwoFactorRepository(
        state: fakeTwoFactorOff,
      );

      await tester.pumpWidget(
        challengeHarness(repository: repository, client: client),
      );
      await tester.pumpAndSettle();

      final AppLocalizations strings = stringsOf(tester);
      await tester.tap(find.text('envoyer'));
      await tester.pumpAndSettle();

      expect(find.text(strings.twoFactorProofMissing), findsNothing);
      expect(requests, hasLength(1));
      expect(find.text('refusé'), findsOneWidget);
    });

    testWidgets('un code refusé ne répète pas la requête', (tester) async {
      final List<http.Request> requests = <http.Request>[];
      final ApiClient client = _clientOf((http.Request request) async {
        requests.add(request);
        return _unauthorized();
      });
      final FakeTwoFactorRepository repository = FakeTwoFactorRepository(
        state: fakeTwoFactorOn,
      )..verifyError = const ApiUnauthorizedException('Code invalide.');

      await tester.pumpWidget(
        challengeHarness(repository: repository, client: client),
      );
      await tester.pumpAndSettle();

      final AppLocalizations strings = stringsOf(tester);
      await tester.tap(find.text('envoyer'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(LimpidTextField), '000000');
      await tester.tap(find.text(strings.twoFactorVerify));
      await tester.pumpAndSettle();

      expect(find.text(strings.twoFactorInvalidCode), findsOneWidget);
      expect(requests, hasLength(1));
      expect(find.text('accepté'), findsNothing);
    });
  });

  group('la session', () {
    testWidgets('qui se ferme lâche la preuve', (tester) async {
      TwoFactorProofHolder.set(fakeTwoFactorProof);
      final FakeAuthRepository auth = FakeAuthRepository(
        session: const AuthSession(userId: 'auteur-1', email: 'auteur@test'),
      );
      final ProviderContainer container = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWithValue(auth),
          twoFactorRepositoryProvider.overrideWithValue(
            FakeTwoFactorRepository(),
          ),
        ],
      );
      addTearDown(container.dispose);

      // Le port est écouté : la session est observée jusqu'à la fin du test.
      final ProviderSubscription<AsyncValue<AuthSession?>> subscription =
          container.listen(twoFactorSessionProvider, (_, _) {});
      addTearDown(subscription.close);
      await tester.pump();
      expect(TwoFactorProofHolder.current, isNotNull);

      auth.closeSession();
      await tester.pumpAndSettle();
      expect(TwoFactorProofHolder.current, isNull);
    });
  });
}

/// L'écran qui appelle une action protégée par le second facteur.
class _ProtectedScreen extends ConsumerStatefulWidget {
  /// Crée l'écran.
  const _ProtectedScreen({required this.client});

  /// Le client de l'API.
  final ApiClient client;

  @override
  ConsumerState<_ProtectedScreen> createState() => _ProtectedScreenState();
}

/// L'état de l'écran qui appelle une action protégée.
class _ProtectedScreenState extends ConsumerState<_ProtectedScreen> {
  /// Le résultat de l'appel.
  String _outcome = 'en cours';

  /// Appelle l'action protégée.
  Future<void> _run() async {
    try {
      await runWithTwoFactor(
        context,
        ref,
        action: () => widget.client.get('/v1/me/plan'),
      );
      if (!mounted) return;
      setState(() => _outcome = 'accepté');
    } on Object {
      if (!mounted) return;
      setState(() => _outcome = 'refusé');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: <Widget>[
          LimpidButton(label: 'envoyer', onPressed: _run),
          Text(_outcome),
        ],
      ),
    );
  }
}

/// Builds the screen that calls a protected request.
Widget challengeHarness({
  required TwoFactorRepository repository,
  required ApiClient client,
}) {
  return ProviderScope(
    overrides: [twoFactorRepositoryProvider.overrideWithValue(repository)],
    child: MaterialApp(
      theme: LimpidTheme.of(LimpidThemeVariant.paper),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: _ProtectedScreen(client: client),
    ),
  );
}

/// The strings of the screen of the test.
AppLocalizations stringsOf(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(_ProtectedScreen)));

/// Builds a client talking to a fake server.
ApiClient _clientOf(
  Future<http.Response> Function(http.Request request) handler,
) => ApiClient(
  baseUrl: Uri.parse('https://api.test'),
  client: MockClient(handler),
  twoFactorProof: () => TwoFactorProofHolder.currentValue,
);

/// Builds a successful answer carrying the envelope of the API.
http.Response _ok(Object? data) => http.Response(
  jsonEncode(<String, Object?>{'data': data}),
  200,
  headers: <String, String>{'content-type': 'application/json'},
);

/// Builds the answer of a server that refuses the proof.
http.Response _unauthorized() => http.Response(
  jsonEncode(<String, Object?>{
    'error': <String, Object?>{
      'code': 'unauthorized',
      'message': 'La preuve du second facteur est absente.',
    },
  }),
  401,
  headers: <String, String>{'content-type': 'application/json'},
);

/// An [AuthRepository] the test drives by hand.
final class FakeAuthRepository implements AuthRepository {
  /// Creates a repository.
  FakeAuthRepository({this.session});

  /// The session the repository serves.
  AuthSession? session;

  final StreamController<AuthSession?> _updates =
      StreamController<AuthSession?>.broadcast();

  @override
  Stream<AuthSession?> watchSession() =>
      SessionStream(current: () => session, updates: _updates.stream);

  /// Closes the session of the author.
  void closeSession() {
    session = null;
    _updates.add(null);
  }

  @override
  Future<void> sendMagicLink(String email, {String? authorName}) async {}

  @override
  Future<void> signInWithPassword(String email, String password) async {}

  @override
  Future<void> signOut() async => closeSession();
}
