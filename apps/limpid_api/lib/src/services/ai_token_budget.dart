import 'package:limpid_ai/limpid_ai.dart'
    show HeuristicTokenEstimator, TokenEstimator;
import 'package:limpid_core/limpid_core.dart' show PlanDefinition;

import '../errors/app_exception.dart';
import 'plan_catalog.dart';
import 'quota_service.dart';

/// Le nombre maximal de tokens qu'un seul appel à l'IA peut coûter.
///
/// Ce plafond est une **constante**, pas un quota de formule : il protège
/// le budget du service d'un appel qui dérive — une invite devenue un
/// chapitre collé par mégarde, une génération sans fin. Il vaut pour
/// toutes les formules : le quota mensuel de la formule borne le mois,
/// ce plafond borne l'appel.
const int maxAiTokensPerRequest = 16000;

/// Le nombre de tokens de sortie retenu quand la demande n'en précise pas.
///
/// C'est le plafond de sortie par défaut de la fournisseur : une demande
/// qui ne demande rien de particulier reçoit une réponse ordinaire.
const int defaultAiOutputTokens = 4096;

/// La garde des jetons de l'IA.
///
/// Deux gardes cohabitent, et ce n'est pas la même chose :
/// - la **garde par requête**, une constante qui refuse une demande dont
///   le coût propre dépasserait le budget d'un appel ;
/// - la **garde par période**, le quota mensuel de la formule, compté
///   comme les autres compteurs.
///
/// Les deux refusent **avant** l'appel à la fournisseur : une demande
/// refusée ne coûte rien.
final class AiTokenBudget {
  /// Crée une garde.
  ///
  /// [clock] rend l'heure injectable : les tests font passer le temps sans
  /// attendre.
  AiTokenBudget({
    required this.quota,
    this.maxTokensPerRequest = maxAiTokensPerRequest,
    this.estimator = const HeuristicTokenEstimator(),
    DateTime Function()? clock,
  }) : _clock = clock ?? _utcNow;

  /// Le service de quota : il porte le compteur mensuel.
  final QuotaService quota;

  /// Le plafond d'un appel, en tokens.
  final int maxTokensPerRequest;

  /// L'estimateur des tokens d'un texte.
  final TokenEstimator estimator;

  final DateTime Function() _clock;

  static DateTime _utcNow() => DateTime.now().toUtc();

  /// Le nombre de tokens que coûterait au plus la demande.
  ///
  /// L'entrée est estimée sur le matériau que l'auteur envoie ; la sortie
  /// est le plafond que la demande réclame, ou le plafond par défaut de la
  /// fournisseur quand la demande n'en réclame pas.
  ///
  /// C'est le **coût possible** de l'appel qui est mesuré, pas son coût
  /// probable : c'est ce coût-là que le budget d'un appel doit couvrir.
  int estimateRequestTokens({
    required String input,
    int? requestedOutputTokens,
  }) {
    final int output = requestedOutputTokens ?? defaultAiOutputTokens;
    return estimator.estimate(input) + output;
  }

  /// Refuse une demande dont le coût propre dépasse le budget d'un appel.
  ///
  /// Le refus précède l'appel à la fournisseur : la demande refusée ne
  /// coûte rien.
  void ensureRequestFits({
    required int estimatedTokens,
    required String feature,
  }) {
    if (estimatedTokens <= maxTokensPerRequest) return;
    throw QuotaExceededException(
      message:
          'Un appel à l\'IA ne peut pas dépasser $maxTokensPerRequest tokens : '
          'réduisez la demande ou le plafond « max_tokens » demandé.',
      details: <String, Object?>{
        'feature': feature,
        'scope': 'request',
        'limit': maxTokensPerRequest,
        'estimated_tokens': estimatedTokens,
        // La garde par requête n'a pas de période : son budget est libéré
        // dès que la demande est refusée, il n'y a donc rien à attendre.
        'reset_at': null,
      },
    );
  }

  /// Refuse un appel dont le compte a atteint son quota mensuel de jetons.
  ///
  /// Le refus précède l'appel à la fournisseur, comme la garde par
  /// requête. La réponse porte la date de la remise à zéro : un auteur
  /// qui ne sait pas quand le quota revient écrit au support.
  ///
  /// La garde ne lit qu'un compteur : elle ne mesure pas les jauges du
  /// compte, qui coûteraient la reconstruction de ses manuscrits.
  Future<void> ensureMonthlyQuota({required String userId}) async {
    final QuotaCounter counter = await quota.counterOf(
      userId: userId,
      feature: QuotaFeature.aiTokens,
    );
    final int? limit = counter.limit;
    if (limit == null) return;
    final int used = counter.used;
    if (used < limit) return;
    final PlanDefinition definition = await quota.definitionOf(userId);
    throw QuotaExceededException(
      message:
          'Le quota de jetons d\'IA de la formule '
          '${definition.displayName} est atteint pour ce mois-ci.',
      details: <String, Object?>{
        'feature': QuotaFeature.aiTokens.key,
        'scope': 'period',
        'limit': limit,
        'used': used,
        'period': QuotaPeriod.month.key,
        'period_key': counter.periodKey,
        'reset_at': _nextPeriodStart().toIso8601String(),
      },
    );
  }

  /// Enregistre les jetons consommés par un appel terminé.
  ///
  /// L'appel se fait **après** le succès de l'appel au modèle : une
  /// génération refusée ou interrompue ne consomme rien.
  ///
  /// Une estimation est comptée comme un usage : elle protège le budget
  /// comme le ferait un relevé exact. Elle reste marquée comme estimation
  /// dans la réponse et dans le journal, jamais confondue avec un relevé
  /// de la fournisseur.
  Future<void> recordConsumption({
    required String userId,
    required int tokens,
  }) async {
    if (tokens <= 0) return;
    await quota.recordConsumption(
      userId: userId,
      feature: QuotaFeature.aiTokens,
      amount: tokens,
    );
  }

  /// Le premier instant de la période de quota suivante.
  DateTime _nextPeriodStart() {
    final DateTime now = _clock().toUtc();
    return DateTime.utc(now.year, now.month + 1);
  }
}
