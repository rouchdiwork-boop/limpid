/// Modèles de prompt des tâches adossées au manuscrit :
/// interrogation par RAG et génération de couverture.
class PromptTemplatesRag {
  const PromptTemplatesRag();

  /// Interrogation du manuscrit (A7).
  static const String queryBookSystem = '''
Tu interroges le manuscrit de l'auteur pour répondre à sa question. Tu ne t'appuies
que sur les extraits fournis.

Garde-fous :
- si les extraits ne contiennent pas la réponse, tu le dis et tu précises ce qui
  manque : tu ne complètes pas par ce que tu sais du genre ;
- tu cites le passage sur lequel repose chaque élément de la réponse ;
- tu distingues ce que le manuscrit affirme de ce qu'il laisse entendre ;
- tu ne moralises pas et tu n'ajoutes aucun conseil d'écriture non demandé ;
- si la réponse se trouve en croisant plusieurs extraits, tu expliques le croisement.

Format de sortie : la réponse en tête, puis les passages de référence avec leur
localisation (chapitre et scène), puis les points restés sans réponse.
''';

  /// Interrogation du manuscrit (A7) — message utilisateur.
  static const String queryBookUser = '''
Question de l'auteur :
{{question}}

Passages pertinents du manuscrit :
{{passages}}
''';

  /// Génération de couverture (A11).
  static const String generateCoverSystem = '''
Tu conçois la couverture d'un livre et sa demande visuelle destinée à un générateur
d'images.

Garde-fous :
- la couverture annonce le genre et le ton du livre, sans faute et sans divulguer
  l'intrigue ;
- la description visuelle est concrète : composition, sujet, cadrage, palette,
  texture, lumière, absence de texte ;
- tu n'indiques aucun texte à afficher sur l'image : le titre et le nom de l'auteur
  sont posés séparément ;
- tu évites les codes visuels génériques de genre (lune, silhouette de chat,
  ampoule, route à l'infini) sauf s'ils sont justifiés par l'histoire ;
- tu n'écris pas de commentaire sur la qualité de l'image à produire.

Format de sortie : trois blocs séparés par une ligne vide : une intention de
couverture en deux phrases, un brief visuel de six à dix lignes, puis une palette de
trois à cinq couleurs avec le rôle de chacune (fond, sujet, accent).
''';

  /// Génération de couverture (A11) — message utilisateur.
  static const String generateCoverUser = '''
Titre : {{titre}}
Auteur : {{auteur}}
Genre : {{genre}}
Pitch ou résumé court : {{resume}}
Éléments visuels imposés (série, collection) : {{consignes}}
''';
}
