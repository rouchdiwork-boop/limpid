import 'dart:convert';

import 'package:limpid_app/src/auth/two_factor_proof_holder.dart';
import 'package:limpid_app/src/domain/errors.dart';
import 'package:limpid_app/src/domain/gdpr_repository.dart';
import 'package:limpid_app/src/domain/kdp_repository.dart';
import 'package:limpid_app/src/domain/plan_repository.dart';
import 'package:limpid_app/src/domain/repositories.dart';
import 'package:limpid_app/src/domain/team_repository.dart';
import 'package:limpid_app/src/domain/webhook_repository.dart';
import 'package:limpid_core/limpid_core.dart';

import '../../support/hierarchy_stub.dart';

/// The refusal of the server when the proof of the second factor expired.
///
/// The server answers `401` when the account carries the second factor and
/// the request does not carry its proof.
const ApiUnauthorizedException refusedProof = ApiUnauthorizedException(
  'La preuve du second facteur est absente.',
  code: 'unauthorized',
  statusCode: 401,
);

/// The behaviour shared by the repositories that refuse the first call.
///
/// The server refuses the first request when the proof of the second factor
/// has expired. The fake counts the calls, notes the proof the application
/// carried at each of them, and refuses the first one — the repetition of
/// the action, made with a fresh proof, succeeds.
mixin RefusesTheFirstCall {
  /// The number of calls the repository received.
  int calls = 0;

  /// The error the first call throws.
  ///
  /// The default is the refusal of the second factor. A test that wants
  /// another failure — a `404`, a network cut — gives it here.
  Object refusal = refusedProof;

  /// The proof the application carried at each call, in the order of the
  /// calls.
  ///
  /// The first call carries no proof, the second carries the one the author
  /// just gave.
  final List<String?> proofs = <String?>[];

  /// Refuses the call when it is the first one.
  void refuseIfFirst() {
    calls++;
    proofs.add(TwoFactorProofHolder.currentValue);
    if (calls == 1) {
      throw refusal;
    }
  }
}

/// An export repository that refuses the first export.
final class RefusingExportRepository
    with RefusesTheFirstCall
    implements ExportRepository {
  @override
  Future<ExportArtefact> export({
    required String projectId,
    required ExportFormat format,
  }) async {
    refuseIfFirst();
    return ExportArtefact(
      fileName: 'livre.md',
      mimeType: 'text/markdown',
      bytes: utf8.encode('# Livre\n'),
    );
  }
}

/// An assistant that refuses the first answer.
final class RefusingAiRepository
    with RefusesTheFirstCall
    implements AiRepository {
  @override
  Stream<String> rewrite({
    required String sceneId,
    required String selection,
    required String instruction,
  }) async* {
    refuseIfFirst();
    yield 'La cloche sonna';
  }

  @override
  Stream<String> answer({
    required String projectId,
    required String question,
  }) async* {
    refuseIfFirst();
    yield 'La cloche sonna';
  }
}

/// A plan repository that refuses the first change of plan.
final class RefusingPlanRepository
    with RefusesTheFirstCall
    implements PlanRepository {
  @override
  Future<AccountPlan> changePlan({
    required SubscriptionPlan plan,
    required BillingPeriod period,
  }) async {
    refuseIfFirst();
    return AccountPlan(
      plan: plan,
      displayName: 'Pro',
      status: PlanStatus.active,
      period: period,
      periodStartedAt: DateTime.utc(2026, 11, 1),
    );
  }

  @override
  Future<CheckoutSession> openCheckout({
    required SubscriptionPlan plan,
    required BillingPeriod period,
    required Uri returnTo,
  }) async {
    refuseIfFirst();
    return const CheckoutSession(
      id: 'cs_test_1',
      url: 'https://checkout.test/session/1',
    );
  }

  @override
  Future<AccountPlan> currentPlan() async => AccountPlan(
    plan: SubscriptionPlan.pro,
    displayName: 'Pro',
    status: PlanStatus.active,
    period: BillingPeriod.monthly,
    periodStartedAt: DateTime.utc(2026, 11, 1),
  );

  @override
  Future<List<PlanOffer>> offers() async => const <PlanOffer>[];

  @override
  Future<List<QuotaReading>> usage() async => const <QuotaReading>[];
}

/// A team repository that refuses the first change of role.
final class RefusingTeamRepository
    with RefusesTheFirstCall
    implements TeamRepository {
  @override
  Future<TeamMember> changeRole({
    required String teamId,
    required String userId,
    required TeamRole role,
  }) async {
    refuseIfFirst();
    return TeamMember(
      teamId: teamId,
      userId: userId,
      role: role,
      createdAt: DateTime.utc(2026, 11, 1),
    );
  }

  @override
  Future<List<Team>> listTeams() async => const <Team>[];

  @override
  Future<Team> createTeam({required String name}) async {
    refuseIfFirst();
    return Team(
      id: 'team-1',
      name: name,
      ownerId: 'owner-1',
      createdAt: DateTime.utc(2026, 11, 1),
      updatedAt: DateTime.utc(2026, 11, 1),
    );
  }

  @override
  Future<List<TeamMember>> listMembers({required String teamId}) async =>
      const <TeamMember>[];

  @override
  Future<CreatedTeamInvitation> inviteByEmail({
    required String teamId,
    required String email,
    required TeamRole role,
  }) async {
    refuseIfFirst();
    return CreatedTeamInvitation(
      invitation: TeamEmailInvitation(
        id: 'invitation-1',
        teamId: teamId,
        email: email,
        role: role,
        status: TeamInvitationStatus.pending,
        invitedBy: 'owner-1',
        createdAt: DateTime.utc(2026, 11, 1),
        expiresAt: DateTime.utc(2026, 11, 8),
      ),
    );
  }

  @override
  Future<List<TeamEmailInvitation>> listInvitations({
    required String teamId,
  }) async => const <TeamEmailInvitation>[];

  @override
  Future<TeamEmailInvitation> revokeInvitation({
    required String teamId,
    required String invitationId,
  }) async => throw UnimplementedError();

  @override
  Future<TeamEmailInvitation> acceptInvitation({required String token}) async =>
      throw UnimplementedError();

  @override
  Future<TeamInvitation> invite({
    required String teamId,
    required String userId,
    required TeamRole role,
  }) async {
    refuseIfFirst();
    return TeamInvitation(
      id: 'invitation-1',
      teamId: teamId,
      userId: userId,
      role: role,
      invitedBy: 'owner-1',
      createdAt: DateTime.utc(2026, 11, 1),
    );
  }

  @override
  Future<void> removeMember({
    required String teamId,
    required String userId,
  }) async {
    refuseIfFirst();
  }

  @override
  Future<void> deleteTeam({required String teamId}) async {
    refuseIfFirst();
  }
}

/// A webhook repository that refuses the first point of reception.
final class RefusingWebhookRepository
    with RefusesTheFirstCall
    implements WebhookRepository {
  @override
  Future<WebhookEndpointSecret> createEndpoint({
    required String url,
    required Set<String> events,
  }) async {
    refuseIfFirst();
    return WebhookEndpointSecret(endpoint: _endpoint, secret: 'whsec_secret');
  }

  @override
  Future<CreatedApiKey> createApiKey({
    required String name,
    required Set<ApiKeyScope> scopes,
  }) async {
    refuseIfFirst();
    return CreatedApiKey(key: _key, secret: 'lk.secret');
  }

  @override
  Future<List<WebhookEndpoint>> endpoints() async => const <WebhookEndpoint>[];

  @override
  Future<List<ApiKey>> apiKeys() async => const <ApiKey>[];

  @override
  Future<List<WebhookEvent>> availableEvents() async => const <WebhookEvent>[
    WebhookEvent(key: 'project.published', label: 'Projet publié'),
  ];

  @override
  Future<List<WebhookDelivery>> deliveries() async => const <WebhookDelivery>[];

  @override
  Future<WebhookEndpoint> updateEndpoint(
    String endpointId, {
    String? url,
    Set<String>? events,
  }) async {
    refuseIfFirst();
    return _endpoint;
  }

  @override
  Future<WebhookEndpointSecret> rotateEndpointSecret(String endpointId) async {
    refuseIfFirst();
    return WebhookEndpointSecret(endpoint: _endpoint, secret: 'whsec_secret');
  }

  @override
  Future<CreatedApiKey> rotateApiKey(String keyId) async {
    refuseIfFirst();
    return CreatedApiKey(key: _key, secret: 'lk.secret');
  }

  @override
  Future<void> deleteEndpoint(String endpointId) async {
    refuseIfFirst();
  }

  @override
  Future<void> deleteApiKey(String keyId) async {
    refuseIfFirst();
  }

  @override
  Future<WebhookDelivery> replayDelivery(String deliveryId) async {
    refuseIfFirst();
    return WebhookDelivery(
      id: 'delivery-1',
      endpointId: 'endpoint-1',
      event: 'project.published',
      status: WebhookDeliveryStatus.succeeded,
      attempts: 1,
      createdAt: _createdAt,
    );
  }

  /// The point of reception the fake serves.
  static final WebhookEndpoint _endpoint = WebhookEndpoint(
    id: 'endpoint-1',
    url: 'https://exemple.test/limpid',
    events: <String>{'project.published'},
    isActive: true,
    hasPreviousSecret: false,
    createdAt: _createdAt,
    updatedAt: _createdAt,
  );

  /// The key the fake serves.
  static final ApiKey _key = ApiKey(
    id: 'key-1',
    name: 'Intégration',
    scopes: <ApiKeyScope>{ApiKeyScope.read},
    isActive: true,
    isRevoked: false,
    createdAt: _createdAt,
  );

  /// The moment the fake serves.
  static final DateTime _createdAt = DateTime.utc(2026, 11, 1);
}

/// A publication repository that refuses the first deposit.
final class RefusingKdpRepository
    with RefusesTheFirstCall
    implements KdpRepository {
  @override
  Future<KdpSubmission> deposit({required String submissionId}) async {
    refuseIfFirst();
    return _submission(submissionId);
  }

  @override
  Future<KdpSubmission> prepare({
    required String projectId,
    required KdpMetadata metadata,
  }) async {
    refuseIfFirst();
    return _submission('submission-1');
  }

  @override
  Future<List<KdpSubmission>> list() async => const <KdpSubmission>[];

  @override
  Future<KdpSubmission?> find(String submissionId) async => null;

  /// The deposit the fake serves.
  static KdpSubmission _submission(String id) => KdpSubmission(
    id: id,
    projectId: 'project-1',
    title: 'Les Heures de Cendre',
    author: 'Camille',
    description: 'Un livre.',
    keywords: const <String>[],
    categories: const <String>[],
    language: 'fr',
    publisher: 'Atelier',
    isbn: null,
    state: KdpState.submitted,
    isReady: true,
    issues: const <KdpIssue>[],
    wordCount: 1200,
    pageCount: 42,
    createdAt: DateTime.utc(2026, 11, 1),
  );
}

/// A personal data repository that refuses the first export.
final class RefusingGdprRepository
    with RefusesTheFirstCall
    implements GdprRepository {
  @override
  Future<PersonalDataExport> exportPersonalData() async {
    refuseIfFirst();
    return PersonalDataExport(
      fileName: 'limpid-donnees.json',
      mimeType: 'application/json',
      bytes: utf8.encode('{"projects": []}'),
      generatedAt: DateTime.utc(2026, 11, 1),
      projectCount: 0,
    );
  }

  @override
  Future<AccountDeletion> requestAccountDeletion() async {
    refuseIfFirst();
    return AccountDeletion(
      requestedAt: DateTime.utc(2026, 11, 1),
      scheduledFor: DateTime.utc(2026, 12, 1),
      retentionDays: 30,
    );
  }
}

/// A manuscript repository whose local write fails.
///
/// The manuscript lives on the device: the write never asks the server. The
/// failure looks like a refusal of the proof, and the window of the second
/// factor must still not open — the action is local, it is not wrapped.
final class FailingLocalManuscriptRepository extends StubHierarchyRepository
    implements ManuscriptRepository {
  /// The number of writes the repository received.
  int writes = 0;

  @override
  Future<Project> saveProject(Project project) async {
    writes++;
    throw refusedProof;
  }

  @override
  Future<List<Project>> listProjects() async => const <Project>[];

  @override
  Future<Project?> findProject(String projectId) async => null;

  @override
  Future<Project> createProject({
    required String title,
    String synopsis = '',
  }) async => throw refusedProof;

  @override
  Future<void> deleteProject(String projectId) async {}

  @override
  Future<List<Chapter>> listChapters(String projectId) async =>
      const <Chapter>[];

  @override
  Future<Chapter> saveChapter(Chapter chapter) async => chapter;

  @override
  Future<List<Scene>> listScenes(String chapterId) async => const <Scene>[];

  @override
  Future<Scene> saveScene(Scene scene) async => scene;

  @override
  Future<CrdtDocument> loadDocument(String documentId) async =>
      CrdtDocument.empty(DocumentId(documentId));

  @override
  Future<void> applyOperations(List<SyncOp> operations) async {}
}
