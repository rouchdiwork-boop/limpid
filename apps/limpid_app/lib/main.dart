import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:limpid_app/src/app/dependencies.dart';
import 'package:limpid_app/src/app/limpid_app.dart';
import 'package:limpid_app/src/bootstrap/app_bootstrap.dart';
import 'package:limpid_app/src/domain/providers.dart';
import 'package:limpid_app/src/domain/publication_repository.dart';
import 'package:limpid_app/src/features/revision/revision_providers.dart';
import 'package:limpid_app/src/features/settings/settings_providers.dart';

/// Entry point of the Limpid application.
///
/// The bootstrap runs before the first frame so that the session of the author
/// is known, then the dependencies are built: the local database is opened,
/// the migrations are applied, and the repositories are given to the ports of
/// `lib/src/domain/providers.dart`.
///
/// The screens never build a repository themselves: they read the ports, and
/// the ports read what the composition root decided.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppBootstrap.run();
  final AppDependencies dependencies = await buildAppDependencies();

  runApp(
    ProviderScope(
      overrides: [
        manuscriptRepositoryProvider.overrideWithValue(
          dependencies.manuscripts,
        ),
        syncRepositoryProvider.overrideWithValue(dependencies.sync),
        preferencesRepositoryProvider.overrideWithValue(
          dependencies.preferences,
        ),
        exportRepositoryProvider.overrideWithValue(dependencies.exports),
        aiRepositoryProvider.overrideWithValue(dependencies.ai),
        gdprRepositoryProvider.overrideWithValue(dependencies.gdpr),
        publicationRepositoryProvider.overrideWithValue(
          dependencies.publication,
        ),
        revisionRepositoryProvider.overrideWithValue(dependencies.revision),
        planRepositoryProvider.overrideWithValue(dependencies.plans),
        localDataEraserProvider.overrideWithValue(dependencies.localDataEraser),
        authorIdProvider.overrideWithValue(dependencies.author),
      ],
      child: const LimpidApp(),
    ),
  );
}
