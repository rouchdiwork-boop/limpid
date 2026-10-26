/// Le total des parts, en millièmes.
///
/// Les parts sont comptées en millièmes : 9 000 millièmes font 90 %. Un
/// entier évite les arrondis flottants, qui finissent par ne plus faire la
/// somme : le centime restant part toujours du côté de la plateforme.
const int revenueShareTotal = 10000;

/// La part de l'auteur par défaut, en millièmes.
///
/// La règle du partage des revenus est simple : 90 % pour l'auteur, 10 %
/// pour la plateforme. Elle est le **défaut**, pas une invariant : le
/// compte qui la configure porte une autre part dans sa table de vente.
const int defaultAuthorShare = 9000;

/// La part de la plateforme par défaut, en millièmes.
const int defaultPlatformShare = revenueShareTotal - defaultAuthorShare;

/// La ventilation d'un montant payé entre l'auteur et la plateforme.
///
/// La ventilation est écrite quand la commande est payée, jamais avant :
/// tant que le paiement n'est pas confirmé, l'auteur n'a rien à
/// recevoir et la plateforme n'a rien à garder.
final class RevenueSplit {
  /// Crée une ventilation.
  const RevenueSplit({
    required this.amountInCents,
    required this.authorShare,
    required this.platformShare,
    required this.authorAmountInCents,
    required this.platformAmountInCents,
  });

  /// Le montant partagé, en centimes.
  final int amountInCents;

  /// La part de l'auteur, en millièmes.
  final int authorShare;

  /// La part de la plateforme, en millièmes.
  final int platformShare;

  /// La part de l'auteur, en centimes.
  final int authorAmountInCents;

  /// La part de la plateforme, en centimes.
  final int platformAmountInCents;

  /// La représentation JSON de la ventilation.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'amount_cents': amountInCents,
      'author_share': authorShare,
      'platform_share': platformShare,
      'author_amount_cents': authorAmountInCents,
      'platform_amount_cents': platformAmountInCents,
    };
  }
}

/// Le service qui ventile un montant payé.
///
/// Le service ne lit aucune base et n'écrit rien : il porte la règle, et la
/// ligne qui la porte est écrite par le service de vente, au moment où le
/// paiement est confirmé.
final class RevenueShareService {
  /// Crée un service.
  const RevenueShareService();

  /// La ventilation du montant [amountInCents], selon la part [authorShare].
  ///
  /// La part est exprimée en millièmes : 9 000 pour 90 %. Le centime qui
  /// ne tombe pas juste part à la plateforme, pour que la somme des deux
  /// parts soit **exactement** le montant partagé.
  ///
  /// Un montant nul ne ventile rien : c'est le cas du livre gratuit, dont
  /// le droit est accordé sans que la plateforme ne reçoive rien.
  RevenueSplit split({
    required int amountInCents,
    int authorShare = defaultAuthorShare,
  }) {
    if (amountInCents < 0) {
      throw ArgumentError.value(
        amountInCents,
        'amountInCents',
        'Un montant partagé ne peut pas être négatif.',
      );
    }
    if (authorShare < 0 || authorShare > revenueShareTotal) {
      throw ArgumentError.value(
        authorShare,
        'authorShare',
        'La part de l\'auteur doit être comprise entre 0 et '
            '$revenueShareTotal millièmes.',
      );
    }
    final int authorAmount = amountInCents * authorShare ~/ revenueShareTotal;
    return RevenueSplit(
      amountInCents: amountInCents,
      authorShare: authorShare,
      platformShare: revenueShareTotal - authorShare,
      authorAmountInCents: authorAmount,
      platformAmountInCents: amountInCents - authorAmount,
    );
  }
}
