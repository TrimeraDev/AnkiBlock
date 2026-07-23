import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/assets/app_assets.dart';
import '../../core/di/providers.dart';
import '../../core/navigation/router.dart';
import '../../core/services/ankidroid_service.dart';
import '../../core/setup/setup_actions.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/blocking_goal.dart';
import '../../core/widgets/brand_widgets.dart';
import '../../core/widgets/deck_picker_panel.dart';
import '../../core/widgets/setup_panels.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen>
    with WidgetsBindingObserver {
  static const _pageCount = 7;

  final _controller = PageController();
  int _page = 0;

  bool _ankiInstalled = false;
  bool _ankiPermission = false;
  bool _hasUsage = false;
  bool _hasOverlay = false;
  bool _autoSelectedDueDecks = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
    // Warm app list for the block-apps step; warm decks for the next step.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _warmAppData();
      _warmDeckData();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final perm = ref.read(permissionServiceProvider);
    final anki = ref.read(ankiDroidServiceProvider);
    final hadUsage = _hasUsage;
    final hadAnkiReady = _ankiInstalled && _ankiPermission;
    final usage = await perm.hasUsageAccessPermission();
    final overlay = await perm.hasOverlayPermission();
    final ankiStatus = await anki.getStatus();
    if (!mounted) return;
    final ankiReady = ankiStatus.installed && ankiStatus.permissionGranted;
    setState(() {
      _hasUsage = usage;
      _hasOverlay = overlay;
      _ankiInstalled = ankiStatus.installed;
      _ankiPermission = ankiStatus.permissionGranted;
    });
    ref.invalidate(blockingPermissionsProvider);
    ref.invalidate(protectionStatusProvider);
    if (ankiReady && !hadAnkiReady) {
      ref.invalidate(ankiDroidStatusProvider);
      _warmDeckData();
    }
    if (usage && !hadUsage) {
      unawaited(ref.read(installedAppsProvider.notifier).refresh());
    } else if (usage && _page == 4) {
      // Re-sort with screen time after returning from system settings.
      unawaited(ref.read(installedAppsProvider.notifier).refresh());
    }
  }

  void _warmAppData() {
    ref.read(installedAppsProvider.future);
  }

  /// Start loading deck list + scope while the user is still on earlier steps.
  void _warmDeckData() {
    if (!_ankiInstalled || !_ankiPermission) return;
    ref.read(studyScopeProvider.future);
    ref.read(ankiDroidDecksProvider.future);
  }

  Future<void> _finish() async {
    await markOnboardingComplete(ref);
    if (mounted) context.go('/');
  }

  /// Prefer decks that currently have due cards for new installs.
  Future<void> _autoSelectDecksWithDue() async {
    if (_autoSelectedDueDecks) return;
    _autoSelectedDueDecks = true;
    try {
      final status = await ref.read(ankiDroidStatusProvider.future);
      if (!status.isReady) return;
      final decks = await ref.read(ankiDroidDecksProvider.future);
      if (decks.isEmpty) return;
      final withDue = decks.where((d) => d.totalDue > 0).toList();
      if (withDue.isEmpty) return;
      final svc = ref.read(studyScopeServiceProvider);
      final disabled =
          decks.where((d) => d.totalDue == 0).map((d) => d.id).toSet();
      await svc.setDisabledDeckIds(disabled);
      ref.invalidate(studyScopeProvider);
      ref.invalidate(studyCountsProvider);
      await syncStudyScopeToNative(ref);
    } catch (_) {
      // Non-fatal — user can still pick decks manually.
    }
  }

  void _next() {
    if (_page < _pageCount - 1) {
      _controller.nextPage(
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOut,
      );
    } else {
      _finish();
    }
  }

  @override
  Widget build(BuildContext context) {
    final perm = ref.read(permissionServiceProvider);
    final anki = ref.read(ankiDroidServiceProvider);
    final ankiReady = _ankiInstalled && _ankiPermission;
    final ruleAsync = ref.watch(blockRuleProvider);
    final unlockGoal = ruleAsync.valueOrNull?.cardsRequired ?? 10;
    final blockingMode =
        BlockingMode.fromStorage(ruleAsync.valueOrNull?.blockingMode);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView(
                controller: _controller,
                onPageChanged: (i) {
                  setState(() => _page = i);
                  if (i == 3) {
                    _warmAppData();
                    if (_hasUsage) {
                      unawaited(
                        ref.read(installedAppsProvider.notifier).refresh(),
                      );
                    }
                  }
                  if (i == 4) _warmDeckData();
                  if (i == 5) {
                    _warmDeckData();
                    unawaited(_autoSelectDecksWithDue());
                  }
                },
                children: [
                  const _IntroPage(),
                  _PermissionPage(
                    icon: Icons.sync,
                    title: 'Built for AnkiDroid',
                    body: !_ankiInstalled
                        ? 'AnkiDroid must be installed. AnkiBlock connects to '
                            'AnkiDroid and uses your real study progress to '
                            'unlock apps.'
                        : !_ankiPermission
                            ? 'AnkiDroid is installed. Grant database access '
                                'so AnkiBlock can read your decks and due counts.'
                            : 'AnkiBlock is connected to your AnkiDroid collection.',
                    granted: ankiReady,
                    showAnkiBadge: true,
                    actionLabel: !_ankiInstalled
                        ? 'Install AnkiDroid'
                        : 'Grant access',
                    onAction: () async {
                      if (!_ankiInstalled) {
                        await anki.openAnkiDroid();
                      } else {
                        try {
                          await anki.requestPermission();
                        } on AnkiDroidUnavailable {
                          await anki.openAnkiDroid();
                        }
                      }
                      await _refresh();
                      ref.invalidate(ankiDroidStatusProvider);
                      _warmDeckData();
                    },
                  ),
                  _PermissionPage(
                    icon: Icons.visibility_outlined,
                    title: 'Allow Usage Access',
                    body:
                        'AnkiBlock needs Usage Access to detect when you open a '
                        'blocked app. Your data stays on your device.',
                    granted: _hasUsage,
                    actionLabel: 'Open settings',
                    onAction: () async {
                      await perm.openUsageAccessSettings();
                      await _refresh();
                    },
                  ),
                  _PermissionPage(
                    icon: Icons.layers_outlined,
                    title: 'Allow Display Over Apps',
                    body:
                        'This lets the study gate appear instantly when you open '
                        'a blocked app — no need to launch AnkiBlock manually.',
                    granted: _hasOverlay,
                    actionLabel: 'Open settings',
                    onAction: () async {
                      await perm.openOverlaySettings();
                      await _refresh();
                    },
                  ),
                  _SetupScrollPage(
                    title: 'How should apps stay locked?',
                    subtitle:
                        'Lock down the phone (recommended), or pick specific apps.',
                    expandChild: true,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _OnboardingBlockingChoice(
                          mode: blockingMode,
                          onChanged: (m) =>
                              updateBlockingMode(ref, m.storageValue),
                        ),
                        const SizedBox(height: 16),
                        if (blockingMode == BlockingMode.lockdown)
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Text(
                                'Most apps stay locked until learning & reviews '
                                'are done. AnkiDroid, Phone, and AnkiBlock stay '
                                'available. Emergency calls always work.',
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ),
                          )
                        else
                          Expanded(
                            child: AppBlockSetupPanel(
                              showUsage: _hasUsage,
                              shrinkWrap: false,
                              padding: EdgeInsets.zero,
                            ),
                          ),
                      ],
                    ),
                  ),
                  _SetupScrollPage(
                    title: 'Choose decks to study',
                    subtitle:
                        'Learning & reviews from selected decks unlock apps. '
                        'Decks with due cards are selected by default.',
                    expandChild: true,
                    child: const DeckPickerPanel(
                      shrinkWrap: false,
                      padding: EdgeInsets.zero,
                    ),
                  ),
                  _SetupScrollPage(
                    title: 'Cards per app unlock',
                    subtitle:
                        'Study this many cards each time you open a blocked app. '
                        'Your daily unlock follows AnkiDroid\'s learning & '
                        'review counts automatically.',
                    child: UnlockGoalPanel(
                      initial: unlockGoal,
                      showTitle: false,
                    ),
                  ),
                ],
              ),
            ),
            _PageDots(count: _pageCount, current: _page),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
              child: Row(
                children: [
                  TextButton(
                    onPressed: _finish,
                    child: const Text('Skip'),
                  ),
                  const Spacer(),
                  if (_page == _pageCount - 1)
                    Expanded(
                      child: GradientButton(
                        expand: true,
                        onPressed: _next,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        child: const Text('Get Started'),
                      ),
                    )
                  else
                    FilledButton(
                      onPressed: _next,
                      child: const Text('Next'),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OnboardingBlockingChoice extends StatelessWidget {
  final BlockingMode mode;
  final ValueChanged<BlockingMode> onChanged;

  const _OnboardingBlockingChoice({
    required this.mode,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _ChoiceCard(
          selected: mode == BlockingMode.lockdown,
          title: 'Lock down phone',
          subtitle: 'Recommended · block almost everything until you study',
          onTap: () => onChanged(BlockingMode.lockdown),
        ),
        const SizedBox(height: 10),
        _ChoiceCard(
          selected: mode == BlockingMode.selectedApps,
          title: 'Choose apps to block',
          subtitle: 'Only the apps you pick stay locked',
          onTap: () => onChanged(BlockingMode.selectedApps),
        ),
      ],
    );
  }
}

class _ChoiceCard extends StatelessWidget {
  final bool selected;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ChoiceCard({
    required this.selected,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return BrandCard(
      color: selected
          ? AppTheme.accent.withValues(alpha: 0.12)
          : AppTheme.cardElevated,
      onTap: onTap,
      child: Row(
        children: [
          Icon(
            selected ? Icons.radio_button_checked : Icons.radio_button_off,
            color: selected ? AppTheme.accent : AppTheme.onSurfaceVariant,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 2),
                Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SetupScrollPage extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;
  final bool expandChild;

  const _SetupScrollPage({
    required this.title,
    required this.subtitle,
    required this.child,
    this.expandChild = false,
  });

  @override
  Widget build(BuildContext context) {
    final header = <Widget>[
      Text(
        title,
        style: Theme.of(context).textTheme.headlineMedium,
      ),
      const SizedBox(height: 8),
      Text(
        subtitle,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: AppTheme.onSurfaceVariant,
            ),
      ),
      const SizedBox(height: 20),
    ];

    if (expandChild) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ...header,
            Expanded(child: child),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
      children: [
        ...header,
        child,
      ],
    );
  }
}

class _IntroPage extends StatelessWidget {
  const _IntroPage();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Image.asset(
            AppAssets.logo,
            width: 96,
            height: 96,
          ),
          const SizedBox(height: 24),
          const AnkiBlockWordmark(),
          const SizedBox(height: 12),
          const AccentHeadline(
            before: 'Study first. ',
            accent: 'Unlock freedom.',
          ),
          const SizedBox(height: 20),
          Text(
            'AnkiBlock blocks your most distracting apps until you complete '
            'your Anki cards in AnkiDroid.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 16),
          const BrandBadge(
            label: 'Requires AnkiDroid',
            icon: Icons.info_outline,
          ),
        ],
      ),
    );
  }
}

class _PermissionPage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final bool granted;
  final bool showAnkiBadge;
  final String actionLabel;
  final Future<void> Function() onAction;

  const _PermissionPage({
    required this.icon,
    required this.title,
    required this.body,
    required this.granted,
    this.showAnkiBadge = false,
    required this.actionLabel,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppTheme.cardElevated,
              shape: BoxShape.circle,
              border: Border.all(color: AppTheme.divider),
            ),
            child: Icon(icon, size: 48, color: AppTheme.accent),
          ),
          const SizedBox(height: 24),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          if (showAnkiBadge) ...[
            const SizedBox(height: 12),
            const BrandBadge(label: 'Requires AnkiDroid', icon: Icons.sync),
          ],
          const SizedBox(height: 16),
          Text(
            body,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 24),
          if (granted)
            const _GrantedPill()
          else
            FilledButton.icon(
              onPressed: onAction,
              icon: const Icon(Icons.open_in_new),
              label: Text(actionLabel),
            ),
        ],
      ),
    );
  }
}

class _GrantedPill extends StatelessWidget {
  const _GrantedPill();
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.success.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.success.withValues(alpha: 0.35)),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle, color: AppTheme.success, size: 18),
          SizedBox(width: 6),
          Text('Granted', style: TextStyle(color: AppTheme.success)),
        ],
      ),
    );
  }
}

class _PageDots extends StatelessWidget {
  final int count;
  final int current;
  const _PageDots({required this.count, required this.current});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (i) {
        final selected = i == current;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: selected ? 18 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: selected ? AppTheme.accent : AppTheme.cardElevated,
            borderRadius: BorderRadius.circular(4),
          ),
        );
      }),
    );
  }
}
