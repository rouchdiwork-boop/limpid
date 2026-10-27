import 'package:limpid_core/limpid_core.dart';

import '../db/audit_entry.dart';
import '../db/audit_log.dart';
import '../db/book_sale_store.dart';
import '../db/bundle_record.dart';
import '../db/entitlement_store.dart';
import '../db/project_record.dart';
import '../errors/app_exception.dart';
import 'book_sale_service.dart';
import 'payment_gateway.dart';
import 'promo_code_service.dart';
import 'revenue_share_service.dart';

/// La commande d'un bundle.
///
/// La commande porte le prix **lu dans la base** et la remise qui lui a été
/// appliquée. Elle ne porte jamais un montant venu du client.
final class BundleOrder {
  /// Crée une commande.
  const BundleOrder({
    required this.bundleId,
    required this.buyerId,
    required this.priceInCents,
    required this.currency,
    required this.discountInCents,
    this.promoCode,
    this.session,
    this.entitlements = const <EntitlementRecord>[],
  });

  /// Le bundle commandé.
  final String bundleId;

  /// Le compte qui a commandé.
  final String buyerId;

  /// Le prix du bundle, en centimes, avant la remise.
  final int priceInCents;

  /// La devise du prix.
  final String currency;

  /// La remise appliquée, en centimes.
  final int discountInCents;

  /// Le code promo appliqué, `null` quand il n'y en a pas.
  final String? promoCode;

  /// La session de paiement, `null` pour un bundle gratuit.
  final CheckoutSession? session;

  /// Les droits accordés, quand le bundle a été gratuit.
  ///
  /// Ils sont vides tant que le paiement n'est pas confirmé : le droit est
  /// alors accordé par le rappel du prestataire de paiement.
  final List<EntitlementRecord> entitlements;

  /// Le montant à payer, en centimes.
  int get amountInCents => priceInCents - discountInCents;

  /// Le bundle est-il gratuit ?
  ///
  /// Un bundle gratuit n'ouvre aucune session de paiement : les droits sont
  /// accordés tout de suite, et la ventilation est nulle.
  bool get isFree => session == null;

  /// La représentation JSON de la commande.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'bundle_id': bundleId,
      'price_cents': priceInCents,
      'amount_cents': amountInCents,
      'currency': currency,
      'discount_cents': discountInCents,
      'promo_code': promoCode,
      'is_free': isFree,
      'granted': entitlements.isNotEmpty,
      'project_ids': List<String>.unmodifiable(
        entitlements.map((EntitlementRecord record) => record.projectId),
      ),
      if (session != null) ...session!.toJson(),
    };
  }
}

/// Le service des bundles.
///
/// Le service porte les règles du bundle : il porte **au moins deux
/// livres**, les livres doivent être **en vente**, le bundle a **un**
/// vendeur, et son prix est **posé**. Le prix vient de la base, la remise
/// s'y applique comme sur le prix d'un livre, et les droits sont accordés
/// sur **chaque** livre quand le paiement est confirmé.
///
/// Le service ne connaît ni la route, ni le format de la réponse.
final class BundleService {
  /// Crée un service.
  BundleService({
    required this.bundles,
    required this.books,
    required this.audit,
    DateTime Function()? clock,
    UlidGenerator? generator,
  }) : _clock = clock ?? _utcNow,
       _generator = generator ?? UlidGenerator(),
       _revenue = const RevenueShareService();

  /// Le magasin des bundles.
  final BundleStore bundles;

  /// Le service de la vente des livres.
  ///
  /// Le bundle s'y greffe : c'est ce service qui porte la remise et la
  /// ventilation des droits, et le bundle ne les réécrit pas.
  final BookSaleService books;

  /// Le journal d'audit.
  final AuditLog audit;

  final DateTime Function() _clock;
  final UlidGenerator _generator;
  final RevenueShareService _revenue;

  static DateTime _utcNow() => DateTime.now().toUtc();

  DateTime _now() => _clock().toUtc();

  /// Le bundle [bundleId], `null` quand il n'existe pas.
  Future<BundleRecord?> bundleOf(String bundleId) {
    return bundles.findById(bundleId);
  }

  /// Les bundles du compte [ownerId], les plus récents d'abord.
  Future<List<BundleRecord>> bundlesOf(String ownerId) {
    return bundles.listByOwner(ownerId);
  }

  /// Crée le bundle du compte [ownerId].
  ///
  /// Le bundle porte **au moins deux livres** : un bundle d'un seul livre
  /// est une vente simple, malaisiee. Les livres doivent être **en vente**,
  /// et le compte qui vend le bundle doit être l'auteur de **tous** les
  /// livres qu'il contient : un bundle multi-vendeurs n'a pas de vendeur,
  /// et la ventilation des droits n'a pas de sens.
  ///
  /// Le bundle créé n'est **pas** en vente : la mise en vente est une
  /// décision de plus, et elle vérifie une fois de plus que les livres
  /// sont en vente.
  Future<BundleRecord> create({
    required String ownerId,
    required String title,
    required String description,
    required List<String> projectIds,
    required int priceInCents,
    String currency = 'eur',
  }) async {
    final String name = _readTitle(title);
    final int price = _readPrice(priceInCents);
    final String money = _readCurrency(currency);
    final List<String> books = _readProjectIds(projectIds);
    await _requireSellableBooks(ownerId: ownerId, projectIds: books);
    final BundleRecord record = BundleRecord(
      id: _generator.generate().value,
      ownerId: ownerId,
      title: name,
      description: description.trim(),
      projectIds: books,
      priceInCents: price,
      currency: money,
      isPublished: false,
      createdAt: _now(),
    );
    await bundles.save(record);
    return record;
  }

  /// Met le bundle [bundleId] en vente, ou le retire de la vente.
  ///
  /// Seul le compte qui vend le bundle peut le publier : un compte qui n'a
  /// rien dessus est refusé comme si le bundle n'existait pas.
  ///
  /// La mise en vente relit les livres du bundle : un livre qui n'est plus
  /// en vente ne peut pas être vendu dans un ensemble.
  Future<BundleRecord> publish({
    required String ownerId,
    required String bundleId,
    required bool isPublished,
  }) async {
    final BundleRecord record = await _requireOwned(
      bundleId: bundleId,
      ownerId: ownerId,
    );
    if (isPublished) {
      await _requireSellableBooks(
        ownerId: ownerId,
        projectIds: record.projectIds,
      );
    }
    final BundleRecord updated = record.copyWith(isPublished: isPublished);
    await bundles.save(updated);
    return updated;
  }

  /// Commande le bundle [bundleId] pour le compte [buyerId].
  ///
  /// Le prix vient de la base, jamais du corps de la requête. Un bundle qui
  /// n'est pas en vente est refusé, et le refus nomme la raison.
  ///
  /// Un bundle gratuit n'ouvre aucune session de paiement : les droits sont
  /// accordés immédiatement, et rien n'est ventilé. Un bundle payé ouvre
  /// une session en mode `payment` : les droits seront accordés quand le
  /// rappel de paiement confirmera l'encaissement.
  Future<BundleOrder> order({
    required String buyerId,
    required String bundleId,
    required String successUrl,
    required String cancelUrl,
    required BookPaymentGateway gateway,
    String? promoCode,
    String? idempotencyKey,
  }) async {
    final BundleRecord bundle = await _requireForSale(bundleId);
    final List<BookSaleRecord> sales;
    try {
      sales = await _requireSellableBooks(
        ownerId: bundle.ownerId,
        projectIds: bundle.projectIds,
      );
    } on ValidationException {
      // Un des livres du bundle n'est plus en vente : le bundle ne peut
      // plus etre vendu. C'est un conflit, pas une faute de la requete.
      throw const ConflictException(
        message:
            "Un des livres de ce bundle n'est plus en vente : le bundle ne "
            'peut pas etre vendu.',
      );
    }

    final PromoRedemption? redemption = await books.redeemPromo(
      buyerId: buyerId,
      priceInCents: bundle.priceInCents,
      currency: bundle.currency,
      promoCode: promoCode,
    );
    final int discount = redemption?.discountInCents ?? 0;
    final int amount = bundle.priceInCents - discount;

    if (amount <= 0) {
      final List<EntitlementRecord> entitlements = await books.grantSale(
        buyerId: buyerId,
        lines: _linesOf(
          sales: sales,
          amountInCents: 0,
          source: 'free_${_generator.generate().value}',
        ),
        currency: bundle.currency,
        promoCode: redemption?.code,
        bundleId: bundle.id,
      );
      return BundleOrder(
        bundleId: bundle.id,
        buyerId: buyerId,
        priceInCents: bundle.priceInCents,
        currency: bundle.currency,
        discountInCents: discount,
        promoCode: redemption?.code,
        entitlements: entitlements,
      );
    }

    final CheckoutSession session;
    try {
      session = await gateway.createBundleSession(
        BundleCheckoutRequest(
          userId: buyerId,
          bundleId: bundle.id,
          title: bundle.title,
          priceInCents: amount,
          currency: bundle.currency,
          successUrl: successUrl,
          cancelUrl: cancelUrl,
          idempotencyKey: idempotencyKey,
          promoCode: redemption?.code,
        ),
      );
    } on Object {
      // La session n'a pas pu etre ouverte : la reservation du code est
      // rendue. Sans elle, une commande qui echoue epuise le quota d'un
      // code que l'acheteur n'a jamais utilise.
      await books.releasePromo(code: redemption?.code, buyerId: buyerId);
      rethrow;
    }

    return BundleOrder(
      bundleId: bundle.id,
      buyerId: buyerId,
      priceInCents: bundle.priceInCents,
      currency: bundle.currency,
      discountInCents: discount,
      promoCode: redemption?.code,
      session: session,
    );
  }

  /// Accorde les droits de lecture d'un paiement de bundle confirmé.
  ///
  /// L'acheteur reçoit le droit de lecture sur **chaque** livre du
  /// bundle. La ventilation se fait sur le montant **payé** : la remise
  /// d'un code promo ne sort jamais de la poche de l'auteur.
  ///
  /// L'octroi est **idempotent** : le même paiement ne crée pas deux fois
  /// le même droit, et la ventilation du premier paiement est conservée.
  ///
  /// Rend l'action tracée dans le journal d'audit, `null` quand le bundle
  /// n'existe pas ou que les droits existaient déjà.
  Future<String?> applyPayment({
    required String buyerId,
    required String bundleId,
    required String source,
    int? amountInCents,
    String? promoCode,
    String? ip,
  }) async {
    final BundleRecord? bundle = await bundles.findById(bundleId);
    if (bundle == null) {
      // Le bundle n'existe pas : le paiement ne donne aucun droit.
      return null;
    }
    final List<BookSaleRecord> sales = await _salesOf(bundle);
    final int amount = amountInCents ?? bundle.priceInCents;
    final List<EntitlementRecord> granted = await books.grantSale(
      buyerId: buyerId,
      lines: _linesOf(sales: sales, amountInCents: amount, source: source),
      currency: bundle.currency,
      promoCode: promoCode,
      bundleId: bundle.id,
    );
    if (granted.isEmpty) {
      // Les droits existaient deja : le paiement a deja ete traite.
      return null;
    }
    final int authorAmount = granted.fold(
      0,
      (int sum, EntitlementRecord record) => sum + record.authorAmountInCents,
    );
    final int platformAmount = granted.fold(
      0,
      (int sum, EntitlementRecord record) => sum + record.platformAmountInCents,
    );
    await audit.record(
      AuditEntry(
        userId: buyerId,
        action: 'bundle.purchase_completed',
        targetType: 'bundle',
        targetId: bundle.id,
        metadata: <String, Object?>{
          'payment_reference': source,
          'amount_cents': amount,
          'currency': bundle.currency,
          'author_amount_cents': authorAmount,
          'platform_amount_cents': platformAmount,
          'owner_id': bundle.ownerId,
          'project_ids': List<String>.unmodifiable(bundle.projectIds),
          'promo_code': ?promoCode,
        },
        ip: ip,
      ),
    );
    return 'bundle.purchase_completed';
  }

  /// Les ventes des livres du bundle.
  ///
  /// Une vente disparue ne fait pas echouer le paiement : le paiement est
  /// deja encaisse, et l'acheteur a paye pour ces livres. Le livre sans
  /// vente ne contribue alors rien au prix, et la part de l'auteur par
  /// defaut s'applique.
  Future<List<BookSaleRecord>> _salesOf(BundleRecord bundle) async {
    final List<BookSaleRecord> sales = <BookSaleRecord>[];
    for (final String projectId in bundle.projectIds) {
      final BookSaleRecord? sale = await books.saleOf(projectId);
      if (sale == null) {
        sales.add(
          BookSaleRecord(
            projectId: projectId,
            ownerId: bundle.ownerId,
            title: '',
            priceInCents: 0,
            currency: bundle.currency,
            status: BookSaleStatus.withdrawn,
            authorShare: defaultAuthorShare,
            platformShare: revenueShareTotal - defaultAuthorShare,
            createdAt: bundle.createdAt,
            updatedAt: bundle.createdAt,
          ),
        );
        continue;
      }
      sales.add(sale);
    }
    return sales;
  }

  /// Les lignes de la vente : la part de chaque livre dans le montant payé.
  ///
  /// La part est le **prorata** de ce que chaque livre contribue au prix :
  /// le livre le plus cher reçoit le plus gros morceau. La part de l'auteur
  /// est celle de la vente du livre : la règle est la même pour un livre
  /// vendu seul et pour un livre vendu dans un bundle.
  ///
  /// Chaque ligne porte **sa** commande : le droit de lecture est unique
  /// par livre, et la source l'est aussi.
  List<SaleLine> _linesOf({
    required List<BookSaleRecord> sales,
    required int amountInCents,
    required String source,
  }) {
    final List<RevenueSplit> splits = _revenue.splitAmong(
      amountInCents: amountInCents,
      lines: <RevenueLine>[
        for (final BookSaleRecord sale in sales)
          RevenueLine(weight: sale.priceInCents, authorShare: sale.authorShare),
      ],
    );
    return List<SaleLine>.unmodifiable(
      List<SaleLine>.generate(sales.length, (int index) {
        final BookSaleRecord sale = sales[index];
        return SaleLine(
          projectId: sale.projectId,
          amountInCents: splits[index].amountInCents,
          authorShare: splits[index].authorShare,
          source: '$source:${sale.projectId}',
        );
      }),
    );
  }

  /// Le bundle [bundleId], refusé quand il n'est pas en vente.
  Future<BundleRecord> _requireForSale(String bundleId) async {
    final BundleRecord? bundle = await bundles.findById(bundleId);
    if (bundle == null) {
      throw const NotFoundException(message: "Ce bundle n'existe pas.");
    }
    if (!bundle.isPublished) {
      throw const ConflictException(message: "Ce bundle n'est pas en vente.");
    }
    return bundle;
  }

  /// Le bundle [bundleId], refusé quand le compte [ownerId] n'en est pas
  /// le vendeur.
  Future<BundleRecord> _requireOwned({
    required String bundleId,
    required String ownerId,
  }) async {
    final BundleRecord? bundle = await bundles.findById(bundleId);
    if (bundle == null) {
      throw const NotFoundException(message: "Ce bundle n'existe pas.");
    }
    if (bundle.ownerId != ownerId) {
      throw const ForbiddenException(
        message: 'Seul le vendeur du bundle peut le publier.',
      );
    }
    return bundle;
  }

  /// Les ventes des livres [projectIds], refusées quand un livre n'est pas
  /// en vente ou n'appartient pas au vendeur.
  ///
  /// Un livre que le vendeur ne possède pas est introuvable : la réponse
  /// ne dit pas à un tiers que le livre existe.
  Future<List<BookSaleRecord>> _requireSellableBooks({
    required String ownerId,
    required List<String> projectIds,
  }) async {
    final List<BookSaleRecord> sales = <BookSaleRecord>[];
    for (final String projectId in projectIds) {
      final ProjectAccess? access = await books.projects.access(
        projectId: projectId,
        userId: ownerId,
      );
      if (access == null) {
        throw const NotFoundException(message: "Ce livre n'existe pas.");
      }
      if (access.role != ProjectRole.owner) {
        throw const ForbiddenException(
          message:
              'Seul le propriétaire du livre peut le vendre dans un bundle.',
        );
      }
      final BookSaleRecord? sale = await books.saleOf(projectId);
      if (sale == null || !sale.isPublished) {
        throw ValidationException(
          field: 'project_ids',
          message:
              'Le livre « $projectId » n\'est pas en vente : un bundle ne '
              'contient que des livres en vente.',
          details: <String, Object?>{'field': 'project_ids'},
        );
      }
      sales.add(sale);
    }
    return sales;
  }

  /// Le titre validé.
  String _readTitle(String title) {
    final String trimmed = title.trim();
    if (trimmed.isEmpty) {
      throw const ValidationException(
        field: 'title',
        message: 'Le champ « title » ne peut pas être vide.',
      );
    }
    return trimmed;
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

  /// La liste des livres validée.
  ///
  /// La liste porte **au moins deux livres**, et aucun livre deux fois :
  /// un bundle d'un seul livre est une vente simple, et un livre répété
  /// fausserait la ventilation.
  List<String> _readProjectIds(List<String> projectIds) {
    final List<String> books = <String>[
      for (final String projectId in projectIds)
        if (projectId.trim().isNotEmpty) projectId.trim(),
    ];
    if (books.length < minimumBundleBooks) {
      throw ValidationException(
        field: 'project_ids',
        message:
            'Le champ « project_ids » doit porter au moins '
            '$minimumBundleBooks livres : un bundle d\'un seul livre est une '
            'vente simple.',
        details: <String, Object?>{'field': 'project_ids'},
      );
    }
    if (books.toSet().length != books.length) {
      throw ValidationException(
        field: 'project_ids',
        message:
            'Le champ « project_ids » ne peut pas porter deux fois le même '
            'livre.',
        details: <String, Object?>{'field': 'project_ids'},
      );
    }
    return List<String>.unmodifiable(books);
  }
}
