import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:limpid_core/limpid_core.dart';

/// The default width of the slash menu, in logical pixels.
const double kSlashMenuWidth = 320;

/// The maximum height of the slash menu, in logical pixels.
const double kSlashMenuMaxHeight = 320;

/// The kind of command offered by the slash menu.
enum LimpidSlashMenuItemKind {
  /// Inserts a block in the manuscript.
  block,

  /// Runs an AI command on the scene.
  ai,
}

/// An entry of the slash menu.
@immutable
class LimpidSlashMenuItem {
  /// Creates a slash menu entry.
  const LimpidSlashMenuItem({
    required this.id,
    required this.label,
    required this.description,
    required this.icon,
    required this.kind,
    this.blockType,
  });

  /// The stable identifier of the entry.
  final String id;

  /// The label of the entry.
  final String label;

  /// The short description of the entry.
  final String description;

  /// The icon of the entry.
  final IconData icon;

  /// The kind of command the entry triggers.
  final LimpidSlashMenuItemKind kind;

  /// The kind of block inserted by the entry, `null` for an AI command.
  final BlockType? blockType;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LimpidSlashMenuItem &&
          other.id == id &&
          other.label == label &&
          other.description == description &&
          other.icon == icon &&
          other.kind == kind &&
          other.blockType == blockType);

  @override
  int get hashCode =>
      Object.hash(id, label, description, icon, kind, blockType);
}

/// The default catalogue of the slash menu.
///
/// The block commands come first, then the AI commands, exactly as the
/// editor presents them.
List<LimpidSlashMenuItem> buildDefaultSlashMenuItems() =>
    const <LimpidSlashMenuItem>[
      LimpidSlashMenuItem(
        id: 'block.paragraph',
        label: 'Paragraphe',
        description: 'Un bloc de texte simple',
        icon: Icons.notes_outlined,
        kind: LimpidSlashMenuItemKind.block,
        blockType: BlockType.paragraph,
      ),
      LimpidSlashMenuItem(
        id: 'block.heading1',
        label: 'Titre 1',
        description: 'Le titre d’une partie',
        icon: Icons.title,
        kind: LimpidSlashMenuItemKind.block,
        blockType: BlockType.heading1,
      ),
      LimpidSlashMenuItem(
        id: 'block.heading2',
        label: 'Titre 2',
        description: 'Le titre d’un chapitre',
        icon: Icons.format_size,
        kind: LimpidSlashMenuItemKind.block,
        blockType: BlockType.heading2,
      ),
      LimpidSlashMenuItem(
        id: 'block.heading3',
        label: 'Titre 3',
        description: 'Le titre d’une scène',
        icon: Icons.format_size,
        kind: LimpidSlashMenuItemKind.block,
        blockType: BlockType.heading3,
      ),
      LimpidSlashMenuItem(
        id: 'block.list',
        label: 'Liste',
        description: 'Un élément de liste à puces',
        icon: Icons.format_list_bulleted,
        kind: LimpidSlashMenuItemKind.block,
        blockType: BlockType.listItem,
      ),
      LimpidSlashMenuItem(
        id: 'block.quote',
        label: 'Citation',
        description: 'Un bloc cité',
        icon: Icons.format_quote,
        kind: LimpidSlashMenuItemKind.block,
        blockType: BlockType.quote,
      ),
      LimpidSlashMenuItem(
        id: 'block.code',
        label: 'Code',
        description: 'Un bloc de code préformaté',
        icon: Icons.code,
        kind: LimpidSlashMenuItemKind.block,
        blockType: BlockType.code,
      ),
      LimpidSlashMenuItem(
        id: 'block.image',
        label: 'Image',
        description: 'Insérer une illustration',
        icon: Icons.image_outlined,
        kind: LimpidSlashMenuItemKind.block,
        blockType: BlockType.image,
      ),
      LimpidSlashMenuItem(
        id: 'block.sceneBreak',
        label: 'Séparation de scène',
        description: 'Marquer une rupture narrative',
        icon: Icons.horizontal_rule,
        kind: LimpidSlashMenuItemKind.block,
        blockType: BlockType.sceneBreak,
      ),
      LimpidSlashMenuItem(
        id: 'ai.continue',
        label: 'Continuer l’écriture',
        description: 'Poursuivre la scène à partir d’ici',
        icon: Icons.auto_awesome_outlined,
        kind: LimpidSlashMenuItemKind.ai,
      ),
      LimpidSlashMenuItem(
        id: 'ai.ask',
        label: 'Interroger le livre',
        description: 'Chercher dans le manuscrit',
        icon: Icons.help_outline,
        kind: LimpidSlashMenuItemKind.ai,
      ),
      LimpidSlashMenuItem(
        id: 'ai.summarize',
        label: 'Résumer la scène',
        description: 'Produire un résumé de la scène',
        icon: Icons.summarize_outlined,
        kind: LimpidSlashMenuItemKind.ai,
      ),
      LimpidSlashMenuItem(
        id: 'ai.inconsistency',
        label: 'Signaler une incohérence',
        description: 'Vérifier la cohérence de la scène',
        icon: Icons.warning_amber_rounded,
        kind: LimpidSlashMenuItemKind.ai,
      ),
    ];

/// The controller of the slash menu.
///
/// The controller owns the state of the menu — whether it is open, the
/// query typed after the slash and the highlighted entry — so that the
/// editor can drive it from its keyboard handler.
class LimpidSlashMenuController extends ChangeNotifier {
  /// Creates a slash menu controller.
  LimpidSlashMenuController({List<LimpidSlashMenuItem>? items})
    : _allItems = List<LimpidSlashMenuItem>.unmodifiable(
        items ?? buildDefaultSlashMenuItems(),
      );

  final List<LimpidSlashMenuItem> _allItems;
  bool _isOpen = false;
  String _query = '';
  int _selectedIndex = 0;

  /// Called when the user picks an entry.
  ValueChanged<LimpidSlashMenuItem>? onSelected;

  /// Every entry of the menu, filtered or not.
  List<LimpidSlashMenuItem> get allItems => _allItems;

  /// Whether the menu is open.
  bool get isOpen => _isOpen;

  /// The text typed after the slash.
  String get query => _query;

  /// The index of the highlighted entry.
  int get selectedIndex => _selectedIndex;

  /// The entries matching the current query.
  List<LimpidSlashMenuItem> get items {
    final String needle = _query.trim().toLowerCase();
    if (needle.isEmpty) {
      return _allItems;
    }
    return _allItems
        .where(
          (LimpidSlashMenuItem item) =>
              item.label.toLowerCase().contains(needle) ||
              item.id.toLowerCase().contains(needle),
        )
        .toList(growable: false);
  }

  /// The highlighted entry, `null` when the query matches nothing.
  LimpidSlashMenuItem? get selectedItem {
    final List<LimpidSlashMenuItem> matches = items;
    if (matches.isEmpty) {
      return null;
    }
    return matches[_selectedIndex.clamp(0, matches.length - 1)];
  }

  /// Opens the menu with the given [query].
  void open({String query = ''}) {
    _isOpen = true;
    _query = query;
    _selectedIndex = 0;
    notifyListeners();
  }

  /// Closes the menu.
  void close() {
    if (!_isOpen) {
      return;
    }
    _isOpen = false;
    _query = '';
    _selectedIndex = 0;
    notifyListeners();
  }

  /// Updates the query and resets the highlight.
  void updateQuery(String query) {
    if (_query == query) {
      return;
    }
    _query = query;
    _selectedIndex = 0;
    notifyListeners();
  }

  /// Moves the highlight by [delta] entries.
  void moveSelection(int delta) {
    final List<LimpidSlashMenuItem> matches = items;
    if (matches.isEmpty) {
      return;
    }
    final int count = matches.length;
    _selectedIndex = (_selectedIndex + delta) % count;
    if (_selectedIndex < 0) {
      _selectedIndex += count;
    }
    notifyListeners();
  }

  /// Highlights the entry at [index].
  void selectIndex(int index) {
    final List<LimpidSlashMenuItem> matches = items;
    if (matches.isEmpty || index < 0 || index >= matches.length) {
      return;
    }
    if (_selectedIndex == index) {
      return;
    }
    _selectedIndex = index;
    notifyListeners();
  }

  /// Handles a key event while the menu is open.
  ///
  /// Returns `true` when the event was consumed by the menu.
  bool handleKeyEvent(KeyEvent event) {
    if (!_isOpen || event is! KeyDownEvent) {
      return false;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      close();
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      moveSelection(1);
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      moveSelection(-1);
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter) {
      final LimpidSlashMenuItem? item = selectedItem;
      if (item == null) {
        return false;
      }
      onSelected?.call(item);
      return true;
    }
    return false;
  }
}
