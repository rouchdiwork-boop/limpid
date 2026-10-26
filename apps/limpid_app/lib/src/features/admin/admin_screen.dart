import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:limpid_app/l10n/generated/app_localizations.dart';
import 'package:limpid_app/src/domain/admin_repository.dart';
import 'package:limpid_app/src/features/admin/admin_providers.dart';
import 'package:limpid_app/src/features/admin/admin_routes.dart';
import 'package:limpid_app/src/features/admin/admin_widgets.dart';
import 'package:limpid_app/src/features/security/two_factor_challenge.dart';
import 'package:limpid_design_system/limpid_design_system.dart';

/// L'écran du back-office.
///
/// L'écran montre les comptes du service et les indicateurs de
/// fonctionnalité. Il est **réservé aux administrateurs** : le serveur
/// refuse la lecture à qui ne l'est pas, et l'écran le dit alors — il ne
/// montre jamais une liste vide qui ferait croire que le service n'a aucun
/// compte.
///
/// L'activation d'un indicateur part au serveur : elle passe par la fenêtre
/// du second facteur, et l'indicateur ne change d'état qu'une fois.
class AdminScreen extends ConsumerStatefulWidget {
  /// Crée l'écran du back-office.
  const AdminScreen({super.key});

  @override
  ConsumerState<AdminScreen> createState() => _AdminScreenState();
}

/// L'état de l'écran du back-office.
final class _AdminScreenState extends ConsumerState<AdminScreen> {
  /// Les indicateurs dont la demande est en cours.
  ///
  /// L'interrupteur de ces indicateurs est en lecture seule : l'écran montre
  /// l'état que le serveur a rendu, jamais un état qu'il a deviné.
  Set<String> _pending = const <String>{};

  @override
  Widget build(BuildContext context) {
    final AppLocalizations strings = AppLocalizations.of(context);
    final LimpidThemeScope scope = context.limpid;
    final AsyncValue<List<AdminAccount>> accounts = ref.watch(
      adminAccountsProvider,
    );
    final AsyncValue<List<AdminFeatureFlag>> flags = ref.watch(
      adminFeatureFlagsProvider,
    );

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.all(scope.spacing.space24),
          children: <Widget>[
            _header(context, strings),
            SizedBox(height: scope.spacing.space24),
            _sectionTitle(context, strings.adminAccountsTitle),
            SizedBox(height: scope.spacing.space12),
            _accounts(context, strings, accounts),
            SizedBox(height: scope.spacing.space24),
            _sectionTitle(context, strings.adminFlagsTitle),
            SizedBox(height: scope.spacing.space12),
            _flags(context, strings, flags),
          ],
        ),
      ),
    );
  }

  /// Le titre et la phrase d'introduction de la page.
  Widget _header(BuildContext context, AppLocalizations strings) {
    final LimpidThemeScope scope = context.limpid;
    final TextTheme textTheme = Theme.of(context).textTheme;

    return Column(
      children: <Widget>[
        Text(
          strings.adminTitle,
          textAlign: TextAlign.center,
          style: textTheme.headlineMedium?.copyWith(
            color: scope.colors.fgDefault,
            fontWeight: FontWeight.w600,
          ),
        ),
        SizedBox(height: scope.spacing.space8),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Text(
            strings.adminSubtitle,
            textAlign: TextAlign.center,
            style: textTheme.bodyMedium?.copyWith(color: scope.colors.fgMuted),
          ),
        ),
      ],
    );
  }

  /// Le titre d'une section de la page.
  Widget _sectionTitle(BuildContext context, String title) {
    final LimpidThemeScope scope = context.limpid;

    return Text(
      title,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
        color: scope.colors.fgDefault,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  /// La liste des comptes du service.
  Widget _accounts(
    BuildContext context,
    AppLocalizations strings,
    AsyncValue<List<AdminAccount>> accounts,
  ) {
    return accounts.when(
      loading: () => const Center(child: LimpidSpinner()),
      error: (Object error, StackTrace stack) => AdminFailureState(
        error: error,
        onRetry: () => ref.invalidate(adminAccountsProvider),
      ),
      data: (List<AdminAccount> list) {
        if (list.isEmpty) {
          return LimpidEmptyState(
            title: strings.adminAccountsEmpty,
            icon: LimpidIcons.users,
          );
        }
        final LimpidThemeScope scope = context.limpid;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            for (final AdminAccount account in list) ...<Widget>[
              AdminAccountCard(
                account: account,
                onTap: () => context.push(AdminRoutes.account(account.userId)),
              ),
              SizedBox(height: scope.spacing.space12),
            ],
          ],
        );
      },
    );
  }

  /// La liste des indicateurs de fonctionnalité.
  Widget _flags(
    BuildContext context,
    AppLocalizations strings,
    AsyncValue<List<AdminFeatureFlag>> flags,
  ) {
    return flags.when(
      loading: () => const Center(child: LimpidSpinner()),
      error: (Object error, StackTrace stack) => AdminFailureState(
        error: error,
        onRetry: () => ref.invalidate(adminFeatureFlagsProvider),
      ),
      data: (List<AdminFeatureFlag> list) {
        if (list.isEmpty) {
          return LimpidEmptyState(
            title: strings.adminFlagsEmpty,
            icon: LimpidIcons.flag,
          );
        }
        final LimpidThemeScope scope = context.limpid;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            for (final AdminFeatureFlag flag in list) ...<Widget>[
              AdminFeatureFlagCard(
                flag: flag,
                onChanged: _pending.contains(flag.key)
                    ? null
                    : (bool isEnabled) {
                        unawaited(_toggle(flag, isEnabled));
                      },
              ),
              SizedBox(height: scope.spacing.space12),
            ],
          ],
        );
      },
    );
  }

  /// Active ou désactive l'indicateur [flag].
  ///
  /// La demande part au serveur : elle passe par la fenêtre du second
  /// facteur. L'indicateur ne change d'état qu'une fois, quand le serveur a
  /// rendu le nouvel état.
  Future<void> _toggle(AdminFeatureFlag flag, bool isEnabled) async {
    setState(() {
      _pending = <String>{..._pending, flag.key};
    });
    try {
      await runWithTwoFactor(
        context,
        ref,
        action: () => ref
            .read(adminRepositoryProvider)
            .setFeatureFlag(flag.key, isEnabled: isEnabled),
      );
      ref.invalidate(adminFeatureFlagsProvider);
      if (!mounted) return;
      _announce(
        AppLocalizations.of(context).adminFlagUpdated,
        LimpidStatusVariant.success,
      );
    } on Exception catch (error) {
      if (!mounted) return;
      _announce(
        AppLocalizations.of(context).adminFlagFailed,
        LimpidStatusVariant.danger,
      );
      debugPrint("L'indicateur ${flag.key} n'a pas pu être modifié : $error");
    } on Object catch (error, stackTrace) {
      // Une `Error` — et non une `Exception` — ne remonte pas dans le
      // `on Exception` ci-dessus : sans ce filet, l'échec disparaît et
      // l'interrupteur semble ne rien faire.
      if (!mounted) return;
      _announce(
        AppLocalizations.of(context).adminFlagFailed,
        LimpidStatusVariant.danger,
      );
      debugPrint(
        "L'indicateur ${flag.key} n'a pas pu être modifié : $error\n$stackTrace",
      );
    } finally {
      if (mounted) {
        setState(() {
          _pending = _pending.difference(<String>{flag.key});
        });
      }
    }
  }

  /// Dit à l'administrateur ce qui vient de se passer.
  void _announce(String message, LimpidStatusVariant variant) {
    LimpidSnackbar.show(context, message: message, variant: variant);
  }
}
