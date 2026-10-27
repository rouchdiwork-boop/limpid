import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:limpid_app/l10n/generated/app_localizations.dart';
import 'package:limpid_app/src/domain/book_sale_repository.dart';
import 'package:limpid_app/src/features/publication/purchases/purchases_actions.dart';
import 'package:limpid_app/src/features/publication/purchases/purchases_states.dart';
import 'package:limpid_app/src/features/publication/sale/sale_providers.dart';
import 'package:limpid_design_system/limpid_design_system.dart';

/// La cle de la ligne d'un livre achete.
Key purchaseTileKey(String projectId) => Key('purchase-tile-$projectId');

/// La cle du bouton qui telecharge un livre achete.
Key purchaseDownloadKey(String projectId) =>
    Key('purchase-download-$projectId');

/// L'ecran des livres achetes par le compte.
///
/// L'ecran montre la liste des livres achetes, la date de l'achat et l'etat
/// du telechargement. Le bouton « Telecharger » demande une adresse au
/// serveur, telecharge le fichier et l'enregistre hors de l'application.
///
/// L'adresse de telechargement **expire** : l'ecran le dit, et l'acheteur
/// peut en demander une autre.
class PurchasesScreen extends ConsumerStatefulWidget {
  /// Cree l'ecran.
  const PurchasesScreen({super.key});

  @override
  ConsumerState<PurchasesScreen> createState() => _PurchasesScreenState();
}

class _PurchasesScreenState extends ConsumerState<PurchasesScreen> {
  /// Le dernier fichier obtenu pour chaque livre.
  Map<String, BookFile> _files = const <String, BookFile>{};

  /// Les livres dont le telechargement est en cours.
  Set<String> _running = const <String>{};

  @override
  Widget build(BuildContext context) {
    final AppLocalizations strings = AppLocalizations.of(context);
    final LimpidThemeScope scope = context.limpid;
    final AsyncValue<List<BookPurchase>> purchases = ref.watch(
      bookPurchasesProvider,
    );

    return Scaffold(
      body: ListView(
        padding: EdgeInsets.all(scope.spacing.space24),
        children: <Widget>[
          Text(
            strings.purchasesTitle,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              color: scope.colors.fgDefault,
              fontWeight: FontWeight.w600,
              fontFamily: LimpidFontFamily.display,
            ),
          ),
          SizedBox(height: scope.spacing.space4),
          Text(
            strings.purchasesSubtitle,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: scope.colors.fgMuted),
          ),
          SizedBox(height: scope.spacing.space20),
          purchases.when(
            loading: () => const PurchasesLoading(),
            error: (Object error, StackTrace stackTrace) => PurchasesFailure(
              onRetry: () => ref.invalidate(bookPurchasesProvider),
            ),
            data: (List<BookPurchase> list) {
              if (list.isEmpty) return const PurchasesEmpty();
              return Column(
                children: <Widget>[
                  for (final BookPurchase purchase in list) ...<Widget>[
                    _PurchaseTile(
                      purchase: purchase,
                      file: _files[purchase.projectId],
                      isRunning: _running.contains(purchase.projectId),
                      onDownload: () => _download(purchase),
                    ),
                    SizedBox(height: scope.spacing.space12),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  /// Telecharge le livre achete et garde le fichier obtenu.
  ///
  /// Le fichier porte la duree de vie de l'adresse qui l'a servi : l'ecran
  /// la dit, et l'acheteur peut en demander une autre.
  Future<void> _download(BookPurchase purchase) async {
    final String projectId = purchase.projectId;
    if (_running.contains(projectId)) return;
    setState(() {
      _running = <String>{..._running, projectId};
    });

    final BookFile? file = await downloadPurchasedBook(context, ref, projectId);

    if (!mounted) return;
    setState(() {
      _running = _running.difference(<String>{projectId});
      if (file != null) {
        _files = <String, BookFile>{..._files, projectId: file};
      }
    });
  }
}

/// La ligne d'un livre achete.
class _PurchaseTile extends StatelessWidget {
  const _PurchaseTile({
    required this.purchase,
    required this.file,
    required this.isRunning,
    required this.onDownload,
  });

  /// Le livre achete.
  final BookPurchase purchase;

  /// Le dernier fichier obtenu pour ce livre, `null` quand il n'y en a pas.
  final BookFile? file;

  /// Le telechargement est-il en cours ?
  final bool isRunning;

  /// Appele quand l'acheteur veut le fichier.
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations strings = AppLocalizations.of(context);
    final LimpidThemeScope scope = context.limpid;
    final TextTheme textTheme = Theme.of(context).textTheme;
    final BookFile? downloaded = file;
    final bool isExpired =
        downloaded != null && downloaded.isExpiredAt(DateTime.now());
    // La provenance de l'achat : un livre achete par un bundle montre le
    // bundle qui l'a porte.
    final String? bundleTitle = purchase.bundleTitle;

    return LimpidCard(
      key: purchaseTileKey(purchase.projectId),
      padding: EdgeInsets.all(scope.spacing.space16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            purchase.title,
            style: textTheme.titleMedium?.copyWith(
              color: scope.colors.fgDefault,
            ),
          ),
          SizedBox(height: scope.spacing.space4),
          Text(
            strings.purchasesBoughtOn(_dateOf(context, purchase.grantedAt)),
            style: textTheme.bodySmall?.copyWith(color: scope.colors.fgMuted),
          ),
          if (bundleTitle != null) ...<Widget>[
            SizedBox(height: scope.spacing.space4),
            Row(
              children: <Widget>[
                Icon(
                  LimpidIcons.library,
                  size: 14,
                  color: scope.colors.fgSubtle,
                ),
                SizedBox(width: scope.spacing.space8),
                Expanded(
                  child: Text(
                    bundleTitle,
                    style: textTheme.bodySmall?.copyWith(
                      color: scope.colors.fgSubtle,
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (downloaded != null) ...<Widget>[
            SizedBox(height: scope.spacing.space4),
            Text(
              isExpired
                  ? strings.purchasesLinkExpired
                  : strings.purchasesLinkExpires(
                      _dateOf(context, downloaded.expiresAt),
                    ),
              style: textTheme.bodySmall?.copyWith(
                color: isExpired ? scope.colors.danger : scope.colors.fgSubtle,
              ),
            ),
          ],
          SizedBox(height: scope.spacing.space12),
          LimpidButton(
            key: purchaseDownloadKey(purchase.projectId),
            label: isExpired
                ? strings.purchasesRenewLink
                : strings.exportDownload,
            icon: LimpidIcons.download,
            size: LimpidButtonSize.small,
            loading: isRunning,
            onPressed: isRunning ? null : onDownload,
          ),
        ],
      ),
    );
  }

  /// Ecrit une date dans la langue de l'interface.
  String _dateOf(BuildContext context, DateTime moment) {
    return MaterialLocalizations.of(context).formatMediumDate(moment);
  }
}
