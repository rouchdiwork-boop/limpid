/// The entry point of the projects of the author.
///
/// The presentation view of a project lives in [project_summary.dart] and the
/// providers that read the manuscripts live in [projects_providers.dart].
/// Both are exported here: the screens of the application keep a single
/// import for the feature.
library;

export 'project_summary.dart';
export 'projects_providers.dart';
