import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/auth_state.dart';
import '../theme/tokens.dart';
import '../widgets/action_bar.dart';
import '../widgets/app_sheet.dart';
import '../l10n/l10n.dart';
import '../theme/app_icons.dart';

/// Registration and sign-in — the app's front door.
///
/// Registering is the primary action, and it is deliberately cheap: no
/// household to name, no members to add, nothing to choose. `handle_new_user`
/// creates the profile, a household and an admin membership server-side in the
/// same transaction as the account, so a brand-new user lands in a working
/// household immediately. Onboarding then only renames it.
class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _register = true;
  bool _obscure = true;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _submit() {
    FocusScope.of(context).unfocus();
    final notifier = ref.read(authProvider.notifier);
    if (_register) {
      notifier.signUp(
        email: _emailController.text,
        password: _passwordController.text,
        displayName: _nameController.text,
      );
    } else {
      notifier.signIn(email: _emailController.text, password: _passwordController.text);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);

    if (auth.status == AuthStatus.awaitingConfirmation) {
      return _ConfirmationPending(email: auth.email ?? '');
    }

    return Scaffold(
      backgroundColor: AppColors.screenBg,
      body: SafeArea(
        child: PinnedActionLayout(
          // The Scaffold resizes for the keyboard, so the bar rides up with it
          // and the action a filled-in form is reaching for stays in view
          // instead of being the thing the keyboard covers.
          action: _PrimaryButton(
            label: _register ? L.s.createAccount : L.s.signIn,
            busy: auth.busy,
            onTap: auth.busy ? null : _submit,
          ),
          bodyBuilder: (context, bottomInset) => SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(AppSpacing.screenPad, 40, AppSpacing.screenPad, bottomInset),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 12),
                Text(_register ? L.s.welcomeToAporah : L.s.welcomeBack, style: AppText.screenTitle),
                const SizedBox(height: 10),
                Text(_register ? L.s.signUpBlurb : L.s.signInBlurb, style: AppText.body),
                const SizedBox(height: 28),

                SectionCard(
                  children: [
                    if (_register) ...[
                      _Field(
                        controller: _nameController,
                        hint: L.s.yourName,
                        textCapitalization: TextCapitalization.words,
                        autofillHints: const [AutofillHints.name],
                      ),
                      CardDivider(),
                    ],
                    _Field(
                      controller: _emailController,
                      hint: L.s.emailAddress,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                    ),
                    CardDivider(),
                    _Field(
                      controller: _passwordController,
                      hint: L.s.password,
                      obscure: _obscure,
                      autofillHints: _register
                          ? const [AutofillHints.newPassword]
                          : const [AutofillHints.password],
                      textInputAction: TextInputAction.go,
                      onSubmitted: (_) => _submit(),
                      trailing: GestureDetector(
                        onTap: () => setState(() => _obscure = !_obscure),
                        behavior: HitTestBehavior.opaque,
                        child: Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: AppIcon(
                            _obscure ? AppIcons.eye : AppIcons.eyeSlash,
                            size: 18,
                            color: AppColors.mutedLight,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),

                if (_register) ...[
                  const SizedBox(height: 10),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      L.s.atLeast8Chars,
                      style: AppText.caption.copyWith(
                        fontWeight: FontWeight.w300,
                        color: AppColors.inkTertiary,
                      ),
                    ),
                  ),
                ],

                if (auth.error != null) ...[const SizedBox(height: 16), _ErrorNote(auth.error!)],

                // The two ways off this form stay in the scroll rather than
                // joining the button in the bar: they are the alternatives to it,
                // and a band carrying three stacked actions stops reading as one
                // primary action at all.
                const SizedBox(height: 24),
                Center(
                  child: GestureDetector(
                    onTap: () {
                      ref.read(authProvider.notifier).clearError();
                      setState(() => _register = !_register);
                    },
                    behavior: HitTestBehavior.opaque,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
                      child: Text(
                        _register ? L.s.haveAccountAlready : L.s.newHereCreateAccount,
                        style: AppText.rowTitle.copyWith(color: Theme.of(context).colorScheme.primary),
                      ),
                    ),
                  ),
                ),

                if (!_register)
                  Center(
                    child: GestureDetector(
                      onTap: auth.busy
                          ? null
                          : () => ref.read(authProvider.notifier).resetPassword(_emailController.text),
                      behavior: HitTestBehavior.opaque,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
                        child: Text(
                          L.s.forgotPassword,
                          style: AppText.body.copyWith(color: AppColors.inkTertiary),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Shown between registering and clicking the link in the mail. Supabase
/// returns a user but no session in that window, which is neither signed in
/// nor signed out.
class _ConfirmationPending extends ConsumerWidget {
  final String email;

  const _ConfirmationPending({required this.email});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accent = Theme.of(context).colorScheme.primary;
    return Scaffold(
      backgroundColor: AppColors.screenBg,
      body: SafeArea(
        child: PinnedActionLayout(
          action: _PrimaryButton(
            label: L.s.toSignIn,
            onTap: () => ref.read(authProvider.notifier).backToSignIn(),
          ),
          // The message stays centred in what is left above the bar, which is
          // what this screen has always been: one sentence and one way on.
          bodyBuilder: (context, bottomInset) => Padding(
            padding: EdgeInsets.fromLTRB(AppSpacing.screenPad, 40, AppSpacing.screenPad, bottomInset),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(color: shade(accent, .14), shape: BoxShape.circle),
                    alignment: Alignment.center,
                    child: AppIcon(AppIcons.envelopeOpen, size: 28, color: accent),
                  ),
                ),
                const SizedBox(height: 22),
                Text(L.s.almostThere, style: AppText.screenTitle, textAlign: TextAlign.center),
                const SizedBox(height: 10),
                Text(L.s.confirmMailSent(email), style: AppText.body, textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final bool obscure;
  final TextInputType? keyboardType;
  final TextCapitalization textCapitalization;
  final Iterable<String>? autofillHints;
  final ValueChanged<String>? onSubmitted;
  final Widget? trailing;

  /// What the keyboard's own return key says and does. The default walks to
  /// the next field; the last field of a form passes the action that submits
  /// it, so the return key and the button below agree.
  final TextInputAction textInputAction;

  const _Field({
    required this.controller,
    required this.hint,
    this.obscure = false,
    this.keyboardType,
    this.textCapitalization = TextCapitalization.none,
    this.autofillHints,
    this.onSubmitted,
    this.trailing,
    this.textInputAction = TextInputAction.next,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              obscureText: obscure,
              keyboardType: keyboardType,
              textCapitalization: textCapitalization,
              autofillHints: autofillHints,
              autocorrect: false,
              textInputAction: textInputAction,
              onSubmitted: onSubmitted,
              style: AppText.inputTitle,
              decoration: InputDecoration(border: InputBorder.none, hintText: hint, isDense: true),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

class _ErrorNote extends StatelessWidget {
  final String message;

  const _ErrorNote(this.message);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(AppRadii.cardSmall),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppIcon(AppIcons.info, size: 17, color: AppColors.danger),
          const SizedBox(width: 10),
          Expanded(child: Text(message, style: AppText.body)),
        ],
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final bool busy;

  const _PrimaryButton({required this.label, required this.onTap, this.busy = false});

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: onTap == null ? .6 : 1,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 16),
          alignment: Alignment.center,
          decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(AppRadii.pill)),
          child: busy
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white),
                )
              : Text(label, style: AppText.buttonLarge.copyWith(color: Colors.white)),
        ),
      ),
    );
  }
}
