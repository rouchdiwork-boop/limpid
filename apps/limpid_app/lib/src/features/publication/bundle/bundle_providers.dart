import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:limpid_app/src/domain/bundle_repository.dart';

/// Le bundle.
///
/// Le provider lit le port des bundles : le prix vient du serveur, et un
/// bundle qui n'est pas en vente n'a pas de prix. La page du bundle lit ce
/// provider, et rien d'autre.
final bundleProvider = FutureProvider.family<Bundle?, String>((
  Ref ref,
  String bundleId,
) async {
  final BundleRepository repository = ref.watch(bundleRepositoryProvider);
  return repository.bundleOf(bundleId);
});
