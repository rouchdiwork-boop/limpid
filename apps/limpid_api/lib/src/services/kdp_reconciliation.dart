/// Ce que l'auteur déclare de l'issue d'un dépôt incertain.
///
/// Un dépôt incertain est parti chez Amazon sans réponse : Amazon a peut-être
/// enregistré la soumission, peut-être pas. Seul l'auteur peut le dire, après
/// avoir regardé la console KDP d'Amazon.
enum KdpReconciliationOutcome {
  /// Amazon a bien enregistré la soumission.
  ///
  /// Le dépôt devient accepté : il ne partira jamais une seconde fois.
  submitted('submitted'),

  /// Amazon n'a rien reçu de ce dossier.
  ///
  /// Le dépôt redevient un échec ordinaire : le dossier peut repartir, et
  /// l'auteur assume le risque d'une fiche en double.
  notReceived('not_received');

  const KdpReconciliationOutcome(this.key);

  /// Le nom technique de la déclaration.
  final String key;
}

/// La déclaration de l'auteur sur l'issue d'un dépôt incertain.
///
/// La déclaration est explicite : elle n'est jamais déduite d'un état du
/// dépôt, et elle ne part jamais sans que l'auteur l'ait demandée.
final class KdpReconciliation {
  /// Crée une déclaration.
  const KdpReconciliation({required this.outcome, this.amazonSubmissionId});

  /// Ce que l'auteur déclare.
  final KdpReconciliationOutcome outcome;

  /// L'identifiant de la soumission chez Amazon.
  ///
  /// Il est exigé quand l'auteur déclare que la soumission existe : c'est
  /// lui qui permet de relire la soumission dans la console KDP.
  final String? amazonSubmissionId;
}
