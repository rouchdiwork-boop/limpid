import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:limpid_app/src/auth/auth_repository.dart';
import 'package:limpid_app/src/auth/session_controller.dart';
import 'package:limpid_app/src/domain/kdp_repository.dart';
import 'package:limpid_app/src/domain/providers.dart';
import 'package:limpid_app/src/features/actions/remote_runner.dart';
import 'package:limpid_app/src/features/security/two_factor_challenge.dart';
import 'package:limpid_core/limpid_core.dart';

/// Les dépôts du compte, lus sur le serveur.
final kdpSubmissionsProvider = FutureProvider<List<KdpSubmission>>((
  Ref ref,
) async {
  final List<KdpSubmission> submissions = await runWithTwoFactorGlobally(
    ref,
    action: () => ref.watch(kdpRepositoryProvider).list(),
  );
  final Map<String, KdpSubmission> known = ref.watch(kdpKnownDepositsProvider);
  return List<KdpSubmission>.unmodifiable(
    submissions.map((KdpSubmission submission) {
      return _merge(submission, known[submission.id]);
    }),
  );
});

/// Un dépôt du compte, lu sur le serveur.
///
/// La lecture porte l'identifiant du dépôt : l'écran rouvre le dossier qu'il
/// a préparé, même après une reprise de l'application.
final kdpSubmissionProvider = FutureProvider.family<KdpSubmission?, String>((
  Ref ref,
  String id,
) async {
  final KdpSubmission? submission = await runWithTwoFactorGlobally(
    ref,
    action: () => ref.watch(kdpRepositoryProvider).find(id),
  );
  final Map<String, KdpSubmission> known = ref.watch(kdpKnownDepositsProvider);
  return _merge(submission, known[id]);
});

/// Les dépôts que l'application connaît dans cette session.
///
/// Le serveur ne rattache pas le dépôt à la publication dans sa liste : le
/// dépôt reste donc dans la mémoire de la session. L'écran ne montre jamais
/// un état qu'il a oublié, et il ne prétend jamais qu'un dossier est parti
/// quand il ne l'a pas vu partir.
final kdpKnownDepositsProvider =
    NotifierProvider<KdpKnownDepositsNotifier, Map<String, KdpSubmission>>(
      KdpKnownDepositsNotifier.new,
    );

/// La mémoire des dépôts de la session.
final class KdpKnownDepositsNotifier
    extends Notifier<Map<String, KdpSubmission>> {
  @override
  Map<String, KdpSubmission> build() => const <String, KdpSubmission>{};

  /// Retient le dépôt [submission], pour que la liste le montre encore.
  void remember(KdpSubmission submission) {
    state = <String, KdpSubmission>{...state, submission.id: submission};
  }
}

/// L'état du dépôt d'un dossier auprès d'Amazon.
@immutable
class KdpDepositState {
  /// Crée un état.
  const KdpDepositState({
    this.isRunning = false,
    this.submissionId,
    this.submission,
    this.error,
  });

  /// Indique qu'un dépôt est en cours.
  final bool isRunning;

  /// Le dépôt que l'état concerne.
  ///
  /// L'état ne concerne qu'un dossier à la fois : l'écran ne montre jamais
  /// l'échec d'un autre dépôt.
  final String? submissionId;

  /// Le dépôt tel qu'Amazon l'a jugé, `null` quand aucun dépôt n'a abouti.
  final KdpSubmission? submission;

  /// L'erreur qui a fait échouer le dépôt, `null` quand il a abouti.
  final Object? error;
}

/// Le dépôt d'un dossier auprès d'Amazon.
///
/// Le dépôt est rendu dans tous les cas : accepté, refusé par Amazon, ou
/// impossible sur ce poste. L'échec est porté par l'état : l'écran montre le
/// motif, il ne dit jamais que le livre est arrivé.
final kdpDepositProvider =
    NotifierProvider<KdpDepositNotifier, KdpDepositState>(
      KdpDepositNotifier.new,
    );

/// Le contrôleur du dépôt d'un dossier.
final class KdpDepositNotifier extends Notifier<KdpDepositState> {
  @override
  KdpDepositState build() => const KdpDepositState();

  /// Dépose le dossier [submissionId] auprès d'Amazon.
  ///
  /// Un seul dépôt court à la fois : Amazon ne reçoit jamais deux fois le
  /// même dossier.
  ///
  /// Le dépôt va au serveur : il passe par [runner], qui ouvre la fenêtre du
  /// second facteur quand le serveur refuse la preuve. Le dépôt refusé n'a
  /// jamais atteint Amazon : la répétition n'en envoie donc qu'un.
  Future<void> submit(
    String submissionId, {
    required RemoteRunner runner,
  }) async {
    if (state.isRunning) return;
    state = KdpDepositState(isRunning: true, submissionId: submissionId);
    try {
      final KdpSubmission submission = await runner(
        () =>
            ref.read(kdpRepositoryProvider).deposit(submissionId: submissionId),
      );
      state = KdpDepositState(
        submissionId: submissionId,
        submission: submission,
      );
      ref.read(kdpKnownDepositsProvider.notifier).remember(submission);
      ref.invalidate(kdpSubmissionsProvider);
      ref.invalidate(kdpSubmissionProvider(submissionId));
    } on Exception catch (error) {
      state = KdpDepositState(submissionId: submissionId, error: error);
    } on Object catch (error, stackTrace) {
      // Une `Error` — et non une `Exception` — ne remonte pas dans le
      // `on Exception` ci-dessus : sans ce filet, l'échec disparaît et
      // l'écran ne dit rien. L'écran montre le motif, et la console porte la
      // cause.
      state = KdpDepositState(submissionId: submissionId, error: error);
      debugPrint('Le dépôt du dossier a échoué : $error\n$stackTrace');
    }
  }
}

/// Les livres que l'auteur peut déposer chez Amazon.
///
/// Les livres viennent du manuscrit : c'est le livre de l'auteur qui part
/// chez Amazon, jamais un autre.
final kdpBooksProvider = FutureProvider<List<Project>>((Ref ref) async {
  final List<Project> projects = await ref
      .watch(manuscriptRepositoryProvider)
      .listProjects();
  return List<Project>.unmodifiable(projects);
});

/// Le nom de l'auteur, tel que la session le porte.
///
/// La session peut être absente — l'application tourne alors en mode
/// démonstration — et le nom reste vide : l'auteur le saisit lui-même.
final kdpAuthorNameProvider = Provider<String>((Ref ref) {
  final AuthSession? session = ref.watch(sessionControllerProvider).value;
  final String name = session?.authorName?.trim() ?? '';
  if (name.isNotEmpty) return name;
  return session?.email.trim() ?? '';
});

/// Le dépôt de la trace du serveur, complété par celui de la session.
///
/// Le serveur ne porte pas le dépôt dans sa liste : la trace lue est
/// complétée par le dépôt que la session a vu.
KdpSubmission? _merge(KdpSubmission? server, KdpSubmission? known) {
  if (server == null) return null;
  if (known == null) return server;
  return server.copyWith(
    state: known.state,
    refusal: known.refusal,
    depositId: known.depositId,
    amazonSubmissionId: known.amazonSubmissionId,
    attempts: known.attempts,
    updatedAt: known.updatedAt,
  );
}
