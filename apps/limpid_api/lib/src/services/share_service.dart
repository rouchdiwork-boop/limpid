import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:limpid_core/limpid_core.dart';

import '../db/project_record.dart';
import '../db/project_store.dart';
import '../db/share_store.dart';
import '../errors/app_exception.dart';
import 'random_secret.dart';

/// Le préfixe d'un jeton de partage.
///
/// Il permet de reconnaître un jeton de partage dans un journal ou une
/// configuration, sans avoir à le déchiffrer.
const String shareTokenPrefix = 'ls';

/// Le séparateur entre le préfixe, l'identifiant et le secret.
const String shareTokenSeparator = '.';

/// La durée de vie par défaut d'un partage, en heures.
///
/// Sept jours suffisent à faire relire un manuscrit à un lecteur, sans
/// laisser un lien dormant dans la nature.
const int defaultShareLifetimeHours = 168;

/// La durée de vie minimale d'un partage, en heures.
const int minShareLifetimeHours = 1;

/// La durée de vie maximale d'un partage, en heures.
///
/// Trente jours est la borne de la conservation des données d'un compte
/// (D-19) : un lien ne vit pas plus longtemps que les données qu'il ouvre.
const int maxShareLifetimeHours = 720;

/// Un partage et son jeton, au moment de la création.
///
/// Le jeton n'existe que dans cette réponse : la base ne conserve que son
/// empreinte, et le serveur ne rend plus jamais le jeton.
final class CreatedShare {
  /// Crée un résultat.
  const CreatedShare({required this.record, required this.token});

  /// Le partage tel que la base le stocke.
  final ShareRecord record;

  /// Le jeton en clair, à montrer une seule fois.
  final String token;
}

/// Le service des partages en lecture.
///
/// Le service tire le jeton, l'empreinte, crée le partage, le liste et le
/// révoque. Il ne connaît ni la route, ni la formule du compte : la
/// lecture du jeton et les règles d'échéance sont les siennes.
final class ShareService {
  /// Crée un service sur les magasins [store] et [projects].
  ShareService({
    required this.store,
    required this.projects,
    UlidGenerator? generator,
    DateTime Function()? clock,
  }) : _generator = generator ?? UlidGenerator(),
       _clock = clock ?? DateTime.now;

  /// Le magasin des partages.
  final ShareStore store;

  /// Le magasin des projets.
  final ProjectStore projects;

  final UlidGenerator _generator;
  final DateTime Function() _clock;

  /// Crée un partage du projet [projectId] pour le compte [ownerId].
  ///
  /// Le jeton est rendu une seule fois : la base n'en garde que l'empreinte.
  /// Seul le propriétaire du projet peut le partager ; un compte qui n'a
  /// rien sur le livre est refusé comme si le livre n'existait pas.
  Future<CreatedShare> create({
    required String ownerId,
    required String projectId,
    int? lifetimeHours,
  }) async {
    final int hours = _readLifetimeHours(lifetimeHours);
    await _requireOwner(projectId: projectId, ownerId: ownerId);

    final String id = _generator.generate().value;
    final String token = _present(id);
    final DateTime now = _now();
    final ShareRecord record = ShareRecord(
      id: id,
      projectId: projectId,
      ownerId: ownerId,
      tokenHash: hashShareToken(token),
      expiresAt: now.add(Duration(hours: hours)),
      isRevoked: false,
      createdAt: now,
    );
    await store.insert(record);
    return CreatedShare(record: record, token: token);
  }

  /// Les partages du compte [ownerId], les plus récents d'abord.
  Future<SharePage> list({
    required String ownerId,
    required int limit,
    String? cursor,
  }) {
    return store.listByOwner(userId: ownerId, limit: limit, cursor: cursor);
  }

  /// Révoque le partage [shareId] du compte [ownerId].
  ///
  /// La révocation est irréversible et idempotente : révoquer un partage
  /// déjà révoqué rend le même partage, sans second effet. Un partage qui
  /// appartient à un autre compte est refusé comme s'il n'existait pas.
  Future<ShareRecord> revoke({
    required String ownerId,
    required String shareId,
  }) async {
    final ShareRecord? existing = await store.findById(shareId);
    if (existing == null || existing.ownerId != ownerId) {
      throw const NotFoundException(message: "Ce partage n'existe pas.");
    }
    if (existing.isRevoked) return existing;
    final ShareRecord revoked = existing.copyWith(
      isRevoked: true,
      revokedAt: _now(),
    );
    await store.update(revoked);
    return revoked;
  }

  /// Le partage vivant que porte le jeton [token].
  ///
  /// Renvoie `null` quand le jeton est inconnu, falsifié, révoqué ou
  /// expiré : les quatre cas doivent être indiscernables de l'extérieur,
  /// pour ne pas dire à un tiers qu'un partage a existé.
  Future<ShareRecord?> resolve(String token) async {
    final String? id = _identifierOf(token);
    if (id == null) return null;
    final ShareRecord? record = await store.findById(id);
    if (record == null) return null;
    if (!_sameDigest(record.tokenHash, hashShareToken(token))) return null;
    if (!record.isLiveAt(_now())) return null;
    return record;
  }

  /// Vérifie que le compte [ownerId] possède le projet [projectId].
  ///
  /// Un projet hors de la portée du compte est refusé comme s'il n'existait
  /// pas : la route ne doit jamais dire qu'un livre existe à celui qui n'a
  /// rien dessus.
  Future<void> _requireOwner({
    required String projectId,
    required String ownerId,
  }) async {
    final ProjectAccess? access = await projects.access(
      projectId: projectId,
      userId: ownerId,
    );
    if (access == null) {
      throw const NotFoundException(message: "Ce livre n'existe pas.");
    }
    if (access.role != ProjectRole.owner) {
      throw const ForbiddenException(
        message: 'Seul le propriétaire du livre peut le partager.',
      );
    }
  }

  /// La durée de vie demandée, en heures, bornée par le contrat.
  int _readLifetimeHours(int? lifetimeHours) {
    final int hours = lifetimeHours ?? defaultShareLifetimeHours;
    if (hours < minShareLifetimeHours || hours > maxShareLifetimeHours) {
      throw ValidationException(
        field: 'expires_in_hours',
        message:
            'La durée de vie du partage doit être comprise entre '
            '$minShareLifetimeHours et $maxShareLifetimeHours heures.',
      );
    }
    return hours;
  }

  /// Le jeton en clair, fait de son identifiant et d'un secret.
  ///
  /// Le secret vient de `random_secret.dart` : il porte 256 bits de hasard,
  /// le jeton n'est donc pas devinable.
  String _present(String id) {
    return '$shareTokenPrefix$shareTokenSeparator$id'
        '$shareTokenSeparator${generateRandomSecret()}';
  }

  /// L'identifiant porté par le jeton présenté, `null` quand le jeton est
  /// mal formé.
  String? _identifierOf(String presentedToken) {
    final String trimmed = presentedToken.trim();
    final String head = '$shareTokenPrefix$shareTokenSeparator';
    if (!trimmed.startsWith(head)) return null;
    final String rest = trimmed.substring(head.length);
    final int separator = rest.indexOf(shareTokenSeparator);
    if (separator <= 0 || separator == rest.length - 1) return null;
    return rest.substring(0, separator);
  }

  DateTime _now() => _clock().toUtc();
}

/// L'empreinte d'un jeton de partage.
///
/// L'empreinte est le SHA-256 du jeton complet, en hexadécimal : elle ne
/// permet pas de retrouver le jeton.
String hashShareToken(String presentedToken) {
  return sha256.convert(utf8.encode(presentedToken)).toString();
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
