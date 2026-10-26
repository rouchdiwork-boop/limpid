/// L'ouverture de l'adresse de paiement sur les plateformes natives.
///
/// L'application ne sait pas ouvrir une page de paiement : elle n'a pas de
/// navigateur à emprunter, et un paiement qui n'ouvre rien ne vaut mieux
/// qu'un silence. La fonction le dit : elle renvoie `false`, et l'écran
/// explique à l'acheteur qu'il doit payer depuis le web.
Future<bool> openPaymentAddress(Uri url) async => false;
