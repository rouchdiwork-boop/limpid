import 'package:flutter/material.dart';
import 'package:limpid_app/l10n/generated/app_localizations.dart';
import 'package:limpid_app/src/features/auth/widgets/auth_form.dart';
import 'package:limpid_design_system/limpid_design_system.dart';

/// The sign-in screen.
class SignInScreen extends StatelessWidget {
  /// Creates the screen.
  const SignInScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final scope = context.limpid;

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(
            horizontal: scope.spacing.space24,
            vertical: scope.spacing.space40,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  'Limpid.',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: scope.colors.accent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: scope.spacing.space32),
                Text(
                  strings.signInTitle,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: scope.colors.fgDefault,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: scope.spacing.space8),
                Text(
                  strings.signInSubtitle,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: scope.colors.fgMuted),
                ),
                SizedBox(height: scope.spacing.space32),
                const AuthForm(mode: AuthFormMode.signIn),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
