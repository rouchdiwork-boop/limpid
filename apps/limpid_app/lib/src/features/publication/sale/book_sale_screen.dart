import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:limpid_app/l10n/generated/app_localizations.dart';
import 'package:limpid_app/src/app/router.dart';
import 'package:limpid_app/src/domain/book_sale_repository.dart';
import 'package:limpid_app/src/domain/errors.dart';
import 'package:limpid_app/src/domain/providers.dart';
import 'package:limpid_app/src/domain/publication_repository.dart';
import 'package:limpid_app/src/features/billing/billing_formatters.dart';
import 'package:limpid_app/src/features/dashboard/dashboard_providers.dart';
import 'package:limpid_app/src/features/projects/project_cover.dart';
import 'package:limpid_app/src/features/projects/project_metrics.dart';
import 'package:limpid_app/src/features/publication/publication_providers.dart';
import 'package:limpid_app/src/features/publication/publication_routes.dart';
import 'package:limpid_app/src/features/publication/sale/sale_actions.dart';
import 'package:limpid_app/src/features/publication/sale/sale_providers.dart';
import 'package:limpid_app/src/features/publication/sale/sale_states.dart';
import 'package:limpid_core/limpid_core.dart';
import 'package:limpid_design_system/limpid_design_system.dart';

/// La cle du prix affiche sur la page de vente.
const Key bookSalePriceKey = Key('book-sale-price');

/// La cle du bouton qui achete le livre.
const Key bookSaleBuyKey = Key('book-sale-buy');

/// La cle de la couverture du livre, sur la page de vente.
const Key bookSaleCoverKey = Key('book-sale-cover');

/// La page de vente d'un livre.
///
/// La page montre le titre, la couverture, le resume et le **prix** du
/// livre. Le prix vient du serveur : un livre qui n'est pas en vente n'a
/// pas de prix, et la page le dit au lieu d'en afficher un.
///
/// Le bouton « Acheter » commande le livre et ouvre l'adresse de paiement
/// que le serveur renvoie. Sur les plateformes natives, l'application ne
/// peut pas ouvrir une page de paiement : elle le dit.
class BookSaleScreen extends ConsumerStatefulWidget {
  /// Cree la page de vente.
  const BookSaleScreen({required this.projectId, super.key});

  /// L'identifiant du livre vendu.
  final String projectId;

  @override
  ConsumerState<BookSaleScreen> createState() => _BookSaleScreenState();
}

class _BookSaleScreenState extends ConsumerState<BookSaleScreen> {
  bool _isOrdering = false;

  @override
  Widget build(BuildContext context) {
    final AsyncValue<BookSale?> sale = ref.watch(
      bookSaleProvider(widget.projectId),
    );

    return Scaffold(
      body: SafeArea(
        child: sale.when(
          loading: () => const BookSaleLoading(),
          error: (Object error, StackTrace stackTrace) => switch (error) {
            ApiUnauthorizedException() => BookSaleSignInRequired(
              onSignIn: () => context.go(AppRoutes.signIn),
            ),
            _ => BookSaleFailure(
              onRetry: () => ref.invalidate(bookSaleProvider(widget.projectId)),
            ),
          },
          data: (BookSale? data) => data == null
              ? const BookSaleNotForSale()
              : _SaleBody(sale: data, isOrdering: _isOrdering, onBuy: _buy),
        ),
      ),
    );
  }

  /// Commande le livre et ouvre l'adresse de paiement.
  ///
  /// Le bouton est desactive pendant la commande : deux commandes ne
  /// doivent pas partir d'un double-clic.
  Future<void> _buy() async {
    if (_isOrdering) return;
    setState(() => _isOrdering = true);
    await buyBook(context, ref, widget.projectId);
    if (!mounted) return;
    setState(() => _isOrdering = false);
  }
}

/// Le corps de la page de vente d'un livre en vente.
class _SaleBody extends ConsumerWidget {
  const _SaleBody({
    required this.sale,
    required this.isOrdering,
    required this.onBuy,
  });

  /// La vente du livre.
  final BookSale sale;

  /// Une commande est-elle en cours ?
  final bool isOrdering;

  /// Appele quand le lecteur achete le livre.
  final VoidCallback onBuy;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations strings = AppLocalizations.of(context);
    final LimpidThemeScope scope = context.limpid;
    final TextTheme textTheme = Theme.of(context).textTheme;
    final AsyncValue<Publication> publication = ref.watch(
      publicationProvider(sale.projectId),
    );
    final Project? project = _projectOf(publication.value);
    final String title = project?.title ?? sale.title;
    final String synopsis = project?.synopsis ?? '';

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
                  strings.salePageTitle,
                  style: textTheme.titleMedium?.copyWith(
                    color: scope.colors.fgMuted,
                    fontFamily: LimpidFontFamily.display,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: scope.spacing.space24),
          if (project != null) ...<Widget>[
            ProjectCover(
              key: bookSaleCoverKey,
              title: title,
              author: _authorOf(context, ref, project),
              seed: coverSeedOf(project.id.value),
              width: 200,
            ),
            SizedBox(height: scope.spacing.space24),
          ],
          Text(
            title,
            style: textTheme.headlineMedium?.copyWith(
              color: scope.colors.fgDefault,
              fontFamily: LimpidFontFamily.display,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (synopsis.isNotEmpty) ...<Widget>[
            SizedBox(height: scope.spacing.space12),
            Text(
              synopsis,
              style: textTheme.bodyLarge?.copyWith(
                color: scope.colors.fgDefault,
                fontFamily: LimpidFontFamily.manuscript,
                height: 1.75,
              ),
            ),
          ],
          SizedBox(height: scope.spacing.space24),
          _SalePrice(sale: sale),
          if (sale.isPublished) ...<Widget>[
            SizedBox(height: scope.spacing.space16),
            LimpidButton(
              key: bookSaleBuyKey,
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

  /// L'auteur du livre, quand le livre est celui du lecteur.
  ///
  /// La page de vente est publique : le nom du lecteur n'est pas l'auteur
  /// du livre qu'il achete.
  String _authorOf(BuildContext context, WidgetRef ref, Project project) {
    final AuthorId author = ref.watch(authorIdProvider);
    if (project.ownerId.value != author.value) return '';
    return ref.watch(authorNameProvider);
  }

  /// Quitte la page de vente et revient a la page publique du livre.
  void _goBack(BuildContext context) {
    if (context.canPop()) {
      context.pop();
      return;
    }
    context.go(PublicationRoutes.showcase(sale.projectId));
  }
}

/// Le prix du livre, et la devise de la vente.
class _SalePrice extends StatelessWidget {
  const _SalePrice({required this.sale});

  /// La vente du livre.
  final BookSale sale;

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
          _priceOf(strings, sale),
          key: bookSalePriceKey,
          style: textTheme.headlineSmall?.copyWith(
            color: scope.colors.fgDefault,
          ),
        ),
      ],
    );
  }

  /// Le prix ecrit dans la devise de la vente.
  ///
  /// Un livre se vend en euros : la devise n'est ecrite que lorsqu'elle
  /// n'est pas l'euro, pour que l'acheteur sache toujours ce qu'il paie.
  String _priceOf(AppLocalizations strings, BookSale sale) {
    if (sale.isFree) return strings.salePriceFree;
    if (sale.currency.toLowerCase() == 'eur') {
      return formatPrice(sale.priceInCents);
    }
    return '${sale.priceInCents ~/ 100} ${sale.currency}';
  }
}

/// Le manuscrit derriere la page publique du livre.
///
/// La page de vente lit la page publique du livre pour sa couverture et
/// son resume : un livre inconnu n'en a pas, et la page de vente montre
/// alors le seul titre que la vente lui donne.
Project? _projectOf(Publication? publication) => switch (publication) {
  PublishedBook(:final Project project) => project,
  UnpublishedBook(:final Project project) => project,
  UnknownBook() => null,
  null => null,
};
