import 'package:limpid_ai/limpid_ai.dart' show AiTaskKeys;
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../auth/auth_middleware.dart';
import '../config/app_config.dart';
import '../db/sync_op_record.dart';
import '../dependencies.dart';
import '../errors/app_exception.dart';
import '../http/json_body.dart';
import '../logging/logger.dart';
import '../services/access_control.dart';
import '../services/ai_gateway.dart';
import '../services/ai_token_budget.dart';
import '../services/plan_catalog.dart';
import '../services/quota_service.dart';
import '../sync/tree_builder.dart';
import 'sse.dart';

/// The maximum length of a prompt sent to the model.
const int maxPromptLength = 100000;

/// Les clés de tâche qui demandent une couverture IA.
///
/// Le registre des tâches nomme la génération de couverture
/// « generate_cover » (A11) ; l'API publique emploie la clé courte
/// « cover ». Les deux demandent une couverture, et les deux consomment le
/// compteur mensuel des couvertures.
const Set<String> aiCoverTaskKeys = <String>{'cover', AiTaskKeys.generateCover};

/// Registers the routes of the AI.
///
/// [quota] porte le garde-fou des quotas : le quota de réécritures est
/// vérifié avant l'appel au modèle, le quota des couvertures l'est aussi
/// pour une demande de couverture, et les compteurs ne sont incrémentés
/// que lorsque la réponse aboutit. La recherche dans le manuscrit est
/// réservée aux formules qui l'ouvrent. Le point de composition câble le
/// service ; sans lui, la route n'applique aucun plafond.
///
/// La même service porte la garde des jetons : le budget d'un appel et le
/// quota mensuel de la formule sont vérifiés avant l'appel au fournisseur,
/// et les jetons consommés ne sont comptés qu'une fois la réponse
/// aboutie.
///
/// Le consentement de l'auteur (D-08) est demandé avant tout appel : la
/// passerelle qui exige le consentement le vérifie, et la demande est
/// refusée **avant** l'appel à la fournisseur et avant l'ouverture du flux.
void registerAiRoutes(
  Router router,
  AppDependencies dependencies,
  AppConfig config, {
  QuotaService? quota,
}) {
  final AiTokenBudget? tokens = quota == null
      ? null
      : AiTokenBudget(quota: quota);

  router.post('/v1/ai/generate', (Request request) async {
    final AuthContext auth = requireAuthContext(request);
    await _ensureConsent(dependencies.ai, auth.userId);
    final JsonBody body = await JsonBody.fromRequest(
      request,
      maxBytes: config.maxBodyBytes,
    );

    final String prompt = body.requireString(
      'prompt',
      maxLength: maxPromptLength,
    );

    final String? task = body.optionalString('task');
    final bool isCover = task != null && aiCoverTaskKeys.contains(task);

    // Le garde-fou passe avant l'appel au modèle : une génération refusée
    // ne coûte rien au fournisseur. Le quota de la formule compte
    // **toute** appel au modèle, réécriture ou génération.
    if (quota != null) {
      await quota.ensureCounter(
        userId: auth.userId,
        feature: QuotaFeature.aiRewrites,
      );
      if (isCover) {
        // La limite des couvertures est vérifiée avant l'appel : une
        // couverture refusée ne coûte rien au fournisseur.
        await quota.ensureCounter(
          userId: auth.userId,
          feature: QuotaFeature.aiCovers,
        );
      }
    }

    final String? system = body.optionalString(
      'system',
      maxLength: maxPromptLength,
    );
    final int? maxTokens = body.optionalInt('max_tokens', min: 1, max: 32000);

    await _ensureTokenBudget(
      tokens,
      userId: auth.userId,
      feature: 'ai_generate',
      input: system == null ? prompt : '$system\n$prompt',
      maxTokens: maxTokens,
    );

    final AiGenerateRequest aiRequest = AiGenerateRequest(
      userId: auth.userId,
      prompt: prompt,
      system: system,
      taskKey: task,
      maxTokens: maxTokens,
      temperature: _readTemperature(body),
    );

    return sseResponse(
      _counted(
        dependencies.ai.generate(aiRequest),
        quota: quota,
        tokens: tokens,
        userId: auth.userId,
        feature: 'ai_generate',
        logger: dependencies.logger,
        countsCovers: isCover,
      ),
      logger: dependencies.logger,
    );
  });

  router.post('/v1/ai/inline', (Request request) async {
    final AuthContext auth = requireAuthContext(request);
    await _ensureConsent(dependencies.ai, auth.userId);
    final JsonBody body = await JsonBody.fromRequest(
      request,
      maxBytes: config.maxBodyBytes,
    );

    final String action = body.requireString('action');
    if (!aiInlineActions.contains(action)) {
      throw ValidationException(
        field: 'action',
        message:
            'Le champ « action » doit valoir '
            '${aiInlineActions.join(', ')}.',
      );
    }

    // Le garde-fou passe avant l'appel au modèle : une réécriture refusée
    // ne coûte rien au fournisseur.
    if (quota != null) {
      await quota.ensureCounter(
        userId: auth.userId,
        feature: QuotaFeature.aiRewrites,
      );
    }

    final String text = body.requireString('text', maxLength: maxPromptLength);
    final String? instruction = body.optionalString(
      'instruction',
      maxLength: 4000,
    );
    final String? context = body.optionalString(
      'context',
      maxLength: maxPromptLength,
    );
    final int? maxTokens = body.optionalInt('max_tokens', min: 1, max: 32000);

    await _ensureTokenBudget(
      tokens,
      userId: auth.userId,
      feature: 'ai_inline',
      input: _joined(<String?>[text, instruction, context]),
      maxTokens: maxTokens,
    );

    final AiInlineRequest aiRequest = AiInlineRequest(
      userId: auth.userId,
      action: action,
      text: text,
      tone: body.optionalString('tone'),
      instruction: instruction,
      targetLanguage: body.optionalString('target_language') ?? 'français',
      context: context,
      maxTokens: maxTokens,
    );

    return sseResponse(
      _counted(
        dependencies.ai.inline(aiRequest),
        quota: quota,
        tokens: tokens,
        userId: auth.userId,
        feature: 'ai_inline',
        logger: dependencies.logger,
      ),
      logger: dependencies.logger,
    );
  });

  router.post('/v1/ai/query', (Request request) async {
    final AuthContext auth = requireAuthContext(request);
    await _ensureConsent(dependencies.ai, auth.userId);
    final JsonBody body = await JsonBody.fromRequest(
      request,
      maxBytes: config.maxBodyBytes,
    );

    final String question = body.requireString(
      'question',
      maxLength: maxPromptLength,
    );
    final String? projectId = body.optionalString('project_id');
    final List<ManuscriptSource> sources = <ManuscriptSource>[];
    if (projectId != null) {
      await AccessControl.requireProject(
        dependencies.projects,
        projectId,
        auth,
      );
      final List<SyncOpRecord> operations = await dependencies.sync.all(
        projectId: projectId,
      );
      sources.addAll(_sourcesOf(operations));
    }

    // La recherche dans le manuscrit n'est ouverte qu'aux formules qui la
    // comprennent.
    if (quota != null) {
      await quota.ensureCapability(
        userId: auth.userId,
        capability: PlanCapability.rag,
      );
    }

    // La garde des jetons porte sur la question de l'auteur : les passages
    // que le serveur retrieve dans le manuscrit sont un choix de la
    // recherche, pas une matière envoyée par l'auteur. Le quota mensuel
    // borne de toute façon le volume.
    await _ensureTokenBudget(
      tokens,
      userId: auth.userId,
      feature: 'ai_query',
      input: question,
    );

    final AiQueryRequest aiRequest = AiQueryRequest(
      userId: auth.userId,
      question: question,
      sources: sources,
      topK: body.optionalInt('top_k', min: 1, max: 20) ?? 6,
      scope: projectId,
    );

    return sseResponse(
      _counted(
        dependencies.ai.query(aiRequest),
        quota: quota,
        tokens: tokens,
        userId: auth.userId,
        feature: 'ai_query',
        logger: dependencies.logger,
        countsRewrites: false,
      ),
      logger: dependencies.logger,
    );
  });
}

/// Demande le consentement de l'auteur, avant tout appel à la fournisseur.
///
/// La garde est **avant** l'appel : une demande refusée ne coûte rien à la
/// fournisseur, et le flux de la réponse n'est jamais ouvert.
///
/// La garde fait partie du contrat de la passerelle (D-08) : celle qui
/// interroge un tiers exige le consentement de l'auteur et répond `403`
/// quand il manque ; celle qui n'a personne en face — un poste sans
/// fournisseur configuré — refuse l'appel de toute façon.
Future<void> _ensureConsent(AiGateway gateway, String userId) async {
  await gateway.ensureConsent(userId: userId);
}

/// Applique les deux gardes des jetons, avant l'appel à la fournisseur.
///
/// La garde par requête refuse une demande dont le coût propre dépasse le
/// budget d'un appel ; la garde par période refuse un compte qui a atteint
/// son quota mensuel de jetons. Les deux précèdent l'appel : une demande
/// refusée ne coûte rien au fournisseur.
Future<void> _ensureTokenBudget(
  AiTokenBudget? budget, {
  required String userId,
  required String feature,
  required String input,
  int? maxTokens,
}) async {
  if (budget == null) return;
  final int estimated = budget.estimateRequestTokens(
    input: input,
    requestedOutputTokens: maxTokens,
  );
  budget.ensureRequestFits(estimatedTokens: estimated, feature: feature);
  await budget.ensureMonthlyQuota(userId: userId);
}

/// Le flux d'une réponse, qui compte la réécriture quand elle aboutit.
///
/// Le compteur est incrémenté une seule fois, à la fin de la réponse : une
/// réécriture qui n'aboutit pas ne consomme rien. Les jetons consommés
/// sont comptés de la même manière, et une estimation est marquée comme
/// telle dans le journal : elle ne se déguise jamais en relevé de la
/// fournisseur.
///
/// Le compteur des couvertures ne compte que les demandes de couverture :
/// une génération qui n'en est pas une n'en consomme pas.
Stream<AiEvent> _counted(
  Stream<AiEvent> events, {
  required QuotaService? quota,
  required AiTokenBudget? tokens,
  required String userId,
  required String feature,
  required Logger logger,
  bool countsRewrites = true,
  bool countsCovers = false,
}) {
  if (quota == null) return events;
  return events.asyncMap((AiEvent event) async {
    if (event is AiDoneEvent) {
      if (countsRewrites) {
        await quota.recordConsumption(
          userId: userId,
          feature: QuotaFeature.aiRewrites,
        );
      }
      if (countsCovers) {
        await quota.recordConsumption(
          userId: userId,
          feature: QuotaFeature.aiCovers,
        );
      }
      if (tokens != null) {
        final int consumed = event.inputTokens + event.outputTokens;
        if (event.isTokenCountEstimated) {
          logger.info('ai.tokens_estimated', <String, Object?>{
            'user_id': userId,
            'feature': feature,
            'token_count': consumed,
          });
        }
        await tokens.recordConsumption(userId: userId, tokens: consumed);
      }
    }
    return event;
  });
}

/// La réunion des morceaux de texte d'une demande.
///
/// Les morceaux vides sont écartés : ils ne portaient aucune matière.
String _joined(List<String?> parts) {
  return parts
      .where((String? part) => part != null && part.isNotEmpty)
      .join('\n');
}

List<ManuscriptSource> _sourcesOf(List<SyncOpRecord> operations) {
  final List<ManuscriptSource> sources = <ManuscriptSource>[];
  for (final DocumentTree tree in TreeBuilder.build(operations)) {
    for (final BlockNode block in tree.blocks) {
      final String text = block.content.trim();
      if (text.isEmpty) continue;
      sources.add(ManuscriptSource(id: block.id, text: text));
    }
  }
  return sources;
}

double? _readTemperature(JsonBody body) {
  final Object? raw = body.fields['temperature'];
  if (raw == null) return null;
  if (raw is! num) {
    throw const ValidationException(
      field: 'temperature',
      message: 'Le champ « temperature » doit être un nombre.',
    );
  }
  final double value = raw.toDouble();
  if (value < 0 || value > 2) {
    throw const ValidationException(
      field: 'temperature',
      message: 'Le champ « temperature » doit être compris entre 0 et 2.',
    );
  }
  return value;
}
