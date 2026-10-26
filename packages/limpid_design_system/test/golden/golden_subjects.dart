import 'package:flutter/material.dart';
import 'package:limpid_design_system/limpid_design_system.dart';

import 'golden_harness.dart';

/// Les widgets du design system couverts par les temoins.
///
/// Chaque widget est couvert dans les quatre themes. La liste est la preuve
/// que le design system livre au moins trente widgets couverts.
final List<GoldenSubject> kGoldenSubjects = <GoldenSubject>[
  GoldenSubject(
    name: 'LimpidAccordion',
    build: (Key key) => LimpidAccordion(
      key: key,
      title: 'Chapitre premier',
      subtitle: 'Le sel',
      isExpanded: true,
      child: const Text('Le texte du chapitre.'),
    ),
  ),
  GoldenSubject(
    name: 'LimpidAiSuggestionDiff',
    build: (Key key) => LimpidAiSuggestionDiff(
      key: key,
      original: 'Le mur est blanc.',
      suggestion: 'Le mur est couvert de sel.',
      reason: 'Le sel revient au chapitre II',
      onAccept: () {},
      onReject: () {},
    ),
  ),
  GoldenSubject(
    name: 'LimpidAvatar',
    build: (Key key) => LimpidAvatar(key: key, label: 'Ines Barreau'),
  ),
  GoldenSubject(
    name: 'LimpidBadge',
    build: (Key key) => LimpidBadge(
      key: key,
      label: 'En cours',
      variant: LimpidStatusVariant.success,
    ),
  ),
  GoldenSubject(
    name: 'LimpidBanner',
    build: (Key key) => LimpidBanner(
      key: key,
      variant: LimpidStatusVariant.warning,
      title: 'Connexion instable',
      message: 'Le chapitre sera enregistre plus tard.',
    ),
  ),
  GoldenSubject(
    name: 'LimpidBottomSheet',
    build: (Key key) => LimpidBottomSheet(
      key: key,
      title: 'Options du chapitre',
      child: const Text('Le contenu de la feuille.'),
    ),
  ),
  GoldenSubject(
    name: 'LimpidBreadcrumb',
    build: (Key key) => LimpidBreadcrumb(
      key: key,
      items: const <LimpidBreadcrumbItem>[
        LimpidBreadcrumbItem(label: 'Bibliotheque'),
        LimpidBreadcrumbItem(label: 'Les Heures de Cendre'),
      ],
    ),
  ),
  GoldenSubject(
    name: 'LimpidButton',
    build: (Key key) =>
        LimpidButton(key: key, label: 'Enregistrer', onPressed: _ignore),
  ),
  GoldenSubject(
    name: 'LimpidCard',
    build: (Key key) => LimpidCard(
      key: key,
      title: 'Les Heures de Cendre',
      subtitle: 'Un roman',
      child: const Text('Le contenu de la carte.'),
    ),
  ),
  GoldenSubject(
    name: 'LimpidCharacterAvatar',
    build: (Key key) => LimpidCharacterAvatar(
      key: key,
      name: 'Ines Barreau',
      initials: 'IB',
      role: 'Archiviste',
      isOnline: true,
    ),
  ),
  GoldenSubject(
    name: 'LimpidCheckbox',
    build: (Key key) => LimpidCheckbox(
      key: key,
      value: true,
      onChanged: _ignoreBoolOrNull,
      label: 'Chapitre termine',
    ),
  ),
  GoldenSubject(
    name: 'LimpidChip',
    build: (Key key) =>
        LimpidChip(key: key, label: 'Polar', isSelected: true, onTap: _ignore),
  ),
  GoldenSubject(
    name: 'LimpidCircularProgress',
    build: (Key key) => LimpidCircularProgress(key: key, value: 0.4),
  ),
  GoldenSubject(
    name: 'LimpidCombobox',
    build: (Key key) => LimpidCombobox<String>(
      key: key,
      label: 'Genre',
      hint: 'Choisir un genre',
      items: const <LimpidSelectItem<String>>[
        LimpidSelectItem<String>(value: 'polar', label: 'Polar'),
        LimpidSelectItem<String>(value: 'roman', label: 'Roman'),
      ],
      onSelected: _ignoreString,
    ),
  ),
  GoldenSubject(
    name: 'LimpidCommandPalette',
    build: (Key key) => LimpidCommandPalette(
      key: key,
      hint: 'Rechercher une commande',
      commands: const <LimpidCommand>[
        LimpidCommand(
          label: 'Enregistrer le chapitre',
          value: 'save',
          category: 'Fichier',
          shortcut: 'Ctrl+S',
        ),
      ],
      onSelected: _ignoreCommand,
    ),
  ),
  GoldenSubject(
    name: 'LimpidCommandPaletteOverlay',
    build: (Key key) => LimpidCommandPaletteOverlay(
      key: key,
      commands: const <LimpidCommand>[
        LimpidCommand(label: 'Enregistrer le chapitre', value: 'save'),
      ],
      onSelected: _ignoreCommand,
    ),
  ),
  GoldenSubject(
    name: 'LimpidCommentThread',
    build: (Key key) => LimpidCommentThread(
      key: key,
      authorName: 'Ines Barreau',
      text: 'Ce sel est deja pose au chapitre I',
      timestamp: 'Il y a deux heures',
      onReply: _ignore,
    ),
  ),
  GoldenSubject(
    name: 'LimpidCoverPreview',
    build: (Key key) => LimpidCoverPreview(
      key: key,
      title: 'Les Heures de Cendre',
      author: 'Ines Barreau',
    ),
  ),
  GoldenSubject(
    name: 'LimpidDataTable',
    build: (Key key) => LimpidDataTable(
      key: key,
      columns: const <LimpidDataColumn>[
        LimpidDataColumn(title: 'Chapitre'),
        LimpidDataColumn(title: 'Mots', isNumeric: true),
      ],
      rows: const <LimpidDataRow>[
        LimpidDataRow(
          key: 'c1',
          cells: <Widget>[Text('Le sel'), Text('4 200')],
        ),
      ],
    ),
  ),
  GoldenSubject(
    name: 'LimpidDataTableEmpty',
    build: (Key key) => LimpidDataTableEmpty(
      key: key,
      message: 'Aucun chapitre dans ce livre.',
    ),
  ),
  GoldenSubject(
    name: 'LimpidDialog',
    build: (Key key) => LimpidDialog(
      key: key,
      title: 'Supprimer le chapitre',
      actions: const <Widget>[LimpidButton(label: 'Annuler')],
      child: const Text('Cette action est definitive.'),
    ),
  ),
  GoldenSubject(
    name: 'LimpidDrawer',
    build: (Key key) =>
        LimpidDrawer(key: key, child: const Text('Le contenu du tiroir.')),
  ),
  GoldenSubject(
    name: 'LimpidEmptyState',
    build: (Key key) => LimpidEmptyState(
      key: key,
      title: 'Aucun manuscrit',
      message: 'Ecrivez votre premier chapitre.',
    ),
  ),
  GoldenSubject(
    name: 'LimpidIconButton',
    build: (Key key) => LimpidIconButton(
      key: key,
      icon: Icons.delete_outline,
      tooltip: 'Supprimer',
    ),
  ),
  GoldenSubject(
    name: 'LimpidLinearProgress',
    build: (Key key) =>
        LimpidLinearProgress(key: key, value: 0.4, label: 'Progression'),
  ),
  GoldenSubject(
    name: 'LimpidListTile',
    build: (Key key) => LimpidListTile(
      key: key,
      title: 'Les Heures de Cendre',
      subtitle: 'Ecriture',
      onTap: _ignore,
    ),
  ),
  GoldenSubject(
    name: 'LimpidMenu',
    build: (Key key) => LimpidMenu(
      key: key,
      label: 'Actions',
      items: const <LimpidMenuItem>[
        LimpidMenuItem(label: 'Dupliquer', value: 'duplicate'),
        LimpidMenuItem(
          label: 'Supprimer',
          value: 'delete',
          isDestructive: true,
        ),
      ],
      onSelected: _ignoreMenuItem,
    ),
  ),
  GoldenSubject(
    name: 'LimpidOutlineRow',
    build: (Key key) => LimpidOutlineRow(
      key: key,
      title: 'Chapitre premier',
      depth: 1,
      wordCount: 4200,
      hasChildren: true,
      isActive: true,
    ),
  ),
  GoldenSubject(
    name: 'LimpidPagination',
    build: (Key key) => LimpidPagination(
      key: key,
      page: 2,
      pageCount: 5,
      onPageChanged: _ignoreInt,
    ),
  ),
  GoldenSubject(
    name: 'LimpidRadio',
    build: (Key key) => LimpidRadio<String>(
      key: key,
      value: 'draft',
      groupValue: 'draft',
      onChanged: _ignoreStringOrNull,
      label: 'Brouillon',
    ),
  ),
  GoldenSubject(
    name: 'LimpidRadioGroup',
    build: (Key key) => LimpidRadioGroup<String>(
      key: key,
      groupValue: 'draft',
      onChanged: _ignoreStringOrNull,
      child: const LimpidRadio<String>(
        value: 'draft',
        groupValue: 'draft',
        onChanged: _ignoreStringOrNull,
        label: 'Brouillon',
      ),
    ),
  ),
  GoldenSubject(
    name: 'LimpidSceneCard',
    build: (Key key) => LimpidSceneCard(
      key: key,
      title: 'La plage a maree basse',
      excerpt: 'Le sel qui vient des murs recouvre les vitres.',
      wordCount: 1200,
      status: LimpidStatusVariant.success,
      statusLabel: 'En cours',
    ),
  ),
  GoldenSubject(
    name: 'LimpidSearchField',
    build: (Key key) =>
        LimpidSearchField(key: key, hint: 'Rechercher un chapitre'),
  ),
  GoldenSubject(
    name: 'LimpidSegmentedControl',
    build: (Key key) => LimpidSegmentedControl<String>(
      key: key,
      segments: const <LimpidSegment<String>>[
        LimpidSegment<String>(value: 'grid', label: 'Grille'),
        LimpidSegment<String>(value: 'list', label: 'Liste'),
      ],
      selected: const <String>{'grid'},
      onSelectionChanged: _ignoreStringSet,
    ),
  ),
  GoldenSubject(
    name: 'LimpidSelect',
    build: (Key key) => LimpidSelect<String>(
      key: key,
      label: 'Statut',
      hint: 'Choisir un statut',
      items: const <LimpidSelectItem<String>>[
        LimpidSelectItem<String>(value: 'draft', label: 'Brouillon'),
        LimpidSelectItem<String>(value: 'writing', label: 'En ecriture'),
      ],
      value: 'draft',
      onChanged: _ignoreStringOrNull,
    ),
  ),
  GoldenSubject(
    name: 'LimpidSlider',
    build: (Key key) => LimpidSlider(
      key: key,
      value: 0.4,
      onChanged: _ignoreDouble,
      label: 'Progression',
      valueLabel: '40 %',
    ),
  ),
  GoldenSubject(
    name: 'LimpidSnackbar',
    build: (Key key) => LimpidSnackbar(
      key: key,
      message: 'Le chapitre est enregistre.',
      variant: LimpidStatusVariant.success,
    ),
  ),
  GoldenSubject(
    name: 'LimpidSpinner',
    build: (Key key) => LimpidSpinner(key: key, size: LimpidSpinnerSize.medium),
  ),
  GoldenSubject(
    name: 'LimpidStatCard',
    build: (Key key) => LimpidStatCard(
      key: key,
      label: 'Mots aujourd hui',
      value: '1 200',
      delta: '+12 %',
      direction: LimpidStatDirection.up,
    ),
  ),
  GoldenSubject(
    name: 'LimpidStepper',
    build: (Key key) => LimpidStepper(
      key: key,
      currentIndex: 1,
      steps: const <LimpidStepperStep>[
        LimpidStepperStep(label: 'Plan', isComplete: true),
        LimpidStepperStep(label: 'Ecriture'),
        LimpidStepperStep(label: 'Relecture'),
      ],
    ),
  ),
  GoldenSubject(
    name: 'LimpidSwitch',
    build: (Key key) => LimpidSwitch(
      key: key,
      value: true,
      onChanged: _ignoreBool,
      label: 'Synchronisation',
    ),
  ),
  GoldenSubject(
    name: 'LimpidSyncStatusPill',
    build: (Key key) =>
        LimpidSyncStatusPill(key: key, status: LimpidSyncStatus.synced),
  ),
  GoldenSubject(
    name: 'LimpidTabs',
    build: (Key key) => _GoldenTabs(tabKey: key),
  ),
  GoldenSubject(
    name: 'LimpidTag',
    build: (Key key) => LimpidTag(
      key: key,
      label: 'Manuscrit',
      variant: LimpidStatusVariant.info,
    ),
  ),
  GoldenSubject(
    name: 'LimpidTextArea',
    build: (Key key) => LimpidTextArea(
      key: key,
      label: 'Synopsis',
      hint: 'Quelques lignes sur le livre.',
    ),
  ),
  GoldenSubject(
    name: 'LimpidTextField',
    build: (Key key) =>
        LimpidTextField(key: key, label: 'Titre', hint: 'Les Heures de Cendre'),
  ),
  GoldenSubject(
    name: 'LimpidTooltip',
    build: (Key key) => LimpidTooltip(
      key: key,
      message: 'Enregistrer le chapitre',
      child: const Icon(Icons.save_outlined),
    ),
  ),
  GoldenSubject(
    name: 'LimpidWordCountMeter',
    build: (Key key) => LimpidWordCountMeter(
      key: key,
      wordCount: 1200,
      goal: 2000,
      label: 'Objectif du jour',
    ),
  ),
];

/// Ignore une action.
void _ignore() {}

/// Ignore une selection de booleen.
void _ignoreBool(bool _) {}

/// Ignore une selection de booleen nullable.
void _ignoreBoolOrNull(bool? _) {}

/// Ignore une selection de nombre.
void _ignoreDouble(double _) {}

/// Ignore une selection d'entier.
void _ignoreInt(int _) {}

/// Ignore une selection de chaine.
void _ignoreString(String _) {}

/// Ignore une selection de chaine nullable.
void _ignoreStringOrNull(String? _) {}

/// Ignore une selection de plusieurs chaines.
void _ignoreStringSet(Set<String> _) {}

/// Ignore le choix d'une commande.
void _ignoreCommand(LimpidCommand _) {}

/// Ignore le choix d'un entree de menu.
void _ignoreMenuItem(LimpidMenuItem _) {}

/// La barre d'onglets du temoin.
///
/// Le widget possede son controleur : il le libere quand il quitte l'ecran.
/// La cle portee par la barre elle-meme permet de retrouver le widget sous
/// test dans l'arbre rendu.
class _GoldenTabs extends StatefulWidget {
  /// Cree la barre d'onglets.
  const _GoldenTabs({required this.tabKey});

  /// La cle de la barre d'onglets.
  final Key tabKey;

  @override
  State<_GoldenTabs> createState() => _GoldenTabsState();
}

/// L'etat de la barre d'onglets du temoin.
class _GoldenTabsState extends State<_GoldenTabs>
    with SingleTickerProviderStateMixin {
  late final TabController _controller = TabController(length: 3, vsync: this);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LimpidTabs(
      key: widget.tabKey,
      tabs: const <LimpidTab>[
        LimpidTab(label: 'Plan'),
        LimpidTab(label: 'Manuscrit'),
        LimpidTab(label: 'Relecture'),
      ],
      controller: _controller,
    );
  }
}
