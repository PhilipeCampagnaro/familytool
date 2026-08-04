import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../state/onboarding_state.dart';
import '../theme/tokens.dart';
import '../widgets/app_sheet.dart';
import '../widgets/native_switch.dart';
import '../l10n/l10n.dart';

/// First-run wizard: welcome -> family (invite) -> address (calendar
/// toggles) -> done. Mirrors the old web app's admin path (see CLAUDE.md's
/// "Ported feature knowledge" -> Onboarding flow) with the wallet step and
/// "Meet Kai" card dropped (out of scope). [replay] is set when reopened
/// from Settings' "Willkommenstour wiederholen" row, which pushes this
/// screen instead of it being the app's `home`.
class OnboardingScreen extends ConsumerWidget {
  final bool replay;

  const OnboardingScreen({super.key, this.replay = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final step = ref.watch(onboardingProvider.select((s) => s.step));

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 260),
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(begin: const Offset(0, 0.03), end: Offset.zero).animate(animation),
              child: child,
            ),
          ),
          child: KeyedSubtree(
            key: ValueKey(step),
            child: switch (step) {
              0 => _WelcomeStep(),
              1 => _FamilyStep(),
              2 => _AddressStep(),
              _ => _DoneStep(replay: replay),
            },
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  final VoidCallback? onBack;
  final VoidCallback? onSkip;

  const _TopBar({this.onBack, this.onSkip});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 20, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          onBack != null
              ? IconButton(icon: Icon(LucideIcons.chevronLeft, color: AppColors.muted), onPressed: onBack)
              : const SizedBox(width: 48),
          if (onSkip != null)
            TextButton(
              onPressed: onSkip,
              child: Text(L.s.skip, style: AppText.buttonSmall.copyWith(color: AppColors.muted)),
            )
          else
            const SizedBox(width: 48),
        ],
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  final String asset;

  const _Hero(this.asset);

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadii.card),
      child: Image.asset(asset, height: 200, width: double.infinity, fit: BoxFit.cover),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _PrimaryButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16),
        alignment: Alignment.center,
        decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(AppRadii.pill)),
        child: Text(label, style: AppText.buttonLarge.copyWith(color: Colors.white)),
      ),
    );
  }
}

class _WelcomeStep extends ConsumerWidget {
  const _WelcomeStep();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _TopBar(onSkip: () => ref.read(onboardingProvider.notifier).complete()),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(AppSpacing.screenPad, 12, AppSpacing.screenPad, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _Hero('assets/onboarding/hero_welcome.png'),
                const SizedBox(height: 28),
                Text(L.s.onboardSetUpFamily, style: AppText.screenTitle),
                const SizedBox(height: 10),
                Text(
                  L.s.onboardSetUpFamilyBody,
                  style: AppText.body,
                ),
                const SizedBox(height: 28),
                _PrimaryButton(label: L.s.letsGo, onTap: () => ref.read(onboardingProvider.notifier).next()),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _FamilyStep extends ConsumerStatefulWidget {
  const _FamilyStep();

  @override
  ConsumerState<_FamilyStep> createState() => _FamilyStepState();
}

class _FamilyStepState extends ConsumerState<_FamilyStep> {
  final _emailController = TextEditingController();
  final _nameController = TextEditingController();
  bool _isChild = false;

  @override
  void dispose() {
    _emailController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  void _addInvite() {
    final email = _emailController.text.trim();
    if (email.isEmpty) return;
    ref.read(onboardingProvider.notifier).addInvite(OnboardingInvite(email: email, name: _nameController.text.trim(), isChild: _isChild));
    setState(() {
      _emailController.clear();
      _nameController.clear();
      _isChild = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final invites = ref.watch(onboardingProvider.select((s) => s.invites));
    final accent = Theme.of(context).colorScheme.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _TopBar(
          onBack: () => ref.read(onboardingProvider.notifier).back(),
          onSkip: () => ref.read(onboardingProvider.notifier).next(),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(AppSpacing.screenPad, 4, AppSpacing.screenPad, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _Hero('assets/onboarding/hero_members.png'),
                const SizedBox(height: 24),
                Text(L.s.onboardInviteTitle, style: AppText.screenTitle),
                const SizedBox(height: 8),
                Text(L.s.onboardInviteBody, style: AppText.body),
                const SizedBox(height: 20),
                SectionCard(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      child: TextField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        style: AppText.inputTitle,
                        decoration: InputDecoration(border: InputBorder.none, hintText: L.s.emailAddress, isDense: true),
                      ),
                    ),
                    CardDivider(),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      child: TextField(
                        controller: _nameController,
                        style: AppText.inputTitle,
                        decoration: InputDecoration(border: InputBorder.none, hintText: L.s.nameOptional, isDense: true),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: _RoleChip(label: L.s.adult, selected: !_isChild, accent: accent, onTap: () => setState(() => _isChild = false))),
                    const SizedBox(width: 8),
                    Expanded(child: _RoleChip(label: L.s.child, selected: _isChild, accent: accent, onTap: () => setState(() => _isChild = true))),
                  ],
                ),
                const SizedBox(height: 12),
                OutlinedButton(onPressed: _addInvite, child: Text(L.s.add)),
                if (invites.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final invite in invites)
                        Chip(label: Text(invite.name.isNotEmpty ? invite.name : invite.email)),
                    ],
                  ),
                ],
                const SizedBox(height: 28),
                _PrimaryButton(label: L.s.next, onTap: () => ref.read(onboardingProvider.notifier).next()),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _RoleChip extends StatelessWidget {
  final String label;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  const _RoleChip({required this.label, required this.selected, required this.accent, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 11),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? shade(accent, .12) : AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(AppRadii.chip),
          border: Border.all(color: selected ? accent : Colors.transparent),
        ),
        child: Text(label, style: AppText.buttonSmall.copyWith(color: selected ? accent : AppColors.muted)),
      ),
    );
  }
}

class _AddressStep extends ConsumerStatefulWidget {
  const _AddressStep();

  @override
  ConsumerState<_AddressStep> createState() => _AddressStepState();
}

class _AddressStepState extends ConsumerState<_AddressStep> {
  late final TextEditingController _addressController;

  @override
  void initState() {
    super.initState();
    _addressController = TextEditingController(text: ref.read(onboardingProvider).address);
  }

  @override
  void dispose() {
    _addressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(onboardingProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _TopBar(
          onBack: () => ref.read(onboardingProvider.notifier).back(),
          onSkip: () => ref.read(onboardingProvider.notifier).next(),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(AppSpacing.screenPad, 4, AppSpacing.screenPad, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _Hero('assets/onboarding/hero_address.png'),
                const SizedBox(height: 24),
                Text(L.s.onboardAddressTitle, style: AppText.screenTitle),
                const SizedBox(height: 8),
                Text(L.s.onboardAddressBody, style: AppText.body),
                const SizedBox(height: 20),
                SectionCard(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      child: TextField(
                        controller: _addressController,
                        style: AppText.inputTitle,
                        decoration: InputDecoration(border: InputBorder.none, hintText: L.s.address, isDense: true),
                        onChanged: (v) => ref.read(onboardingProvider.notifier).setAddress(v),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SectionCard(
                  children: [
                    _ToggleRow(
                      icon: LucideIcons.recycle,
                      title: L.s.wasteCalendar,
                      value: state.trashCalendar,
                      onChanged: (v) => ref.read(onboardingProvider.notifier).setTrashCalendar(v),
                    ),
                    CardDivider(),
                    _ToggleRow(
                      icon: LucideIcons.graduationCap,
                      title: L.s.holidayCalendar,
                      value: state.ferienCalendar,
                      onChanged: (v) => ref.read(onboardingProvider.notifier).setFerienCalendar(v),
                    ),
                  ],
                ),
                const SizedBox(height: 28),
                _PrimaryButton(label: L.s.next, onTap: () => ref.read(onboardingProvider.notifier).next()),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ToggleRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _ToggleRow({required this.icon, required this.title, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(color: AppColors.surfaceAlt, borderRadius: BorderRadius.circular(AppRadii.iconTile)),
            alignment: Alignment.center,
            child: Icon(icon, size: 17, color: accent),
          ),
          const SizedBox(width: 13),
          Expanded(child: Text(title, style: AppText.rowTitle)),
          NativeSwitch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _DoneStep extends ConsumerStatefulWidget {
  final bool replay;

  const _DoneStep({required this.replay});

  @override
  ConsumerState<_DoneStep> createState() => _DoneStepState();
}

class _DoneStepState extends ConsumerState<_DoneStep> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 500))..forward();
  late final Animation<double> _scale = CurvedAnimation(parent: _controller, curve: Curves.elasticOut);
  late final Animation<double> _fade = CurvedAnimation(parent: _controller, curve: const Interval(0, 0.4, curve: Curves.easeOut));

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(onboardingProvider);
    final accent = Theme.of(context).colorScheme.primary;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(AppSpacing.screenPad, 40, AppSpacing.screenPad, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: FadeTransition(
              opacity: _fade,
              child: ScaleTransition(
                scale: _scale,
                child: Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(color: shade(accent, .14), shape: BoxShape.circle),
                  alignment: Alignment.center,
                  child: Icon(LucideIcons.check, size: 40, color: accent),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(L.s.onboardReady, textAlign: TextAlign.center, style: AppText.screenTitle),
          const SizedBox(height: 8),
          Text(L.s.onboardReadyBody, textAlign: TextAlign.center, style: AppText.body),
          const SizedBox(height: 24),
          SectionCard(
            children: [
              _RecapRow(
                icon: LucideIcons.userPlus,
                label: state.invites.isEmpty ? L.s.noInvitesSent : L.s.invitedCount(state.invites.length),
                done: state.invites.isNotEmpty,
              ),
              CardDivider(),
              _RecapRow(icon: LucideIcons.recycle, label: L.s.wasteCalendar, done: state.trashCalendar),
              CardDivider(),
              _RecapRow(icon: LucideIcons.graduationCap, label: L.s.holidayCalendar, done: state.ferienCalendar),
            ],
          ),
          const SizedBox(height: 28),
          _PrimaryButton(
            label: L.s.letsGo,
            onTap: () {
              ref.read(onboardingProvider.notifier).complete();
              if (widget.replay) Navigator.of(context).maybePop();
            },
          ),
        ],
      ),
    );
  }
}

class _RecapRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool done;

  const _RecapRow({required this.icon, required this.label, required this.done});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.muted),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: AppText.rowTitle)),
          Icon(done ? LucideIcons.check : LucideIcons.x, size: 16, color: done ? AppColors.success : AppColors.mutedLight),
        ],
      ),
    );
  }
}
