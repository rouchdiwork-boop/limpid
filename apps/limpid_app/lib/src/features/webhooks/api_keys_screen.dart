import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:limpid_app/l10n/generated/app_localizations.dart';
import 'package:limpid_app/src/domain/providers.dart';
import 'package:limpid_app/src/domain/webhook_repository.dart';
import 'package:limpid_app/src/features/security/two_factor_challenge.dart';
import 'package:limpid_app/src/features/webhooks/api_keys_dialogs.dart';
import 'package:limpid_app/src/features/webhooks/webhook_providers.dart';
import 'package:limpid_app/src/features/webhooks/webhook_widgets.dart';
import 'package:limpid_design_system/limpid_design_system.dart';

/// L'écran des clés d'API du compte.
///
/// L'écran montre les clés de l'auteur, en crée, en renouvelle le secret et
/// en supprime. Le secret d'une clé est **rendu une seule fois** : l'écran
/// le montre au moment de la création ou du renouvellement, puis il ne
/// ment jamais sur sa présence — il ne prétend pas savoir le retrouver.
class ApiKeysScreen extends ConsumerStatefulWidget {
  /// Crée l'écran.
  const ApiKeysScreen({super.key});

  @override
  ConsumerState<ApiKeysScreen> createState() => _ApiKeysScreenState();
}

/// L'état de l'écran des clés d'API.
final class _ApiKeysScreenState extends ConsumerState<ApiKeysScreen> {
  /// Le secret montré à l'auteur, `null` quand l'écran n'en montre aucun.
  ///
  /// Le secret vit dans l'état de l'écran : il disparaît avec lui. L'écran
  /// ne le range nulle part et ne prétend pas savoir le rendre à nouveau.
  String? _secret;

  /// Le nom de la clé dont le secret est montré.
  String? _secretName;

  /// Une opération est-elle en cours ?
  bool _isBusy = false;

  /// Ouvre la fenêtre de création d'une clé.
  ///
  /// La création va au serveur : elle passe par la fenêtre du second
  /// facteur, et la clé n'est créée qu'une fois.
  Future<void> _create() async {
    final ApiKeyDraft? draft = await showApiKeyCreation(context);
    if (draft == null || !mounted) return;

    setState(() => _isBusy = true);
    try {
      final CreatedApiKey created = await runWithTwoFactor(
        context,
        ref,
        action: () => ref
            .read(webhookRepositoryProvider)
            .createApiKey(name: draft.name, scopes: draft.scopes),
      );
      if (!mounted) return;
      setState(() {
        _secret = created.secret;
        _secretName = created.key.name;
        _isBusy = false;
      });
      ref.invalidate(apiKeysProvider);
    } on Exception catch (error) {
      if (!mounted) return;
      setState(() => _isBusy = false);
      _reportFailure(error);
    } on Object catch (error, stackTrace) {
      // Une `Error` — et non une `Exception` — ne remonte pas dans le
      // `on Exception` ci-dessus : sans ce filet, l'échec disparaît et le
      // bouton semble ne rien faire. L'auteur voit un message, et la console
      // porte la cause.
      if (!mounted) return;
      setState(() => _isBusy = false);
      _reportFailure(error);
      debugPrint('L\'action sur la clé d\'API a échoué : $error\n$stackTrace');
    }
  }

  /// Renouvelle le secret de la clé [key] et montre le nouveau secret.
  ///
  /// Le renouvellement va au serveur : il passe par la fenêtre du second
  /// facteur. Le secret refusé n'a jamais été renouvelé : la répétition
  /// n'en rend donc qu'un.
  Future<void> _rotate(ApiKey key) async {
    setState(() => _isBusy = true);
    try {
      final CreatedApiKey rotated = await runWithTwoFactor(
        context,
        ref,
        action: () => ref.read(webhookRepositoryProvider).rotateApiKey(key.id),
      );
      if (!mounted) return;
      setState(() {
        _secret = rotated.secret;
        _secretName = rotated.key.name;
        _isBusy = false;
      });
      ref.invalidate(apiKeysProvider);
    } on Exception catch (error) {
      if (!mounted) return;
      setState(() => _isBusy = false);
      _reportFailure(error);
    } on Object catch (error, stackTrace) {
      // Une `Error` — et non une `Exception` — ne remonte pas dans le
      // `on Exception` ci-dessus : sans ce filet, l'échec disparaît et le
      // bouton semble ne rien faire. L'auteur voit un message, et la console
      // porte la cause.
      if (!mounted) return;
      setState(() => _isBusy = false);
      _reportFailure(error);
      debugPrint('L\'action sur la clé d\'API a échoué : $error\n$stackTrace');
    }
  }

  /// Supprime la clé [key], après la confirmation de l'auteur.
  ///
  /// La suppression va au serveur : elle passe par la fenêtre du second
  /// facteur.
  Future<void> _delete(ApiKey key) async {
    final bool confirmed = await showKeyDeletion(context, key.name);
    if (!confirmed || !mounted) return;

    setState(() => _isBusy = true);
    try {
      await runWithTwoFactor(
        context,
        ref,
        action: () => ref.read(webhookRepositoryProvider).deleteApiKey(key.id),
      );
      if (!mounted) return;
      setState(() => _isBusy = false);
      ref.invalidate(apiKeysProvider);
    } on Exception catch (error) {
      if (!mounted) return;
      setState(() => _isBusy = false);
      _reportFailure(error);
    } on Object catch (error, stackTrace) {
      // Une `Error` — et non une `Exception` — ne remonte pas dans le
      // `on Exception` ci-dessus : sans ce filet, l'échec disparaît et le
      // bouton semble ne rien faire. L'auteur voit un message, et la console
      // porte la cause.
      if (!mounted) return;
      setState(() => _isBusy = false);
      _reportFailure(error);
      debugPrint('L\'action sur la clé d\'API a échoué : $error\n$stackTrace');
    }
  }

  /// Referme le panneau du secret : le secret est perdu.
  void _dismissSecret() {
    setState(() {
      _secret = null;
      _secretName = null;
    });
  }

  /// Dit à l'auteur que l'opération a échoué.
  void _reportFailure(Object error) {
    final AppLocalizations strings = AppLocalizations.of(context);
    final String message = error is StudioPlanRequiredException
        ? strings.webhooksStudioOnly
        : strings.errorGeneric;
    LimpidSnackbar.show(
      context,
      message: message,
      variant: error is StudioPlanRequiredException
          ? LimpidStatusVariant.warning
          : LimpidStatusVariant.danger,
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations strings = AppLocalizations.of(context);
    final LimpidThemeScope scope = context.limpid;
    final bool isAvailable =
        ref.watch(webhookRepositoryProvider) is! UnavailableService;
    final AsyncValue<List<ApiKey>> keys = ref.watch(apiKeysProvider);
    final String? secret = _secret;

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.all(scope.spacing.space24),
          children: <Widget>[
            _header(context, strings),
            SizedBox(height: scope.spacing.space24),
            if (secret != null) ...<Widget>[
              WebhookSecretPanel(
                subject: _secretName,
                label: strings.apiKeysSecret,
                secret: secret,
                warning: strings.apiKeysSecretWarning,
                onDismiss: _dismissSecret,
              ),
              SizedBox(height: scope.spacing.space24),
            ],
            if (!isAvailable)
              LimpidBanner(
                variant: LimpidStatusVariant.info,
                title: strings.demoModeTitle,
                message: strings.demoModeMessage,
              )
            else ...<Widget>[
              LimpidButton(
                label: strings.apiKeysCreate,
                icon: LimpidIcons.add,
                expand: true,
                loading: _isBusy,
                onPressed: _create,
              ),
              SizedBox(height: scope.spacing.space16),
              _keys(context, strings, keys),
            ],
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
          strings.apiKeysTitle,
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
            strings.apiKeysSubtitle,
            textAlign: TextAlign.center,
            style: textTheme.bodyMedium?.copyWith(color: scope.colors.fgMuted),
          ),
        ),
      ],
    );
  }

  /// La liste des clés du compte.
  Widget _keys(
    BuildContext context,
    AppLocalizations strings,
    AsyncValue<List<ApiKey>> keys,
  ) {
    return keys.when(
      loading: () => const Center(child: LimpidSpinner()),
      error: (Object error, StackTrace stack) =>
          _failure(context, strings, error),
      data: (List<ApiKey> list) => _list(context, strings, list),
    );
  }

  /// La liste des clés, une fois lue.
  Widget _list(
    BuildContext context,
    AppLocalizations strings,
    List<ApiKey> keys,
  ) {
    final LimpidThemeScope scope = context.limpid;
    if (keys.isEmpty) {
      return LimpidEmptyState(
        title: strings.apiKeysEmpty,
        icon: LimpidIcons.code,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (final ApiKey key in keys) ...<Widget>[
          _keyCard(context, strings, key),
          SizedBox(height: scope.spacing.space12),
        ],
      ],
    );
  }

  /// La carte d'une clé.
  Widget _keyCard(BuildContext context, AppLocalizations strings, ApiKey key) {
    final LimpidThemeScope tokens = context.limpid;

    return LimpidCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                key.isUsable ? LimpidIcons.code : LimpidIcons.offline,
                color: tokens.colors.fgMuted,
              ),
              SizedBox(width: tokens.spacing.space12),
              Expanded(
                child: Text(
                  key.name,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: tokens.colors.fgDefault,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              SizedBox(width: tokens.spacing.space8),
              LimpidBadge(
                label: key.isUsable
                    ? strings.twoFactorStateOn
                    : strings.twoFactorStateOff,
                variant: key.isUsable
                    ? LimpidStatusVariant.success
                    : LimpidStatusVariant.neutral,
              ),
            ],
          ),
          SizedBox(height: tokens.spacing.space12),
          _keyDetails(context, strings, key),
          SizedBox(height: tokens.spacing.space12),
          Row(
            children: <Widget>[
              Expanded(
                child: LimpidButton(
                  label: strings.apiKeysRotate,
                  variant: LimpidButtonVariant.ghost,
                  onPressed: _isBusy ? null : () => _rotate(key),
                ),
              ),
              SizedBox(width: tokens.spacing.space8),
              Expanded(
                child: LimpidButton(
                  label: strings.apiKeysDelete,
                  variant: LimpidButtonVariant.danger,
                  onPressed: _isBusy ? null : () => _delete(key),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Le détail d'une clé : ses périmètres et son dernier usage.
  Widget _keyDetails(
    BuildContext context,
    AppLocalizations strings,
    ApiKey key,
  ) {
    final LimpidThemeScope scope = context.limpid;
    final DateTime? lastUsedAt = key.lastUsedAt;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Wrap(
          spacing: scope.spacing.space8,
          runSpacing: scope.spacing.space4,
          children: <Widget>[
            for (final ApiKeyScope scope in key.scopes)
              LimpidBadge(
                label: scope == ApiKeyScope.write
                    ? strings.apiKeysScopeWrite
                    : strings.apiKeysScopeRead,
                variant: LimpidStatusVariant.neutral,
              ),
          ],
        ),
        SizedBox(height: scope.spacing.space4),
        Row(
          children: <Widget>[
            Icon(LimpidIcons.clock, size: 14, color: scope.colors.fgMuted),
            SizedBox(width: scope.spacing.space4),
            Text(
              lastUsedAt == null
                  ? strings.webhooksNever
                  : formatWebhookDate(context, lastUsedAt),
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scope.colors.fgMuted),
            ),
          ],
        ),
      ],
    );
  }

  /// L'état d'échec de la lecture des clés.
  Widget _failure(
    BuildContext context,
    AppLocalizations strings,
    Object error,
  ) {
    if (error is StudioPlanRequiredException) {
      return LimpidBanner(
        variant: LimpidStatusVariant.warning,
        title: strings.webhooksStudioOnly,
      );
    }
    if (error is ServiceUnavailableException) {
      return LimpidBanner(
        variant: LimpidStatusVariant.info,
        title: strings.demoModeTitle,
        message: strings.demoModeMessage,
      );
    }
    return LimpidEmptyState(
      title: strings.errorGeneric,
      icon: LimpidIcons.error,
      action: LimpidButton(
        label: strings.actionRetry,
        onPressed: () => ref.invalidate(apiKeysProvider),
      ),
    );
  }
}
