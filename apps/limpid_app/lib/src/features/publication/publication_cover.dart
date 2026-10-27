import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:http/http.dart' as http;
import 'package:limpid_app/src/features/projects/project_cover.dart';

/// La fonction qui lit la couverture d'un livre sur le serveur.
///
/// La fonction rend les octets de la couverture, `null` quand le serveur ne
/// la rend pas. Une couverture qui ne vient pas laisse le fond de l'écran à
/// sa place : la page ne montre jamais une image cassée.
typedef PublicationCoverLoader = Future<Uint8List?> Function(String url);

/// La couverture d'un livre public.
///
/// La couverture vient du serveur quand le livre en a une : c'est
/// l'artefact que le moteur d'export produit. Un livre sans couverture —
/// ou une couverture que le serveur ne rend plus — montre le fond de
/// l'écran : la couverture dessinée.
class PublicationCover extends StatefulWidget {
  /// Crée la couverture d'un livre public.
  const PublicationCover({
    required this.title,
    required this.author,
    required this.seed,
    this.url = '',
    this.width,
    this.loader,
    super.key,
  });

  /// Le titre imprimé sur la couverture.
  final String title;

  /// L'auteur imprimé sur la couverture.
  final String author;

  /// L'index de la palette, qui donne à chaque livre sa couleur.
  final int seed;

  /// L'adresse de la couverture du serveur, vide quand le livre n'en a pas.
  final String url;

  /// La largeur de la couverture.
  final double? width;

  /// La fonction qui lit la couverture, quand elle n'est pas celle du
  /// widget.
  final PublicationCoverLoader? loader;

  @override
  State<PublicationCover> createState() => _PublicationCoverState();
}

/// L'état de la couverture : les octets de l'artefact, quand il est venu.
class _PublicationCoverState extends State<PublicationCover> {
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(PublicationCover oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url == widget.url) return;
    _bytes = null;
    _load();
  }

  /// Lit la couverture du serveur.
  ///
  /// Une couverture qui ne vient pas laisse le fond : l'écran montre alors
  /// la couverture qu'il dessine, jamais une image cassée.
  Future<void> _load() async {
    final String url = widget.url;
    if (url.isEmpty) return;
    final PublicationCoverLoader loader = widget.loader ?? _read;
    final Uint8List? bytes = await loader(url);
    if (!mounted || bytes == null) return;
    setState(() => _bytes = bytes);
  }

  /// La lecture par défaut : l'application lit la couverture du serveur.
  static Future<Uint8List?> _read(String url) async {
    final Uri? uri = Uri.tryParse(url);
    if (uri == null || !_isReadableScheme(uri)) {
      // L'adresse n'est pas une adresse web : la couverture n'est pas
      // lue, et l'écran garde le fond qu'il dessine.
      return null;
    }
    try {
      final http.Response response = await http
          .get(uri)
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return null;
      return response.bodyBytes;
    } on Object catch (error) {
      // Le serveur ne rend pas la couverture : l'écran garde son fond, et
      // l'anomalie est dite.
      debugPrint('La couverture du livre n\'a pas été lue : $error');
      return null;
    }
  }

  /// Indique si l'adresse [uri] est une adresse que l'application lit.
  ///
  /// Seuls `http` et `https` sont lus : un fichier local ou une adresse
  /// `file:` n'a rien à faire dans une couverture.
  static bool _isReadableScheme(Uri uri) {
    final String scheme = uri.scheme.toLowerCase();
    return scheme == 'http' || scheme == 'https';
  }

  @override
  Widget build(BuildContext context) {
    final Uint8List? bytes = _bytes;
    final Widget content = bytes == null
        ? _drawn()
        : SvgPicture.memory(bytes, fit: BoxFit.cover);
    final double? bounded = widget.width;
    if (bounded == null) return content;
    return SizedBox(
      width: bounded,
      height: bounded * _coverHeightRatio,
      child: content,
    );
  }

  /// Le rapport entre la hauteur de la couverture et sa largeur.
  ///
  /// C'est le rapport du livre imprimé : la couverture garde la forme de
  /// celle que l'écran dessine quand le serveur n'en rend pas.
  static const double _coverHeightRatio = 1.5;

  /// La couverture dessinée : le fond de l'écran.
  Widget _drawn() {
    return ProjectCover(
      title: widget.title,
      author: widget.author,
      seed: widget.seed,
      width: widget.width,
    );
  }
}
