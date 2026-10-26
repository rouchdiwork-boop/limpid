import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:limpid_app/src/features/settings/settings_providers.dart';

/// The models offered when the author creates their first project.
enum ProjectTemplate {
  /// A long fiction.
  novel,

  /// Short forms and novellas.
  shortForm,

  /// An argumentative work.
  essay,

  /// Poetry.
  poetry,

  /// A technical work.
  technical,

  /// An existing file.
  import,
}

/// The answers of the wizard, before the project is created.
@immutable
class OnboardingDraft {
  /// Creates a draft.
  const OnboardingDraft({
    this.template = ProjectTemplate.novel,
    this.title = '',
    this.dailyGoalWords = regularDailyWordGoal,
  });

  /// The model the author chose.
  final ProjectTemplate template;

  /// The title of the book.
  final String title;

  /// The number of words the author writes every day.
  final int dailyGoalWords;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is OnboardingDraft &&
          other.template == template &&
          other.title == title &&
          other.dailyGoalWords == dailyGoalWords);

  @override
  int get hashCode => Object.hash(template, title, dailyGoalWords);
}

/// Stores the answers of the onboarding wizard.
final onboardingDraftProvider =
    NotifierProvider<OnboardingDraftNotifier, OnboardingDraft>(
      OnboardingDraftNotifier.new,
    );

/// Stores the answers of the onboarding wizard.
///
/// The wizard keeps its answers in a provider so that the creation of the
/// project reads the same state as the interface.
final class OnboardingDraftNotifier extends Notifier<OnboardingDraft> {
  @override
  OnboardingDraft build() => const OnboardingDraft();

  /// Chooses the model of the project.
  void selectTemplate(ProjectTemplate template) {
    if (template == state.template) {
      return;
    }
    state = _copyWith(template: template);
  }

  /// Sets the title of the book.
  void setTitle(String title) {
    if (title == state.title) {
      return;
    }
    state = _copyWith(title: title);
  }

  /// Sets the number of words the author writes every day.
  void setDailyGoal(int words) {
    if (words == state.dailyGoalWords) {
      return;
    }
    state = _copyWith(dailyGoalWords: words);
  }

  OnboardingDraft _copyWith({
    ProjectTemplate? template,
    String? title,
    int? dailyGoalWords,
  }) {
    return OnboardingDraft(
      template: template ?? state.template,
      title: title ?? state.title,
      dailyGoalWords: dailyGoalWords ?? state.dailyGoalWords,
    );
  }
}
