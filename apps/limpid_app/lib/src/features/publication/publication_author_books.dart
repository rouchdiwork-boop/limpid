import 'package:flutter/foundation.dart';
import 'package:limpid_app/src/domain/publication_repository.dart';

/// Un livre publié d'un auteur, tel que la vitrine le publie.
///
/// La fiche ne porte jamais le texte d'un manuscrit : elle montre la
/// couverture, le titre, le résumé et le nombre de mots du livre. Un lecteur
/// qui veut le livre l'achète.
@immutable
final class AuthorBook {
  /// Crée la fiche d'un livre publié.
  const AuthorBook({
    required this.id,
    required this.title,
    required this.synopsis,
    required this.wordCount,
  });

  /// L'identifiant du livre.
  final String id;

  /// Le titre du livre.
  final String title;

  /// Le résumé du livre.
  final String synopsis;

  /// Le nombre de mots du livre.
  final int wordCount;
}

/// La capacité dont la page d'un auteur a besoin.
///
/// La capacité étend le contrat de la publication : une implémentation qui
/// la déclare sait déjà servir une page de livre, elle sait donc servir le
/// catalogue d'un auteur.
///
/// Le contrat `PublicationRepository` ne porte pas encore la méthode : la
/// page dégrade vers son état vide tant que la couche de données ne sait
/// pas servir les livres d'un auteur. La capacité reste le point de
/// branchement : l'implémentation qui lit l'API la déclare, et la page
/// passe du vide au catalogue.
abstract interface class AuthorBooksPort implements PublicationRepository {
  /// Les livres publiés que le serveur publie pour l'auteur [authorId].
  ///
  /// La réponse n'est jamais une erreur que l'interface doit montrer : un
  /// auteur qui ne publie aucun livre a une liste vide, et le serveur
  /// injoignable aussi.
  Future<List<AuthorBook>> listShowcaseBooks({required String authorId});
}
