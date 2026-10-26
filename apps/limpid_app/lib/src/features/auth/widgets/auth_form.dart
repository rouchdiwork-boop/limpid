import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:limpid_app/l10n/generated/app_localizations.dart';
import 'package:limpid_app/src/app/router.dart';
import 'package:limpid_app/src/auth/auth_errors.dart';
import 'package:limpid_app/src/auth/auth_repository.dart';
import 'package:limpid_app/src/auth/supabase_auth_repository.dart';
import 'package:limpid_app/src/bootstrap/app_bootstrap.dart';
import 'package:limpid_design_system/limpid_design_system.dart';

/// The two modes of the authentication form.
enum AuthFormMode {
  /// The author already has an account.
  signIn,

  /// The author creates an account.
  signUp,
}

/// The authentication form.
///
/// The magic link is the primary path: the author never has to invent or
/// remember a password (D-15). The password field only appears once the
/// author explicitly asks for it.
class AuthForm extends ConsumerStatefulWidget {
  /// Creates the form.
  const AuthForm({required this.mode, super.key});

  /// The mode of the form.
  final AuthFormMode mode;

  @override
  ConsumerState<AuthForm> createState() => _AuthFormState();
}

class _AuthFormState extends ConsumerState<AuthForm> {
  final _emailController = TextEditingController();
  final _nameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _emailFocus = FocusNode();

  bool _usePassword = false;
  bool _sending = false;
  bool _linkSent = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _nameController.dispose();
    _passwordController.dispose();
    _emailFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final strings = AppLocalizations.of(context);
    final email = _emailController.text.trim();
    final name = _nameController.text.trim();

    if (email.isEmpty) {
      setState(() => _error = strings.errorEmptyEmail);
      _emailFocus.requestFocus();
      return;
    }
    if (!isValidEmail(email)) {
      setState(() => _error = strings.errorInvalidEmail);
      _emailFocus.requestFocus();
      return;
    }
    if (widget.mode == AuthFormMode.signUp && name.isEmpty) {
      setState(() => _error = strings.errorEmptyName);
      return;
    }

    setState(() {
      _sending = true;
      _error = null;
    });

    try {
      final repository = ref.read(authRepositoryProvider);
      if (_usePassword) {
        await repository.signInWithPassword(email, _passwordController.text);
      } else {
        await repository.sendMagicLink(
          email,
          authorName: widget.mode == AuthFormMode.signUp ? name : null,
        );
      }
      if (!mounted) return;
      setState(() {
        _sending = false;
        _linkSent = true;
      });
    } on AuthException catch (error) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = authErrorMessage(error.kind, strings);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final scope = context.limpid;

    if (_linkSent) {
      return _LinkSent(
        email: _emailController.text.trim(),
        onResend: () => setState(() => _linkSent = false),
        onChangeAddress: () => setState(() {
          _linkSent = false;
          _emailController.clear();
        }),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (!AppBootstrap.isSupabaseConfigured) ...<Widget>[
          LimpidBanner(
            variant: LimpidStatusVariant.info,
            title: strings.demoModeTitle,
            message: strings.demoModeMessage,
          ),
          SizedBox(height: scope.spacing.space20),
        ],
        if (widget.mode == AuthFormMode.signUp) ...<Widget>[
          LimpidTextField(
            controller: _nameController,
            label: strings.fieldAuthorName,
            helperText: strings.fieldAuthorNameHint,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            onChanged: (_) => setState(() => _error = null),
          ),
          SizedBox(height: scope.spacing.space16),
        ],
        LimpidTextField(
          controller: _emailController,
          focusNode: _emailFocus,
          label: strings.fieldEmail,
          keyboardType: TextInputType.emailAddress,
          textInputAction: _usePassword
              ? TextInputAction.next
              : TextInputAction.done,
          autofillHints: const <String>[AutofillHints.email],
          onChanged: (_) => setState(() => _error = null),
          onSubmitted: (_) => _usePassword ? _submit() : null,
          errorText: _error,
        ),
        if (_usePassword) ...<Widget>[
          SizedBox(height: scope.spacing.space16),
          LimpidTextField(
            controller: _passwordController,
            label: strings.fieldPassword,
            obscureText: true,
            textInputAction: TextInputAction.done,
            autofillHints: const <String>[AutofillHints.password],
            onSubmitted: (_) => _submit(),
          ),
        ],
        SizedBox(height: scope.spacing.space24),
        LimpidButton(
          label: _error != null
              ? strings.actionRetry
              : (_usePassword
                    ? strings.actionContinue
                    : strings.actionSendLink),
          variant: LimpidButtonVariant.primary,
          size: LimpidButtonSize.large,
          loading: _sending,
          expand: true,
          onPressed: _submit,
        ),
        SizedBox(height: scope.spacing.space12),
        Align(
          alignment: Alignment.center,
          child: TextButton(
            onPressed: () => setState(() => _usePassword = !_usePassword),
            child: Text(strings.signInUsePassword),
          ),
        ),
        SizedBox(height: scope.spacing.space8),
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 4,
          children: <Widget>[
            Text(
              widget.mode == AuthFormMode.signIn
                  ? strings.signInNoAccount
                  : strings.signUpHaveAccount,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: scope.colors.fgMuted),
            ),
            TextButton(
              onPressed: () => context.go(
                widget.mode == AuthFormMode.signIn
                    ? AppRoutes.signUp
                    : AppRoutes.signIn,
              ),
              child: Text(
                widget.mode == AuthFormMode.signIn
                    ? strings.signInCreateAccount
                    : strings.signUpSignIn,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _LinkSent extends StatelessWidget {
  const _LinkSent({
    required this.email,
    required this.onResend,
    required this.onChangeAddress,
  });

  final String email;
  final VoidCallback onResend;
  final VoidCallback onChangeAddress;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final scope = context.limpid;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        LimpidBanner(
          variant: LimpidStatusVariant.success,
          title: strings.linkSentTitle,
          message: strings.linkSentMessage(email),
        ),
        SizedBox(height: scope.spacing.space24),
        LimpidButton(
          label: strings.linkSentResend,
          variant: LimpidButtonVariant.secondary,
          size: LimpidButtonSize.large,
          expand: true,
          onPressed: onResend,
        ),
        SizedBox(height: scope.spacing.space8),
        Align(
          alignment: Alignment.center,
          child: TextButton(
            onPressed: onChangeAddress,
            child: Text(strings.linkSentChangeAddress),
          ),
        ),
      ],
    );
  }
}
