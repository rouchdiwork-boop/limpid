import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../auth/auth_middleware.dart';
import '../config/app_config.dart';
import '../db/sync_op_record.dart';
import '../dependencies.dart';
import '../errors/app_exception.dart';
import '../http/json_body.dart';
import '../services/access_control.dart';
import '../services/ai_gateway.dart';
import '../services/plan_catalog.dart';
import '../services/quota_service.dart';
import '../sync/tree_builder.dart';
import 'sse.dart';

/// The maximum length of a prompt sent to the model.
const int maxPromptLength = 100000;

/// Registers the routes of the AI.
///
/// [quota] porte le garde-fou des quotas : le quota de réécritures est
/// vérifié avant l'appel au modèle, et le compteur n'est incrémenté que
/// lorsque la réponse aboutit. La recherche dans le manuscrit est réservée
/// aux formules qui l'ouvrent. Le point de composition câble le service ;
/// sans lui, la route n'applique aucun plafond.
void registerAiRoutes(
  Router router,
  AppDependencies dependencies,
  AppConfig config, {
  QuotaService? quota,
}) {
  router.post('/v1/ai/generate', (Request request) async {
    final AuthContext auth = requireAuthContext(request);
    final JsonBody body = await JsonBody.fromRequest(
      request,
      maxBytes: config.maxBodyBytes,
    );

    final String prompt = body.requireString(
      'prompt',
      maxLength: maxPromptLength,
    );
    final AiGenerateRequest aiRequest = AiGenerateRequest(
      userId: auth.userId,
      prompt: prompt,
      system: body.optionalString('system', maxLength: maxPromptLength),
      taskKey: body.optionalString('task'),
      maxTokens: body.optionalInt('max_tokens', min: 1, max: 32000),
      temperature: _readTemperature(body),
    );

    return sseResponse(
      dependencies.ai.generate(aiRequest),
      logger: dependencies.logger,
    );
  });

  router.post('/v1/ai/inline', (Request request) async {
    final AuthContext auth = requireAuthContext(request);
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

    final AiInlineRequest aiRequest = AiInlineRequest(
      userId: auth.userId,
      action: action,
      text: body.requireString('text', maxLength: maxPromptLength),
      tone: body.optionalString('tone'),
      instruction: body.optionalString('instruction', maxLength: 4000),
      targetLanguage: body.optionalString('target_language') ?? 'français',
      context: body.optionalString('context', maxLength: maxPromptLength),
      maxTokens: body.optionalInt('max_tokens', min: 1, max: 32000),
    );

    return sseResponse(
      _counted(
        dependencies.ai.inline(aiRequest),
        quota: quota,
        userId: auth.userId,
      ),
      logger: dependencies.logger,
    );
  });

  router.post('/v1/ai/query', (Request request) async {
    final AuthContext auth = requireAuthContext(request);
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

    final AiQueryRequest aiRequest = AiQueryRequest(
      userId: auth.userId,
      question: question,
      sources: sources,
      topK: body.optionalInt('top_k', min: 1, max: 20) ?? 6,
      scope: projectId,
    );

    return sseResponse(
      dependencies.ai.query(aiRequest),
      logger: dependencies.logger,
    );
  });
}

/// Le flux d'une réponse, qui compte la réécriture quand elle aboutit.
///
/// Le compteur est incrémenté une seule fois, à la fin de la réponse : une
/// réécriture qui n'aboutit pas ne consomme rien.
Stream<AiEvent> _counted(
  Stream<AiEvent> events, {
  required QuotaService? quota,
  required String userId,
}) {
  if (quota == null) return events;
  return events.asyncMap((AiEvent event) async {
    if (event is AiDoneEvent) {
      await quota.recordConsumption(
        userId: userId,
        feature: QuotaFeature.aiRewrites,
      );
    }
    return event;
  });
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
