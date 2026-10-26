import 'package:web/web.dart' as web;

/// La cible de l'adresse de paiement : l'onglet qui l'a demandée.
///
/// Le prestataire de paiement ne rend pas dans une fenêtre : la page doit
/// remplacer l'onglet courant, sinon l'acheteur reste devant la vitrine
/// pendant que le paiement se fait ailleurs.
const String _paymentTarget = '_self';

/// Ouvre l'adresse de paiement dans l'onglet courant.
///
/// L'adresse vient du serveur et elle est signée : le navigateur la suit
/// telle quelle, sans jeton de session à lui ajouter.
Future<bool> openPaymentAddress(Uri url) async {
  final web.HTMLAnchorElement anchor =
      web.document.createElement('a') as web.HTMLAnchorElement
        ..href = url.toString()
        ..target = _paymentTarget;
  web.document.body?.appendChild(anchor);
  anchor.click();
  anchor.remove();
  return true;
}
