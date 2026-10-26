import 'kdp_deposit_record.dart';
import 'kdp_deposit_store.dart';

/// La base des dépôts de dossiers tenue en mémoire, pour la suite de tests.
///
/// L'implémentation garde les mêmes invariants que les bases SQL : un dépôt
/// appartient à un compte, la trace n'est jamais rendue à un autre compte,
/// une publication ne porte qu'un dépôt et les dépôts d'un compte sont
/// rendus les plus récents d'abord.
final class InMemoryKdpDepositStore implements KdpDepositStore {
  /// Crée une base vide.
  InMemoryKdpDepositStore();

  final Map<String, KdpDeposit> _deposits = <String, KdpDeposit>{};

  @override
  Future<KdpDeposit?> findDeposit({
    required String depositId,
    required String userId,
  }) async {
    final KdpDeposit? deposit = _deposits[depositId];
    if (deposit == null || deposit.userId != userId) return null;
    return deposit;
  }

  @override
  Future<KdpDeposit?> findDepositByPublication({
    required String publicationId,
    required String userId,
  }) async {
    for (final KdpDeposit deposit in _deposits.values) {
      if (deposit.publicationId != publicationId) continue;
      if (deposit.userId != userId) continue;
      return deposit;
    }
    return null;
  }

  @override
  Future<List<KdpDeposit>> listDeposits({required String userId}) async {
    final List<KdpDeposit> deposits =
        _deposits.values
            .where((KdpDeposit deposit) => deposit.userId == userId)
            .toList()
          ..sort(_compareDeposits);
    return List<KdpDeposit>.unmodifiable(deposits);
  }

  @override
  Future<void> insertDeposit(KdpDeposit deposit) async {
    if (_deposits.containsKey(deposit.id)) {
      throw StateError('The deposit ${deposit.id} already exists.');
    }
    for (final KdpDeposit existing in _deposits.values) {
      if (existing.publicationId != deposit.publicationId) continue;
      // Une publication ne porte qu'un dépôt : deux dépôts pour le même
      // dossier partiraient deux fois chez Amazon.
      throw StateError(
        'The publication ${deposit.publicationId} already has a deposit.',
      );
    }
    _deposits[deposit.id] = deposit;
  }

  @override
  Future<void> updateDeposit(KdpDeposit deposit) async {
    final KdpDeposit? existing = _deposits[deposit.id];
    if (existing == null) {
      throw StateError('Unknown deposit ${deposit.id}.');
    }
    if (existing.userId != deposit.userId) {
      // Un dépôt ne change pas de compte : la trace est la preuve que le
      // dossier n'est parti que pour un seul auteur.
      throw StateError('The deposit ${deposit.id} belongs to another account.');
    }
    _deposits[deposit.id] = deposit;
  }

  @override
  Future<bool> updateDepositIfStatus(
    KdpDeposit deposit, {
    required KdpDepositStatus expectedStatus,
  }) async {
    final KdpDeposit? existing = _deposits[deposit.id];
    if (existing == null) {
      throw StateError('Unknown deposit ${deposit.id}.');
    }
    if (existing.userId != deposit.userId) {
      throw StateError('The deposit ${deposit.id} belongs to another account.');
    }
    if (existing.status != expectedStatus) return false;
    _deposits[deposit.id] = deposit;
    return true;
  }

  static int _compareDeposits(KdpDeposit left, KdpDeposit right) {
    final int byDate = right.createdAt.compareTo(left.createdAt);
    if (byDate != 0) return byDate;
    return left.id.compareTo(right.id);
  }
}
