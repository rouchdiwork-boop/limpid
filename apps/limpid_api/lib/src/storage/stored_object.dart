/// Un objet du stockage objet, avec sa taille.
///
/// La taille est celle que le seau annonce : le dialecte S3 la porte dans
/// la réponse d'une liste d'objets. Mesurer le stockage d'un compte ne
/// coûte donc aucune lecture d'artefact.
final class StoredObject {
  /// Crée un objet.
  const StoredObject({required this.key, required this.sizeBytes});

  /// La clé de l'objet dans le seau.
  final String key;

  /// La taille de l'objet, en octets.
  ///
  /// Elle vaut zéro quand le seau ne l'annonce pas : la liste des objets
  /// est alors muette sur ce qu'il occupe.
  final int sizeBytes;
}
