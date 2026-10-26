import 'package:limpid_core/limpid_core.dart';

import '../db/audit_entry.dart';
import '../db/audit_log.dart';
import '../db/book_sale_store.dart';
import '../db/entitlement_store.dart';
import '../db/project_record.dart';
import '../db/project_store.dart';
import '../db/promo_code_store.dart';
import '../errors/app_exception.dart';
import '../storage/artifact_keys.dart';
import '../storage/object_storage.dart';
import 'payment_gateway.dart';
import 'promo_code_service.dart';
import 'revenue_share_service.dart';

/// La durée de vie de l'URL signée de téléchargement.
///
/// Vingt-quatre heures : le lien reste assez longtemps pour que l'acheteur
/// récupère son livre, et il ne dort pas dans la nature. Passé ce délai,
/// l'acheteur en demande un autre.
const Duration bookDownloadLifetime = Duration(hours: 24);

/// L'extension du fichier EPUB, searched dans le stockage objet.
const String bookEpubExtension = '.epub';

/// La commande d'un livre.
///
/// La commande porte le prix **lu dans la base** et la remise qui lui a
/// été appliquée. Elle ne porte jamais un montant venu du client.
final class BookOrder {
  /// Crée une commande.
  const BookOrder({
    required this.projectId,
    required this.buyerId,
    required this.priceInCents,
    required this.currency,
    required this.discountInCents,
    this.promoCode,
    this.session,
    this.entitlement,
  });

  /// Le livre commandé.
  final String projectId;

  /// Le compte qui a commandé.
  final String buyerId;

  /// Le prix du livre, en centimes, avant la remise.
  final int priceInCents;

  /// La devise du prix.
  final String currency;

  /// La remise appliquée, en centimes.
  final int discountInCents;

  /// Le code promo appliqué, `null` quand il n'y en a pas.
  final String? promoCode;

  /// La session de paiement, `null` pour un livre gratuit.
  final CheckoutSession? session;

  /// Le droit accordé, `null` quand le paiement n'est pas encore confirmé.
  final EntitlementRecord? entitlement;

  /// Le montant à payer, en centimes.
  int get amountInCents => priceInCents - discountInCents;

  /// Le livre est-il gratuit ?
  ///
  /// Un livre gratuit n'ouvre aucune session de paiement : le droit est
  /// accordé tout de suite, et la ventilation est nulle.
  bool get isFree => session == null;

  /// La représentation JSON de la commande.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'project_id': projectId,
      'price_cents': priceInCents,
      'amount_cents': amountInCents,
      'currency': currency,
      'discount_cents': discountInCents,
      'promo_code': promoCode,
      'is_free': isFree,
      'granted': entitlement != null,
      if (session != null) ...session!.toJson(),
      if (entitlement != null) 'entitlement': entitlement!.toJson(),
    };
  }
}

/// Un livre acheté, tel que l'acheteur le voit.
final class BookPurchase {
  /// Crée un achat.
  const BookPurchase({
    required this.entitlement,
    required this.title,
    required this.ownerId,
  });

  /// Le droit de lecture.
  final EntitlementRecord entitlement;

  /// Le titre du livre, tel qu'il est en vente aujourd'hui.
  final String title;

  /// Le compte qui encaisse la vente.
  final String ownerId;

  /// La représentation JSON de l'achat.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      ...entitlement.toJson(),
      'title': title,
      'owner_id': ownerId,
    };
  }
}

/// L'URL signée de téléchargement d'un livre acheté.
final class BookDownload {
  /// Crée une URL de téléchargement.
  const BookDownload({
    required this.projectId,
    required this.url,
    required this.expiresAt,
    required this.artifactKey,
  });

  /// Le livre téléchargé.
  final String projectId;

  /// L'URL signée.
  final String url;

  /// L'instant d'expiration de l'URL.
  final DateTime expiresAt;

  /// La clé du fichier dans le stockage objet.
  final String artifactKey;

  /// La représentation JSON du téléchargement.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'project_id': projectId,
      'download_url': url,
      'artifact_key': artifactKey,
      'expires_at': expiresAt.toUtc().toIso8601String(),
      'expires_in_seconds': bookDownloadLifetime.inSeconds,
    };
  }
}

/// Le service de la vente des livres.
///
/// Le service porte les règles de la vente : le prix vient de la base, le
/// livre doit être en vente, la remise s'applique au prix, le droit est
/// accordé quand le paiement est confirmé, et la ventilation suit le
/// paiement. Il ne connaît ni la route, ni le format de la réponse.
final class BookSaleService {
  /// Crée un service.
  BookSaleService({
    required this.sales,
    required this.entitlements,
    required this.promoCodes,
    required this.projects,
    required this.storage,
    required this.audit,
    DateTime Function()? clock,
    UlidGenerator? generator,
  }) : _clock = clock ?? _utcNow,
       _generator = generator ?? UlidGenerator(),
       _revenue = const RevenueShareService(),
       _promos = PromoCodeService(store: promoCodes, clock: clock ?? _utcNow);

  /// Le magasin des ventes.
  final BookSaleStore sales;

  /// Le magasin des droits de lecture.
  final EntitlementStore entitlements;

  /// Le magasin des codes promo.
  final PromoCodeStore promoCodes;

  /// Le magasin des projets.
  final ProjectStore projects;

  /// Le stockage des artefacts.
  final ObjectStorage storage;

  /// Le journal d'audit.
  final AuditLog audit;

  final DateTime Function() _clock;
  final UlidGenerator _generator;
  final RevenueShareService _revenue;
  final PromoCodeService _promos;

  static DateTime _utcNow() => DateTime.now().toUtc();

  DateTime _now() => _clock().toUtc();

  /// La vente du livre [projectId], `null` quand le livre n'est pas en
  /// vente.
  Future<BookSaleRecord?> saleOf(String projectId) {
    return sales.findByProject(projectId);
  }

  /// Les ventes du compte [ownerId], les plus récentes d'abord.
  Future<List<BookSaleRecord>> salesOf(String ownerId) {
    return sales.listByOwner(ownerId);
  }

  /// Met le livre [projectId] en vente pour le compte [ownerId].
  ///
  /// Seul le propriétaire du livre peut le vendre : un compte qui n'a rien
  /// dessus est refusé comme si le livre n'existait pas.
  ///
  /// Le prix est validé : il n'est pas négatif, la devise est dans la
  /// liste fermée, et la part de l'auteur est comprise entre 0 et 10 000
  /// millièmes. Un prix nul fait un **livre gratuit** : il se vend sans
  /// paiement, et sa ventilation est nulle.
  Future<BookSaleRecord> publish({
    required String ownerId,
    required String projectId,
    required int priceInCents,
    required String currency,
    BookSaleStatus status = BookSaleStatus.published,
    int? authorShare,
    String? artifactKey,
  }) async {
    final ProjectAccess access = await _requireOwner(
      projectId: projectId,
      ownerId: ownerId,
    );
    final int price = _readPrice(priceInCents);
    final String money = _readCurrency(currency);
    final int share = _readShare(authorShare);
    final DateTime now = _now();
    final BookSaleRecord? existing = await sales.findByProject(projectId);

    final BookSaleRecord record = BookSaleRecord(
      projectId: projectId,
      ownerId: ownerId,
      title: access.project.title,
      priceInCents: price,
      currency: money,
      status: status,
      authorShare: share,
      platformShare: revenueShareTotal - share,
      artifactKey: artifactKey ?? existing?.artifactKey,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
      publishedAt: status == BookSaleStatus.published
          ? (existing?.publishedAt ?? now)
          : existing?.publishedAt,
    );
    await sales.save(record);
    return record;
  }

  /// Commande le livre [projectId] pour le compte [buyerId].
  ///
  /// Le prix vient de la base, jamais du corps de la requête. Un livre qui
  /// n'est pas en vente est refusé, et le refus nomme la raison.
  ///
  /// Un livre gratuit n'ouvre aucune session de paiement : le droit est
  /// accordé immédiatement, et rien n'est ventilé. Un livre payé ouvre une
  /// session en mode `payment` : le droit sera accordé quand le webhook
  /// de paiement confirmera l'encaissement.
  Future<BookOrder> order({
    required String buyerId,
    required String projectId,
    required String successUrl,
    required String cancelUrl,
    required BookPaymentGateway gateway,
    String? promoCode,
    String? idempotencyKey,
  }) async {
    final BookSaleRecord sale = await _requireSellable(projectId);

    int discount = 0;
    String? appliedCode;
    final String? requested = _cleanCode(promoCode);
    if (requested != null) {
      final PromoRedemption redemption = await _promos.redeem(
        code: requested,
        userId: buyerId,
        priceInCents: sale.priceInCents,
        currency: sale.currency,
      );
      discount = redemption.discountInCents;
      appliedCode = redemption.code;
    }

    final int amount = sale.priceInCents - discount;
    if (amount <= 0) {
      final EntitlementRecord entitlement = await _grantFree(
        buyerId: buyerId,
        sale: sale,
        promoCode: appliedCode,
      );
      return BookOrder(
        projectId: projectId,
        buyerId: buyerId,
        priceInCents: sale.priceInCents,
        currency: sale.currency,
        discountInCents: discount,
        promoCode: appliedCode,
        entitlement: entitlement,
      );
    }

    final CheckoutSession session = await gateway.createBookSession(
      BookCheckoutRequest(
        userId: buyerId,
        projectId: projectId,
        title: sale.title,
        priceInCents: amount,
        currency: sale.currency,
        successUrl: successUrl,
        cancelUrl: cancelUrl,
        idempotencyKey: idempotencyKey,
        promoCode: appliedCode,
      ),
    );

    return BookOrder(
      projectId: projectId,
      buyerId: buyerId,
      priceInCents: sale.priceInCents,
      currency: sale.currency,
      discountInCents: discount,
      promoCode: appliedCode,
      session: session,
    );
  }

  /// Accorde le droit de lecture d'un paiement confirmé.
  ///
  /// L'octroi est **idempotent** : le même paiement ne crée pas deux
  /// droits, et la ventilation du premier paiement est conservée. La
  /// ventilation est écrite ici, jamais avant : tant que le paiement n'est
  /// pas confirmé, l'auteur n'a rien à recevoir.
  ///
  /// Rend l'action tracée dans le journal d'audit, `null` quand le livre
  /// n'est pas en vente ou que le droit existait déjà.
  Future<String?> applyPayment({
    required String buyerId,
    required String projectId,
    required String source,
    int? amountInCents,
    String? promoCode,
    String? ip,
  }) async {
    final BookSaleRecord? sale = await sales.findByProject(projectId);
    if (sale == null) {
      // Le livre n'est pas en vente : le paiement ne donne aucun droit.
      return null;
    }
    final int amount = amountInCents ?? sale.priceInCents;
    final RevenueSplit split = _revenue.split(
      amountInCents: amount,
      authorShare: sale.authorShare,
    );
    final DateTime now = _now();
    final EntitlementGrant grant = await entitlements.grant(
      EntitlementRecord(
        id: _generator.generate().value,
        userId: buyerId,
        projectId: projectId,
        source: source,
        grantedAt: now,
        createdAt: now,
        amountInCents: split.amountInCents,
        currency: sale.currency,
        authorShare: split.authorShare,
        platformShare: split.platformShare,
        authorAmountInCents: split.authorAmountInCents,
        platformAmountInCents: split.platformAmountInCents,
        promoCode: promoCode,
      ),
    );
    if (!grant.isNew) {
      // Le droit existait deja : le paiement a deja ete traite.
      return null;
    }
    await audit.record(
      AuditEntry(
        userId: buyerId,
        action: 'book.purchase_completed',
        targetType: 'book_sale',
        targetId: projectId,
        metadata: <String, Object?>{
          'payment_reference': source,
          'amount_cents': split.amountInCents,
          'currency': sale.currency,
          'author_share': split.authorShare,
          'author_amount_cents': split.authorAmountInCents,
          'platform_amount_cents': split.platformAmountInCents,
          'owner_id': sale.ownerId,
          'promo_code': ?promoCode,
        },
        ip: ip,
      ),
    );
    return 'book.purchase_completed';
  }

  /// Les livres achetés par le compte [userId], les plus récents d'abord.
  Future<List<BookPurchase>> purchases(String userId) async {
    final List<EntitlementRecord> records = await entitlements.listByUser(
      userId,
    );
    final List<BookPurchase> purchases = <BookPurchase>[];
    for (final EntitlementRecord record in records) {
      final BookSaleRecord? sale = await sales.findByProject(record.projectId);
      purchases.add(
        BookPurchase(
          entitlement: record,
          title: sale?.title ?? '',
          ownerId: sale?.ownerId ?? '',
        ),
      );
    }
    return List<BookPurchase>.unmodifiable(purchases);
  }

  /// L'URL signée de téléchargement du livre [projectId].
  ///
  /// Sans droit, la réponse est un `404` : elle ne dit jamais que le livre
  /// existe. Avec un droit, l'URL est signée et expire après vingt-quatre
  /// heures.
  Future<BookDownload> download({
    required String userId,
    required String projectId,
  }) async {
    final EntitlementRecord? entitlement = await entitlements.find(
      userId: userId,
      projectId: projectId,
    );
    if (entitlement == null) {
      throw const NotFoundException(message: "Ce livre n'a pas été acheté.");
    }
    final String key = await _artifactKeyOf(projectId);
    final String url = await storage.presignedUrl(
      key: key,
      expires: bookDownloadLifetime,
    );
    return BookDownload(
      projectId: projectId,
      url: url,
      expiresAt: _now().add(bookDownloadLifetime),
      artifactKey: key,
    );
  }

  /// Le droit du compte [userId] sur le livre [projectId], `null` quand il
  /// n'y en a pas.
  Future<EntitlementRecord?> entitlementOf({
    required String userId,
    required String projectId,
  }) {
    return entitlements.find(userId: userId, projectId: projectId);
  }

  /// Accorde le droit d'un livre gratuit.
  ///
  /// La ventilation est nulle : un livre gratuit ne ventile rien.
  Future<EntitlementRecord> _grantFree({
    required String buyerId,
    required BookSaleRecord sale,
    String? promoCode,
  }) async {
    final DateTime now = _now();
    final EntitlementGrant grant = await entitlements.grant(
      EntitlementRecord(
        id: _generator.generate().value,
        userId: buyerId,
        projectId: sale.projectId,
        source: 'free_${_generator.generate().value}',
        grantedAt: now,
        createdAt: now,
        amountInCents: 0,
        currency: sale.currency,
        promoCode: promoCode,
      ),
    );
    return grant.record;
  }

  /// La vente du livre [projectId], refusée quand le livre n'est pas en
  /// vente.
  Future<BookSaleRecord> _requireSellable(String projectId) async {
    final BookSaleRecord? sale = await sales.findByProject(projectId);
    if (sale == null) {
      throw const NotFoundException(message: "Ce livre n'est pas en vente.");
    }
    if (sale.status == BookSaleStatus.draft) {
      throw const ConflictException(
        message: "Ce livre n'est pas encore publié : il n'est pas en vente.",
      );
    }
    if (sale.status == BookSaleStatus.withdrawn) {
      throw const ConflictException(
        message: 'Ce livre a été retiré de la vente.',
      );
    }
    return sale;
  }

  /// La vente du livre [projectId], refusée quand le compte [ownerId] n'en
  /// est pas le propriétaire.
  Future<ProjectAccess> _requireOwner({
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
        message: 'Seul le propriétaire du livre peut le mettre en vente.',
      );
    }
    return access;
  }

  /// La clé du fichier vendu, dans le stockage objet.
  ///
  /// La clé connue de la vente est utilisée quand elle existe. Sinon, le
  /// fichier est cherché dans les exports du livre : le fichier EPUB est
  /// préféré, et le premier artefact trouvé vient à défaut.
  Future<String> _artifactKeyOf(String projectId) async {
    final BookSaleRecord? sale = await sales.findByProject(projectId);
    final String? known = sale?.artifactKey;
    if (known != null && known.isNotEmpty) return known;

    final ObjectStorageReader? reader = switch (storage) {
      final ObjectStorageReader capable => capable,
      _ => null,
    };
    if (reader == null) {
      throw const NotFoundException(
        message: "Le fichier de ce livre n'est pas disponible.",
      );
    }
    final List<String> keys = await reader.listKeys(
      prefix: ArtifactKeys.prefixOfProject(projectId),
    );
    if (keys.isEmpty) {
      throw const NotFoundException(
        message: "Le fichier de ce livre n'est pas disponible.",
      );
    }
    for (final String key in keys) {
      if (key.toLowerCase().endsWith(bookEpubExtension)) return key;
    }
    return keys.first;
  }

  /// Le prix validé.
  int _readPrice(int priceInCents) {
    if (priceInCents < 0) {
      throw ValidationException(
        field: 'price_cents',
        message: 'Le champ « price_cents » ne peut pas porter un prix négatif.',
      );
    }
    return priceInCents;
  }

  /// La devise validée.
  String _readCurrency(String currency) {
    final String normalized = currency.trim().toLowerCase();
    if (!bookSaleCurrencies.contains(normalized)) {
      throw ValidationException(
        field: 'currency',
        message:
            'Le champ « currency » doit valoir '
            '${bookSaleCurrencies.join(' ou ')}.',
      );
    }
    return normalized;
  }

  /// La part de l'auteur validée, en millièmes.
  int _readShare(int? authorShare) {
    final int share = authorShare ?? defaultAuthorShare;
    if (share < 0 || share > revenueShareTotal) {
      throw ValidationException(
        field: 'author_share',
        message:
            'Le champ « author_share » doit être compris entre 0 et '
            '$revenueShareTotal millièmes.',
      );
    }
    return share;
  }

  /// Le code promo demandé, `null` quand il n'y en a pas.
  static String? _cleanCode(String? code) {
    if (code == null) return null;
    final String trimmed = code.trim();
    if (trimmed.isEmpty) return null;
    return trimmed;
  }
}
