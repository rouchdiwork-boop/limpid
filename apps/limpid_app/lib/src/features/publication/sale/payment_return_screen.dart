import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:limpid_app/l10n/generated/app_localizations.dart';
import 'package:limpid_app/src/domain/book_sale_repository.dart';
import 'package:limpid_app/src/features/publication/publication_routes.dart';
import 'package:limpid_app/src/features/publication/purchases/purchases_routes.dart';
import 'package:limpid_app/src/features/publication/sale/sale_providers.dart';
import 'package:limpid_app/src/features/publication/sale/sale_states.dart';
import 'package:limpid_design_system/limpid_design_system.dart';

/// La cle du titre de l'ecran de retour.
const Key paymentReturnTitleKey = Key('payment-return-title');

/// L'ecran de retour du paiement d'un livre.
///
/// Le prestataire de paiement renvoie l'acheteur ici. L'ecran ne croit
/// **jamais** l'adresse qui l'a ramene : c'est la liste des achats du
/// compte qui fait foi, et l'ecran s'y fie. Un livre absent de la liste
/// n'est pas declare achete.
class PaymentReturnScreen extends ConsumerWidget {
  /// Cree l'ecran de retour.
  const PaymentReturnScreen({required this.projectId, super.key});

  /// L'identifiant du livre paye.
  final String projectId;

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
          data: (List<BookPurchase> list) {
            final BookPurchase? purchase = _purchaseOf(list, projectId);
            return purchase == null
                ? _PaymentFailure(projectId: projectId)
                : _PaymentSuccess(purchase: purchase);
          },
        ),
      ),
    );
  }

  /// L'achat du livre dans la liste du compte, `null` quand il n'y est pas.
  BookPurchase? _purchaseOf(List<BookPurchase> list, String projectId) {
    for (final BookPurchase purchase in list) {
      if (purchase.projectId == projectId) return purchase;
    }
    return null;
  }
}

/// L'ecran de retour d'un paiement que le compte a paye.
class _PaymentSuccess extends StatelessWidget {
  const _PaymentSuccess({required this.purchase});

  /// L'achat que la liste des achats atteste.
  final BookPurchase purchase;

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
        action: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              purchase.title,
              key: paymentReturnTitleKey,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            SizedBox(height: scope.spacing.space16),
            LimpidButton(
              label: strings.paymentReturnSeePurchases,
              icon: LimpidIcons.library,
              onPressed: () => context.go(PurchasesRoutes.purchases),
            ),
          ],
        ),
      ),
    );
  }
}

/// L'ecran de retour d'un paiement que le compte n'a pas paye.
class _PaymentFailure extends StatelessWidget {
  const _PaymentFailure({required this.projectId});

  /// L'identifiant du livre paye.
  final String projectId;

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
          onPressed: () => context.go(PublicationRoutes.sale(projectId)),
        ),
      ),
    );
  }
}
