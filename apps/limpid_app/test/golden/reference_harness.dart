import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:limpid_app/l10n/generated/app_localizations.dart';
import 'package:limpid_app/src/app/theme_controller.dart';
import 'package:limpid_app/src/auth/supabase_auth_repository.dart';
import 'package:limpid_app/src/domain/providers.dart';
import 'package:limpid_app/src/domain/repositories.dart';
import 'package:limpid_app/src/domain/revision_repository.dart';
import 'package:limpid_app/src/features/dashboard/dashboard_providers.dart';
import 'package:limpid_app/src/features/dashboard/dashboard_screen.dart';
import 'package:limpid_app/src/features/library/library_screen.dart';
import 'package:limpid_app/src/features/projects/projects_providers.dart';
import 'package:limpid_app/src/features/revision/revision_models.dart';
import 'package:limpid_app/src/features/revision/revision_panel.dart';
import 'package:limpid_app/src/features/revision/revision_providers.dart';
import 'package:limpid_app/src/features/settings/settings_screen.dart';
import 'package:limpid_app/src/features/writing/writing_screen.dart';
import 'package:limpid_core/limpid_core.dart';
import 'package:limpid_design_system/golden.dart';
import 'package:limpid_design_system/limpid_design_system.dart';

import '../editor/fakes.dart' as editor;
import '../features/projects/fakes.dart' as projects;
import '../features/revision/fakes.dart';
import '../onboarding/fakes.dart' as onboarding;

/// Les quatre themes couverts par les temoins des ecrans.
const List<LimpidThemeVariant> kReferenceVariants = <LimpidThemeVariant>[
  LimpidThemeVariant.paper,
  LimpidThemeVariant.sepia,
  LimpidThemeVariant.night,
  LimpidThemeVariant.contrast,
];

/// Les noms des quatre themes, dans le meme ordre.
List<String> get kReferenceVariantNames => kReferenceVariants
    .map((LimpidThemeVariant variant) => variant.name)
    .toList(growable: false);

/// Le jour que les ecrans lisent.
final DateTime kReferenceToday = DateTime.utc(2026, 10, 25);

/// La cle de la frontiere qui porte l'image du temoin.
const Key kReferenceBoundaryKey = Key('limpid-reference-boundary');

/// Un ecran de reference de l'application.
///
/// Les ecrans de reference sont ceux que le critere du lot 0 nomme : le
/// tableau de bord, la bibliotheque, l'ecran d'ecriture, la relecture et les
/// reglages.
@immutable
class ReferenceScreen {
  /// Cree un ecran de reference.
  const ReferenceScreen({
    required this.name,
    required this.surface,
    required this.build,
    required this.finder,
  });

  /// Le nom de l'ecran : il donne le nom du fichier d'attente.
  final String name;

  /// La surface sur laquelle l'ecran est rendu.
  final Size surface;

  /// Construit l'ecran dans le theme demande.
  final Widget Function(LimpidThemeVariant variant) build;

  /// Le localisateur de l'ecran dans l'arbre rendu.
  final Finder Function() finder;
}

/// Les ecrans de reference, dans l'ordre du critere.
final List<ReferenceScreen> kReferenceScreens = <ReferenceScreen>[
  ReferenceScreen(
    name: 'dashboard',
    surface: const Size(1440, 1100),
    build: (LimpidThemeVariant variant) =>
        _app(variant, child: const _LibraryScope(child: DashboardScreen())),
    finder: () => find.byType(DashboardScreen),
  ),
  ReferenceScreen(
    name: 'library',
    surface: const Size(1440, 1100),
    build: (LimpidThemeVariant variant) =>
        _app(variant, child: const _LibraryScope(child: LibraryScreen())),
    finder: () => find.byType(LibraryScreen),
  ),
  ReferenceScreen(
    name: 'writing',
    surface: const Size(1440, 1100),
    build: (LimpidThemeVariant variant) => _app(
      variant,
      child: ProviderScope(
        overrides: [
          syncRepositoryProvider.overrideWithValue(editor.FakeSyncRepository()),
          aiRepositoryProvider.overrideWithValue(editor.FakeAiRepository()),
          revisionRepositoryProvider.overrideWithValue(_revisionRepository()),
          authorIdProvider.overrideWithValue(kRevisionAuthor),
        ],
        child: const _LibraryScope(
          child: WritingScreen(projectId: kRevisionProjectId),
        ),
      ),
    ),
    finder: () => find.byType(WritingScreen),
  ),
  ReferenceScreen(
    name: 'revision',
    surface: const Size(1440, 1100),
    build: (LimpidThemeVariant variant) => _app(
      variant,
      child: ProviderScope(
        overrides: [
          revisionRepositoryProvider.overrideWithValue(_revisionRepository()),
        ],
        child: Scaffold(
          body: RevisionPanel(
            projectId: kRevisionProjectId,
            threads: _revisionThreads(),
            members: _revisionMembers(),
            currentAuthorId: kRevisionAuthor,
          ),
        ),
      ),
    ),
    finder: () => find.byType(RevisionPanel),
  ),
  ReferenceScreen(
    name: 'settings',
    surface: const Size(1440, 2000),
    build: (LimpidThemeVariant variant) => _app(
      variant,
      child: ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(
            onboarding.FakeAuthRepository(),
          ),
          manuscriptRepositoryProvider.overrideWithValue(
            projects.FakeManuscriptRepository(),
          ),
          themePreferenceStoreProvider.overrideWithValue(
            MemoryThemePreferenceStore(variant),
          ),
          syncRepositoryProvider.overrideWithValue(editor.FakeSyncRepository()),
        ],
        child: const SettingsScreen(),
      ),
    ),
    finder: () => find.byType(SettingsScreen),
  ),
];

/// L'application de test : le theme choisi, les chaines en francais.
Widget _app(LimpidThemeVariant variant, {required Widget child}) {
  return MaterialApp(
    theme: LimpidTheme.of(variant),
    themeMode: variant.isDark ? ThemeMode.dark : ThemeMode.light,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    // Les textes des ecrans sont asserts en francais : la locale est
    // posee, sinon le poste de test choisirait l'anglais.
    locale: const Locale('fr'),
    home: RepaintBoundary(key: kReferenceBoundaryKey, child: child),
  );
}

/// Les doublures de la bibliotheque.
class _LibraryScope extends StatelessWidget {
  /// Cree le contour de la bibliotheque.
  const _LibraryScope({required this.child});

  /// L'ecran rendu.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      overrides: [
        manuscriptRepositoryProvider.overrideWithValue(_manuscripts()),
        preferencesRepositoryProvider.overrideWithValue(
          projects.FakePreferencesRepository(goal: 1500, streak: 7),
        ),
        todayProvider.overrideWithValue(kReferenceToday),
        authorNameProvider.overrideWithValue('Ines Barreau'),
      ],
      child: child,
    );
  }
}

/// La bibliotheque du test.
projects.FakeManuscriptRepository _manuscripts() {
  return projects.FakeManuscriptRepository(
    projects: <Project>[
      projects.fakeProject(
        id: 'heures',
        title: 'Les Heures de Cendre',
        status: ManuscriptStatus.writing,
        chapterIds: <String>['c1'],
      ),
      projects.fakeProject(
        id: 'dune',
        title: 'Carnets de dune',
        status: ManuscriptStatus.draft,
      ),
    ],
    chapters: <String, List<Chapter>>{
      'heures': <Chapter>[
        projects.fakeChapter(
          id: 'c1',
          targetWordCount: 6000,
          sceneIds: <String>['s1'],
        ),
      ],
    },
    scenes: <String, List<Scene>>{
      'c1': <Scene>[
        projects.fakeScene(
          id: 's1',
          chapterId: 'c1',
          wordCount: 120,
          updatedAt: kReferenceToday,
        ),
      ],
    },
    sessions: <WritingSession>[
      WritingSession(day: kReferenceToday, words: 120, minutes: 12),
      WritingSession(
        day: kReferenceToday.subtract(const Duration(days: 1)),
        words: 90,
        minutes: 9,
      ),
    ],
  );
}

/// Le depot des discussions du test.
FakeRevisionRepository _revisionRepository() {
  return FakeRevisionRepository(
    threads: <CommentThread>[_thread()],
    members: _revisionMembers(),
  );
}

/// La discussion du test.
CommentThread _thread() {
  return fakeThread(
    id: 'fil-1',
    markId: 'marque-1',
    comments: <Comment>[
      fakeComment(
        id: 'message-1',
        threadId: 'fil-1',
        authorId: 'auteur-2',
        body: 'Ce sel est deja pose au chapitre I',
      ),
    ],
  );
}

/// Les discussions vues par le panneau de relecture.
List<RevisionThread> _revisionThreads() => <RevisionThread>[
  fakeRevisionThread(thread: _thread()),
];

/// Les collaborateurs du livre.
List<ProjectMember> _revisionMembers() => <ProjectMember>[
  fakeMember(
    id: 'auteur-1',
    displayName: 'Ines Barreau',
    role: ProjectRole.owner,
  ),
  fakeMember(
    id: 'auteur-2',
    displayName: 'Thomas Derval',
    role: ProjectRole.betaReader,
  ),
];

/// Rends l'ecran de reference et rend sa description structurelle.
Future<GoldenDescription> describeReferenceScreen(
  WidgetTester tester,
  ReferenceScreen screen,
  LimpidThemeVariant variant,
) async {
  tester.view.physicalSize = screen.surface;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(screen.build(variant));
  // L'ecran lit ses donnees : plusieurs images sont necessaires pour que
  // les etats asynchrones se resolvent. `pumpAndSettle` ne convient pas :
  // les indicateurs d'activite ne s'arretent jamais.
  for (int frame = 0; frame < 6; frame++) {
    await tester.pump(const Duration(milliseconds: 20));
  }

  return GoldenExtractor.describe(tester.element(screen.finder()));
}

/// Les textes tronques d'un rendu.
///
/// Un texte **dur** tronque est un texte coupe sans points de suspension :
/// le widget l'a coupe, l'auteur ne l'a pas voulu. C'est un defaut.
///
/// Un texte **doux** tronque est un texte que le widget a decide de tronquer
/// — la couverture d'un livre, l'etiquette d'un bouton — : la troncature est
/// voulue, elle fait partie du rendu.
typedef TruncatedTexts = ({List<String> hard, List<String> soft});

/// Les textes tronques de l'ecran rendu.
TruncatedTexts truncatedTextsOf(WidgetTester tester) {
  final List<String> hard = <String>[];
  final List<String> soft = <String>[];
  final Set<RenderParagraph> known = <RenderParagraph>{};

  for (final Element element in find.byType(Text).evaluate()) {
    final Text text = element.widget as Text;
    final RenderObject? render = element.findRenderObject();
    if (render is! RenderParagraph) {
      continue;
    }
    known.add(render);
    if (!render.didExceedMaxLines) {
      continue;
    }
    final String label = text.data ?? text.textSpan?.toPlainText() ?? '';
    if (text.overflow == TextOverflow.ellipsis) {
      soft.add(label);
    } else {
      hard.add(label);
    }
  }

  // Les paragraphes qui ne viennent pas d'un `Text` — une icone, un
  // paragraphe brut — ne sont jamais tronques volontairement.
  for (final RenderParagraph paragraph
      in tester.allRenderObjects.whereType<RenderParagraph>()) {
    if (known.contains(paragraph) || !paragraph.didExceedMaxLines) {
      continue;
    }
    hard.add(paragraph.text.toPlainText());
  }

  return (hard: hard, soft: soft);
}

/// Verifie que l'ecran rend **complet**.
///
/// « Sans retouche » veut dire : pas de debordement, pas de texte coupe.
/// Un debordement de `Flex` est une erreur de rendu que le testeur
/// remonte ; un texte coupe sans points de suspension est un contenu perdu.
void expectScreenRendersCompletely(
  WidgetTester tester,
  ReferenceScreen screen,
) {
  expect(
    tester.takeException(),
    isNull,
    reason: 'L\'ecran « ${screen.name} » a deborde dans le theme.',
  );

  final Size size = tester.getSize(screen.finder());
  expect(
    size.width,
    lessThanOrEqualTo(screen.surface.width),
    reason: 'L\'ecran « ${screen.name} » deborde en largeur.',
  );
  expect(
    size.height,
    lessThanOrEqualTo(screen.surface.height),
    reason: 'L\'ecran « ${screen.name} » deborde en hauteur.',
  );

  final TruncatedTexts truncated = truncatedTextsOf(tester);
  expect(
    truncated.hard,
    isEmpty,
    reason:
        'Les textes suivants sont coupes dans l\'ecran « ${screen.name} » : '
        '${truncated.hard.join(' | ')}',
  );
}

/// Compare le rendu d'un ecran a son attente structurelle.
GoldenWitness checkReferenceScreen({
  required ReferenceScreen screen,
  required LimpidThemeVariant variant,
  required List<String> actual,
  required bool isUpdating,
}) {
  return GoldenWitnessTool.check(
    file: File('test/expectations/${screen.name}.txt'),
    title: screen.name,
    section: variant.name,
    order: kReferenceVariantNames,
    actual: actual,
    isUpdating: isUpdating,
    regenerateCommand: 'cd apps/limpid_app && flutter test --update-goldens',
  );
}
