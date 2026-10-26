import 'package:limpid_core/limpid_core.dart';

import '../db/project_record.dart';
import '../db/project_store.dart';
import '../db/sync_op_record.dart';
import '../db/sync_store.dart';
import '../sync/tree_builder.dart';

/// Les types de bloc qui portent de la prose.
///
/// La liste est celle du domaine partagé : un titre, un bloc de code, une
/// image et un séparateur de scène ne sont pas de la prose, et ne comptent
/// donc pas dans la longueur du manuscrit.
const Set<String> proseBlockTypes = <String>{
  'paragraph',
  'listItem',
  'quote',
  'footnote',
};

/// Le nombre de mots écrits par un compte.
///
/// Le compte est mesuré sur l'ensemble de ses livres : le journal de
/// synchronisation est reconstruit, et les blocs de prose vivants sont
/// comptés. La mesure suit la règle du domaine partagé, donc elle dit la
/// même chose que le compteur de l'application.
final class AccountWordCounter {
  /// Crée un compteur.
  ///
  /// [pageLimit] borne le nombre de livres lus par page : un compte qui
  /// porte beaucoup de livres est lu par pages.
  AccountWordCounter({
    required this.projects,
    required this.sync,
    this.pageLimit = defaultWordCountPageLimit,
  });

  /// Le nombre de livres lus par page, quand la composition n'en dit rien.
  static const int defaultWordCountPageLimit = 50;

  /// Les livres des comptes.
  final ProjectStore projects;

  /// Le journal de synchronisation des livres.
  final SyncStore sync;

  /// Le nombre de livres lus par page.
  final int pageLimit;

  /// Le nombre de mots écrits par le compte [userId].
  ///
  /// [ceiling] borne la mesure : le compteur s'arrête au moment où il
  /// atteint le plafond et rend alors ce plafond. Un compte qui l'a
  /// dépassé est au maximum de sa formule, et la mesure exacte ne vaut
  /// pas le prix qu'elle coûte.
  Future<int> countOf(String userId, {int? ceiling}) async {
    var total = 0;
    String? cursor;
    do {
      final ProjectPage page = await projects.list(
        userId: userId,
        limit: pageLimit,
        cursor: cursor,
      );
      for (final ProjectRecord project in page.items) {
        final List<SyncOpRecord> operations = await sync.all(
          projectId: project.id,
        );
        for (final DocumentTree tree in TreeBuilder.build(operations)) {
          total += _wordsOf(tree.blocks);
          if (ceiling != null && total >= ceiling) return ceiling;
        }
      }
      cursor = page.nextCursor;
    } while (cursor != null);
    return total;
  }

  /// Le nombre de mots des blocs de prose vivants de [blocks].
  static int _wordsOf(List<BlockNode> blocks) {
    var total = 0;
    for (final BlockNode block in blocks) {
      if (!block.deleted && proseBlockTypes.contains(block.type)) {
        total += WordCount.ofText(block.content);
      }
      total += _wordsOf(block.children);
    }
    return total;
  }
}
