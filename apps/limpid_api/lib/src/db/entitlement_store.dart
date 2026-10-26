/// Le droit de lecture d'un livre.
///
/// Un droit relie trois choses : l'acheteur, le livre, et la commande qui
/// l'a payé. La commande est la **clé d'idempotence** : le même paiement ne
/// crée jamais deux droits.
///
/// La ligne porte aussi la ventilation du montant partagé : elle est
/// écrite quand la commande est payée, jamais avant.
final class EntitlementRecord {
  /// Crée un droit.
  const EntitlementRecord({
    required this.id,
    required this.userId,
    required this.projectId,
    required this.source,
    required this.grantedAt,
    required this.createdAt,
    this.amountInCents = 0,
    this.currency = 'eur',
    this.authorShare = 0,
    this.platformShare = 0,
    this.authorAmountInCents = 0,
    this.platformAmountInCents = 0,
    this.promoCode,
  });

  /// L'identifiant du droit.
  final String id;

  /// Le compte qui a acheté le livre.
  final String userId;

  /// Le livre acheté.
  final String projectId;

  /// La commande qui a payé le droit.
  ///
  /// C'est la référence du paiement chez le prestataire : la même
  /// commande ne donne jamais deux droits.
  final String source;

  /// L'instant où le droit a été accordé.
  final DateTime grantedAt;

  /// L'instant de la création de la ligne.
  final DateTime createdAt;

  /// Le montant partagé, en centimes.
  ///
  /// Le montant est celui qui a été **payé** : il porte la remise du code
  /// promo quand le livre a été acheté avec un code. Il vaut zéro pour un
  /// livre gratuit.
  final int amountInCents;

  /// La devise du montant partagé.
  final String currency;

  /// La part de l'auteur appliquée, en millièmes.
  final int authorShare;

  /// La part de la plateforme appliquée, en millièmes.
  final int platformShare;

  /// La part de l'auteur, en centimes.
  final int authorAmountInCents;

  /// La part de la plateforme, en centimes.
  final int platformAmountInCents;

  /// Le code promo utilisé pour l'achat, `null` quand il n'y en a pas.
  final String? promoCode;

  /// La représentation JSON du droit, envoyée aux clients.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'project_id': projectId,
      'source': source,
      'granted_at': grantedAt.toUtc().toIso8601String(),
      'amount_cents': amountInCents,
      'currency': currency,
      'author_share': authorShare,
      'platform_share': platformShare,
      'author_amount_cents': authorAmountInCents,
      'platform_amount_cents': platformAmountInCents,
      'promo_code': promoCode,
    };
  }
}

/// L'issue de l'octroi d'un droit.
///
/// La ligne est **idempotente** : un droit déjà accordé est rendu tel
/// quel, et l'octroi ne crée pas de second droit. Le serveur s'appuie sur
/// cette garantie pour répondre au rejeu d'un paiement sans distribuer le
/// livre deux fois.
final class EntitlementGrant {
  /// Crée une issue.
  const EntitlementGrant({required this.record, required this.isNew});

  /// Le droit accordé.
  final EntitlementRecord record;

  /// Le droit vient-il d'être créé ?
  ///
  /// `false` signifie que le droit existait déjà : la ventilation du
  /// premier paiement est conservée, elle n'est pas recalculée.
  final bool isNew;
}

/// Le port de persistance des droits de lecture.
abstract interface class EntitlementStore {
  /// Le droit du compte [userId] sur le livre [projectId], `null` quand il
  /// n'y en a pas.
  Future<EntitlementRecord?> find({
    required String userId,
    required String projectId,
  });

  /// Le droit accordé par la commande [source], `null` quand elle n'en a
  /// accordé aucun.
  Future<EntitlementRecord?> findBySource(String source);

  /// Accorde le droit [record] et rend l'issue de l'octroi.
  ///
  /// L'octroi est idempotent : un droit déjà accordé pour le même couple
  /// (acheteur, livre) est rendu tel quel, et la ligne n'est pas réécrite.
  Future<EntitlementGrant> grant(EntitlementRecord record);

  /// Les droits du compte [userId], les plus récents d'abord.
  Future<List<EntitlementRecord>> listByUser(String userId);
}
