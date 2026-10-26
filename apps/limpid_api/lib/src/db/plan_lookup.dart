/// La lecture de la formule du compte.
///
/// La fonction reçoit l'identifiant du compte et renvoie le nom de sa
/// formule (`free`, `writer`, `pro`, `studio`), `null` quand la formule est
/// inconnue : le compte est alors traité comme « Gratuit ».
///
/// La lecture est injectée par la composition : les services qui ont besoin
/// de la formule — les équipes, la double authentification — ne dépendent
/// pas du fichier des formules, ni de la base qui les porte.
typedef PlanLookup = Future<String?> Function(String userId);
