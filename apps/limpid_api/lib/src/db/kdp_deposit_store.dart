import 'kdp_deposit_record.dart';

/// Le port de persistance des dépôts de dossiers auprès d'Amazon KDP.
///
/// Le port porte la seule table `kdp_deposits` de la migration
/// `0014_kdp_deposits.sql`. Il ne porte aucune règle métier : le moment du
/// dépôt, la reprise et l'idempotence vivent dans le service.
///
/// Les implémentations garantissent les mêmes invariants : un dépôt
/// appartient à un compte, un dépôt n'est jamais rendu à un autre compte et
/// les dépôts d'un compte sont rendus les plus récents d'abord.
abstract interface class KdpDepositStore {
  /// Le dépôt [depositId] du compte [userId], `null` quand il n'existe pas
  /// ou quand il appartient à un autre compte.
  Future<KdpDeposit?> findDeposit({
    required String depositId,
    required String userId,
  });

  /// Le dépôt de la publication [publicationId] du compte [userId].
  ///
  /// Le résultat est `null` quand la publication n'a jamais été déposée :
  /// une publication préparée porte au plus un dépôt, que les reprises
  /// relancent.
  Future<KdpDeposit?> findDepositByPublication({
    required String publicationId,
    required String userId,
  });

  /// Les dépôts du compte [userId], les plus récents d'abord.
  Future<List<KdpDeposit>> listDeposits({required String userId});

  /// Enregistre un nouveau dépôt.
  ///
  /// Une publication ne porte qu'un dépôt : une seconde trace pour la
  /// même publication est refusée.
  Future<void> insertDeposit(KdpDeposit deposit);

  /// Met à jour un dépôt existant.
  ///
  /// La mise à jour est bornée par le compte : une trace qui n'appartient
  /// pas au compte du dépôt enregistré est refusée, jamais appliquée.
  Future<void> updateDeposit(KdpDeposit deposit);

  /// Met à jour un dépôt dont l'état est encore [expectedStatus].
  ///
  /// La méthode rend `true` quand la mise à jour a été appliquée, `false`
  /// quand l'état du dépôt a changé entre-temps : c'est la comparaison
  /// atomique qui empêche deux réconciliations concurrentes de se
  /// contrarier.
  Future<bool> updateDepositIfStatus(
    KdpDeposit deposit, {
    required KdpDepositStatus expectedStatus,
  });
}
