import 'package:limpid_ai/src/model/ai_provider_kind.dart';

/// Source des clés d'API, résolue à l'exécution.
///
/// L'implémentation réelle vit dans l'API Limpid (qui lit les secrets en
/// base ou en gestionnaire). Ce package ne contient **aucun** secret et ne
/// lit aucun fichier de configuration.
abstract class AiCredentialStore {
  /// Renvoie la clé d'API d'une fournisseur, ou `null` si elle est absente.
  ///
  /// [scope] distingue plusieurs endpoints compatibles OpenAI (par exemple
  /// `groq` et `together` partageant le même type de fournisseur).
  Future<String?> read(AiProviderKind provider, {String? scope});
}

/// Magasin de clés en mémoire, fourni à titre de référence.
///
/// Utile pour les tests et pour un serveur qui charge ses secrets au
/// démarrage. Ne persiste rien : le contenu est perdu au redémarrage.
class InMemoryCredentialStore implements AiCredentialStore {
  /// Crée un magasin à partir d'une table existante.
  InMemoryCredentialStore([Map<AiProviderKind, Map<String, String>>? initial])
    : _entries = <AiProviderKind, Map<String, String>>{
        for (final MapEntry<AiProviderKind, Map<String, String>> entry
            in (initial ?? <AiProviderKind, Map<String, String>>{}).entries)
          entry.key: Map<String, String>.of(entry.value),
      };

  final Map<AiProviderKind, Map<String, String>> _entries;

  /// Ajoute ou remplace une clé pour une fournisseur et un périmètre.
  void store(AiProviderKind provider, String apiKey, {String? scope}) {
    final String key = scope ?? _defaultScope;
    final Map<String, String> bucket = _entries.putIfAbsent(
      provider,
      () => <String, String>{},
    );
    _entries[provider] = <String, String>{...bucket, key: apiKey};
  }

  /// Supprime une clé.
  void remove(AiProviderKind provider, {String? scope}) {
    final String key = scope ?? _defaultScope;
    final Map<String, String>? bucket = _entries[provider];
    if (bucket == null) {
      return;
    }
    _entries[provider] = Map<String, String>.of(bucket)..remove(key);
  }

  static const String _defaultScope = '';

  @override
  Future<String?> read(AiProviderKind provider, {String? scope}) async {
    final Map<String, String>? bucket = _entries[provider];
    if (bucket == null) {
      return null;
    }
    return bucket[scope ?? _defaultScope];
  }
}
