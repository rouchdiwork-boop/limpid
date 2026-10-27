import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:limpid_app/l10n/generated/app_localizations.dart';
import 'package:limpid_app/src/app/router.dart';
import 'package:limpid_app/src/domain/book_sale_repository.dart';
import 'package:limpid_app/src/domain/bundle_repository.dart';
import 'package:limpid_app/src/domain/errors.dart';
import 'package:limpid_app/src/features/billing/billing_formatters.dart';
import 'package:limpid_app/src/features/publication/bundle/bundle_actions.dart';
import 'package:limpid_app/src/features/publication/bundle/bundle_providers.dart';
import 'package:limpid_app/src/features/publication/bundle/bundle_routes.dart';
import 'package:limpid_app/src/features/publication/purchases/purchases_routes.dart';
import 'package:limpid_app/src/features/publication/sale/sale_providers.dart';
import 'package:limpid_app/src/features/publication/sale/sale_states.dart';
import 'package:limpid_design_system/limpid_design_system.dart';

/// La cle du prix affiche sur la page du bundle.
const Key bundlePriceKey = Key('bundle-price');

/// La cle du bouton qui achete le bundle.
const Key bundleBuyKey = Key('bundle-buy');

/// La cle du titre du bundle.
const Key bundleTitleKey = Key('bundle-title');

/// La cle de la ligne d'un livre du bundle.
Key bundleBookKey(String projectId) => Key('bundle-book-$projectId');

/// La page d'un bundle.
///
/// La page montre les livres que le bundle contient, son prix et son bouton
/// d'achat. Le prix vient du serveur : un bundle qui n'est pas en vente
/// n'a pas de prix, et la page le dit au lieu d'en afficher un.
///
/// Le bouton « Acheter » commande le bundle et ouvre l'adresse de paiement
/// que le serveur renvoie. Sur les plateformes natives, l'application ne
/// peut pas ouvrir une page de paiement : elle le dit.
class BundleScreen extends ConsumerStatefulWidget {
  /// Cree la page du bundle.
  const BundleScreen({required this.bundleId, super.key});

  /// L'identifiant du bundle vendu.
  final String bundleId;

  @override
  ConsumerState<BundleScreen> createState() => _BundleScreenState();
}

class _BundleScreenState extends ConsumerState<BundleScreen> {
  bool _isOrdering = false;

  @override
  Widget build(BuildContext context) {
    final AsyncValue<Bundle?> bundle = ref.watch(
      bundleProvider(widget.bundleId),
    );

    return Scaffold(
      body: SafeArea(
        child: bundle.when(
          loading: () => const BookSaleLoading(),
          error: (Object error, StackTrace stackTrace) => switch (error) {
            ApiUnauthorizedException() => BookSaleSignInRequired(
              onSignIn: () => context.go(AppRoutes.signIn),
            ),
            _ => BookSaleFailure(
              onRetry: () => ref.invalidate(bundleProvider(widget.bundleId)),
            ),
          },
          data: (Bundle? data) => data == null
              ? const BookSaleNotForSale()
              : _BundleBody(bundle: data, isOrdering: _isOrdering, onBuy: _buy),
        ),
      ),
    );
  }

  /// Commande le bundle et ouvre l'adresse de paiement.
  ///
  /// Le bouton est desactive pendant la commande : deux commandes ne
  /// doivent pas partir d'un double-clic.
  Future<void> _buy() async {
    if (_isOrdering) return;
    setState(() => _isOrdering = true);
    await buyBundle(context, ref, widget.bundleId);
    if (!mounted) return;
    setState(() => _isOrdering = false);
  }
}

/// Le corps de la page d'un bundle en vente.
class _BundleBody extends StatelessWidget {
  const _BundleBody({
    required this.bundle,
    required this.isOrdering,
    required this.onBuy,
  });

  /// Le bundle affiche.
  final Bundle bundle;

  /// Une commande est-elle en cours ?
  final bool isOrdering;

  /// Appele quand le lecteur achete le bundle.
  final VoidCallback onBuy;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations strings = AppLocalizations.of(context);
    final LimpidThemeScope scope = context.limpid;
    final TextTheme textTheme = Theme.of(context).textTheme;

    return SingleChildScrollView(
      padding: EdgeInsets.all(scope.spacing.space24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              LimpidIconButton(
                icon: LimpidIcons.arrowLeft,
                tooltip: strings.projectPublicPage,
                size: LimpidButtonSize.large,
                onPressed: () => _goBack(context),
              ),
              SizedBox(width: scope.spacing.space12),
              Expanded(
                child: Text(
                  strings.bundlePageTitle,
                  style: textTheme.titleMedium?.copyWith(
                    color: scope.colors.fgMuted,
                    fontFamily: LimpidFontFamily.display,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: scope.spacing.space24),
          Text(
            bundle.title,
            key: bundleTitleKey,
            style: textTheme.headlineMedium?.copyWith(
              color: scope.colors.fgDefault,
              fontFamily: LimpidFontFamily.display,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (bundle.description.isNotEmpty) ...<Widget>[
            SizedBox(height: scope.spacing.space12),
            Text(
              bundle.description,
              style: textTheme.bodyLarge?.copyWith(
                color: scope.colors.fgDefault,
                fontFamily: LimpidFontFamily.manuscript,
                height: 1.75,
              ),
            ),
          ],
          SizedBox(height: scope.spacing.space24),
          _BundleBooks(books: bundle.books),
          SizedBox(height: scope.spacing.space24),
          _BundlePrice(bundle: bundle),
          if (bundle.isPublished) ...<Widget>[
            SizedBox(height: scope.spacing.space16),
            LimpidButton(
              key: bundleBuyKey,
              label: strings.saleBuy,
              icon: LimpidIcons.money,
              size: LimpidButtonSize.large,
              expand: true,
              loading: isOrdering,
              onPressed: isOrdering ? null : onBuy,
            ),
          ],
        ],
      ),
    );
  }

  /// Quitte la page du bundle et revient a la page precedente.
  void _goBack(BuildContext context) {
    if (context.canPop()) {
      context.pop();
      return;
    }
    context.go(AppRoutes.dashboard);
  }
}

/// Les livres que le bundle contient.
///
/// L'ordre est celui du bundle : c'est lui qui fait le bundle, et le
/// lecteur le lit dans cet ordre.
class _BundleBooks extends StatelessWidget {
  const _BundleBooks({required this.books});

  /// Les livres du bundle.
  final List<BundleBook> books;

  @override
  Widget build(BuildContext context) {
    final LimpidThemeScope scope = context.limpid;
    final TextTheme textTheme = Theme.of(context).textTheme;

    if (books.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (final BundleBook book in books) ...<Widget>[
          LimpidCard(
            key: bundleBookKey(book.projectId),
            padding: EdgeInsets.all(scope.spacing.space16),
            child: Text(
              book.title,
              style: textTheme.titleMedium?.copyWith(
                color: scope.colors.fgDefault,
              ),
            ),
          ),
          SizedBox(height: scope.spacing.space12),
        ],
      ],
    );
  }
}

/// Le prix du bundle, et la devise de la vente.
class _BundlePrice extends StatelessWidget {
  const _BundlePrice({required this.bundle});

  /// Le bundle affiche.
  final Bundle bundle;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations strings = AppLocalizations.of(context);
    final LimpidThemeScope scope = context.limpid;
    final TextTheme textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          strings.projectMetadataPrice,
          style: textTheme.labelMedium?.copyWith(color: scope.colors.fgMuted),
        ),
        SizedBox(height: scope.spacing.space8),
        Text(
          _priceOf(strings, bundle),
          key: bundlePriceKey,
          style: textTheme.headlineSmall?.copyWith(
            color: scope.colors.fgDefault,
          ),
        ),
      ],
    );
  }

  /// Le prix ecrit dans la devise de la vente.
  ///
  /// Un bundle se vend en euros : la devise n'est ecrite que lorsqu'elle
  /// n'est pas l'euro, pour que l'acheteur sache toujours ce qu'il paie.
  String _priceOf(AppLocalizations strings, Bundle bundle) {
    if (bundle.isFree) return strings.salePriceFree;
    if (bundle.currency.toLowerCase() == 'eur') {
      return formatPrice(bundle.priceInCents);
    }
    return '${bundle.priceInCents ~/ 100} ${bundle.currency}';
  }
}

/// L'ecran de retour du paiement d'un bundle.
///
/// Le prestataire de paiement renvoie l'acheteur ici. L'ecran ne croit
/// **jamais** l'adresse qui l'a ramene : c'est la liste des achats du
/// compte qui fait foi, et l'ecran s'y fie. Un bundle absent de la liste
/// n'est pas declare achete.
class BundlePaymentReturnScreen extends ConsumerWidget {
  /// Cree l'ecran de retour.
  const BundlePaymentReturnScreen({required this.bundleId, super.key});

  /// L'identifiant du bundle paye.
  final String bundleId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<BookPurchase>> purchases = ref.watch(
      bookPurchasesProvider,
    );

    return Scaffold(
      body: SafeArea(
        child: purchases.when(
          loading: () => const BookSaleLoading(),
          error: (Object error, StackTrace stackTrace) => BookSaleFailure(
            onRetry: () => ref.invalidate(bookPurchasesProvider),
          ),
          data: (List<BookPurchase> list) => _purchaseOf(list, bundleId) == null
              ? _BundlePaymentFailure(bundleId: bundleId)
              : _BundlePaymentSuccess(bundle: _purchaseOf(list, bundleId)!),
        ),
      ),
    );
  }

  /// L'achat du bundle dans la liste du compte, `null` quand il n'y est pas.
  BookPurchase? _purchaseOf(List<BookPurchase> list, String bundleId) {
    for (final BookPurchase purchase in list) {
      if (purchase.bundleId == bundleId) return purchase;
    }
    return null;
  }
}

/// L'ecran de retour d'un paiement que le compte a paye.
class _BundlePaymentSuccess extends StatelessWidget {
  const _BundlePaymentSuccess({required this.bundle});

  /// L'achat que la liste des achats atteste.
  final BookPurchase bundle;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations strings = AppLocalizations.of(context);
    final LimpidThemeScope scope = context.limpid;

    return Padding(
      padding: EdgeInsets.symmetric(vertical: scope.spacing.space48),
      child: LimpidEmptyState(
        title: strings.paymentReturnSuccess,
        message: strings.paymentReturnSuccessMessage,
        icon: LimpidIcons.success,
        action: LimpidButton(
          label: strings.paymentReturnSeePurchases,
          icon: LimpidIcons.library,
          onPressed: () => context.go(PurchasesRoutes.purchases),
        ),
      ),
    );
  }
}

/// L'ecran de retour d'un paiement que le compte n'a pas paye.
class _BundlePaymentFailure extends StatelessWidget {
  const _BundlePaymentFailure({required this.bundleId});

  /// L'identifiant du bundle paye.
  final String bundleId;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations strings = AppLocalizations.of(context);
    final LimpidThemeScope scope = context.limpid;

    return Padding(
      padding: EdgeInsets.symmetric(vertical: scope.spacing.space48),
      child: LimpidEmptyState(
        title: strings.paymentReturnFailure,
        message: strings.paymentReturnFailureMessage,
        icon: LimpidIcons.warning,
        action: LimpidButton(
          label: strings.paymentReturnBackToBook,
          icon: LimpidIcons.arrowLeft,
          onPressed: () => context.go(BundleRoutes.bundle(bundleId)),
        ),
      ),
    );
  }
}
