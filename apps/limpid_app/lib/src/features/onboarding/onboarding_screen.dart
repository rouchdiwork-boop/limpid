import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:limpid_app/l10n/generated/app_localizations.dart';
import 'package:limpid_app/src/app/router.dart';
import 'package:limpid_app/src/domain/providers.dart';
import 'package:limpid_app/src/features/onboarding/onboarding_providers.dart';
import 'package:limpid_app/src/features/onboarding/onboarding_widgets.dart';
import 'package:limpid_app/src/features/projects/projects_providers.dart';
import 'package:limpid_app/src/features/settings/settings_providers.dart';
import 'package:limpid_design_system/limpid_design_system.dart';

/// The number of steps of the wizard.
const int onboardingStepCount = 4;

/// The width of the rail of steps, on the wide layouts.
const double onboardingRailWidth = 300;

/// The maximum width of the content of the wizard.
const double onboardingContentMaxWidth = 720;

/// The minimum width of a card of model.
const double onboardingTemplateMinWidth = 220;

/// The aspect ratio of a card of model.
const double onboardingTemplateAspectRatio = 1.05;

/// The width from which the rail of steps appears.
const double onboardingWideLayoutBreakpoint = 900;

/// The onboarding wizard.
///
/// Four steps, one decision per screen: the model of the book, its title and
/// the rhythm of the author. The last step creates the project for real,
/// through the manuscript repository.
class OnboardingScreen extends ConsumerStatefulWidget {
  /// Creates the wizard.
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  int _step = 0;
  bool _isCreating = false;
  late final TextEditingController _titleController;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(
      text: ref.read(onboardingDraftProvider).title,
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations strings = AppLocalizations.of(context);
    final LimpidThemeScope scope = context.limpid;
    final OnboardingDraft draft = ref.watch(onboardingDraftProvider);

    return Scaffold(
      body: Row(
        children: <Widget>[
          if (MediaQuery.sizeOf(context).width >=
              onboardingWideLayoutBreakpoint)
            SizedBox(
              width: onboardingRailWidth,
              child: OnboardingStepsRail(
                step: _step,
                stepCount: onboardingStepCount,
                labels: <String>[
                  strings.onboardingTitle,
                  strings.onboardingProjectTitle,
                  strings.onboardingGoalTitle,
                  strings.onboardingCreateProject,
                ],
              ),
            ),
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(scope.spacing.space40),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: onboardingContentMaxWidth,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        strings.onboardingStepOf(
                          _step + 1,
                          onboardingStepCount,
                        ),
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: scope.colors.fgSubtle,
                        ),
                      ),
                    ),
                    SizedBox(height: scope.spacing.space12),
                    Text(
                      _stepTitle(strings),
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(color: scope.colors.fgDefault),
                    ),
                    SizedBox(height: scope.spacing.space8),
                    Text(
                      _stepSubtitle(strings),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: scope.colors.fgMuted,
                      ),
                    ),
                    SizedBox(height: scope.spacing.space24),
                    _buildStep(strings, draft),
                    SizedBox(height: scope.spacing.space32),
                    Row(
                      children: <Widget>[
                        if (_step > 0)
                          LimpidButton(
                            label: strings.actionCancel,
                            variant: LimpidButtonVariant.ghost,
                            onPressed: () => setState(() => _step--),
                          ),
                        const Spacer(),
                        LimpidButton(
                          label: _step == onboardingStepCount - 1
                              ? strings.onboardingCreateProject
                              : strings.onboardingNext,
                          loading: _isCreating,
                          onPressed: _canContinue ? _onPrimaryAction : null,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool get _canContinue =>
      _step != 1 || _titleController.text.trim().isNotEmpty;

  Widget _buildStep(AppLocalizations strings, OnboardingDraft draft) {
    return switch (_step) {
      0 => _buildTemplateStep(strings, draft),
      1 => _buildTitleStep(),
      2 => _buildGoalStep(strings, draft),
      _ => _buildRecap(strings, draft),
    };
  }

  Widget _buildTemplateStep(AppLocalizations strings, OnboardingDraft draft) {
    final LimpidThemeScope scope = context.limpid;

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final int columns = (constraints.maxWidth / onboardingTemplateMinWidth)
            .floor()
            .clamp(2, 3);
        return GridView.count(
          crossAxisCount: columns,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: scope.spacing.space12,
          crossAxisSpacing: scope.spacing.space12,
          childAspectRatio: onboardingTemplateAspectRatio,
          children: <Widget>[
            for (final ProjectTemplate template in ProjectTemplate.values)
              OnboardingTemplateCard(
                title: _templateTitle(strings, template),
                hint: _templateHint(strings, template),
                isSelected: template == draft.template,
                onTap: () => ref
                    .read(onboardingDraftProvider.notifier)
                    .selectTemplate(template),
              ),
          ],
        );
      },
    );
  }

  Widget _buildTitleStep() {
    final AppLocalizations strings = AppLocalizations.of(context);

    return LimpidTextField(
      controller: _titleController,
      label: strings.onboardingProjectTitle,
      textCapitalization: TextCapitalization.sentences,
      textInputAction: TextInputAction.next,
      onChanged: (String value) {
        ref.read(onboardingDraftProvider.notifier).setTitle(value);
        setState(() {});
      },
      onSubmitted: (String value) {
        if (_canContinue) {
          _goToNextStep();
        }
      },
    );
  }

  Widget _buildGoalStep(AppLocalizations strings, OnboardingDraft draft) {
    final LimpidThemeScope scope = context.limpid;

    return Column(
      children: <Widget>[
        for (final int goal in dailyWordGoalChoices)
          Padding(
            padding: EdgeInsets.only(bottom: scope.spacing.space8),
            child: OnboardingGoalCard(
              title: _goalTitle(strings, goal),
              words: strings.onboardingGoalWords(goal),
              isSelected: goal == draft.dailyGoalWords,
              onTap: () =>
                  ref.read(onboardingDraftProvider.notifier).setDailyGoal(goal),
            ),
          ),
      ],
    );
  }

  Widget _buildRecap(AppLocalizations strings, OnboardingDraft draft) {
    return LimpidCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          LimpidListTile(
            title: _templateTitle(strings, draft.template),
            subtitle: _templateHint(strings, draft.template),
            leading: const Icon(LimpidIcons.book),
          ),
          LimpidListTile(
            title: strings.onboardingProjectTitle,
            subtitle: draft.title,
            leading: const Icon(LimpidIcons.edit),
          ),
          LimpidListTile(
            title: strings.onboardingGoalTitle,
            subtitle: strings.onboardingGoalWords(draft.dailyGoalWords),
            leading: const Icon(LimpidIcons.target),
          ),
        ],
      ),
    );
  }

  void _onPrimaryAction() {
    if (_step == onboardingStepCount - 1) {
      unawaited(_createProject());
      return;
    }
    _goToNextStep();
  }

  void _goToNextStep() {
    if (_step >= onboardingStepCount - 1) {
      return;
    }
    setState(() => _step++);
  }

  Future<void> _createProject() async {
    final AppLocalizations strings = AppLocalizations.of(context);
    final OnboardingDraft draft = ref.read(onboardingDraftProvider);
    setState(() => _isCreating = true);
    try {
      await ref
          .read(manuscriptRepositoryProvider)
          .createProject(
            title: draft.title,
            synopsis: _synopsis(strings, draft.template),
          );
      ref.read(dailyWordGoalProvider.notifier).set(draft.dailyGoalWords);
      // La bibliothèque est conservée en mémoire : sans cette invalidation,
      // le projet que l'auteur vient de créer n'apparaîtrait pas dans la
      // bibliothèque.
      ref.invalidate(libraryProvider);
      if (!mounted) {
        return;
      }
      context.go(AppRoutes.dashboard);
    } on ServiceUnavailableException {
      _showFailure(strings.demoModeMessage);
    } on Exception {
      _showFailure(strings.errorGeneric);
    } finally {
      if (mounted) {
        setState(() => _isCreating = false);
      }
    }
  }

  void _showFailure(String message) {
    if (!mounted) {
      return;
    }
    LimpidSnackbar.show(
      context,
      message: message,
      variant: LimpidStatusVariant.danger,
    );
  }

  String _synopsis(AppLocalizations strings, ProjectTemplate template) {
    final String name = _templateTitle(strings, template);
    final String hint = _templateHint(strings, template);
    return '$name — $hint';
  }

  String _stepTitle(AppLocalizations strings) => switch (_step) {
    0 => strings.onboardingTitle,
    1 => strings.onboardingProjectTitle,
    2 => strings.onboardingGoalTitle,
    _ => strings.onboardingTitle,
  };

  String _stepSubtitle(AppLocalizations strings) => switch (_step) {
    0 => strings.onboardingSubtitle,
    1 => strings.onboardingSubtitle,
    2 => strings.onboardingGoalSubtitle,
    _ => strings.onboardingSubtitle,
  };

  String _templateTitle(AppLocalizations strings, ProjectTemplate template) =>
      switch (template) {
        ProjectTemplate.novel => strings.onboardingTemplateNovel,
        ProjectTemplate.shortForm => strings.onboardingTemplateShort,
        ProjectTemplate.essay => strings.onboardingTemplateEssay,
        ProjectTemplate.poetry => strings.onboardingTemplatePoetry,
        ProjectTemplate.technical => strings.onboardingTemplateTechnical,
        ProjectTemplate.import => strings.onboardingTemplateImport,
      };

  String _templateHint(AppLocalizations strings, ProjectTemplate template) =>
      switch (template) {
        ProjectTemplate.novel => strings.onboardingTemplateNovelHint,
        ProjectTemplate.shortForm => strings.onboardingTemplateShortHint,
        ProjectTemplate.essay => strings.onboardingTemplateEssayHint,
        ProjectTemplate.poetry => strings.onboardingTemplatePoetryHint,
        ProjectTemplate.technical => strings.onboardingTemplateTechnicalHint,
        ProjectTemplate.import => strings.onboardingTemplateImportHint,
      };

  String _goalTitle(AppLocalizations strings, int goal) => switch (goal) {
    lightDailyWordGoal => strings.onboardingGoalLight,
    regularDailyWordGoal => strings.onboardingGoalRegular,
    _ => strings.onboardingGoalIntense,
  };
}
