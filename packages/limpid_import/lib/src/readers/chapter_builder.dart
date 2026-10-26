import '../model/import_block.dart';
import '../model/import_chapter.dart';
import '../model/import_scene.dart';
import '../model/import_skip.dart';
import 'parsed_document.dart';

/// L'assemblage des chapitres, des scenes et des blocs lus.
///
/// Les six lecteurs ecrivent tous dans le meme constructeur : la regle de
/// fermeture d'une scene et d'un chapitre est donc ecrite une seule fois.
///
/// Une scene sans bloc et un chapitre sans scene ne sont jamais rendus : un
/// import n'invente pas de structure vide.
final class ChapterBuilder {
  /// Cree un constructeur.
  ///
  /// [defaultTitle] est le titre donne au chapitre qui s'ouvre avant tout
  /// titre du fichier source.
  ChapterBuilder({this.defaultTitle = ''});

  /// Le titre de repli du chapitre initial.
  final String defaultTitle;

  final List<ImportedChapter> _chapters = <ImportedChapter>[];
  final List<ImportedScene> _scenes = <ImportedScene>[];
  final List<ImportedBlock> _blocks = <ImportedBlock>[];

  String _chapterTitle = '';
  int _chapterLevel = 1;
  String _sceneTitle = '';

  /// Le titre du chapitre en cours.
  String get chapterTitle => _chapterTitle;

  /// Le niveau du chapitre en cours.
  int get chapterLevel => _chapterLevel;

  /// Le nombre de blocs du chapitre en cours.
  int get blockCount => _blocks.length;

  /// Ouvre un chapitre et ferme le chapitre precedent.
  ///
  /// Un chapitre deja ouvert mais vide est perdu : il ne portait rien.
  void openChapter(String title, {int level = 1}) {
    _finishChapter();
    _chapterTitle = title.trim();
    _chapterLevel = level < 1 ? 1 : (level > 3 ? 3 : level);
  }

  /// Ouvre une scene et ferme la scene precedente.
  ///
  /// La scene ouverte recoit [title] ; une scene sans titre reste sans
  /// titre, ce qui est le cas des formats qui ne nomment pas leurs scenes.
  void openScene([String title = '']) {
    _finishScene();
    _sceneTitle = title.trim();
  }

  /// Ajoute un bloc a la scene en cours.
  void addBlock(ImportedBlock block) {
    _blocks.add(block);
  }

  /// Ferme la scene en cours et ouvre une scene sans titre.
  ///
  /// C'est la coupure de scene : un saut de page, un separateur, un titre.
  void breakScene() {
    _finishScene();
    _sceneTitle = '';
  }

  /// Rend le document lu.
  ///
  /// Le titre du document est fourni par l'appelant : le constructeur ne
  /// decide pas du titre final du manuscrit.
  ParsedDocument build({String? title, List<ImportSkip> skipped = const []}) {
    _finishChapter();
    return ParsedDocument(
      chapters: List<ImportedChapter>.unmodifiable(_chapters),
      title: title,
      skipped: List<ImportSkip>.unmodifiable(skipped),
    );
  }

  void _finishScene() {
    if (_blocks.isEmpty) {
      _sceneTitle = '';
      return;
    }
    _scenes.add(
      ImportedScene(
        title: _sceneTitle,
        blocks: List<ImportedBlock>.unmodifiable(_blocks),
      ),
    );
    _blocks.clear();
    _sceneTitle = '';
  }

  void _finishChapter() {
    _finishScene();
    if (_scenes.isEmpty) return;
    _chapters.add(
      ImportedChapter(
        title: _chapterTitle,
        level: _chapterLevel,
        scenes: List<ImportedScene>.unmodifiable(_scenes),
      ),
    );
    _scenes.clear();
    _chapterTitle = defaultTitle;
    _chapterLevel = 1;
  }
}
