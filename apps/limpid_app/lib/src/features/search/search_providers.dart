import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:limpid_app/src/domain/search_repository.dart';

/// The repository answering the searches of the author.
///
/// The port is wired by the composition root of the application: it holds
/// the implementation of the data layer, which answers from the local index.
/// Reading the provider without this replacement fails: the screen never
/// shows a result it has not read.
final Provider<SearchRepository> searchRepositoryProvider =
    Provider<SearchRepository>((Ref ref) {
      throw UnimplementedError(
        'The search repository is not wired: override '
        '`searchRepositoryProvider` with the implementation of the data '
        'layer.',
      );
    });
