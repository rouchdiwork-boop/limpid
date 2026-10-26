/// The convention of the keys of the artefacts in the object storage.
///
/// Les exports d'un projet sont écrits sous le préfixe `exports/<projectId>/`.
/// Ce préfixe est la dérivation qui relie un compte à ses artefacts : un
/// compte possède ses projets, et chaque projet porte ses exports.
///
/// La convention est la seule source de vérité du lien entre un compte et
/// ses artefacts. Aucune table n'enregistre les clés au moment de l'export :
/// un artefact ne peut donc pas échapper à la purge parce qu'une écriture
/// aurait été oubliée.
abstract final class ArtifactKeys {
  /// The prefix holding the artefacts of the project [projectId].
  ///
  /// The prefix ends with a slash: two projects whose identifiers begin
  /// with the same characters never share their artefacts.
  static String prefixOfProject(String projectId) => 'exports/$projectId/';
}
