import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:limpid_core/limpid_core.dart';

import '../db/webhook_database.dart';
import '../db/webhook_record.dart';
import '../errors/app_exception.dart';
import 'random_secret.dart';

/// Le préfixe d'une clé d'API.
///
/// Il permet de reconnaître une clé d'API dans un journal ou une
/// configuration, sans avoir à la déchiffrer.
const String apiKeyPrefix = 'lk';

/// Le séparateur entre le préfixe, l'identifiant et le secret.
const String apiKeySeparator = '.';

/// Le délai au-delà duquel l'horodatage d'usage d'une clé est refreshing.
///
/// Une clé d'API sert à chaque appel de l'intégration : réécrire la date
/// d'usage à chaque appel ferait une charge inutile. La date est donc
/// rafraîchie au plus une fois par minute.
const Duration apiKeyUsageRefreshInterval = Duration(minutes: 1);

/// Le périmètre d'une clé d'API.
///
/// Le périmètre borne ce que la clé peut faire : une clé de lecture n'écrit
/// rien, une clé d'écriture peut tout faire. Une intégration n'a jamais
/// besoin des deux.
enum ApiKeyScope {
  /// Lire les ressources du compte : points de rappel, journal des
  /// livraisons.
  read('read', 'Lecture des ressources du compte'),

  /// Créer et modifier les ressources du compte.
  write('write', 'Écriture des ressources du compte');

  /// Crée un périmètre.
  const ApiKeyScope(this.key, this.label);

  /// Le nom technique du périmètre, stable dans la base.
  final String key;

  /// Le libellé du périmètre, en français.
  final String label;

  /// Le périmètre portant le nom [raw], `null` quand le nom est inconnu.
  static ApiKeyScope? parse(String raw) {
    for (final ApiKeyScope scope in ApiKeyScope.values) {
      if (scope.key == raw) return scope;
    }
    return null;
  }
}

/// Une clé d'API et son secret, au moment de la création ou de la rotation.
///
/// Le secret n'existe que dans cette réponse : la base ne conserve que son
/// empreinte.
final class CreatedApiKey {
  /// Crée un résultat.
  const CreatedApiKey({required this.record, required this.secret});

  /// La clé telle que la base la stocke.
  final ApiKeyRecord record;

  /// La clé en clair, à montrer une seule fois.
  final String secret;
}

/// Le service des clés d'API.
///
/// Le service génère les clés, les empreinte, les fait tourner et les
/// révoque. Il ne connaît pas la formule du compte : le garde-fou de la
/// formule appartient à la route.
final class ApiKeyService {
  /// Crée un service sur le port [database].
  ApiKeyService({
    required this.database,
    UlidGenerator? generator,
    DateTime Function()? clock,
  }) : _generator = generator ?? UlidGenerator(),
       _clock = clock ?? DateTime.now;

  /// Le port de persistance des clés d'API.
  final WebhookDatabase database;
  final UlidGenerator _generator;
  final DateTime Function() _clock;

  /// Crée une clé d'API pour le compte [userId].
  ///
  /// La clé porte le nom donné par l'auteur et le périmètre [scopes]. Le
  /// secret est renvoyé une seule fois : la base n'en garde que
  /// l'empreinte.
  Future<CreatedApiKey> create({
    required String userId,
    required String name,
    required Set<ApiKeyScope> scopes,
  }) async {
    final String id = _generator.generate().value;
    final String secret = _present(id);
    final ApiKeyRecord record = ApiKeyRecord(
      id: id,
      userId: userId,
      name: name,
      keyHash: hashApiKey(secret),
      scopes: scopes.map((ApiKeyScope scope) => scope.key).toSet(),
      isActive: true,
      createdAt: _now(),
    );
    await database.insertApiKey(record);
    return CreatedApiKey(record: record, secret: secret);
  }

  /// Fait tourner la clé [keyId] du compte [userId].
  ///
  /// La clé garde son identité : les intégrations qui la référencent
  /// continuent de fonctionner. Seul le secret change, et l'ancien cesse
  /// aussitôt de servir.
  Future<CreatedApiKey> rotate({
    required String userId,
    required String keyId,
  }) async {
    final ApiKeyRecord existing = await _requireOwned(userId, keyId);
    if (!existing.isUsable) {
      throw const ConflictException(
        message:
            'Cette clé est révoquée : elle ne peut plus être remise en '
            'service.',
      );
    }
    final String secret = _present(existing.id);
    final ApiKeyRecord rotated = existing.copyWith(
      keyHash: hashApiKey(secret),
      rotatedAt: _now(),
    );
    await database.updateApiKey(rotated);
    return CreatedApiKey(record: rotated, secret: secret);
  }

  /// Révoque la clé [keyId] du compte [userId].
  ///
  /// Une clé révoquée ne sert plus : elle est refusée exactement comme une
  /// clé inconnue.
  Future<ApiKeyRecord> revoke({
    required String userId,
    required String keyId,
  }) async {
    final ApiKeyRecord existing = await _requireOwned(userId, keyId);
    if (!existing.isUsable) return existing;
    final ApiKeyRecord revoked = existing.copyWith(
      isActive: false,
      revokedAt: _now(),
    );
    await database.updateApiKey(revoked);
    return revoked;
  }

  /// La clé d'API [keyId] du compte [userId].
  ///
  /// Une clé qui appartient à un autre compte est refusée comme si elle
  /// n'existait pas.
  Future<ApiKeyRecord> find({required String userId, required String keyId}) {
    return _requireOwned(userId, keyId);
  }

  /// Les clés d'API du compte [userId], les plus récentes d'abord.
  Future<WebhookPage<ApiKeyRecord>> list({
    required String userId,
    required int limit,
    String? cursor,
  }) {
    return database.listApiKeys(userId: userId, limit: limit, cursor: cursor);
  }

  /// Résout la clé présentée par l'appelant.
  ///
  /// Renvoie `null` quand la clé est inconnue, révoquée ou falsifiée : la
  /// route répond alors par le même refus que pour une clé absente, sans
  /// rien divulguer sur les clés existantes.
  Future<ApiKeyRecord?> authenticate(String presentedKey) async {
    final String? id = _identifierOf(presentedKey);
    if (id == null) return null;
    final ApiKeyRecord? record = await database.findApiKey(id);
    if (record == null || !record.isUsable) return null;
    if (!_sameDigest(record.keyHash, hashApiKey(presentedKey))) return null;
    return _touchUsage(record);
  }

  /// La clé [keyId] du compte [userId], ou une erreur si elle n'existe pas.
  Future<ApiKeyRecord> _requireOwned(String userId, String keyId) async {
    final ApiKeyRecord? record = await database.findApiKey(keyId);
    if (record == null || record.userId != userId) {
      throw const NotFoundException(message: "Cette clé d'API n'existe pas.");
    }
    return record;
  }

  /// Rafraîchit l'horodatage d'usage de la clé [record].
  ///
  /// La date n'est réécrite qu'une fois par minute : une intégration qui
  /// appelle l'API à chaque seconde ne multiplie pas les écritures.
  Future<ApiKeyRecord> _touchUsage(ApiKeyRecord record) async {
    final DateTime now = _now();
    final DateTime? lastUsedAt = record.lastUsedAt;
    if (lastUsedAt != null &&
        now.toUtc().difference(lastUsedAt.toUtc()) <
            apiKeyUsageRefreshInterval) {
      return record;
    }
    final ApiKeyRecord updated = record.copyWith(lastUsedAt: now);
    await database.updateApiKey(updated);
    return updated;
  }

  /// La clé en clair de l'API, faite de son identifiant et d'un secret.
  String _present(String id) {
    return '$apiKeyPrefix$apiKeySeparator$id'
        '$apiKeySeparator${generateRandomSecret()}';
  }

  /// L'identifiant porté par la clé présentée, `null` quand la clé est
  /// mal formée.
  String? _identifierOf(String presentedKey) {
    final String trimmed = presentedKey.trim();
    final String head = '$apiKeyPrefix$apiKeySeparator';
    if (!trimmed.startsWith(head)) return null;
    final String rest = trimmed.substring(head.length);
    final int separator = rest.indexOf(apiKeySeparator);
    if (separator <= 0 || separator == rest.length - 1) return null;
    return rest.substring(0, separator);
  }

  DateTime _now() => _clock().toUtc();
}

/// L'empreinte d'une clé d'API.
///
/// L'empreinte est le SHA-256 de la clé complète, en hexadécimal : elle ne
/// permet pas de retrouver la clé.
String hashApiKey(String presentedKey) {
  return sha256.convert(utf8.encode(presentedKey)).toString();
}

/// Indique si les deux empreintes [left] et [right] sont identiques.
///
/// La comparaison ne s'arrête pas au premier caractère différent : elle
/// parcourt toute la chaîne, pour que le temps de réponse ne révèle pas
/// combien de caractères sont justes.
bool _sameDigest(String left, String right) {
  if (left.length != right.length) return false;
  int difference = 0;
  for (int index = 0; index < left.length; index++) {
    difference |= left.codeUnitAt(index) ^ right.codeUnitAt(index);
  }
  return difference == 0;
}
