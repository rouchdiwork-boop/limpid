import 'package:limpid_core/limpid_core.dart';

import '../db/plan_lookup.dart';
import '../errors/app_exception.dart';

/// Le garde-fou d'accès à l'API publique.
///
/// L'API publique et les webhooks sortants sont ouverts par la formule
/// Studio (D-15) : la formule porte le drapeau `hasApiAccess`. Le garde-fou
/// lit la formule par la fonction injectée, il ne connaît ni la table des
/// formules ni le service de quota.
///
/// Un compte sans formule, ou dont la formule est inconnue, est traité
/// comme un compte gratuit : il est refusé. Le garde-fou est donc fermé par
/// défaut.
final class ApiAccessGuard {
  /// Crée un garde-fou sur la lecture [planOf].
  const ApiAccessGuard({required this.planOf});

  /// La lecture de la formule du compte.
  final PlanLookup planOf;

  /// Vérifie que le compte [userId] dispose de l'accès à l'API.
  ///
  /// Lève une [ForbiddenException] quand la formule du compte n'ouvre pas
  /// l'API.
  Future<void> requireAccess(String userId) async {
    if (await canAccess(userId)) return;
    throw const ForbiddenException(
      message:
          'L\'API publique et les webhooks sont réservés à la formule Studio.',
      details: <String, Object?>{'feature': 'api_and_webhooks'},
    );
  }

  /// Indique si le compte [userId] dispose de l'accès à l'API.
  ///
  /// La lecture ne lève rien : le dispatcher s'en sert pour arrêter les
  /// livraisons d'un compte qui a quitté la formule Studio.
  Future<bool> canAccess(String userId) async {
    final String? plan = await planOf(userId);
    return hasApiAccess(plan);
  }

  /// Indique si la formule [planName] ouvre l'API publique.
  ///
  /// Le nom est comparé sans casse et sans accent : `Studio`, `studio` et
  /// `STUDIO` désignent la même formule.
  static bool hasApiAccess(String? planName) {
    final String normalized = normalizePlanName(planName);
    if (normalized.isEmpty) return false;
    for (final SubscriptionPlan plan in SubscriptionPlan.values) {
      final PlanDefinition definition = PlanDefinition.of(plan);
      if (plan.name == normalized ||
          normalizePlanName(definition.displayName) == normalized) {
        return definition.hasApiAccess;
      }
    }
    return false;
  }

  /// Normalise le nom d'une formule : sans casse et sans accent.
  static String normalizePlanName(String? planName) {
    final String lowered = (planName ?? '').trim().toLowerCase();
    final StringBuffer buffer = StringBuffer();
    for (final int unit in lowered.codeUnits) {
      final String character = String.fromCharCode(unit);
      buffer.write(_diacritics[character] ?? character);
    }
    return buffer.toString();
  }
}

/// Les caractères accentués et leur version sans accent.
const Map<String, String> _diacritics = <String, String>{
  'à': 'a',
  'â': 'a',
  'ä': 'a',
  'é': 'e',
  'è': 'e',
  'ê': 'e',
  'ë': 'e',
  'î': 'i',
  'ï': 'i',
  'ô': 'o',
  'ö': 'o',
  'ù': 'u',
  'û': 'u',
  'ü': 'u',
  'ç': 'c',
};
