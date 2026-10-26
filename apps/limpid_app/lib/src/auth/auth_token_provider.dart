import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:limpid_app/src/auth/auth_repository.dart';
import 'package:limpid_app/src/auth/supabase_auth_repository.dart';
import 'package:limpid_sync/limpid_sync.dart';

/// The provider of the bearer token used by the synchronisation transport.
///
/// The token is resolved for every request: it expires while the application
/// runs. The demonstration mode has no remote service, the provider then
/// returns `null` and the transport sends anonymous requests.
final authTokenProviderProvider = Provider<AuthTokenProvider>((ref) {
  return () async {
    final repository = ref.read(authRepositoryProvider);
    if (repository case final AccessTokenReader reader) {
      return reader.readAccessToken();
    }
    return null;
  };
});
