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

/// La part d'un livre dans un montant partagé.
///
/// Une vente simple porte **une** ligne : le livre entier. Un bundle en
/// porte une par livre, et le poids de la ligne est le prix du livre : le
/// livre le plus cher contribue plus au prix du bundle.
final class RevenueLine {
  /// Crée une ligne.
  const RevenueLine({required this.weight, required this.authorShare});

  /// Le poids de la ligne : la contribution du livre au prix.
  ///
  /// Un poids nul est possible : un livre gratuit ne contribue rien au
  /// prix. La part du montant est alors partagée à parts égales entre les
  /// lignes.
  final int weight;

  /// La part de l'auteur de cette ligne, en millièmes.
  final int authorShare;
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

  /// La ventilation du montant [amountInCents] entre les lignes [lines].
  ///
  /// Chaque ligne reçoit la part du montant qui correspond à son poids :
  /// c'est le **prorata** de ce que chaque livre contribue au prix. La part
  /// de l'auteur de la ligne s'y applique ensuite comme dans une vente
  /// simple : la règle est la même, seule la partage change.
  ///
  /// La somme des parts vaut **exactement** le montant partagé. Le centime
  /// qui ne tombe pas juste va à la ligne dont le reste est le plus grand,
  /// et le reste de l'arrondi part du côté de la plateforme, comme dans une
  /// vente simple.
  ///
  /// Un montant nul ne ventile rien : c'est le cas du livre gratuit, dont
  /// le droit est accordé sans que la plateforme ne reçoive rien.
  List<RevenueSplit> splitAmong({
    required int amountInCents,
    required List<RevenueLine> lines,
  }) {
    if (amountInCents < 0) {
      throw ArgumentError.value(
        amountInCents,
        'amountInCents',
        'Un montant partagé ne peut pas être négatif.',
      );
    }
    if (lines.isEmpty) return const <RevenueSplit>[];
    final List<int> weights = _weightsOf(lines);
    final int weightSum = weights.fold(
      0,
      (int sum, int weight) => sum + weight,
    );
    final List<int> amounts = <int>[];
    final List<int> remainders = <int>[];
    int shared = 0;
    for (final int weight in weights) {
      final int product = amountInCents * weight;
      final int amount = product ~/ weightSum;
      amounts.add(amount);
      remainders.add(product % weightSum);
      shared += amount;
    }
    _distributeRemainder(
      amounts: amounts,
      remainders: remainders,
      leftover: amountInCents - shared,
    );
    return List<RevenueSplit>.unmodifiable(
      List<RevenueSplit>.generate(
        lines.length,
        (int index) => split(
          amountInCents: amounts[index],
          authorShare: lines[index].authorShare,
        ),
      ),
    );
  }

  /// Les poids des lignes, tous égaux quand aucun livre ne contribue.
  ///
  /// Un bundle dont tous les livres sont gratuits n'a pas de poids total :
  /// le montant se partage alors à parts égales entre les livres.
  static List<int> _weightsOf(List<RevenueLine> lines) {
    final int total = lines.fold(
      0,
      (int sum, RevenueLine line) => sum + line.weight,
    );
    if (total > 0) {
      return List<int>.unmodifiable(
        lines.map((RevenueLine line) => line.weight).toList(growable: false),
      );
    }
    return List<int>.unmodifiable(
      List<int>.filled(lines.length, 1, growable: false),
    );
  }

  /// Répartit les centimes qui ne tombent pas juste.
  ///
  /// Le centime va à la ligne dont le reste est le plus grand : c'est elle
  /// qui a été la plus mal servie par l'arrondi. Les ex aequo sont départagés
  /// par l'ordre des lignes, pour que la répartition soit la même partout.
  static void _distributeRemainder({
    required List<int> amounts,
    required List<int> remainders,
    required int leftover,
  }) {
    if (leftover <= 0) return;
    final List<int> order = List<int>.generate(amounts.length, (int i) => i)
      ..sort((int left, int right) {
        final int byRest = remainders[right].compareTo(remainders[left]);
        if (byRest != 0) return byRest;
        return left.compareTo(right);
      });
    for (int index = 0; index < leftover; index++) {
      amounts[order[index % order.length]] += 1;
    }
  }
}
