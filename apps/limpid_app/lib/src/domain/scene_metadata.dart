/// Les métadonnées qu'une scène porte dans son document CRDT.
///
/// La scène est l'unité atomique de stockage et de synchronisation (D-02) :
/// son document porte le texte, et ses métadonnées portent le reste — son
/// titre et sa position dans son chapitre.
///
/// Les clés sont une convention partagée avec le serveur : le serveur
/// reconstruit le livre à partir des documents, et il lit le titre d'une
/// scène dans la métadonnée `title`.
library;

/// La clé de la métadonnée qui porte le titre d'une scène.
///
/// Le serveur lit cette clé pour nommer le chapitre qu'il exporte : une
/// scène sans titre reste un chapitre sans nom.
const String sceneTitleMetaKey = 'title';

/// La clé de la métadonnée qui porte la position d'une scène.
///
/// La valeur est l'index fractionnaire de la scène dans son chapitre : le
/// déplacement d'une scène ne porte que cet index, le texte ne bouge pas.
const String sceneOrderMetaKey = 'scene.order';

/// La clé de la métadonnée qui porte le chapitre d'une scène.
///
/// Le serveur reconstruit la hiérarchie du livre avec elle : une scène qui
/// déclare son chapitre le rejoint dans la page publique du livre.
const String sceneChapterIdMetaKey = 'chapter_id';

/// La clé de la métadonnée qui porte le titre du chapitre d'une scène.
///
/// Le titre accompagne l'identifiant : le serveur ne lit pas la hiérarchie
/// du périphérique, et la page publique nomme le chapitre sans lui.
const String sceneChapterTitleMetaKey = 'chapter_title';
