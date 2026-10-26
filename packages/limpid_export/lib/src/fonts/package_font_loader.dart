/// Lecture des faces de police livrees avec le paquet.
///
/// Le moteur d'export est en Dart pur : il n'a pas d'acces au bundle
/// Flutter. Sur le serveur (l'API), les faces sont lues sur le disque, dans
/// `packages/limpid_export/assets/fonts/` ; l'application, elle, les sert
/// depuis son bundle et injecte un `rootBundle.load` dans le registre.
///
/// Sur une plateforme sans systeme de fichiers (le web), la lecture renvoie
/// `null` : le moteur utilise alors ses polices de substitution.
library;

export 'package_font_loader_stub.dart'
    if (dart.library.io) 'package_font_loader_io.dart';
