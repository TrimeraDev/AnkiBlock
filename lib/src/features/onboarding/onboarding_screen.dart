import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/di/providers.dart';
import '../../core/navigation/router.dart';
import '../../core/services/ankidroid_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/brand_widgets.dart';
import '../../core/widgets/setup_panels.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen>
    with WidgetsBindingObserver {
  static const _pageCount = 8;

  final _controller = PageController();
  int _page = 0;

  bool _ankiInstalled = false;
  bool _ankiPermission = false;
  bool _hasUsage = false;
  bool _hasOverlay = false;
  bool _hasNotification = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
    // Warm app list for the block-apps step.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(installedAppsProvider.future);
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
    final usage = await perm.hasUsageAccessPermission();
    final overlay = await perm.hasOverlayPermission();
    final notif = await perm.hasNotificationPermission();
    final ankiStatus = await anki.getStatus();
    if (!mounted) return;
    setState(() {
      _hasUsage = usage;
      _hasOverlay = overlay;
      _hasNotification = notif;
      _ankiInstalled = ankiStatus.installed;
      _ankiPermission = ankiStatus.permissionGranted;
    });
  }

  Future<void> _finish() async {
    await markOnboardingComplete(ref);
    if (mounted) context.go('/');
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
    final dailyGoal = ruleAsync.valueOrNull?.dailyCardsGoal ?? 30;
    final unlockGoal = ruleAsync.valueOrNull?.cardsRequired ?? 10;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView(
                controller: _controller,
                onPageChanged: (i) => setState(() => _page = i),
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
                    title: 'Block your worst apps',
                    subtitle:
                        'Toggle the apps that should stay locked until you study.',
                    child: const AppBlockSetupPanel(suggestedOnly: true),
                  ),
                  _SetupScrollPage(
                    title: 'Choose decks to study',
                    subtitle:
                        'Only cards from these AnkiDroid decks count toward unlocking.',
                    child: const DeckStudySetupPanel(),
                  ),
                  _SetupScrollPage(
                    title: 'Set your goals',
                    subtitle:
                        'Hit your daily goal to unlock everything until 3am. '
                        'Otherwise study a smaller batch each time you open a '
                        'blocked app.',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        DailyGoalPanel(
                          initial: dailyGoal,
                          showTitle: false,
                        ),
                        const SizedBox(height: 24),
                        UnlockGoalPanel(
                          initial: unlockGoal,
                          showTitle: false,
                        ),
                      ],
                    ),
                  ),
                  _PermissionPage(
                    icon: Icons.notifications_outlined,
                    title: 'Notifications (optional)',
                    body:
                        'Get reminders when reviews are due and when an unlock '
                        'is about to expire.',
                    granted: _hasNotification,
                    actionLabel: 'Allow notifications',
                    onAction: () async {
                      await perm.requestNotificationPermission();
                      await _refresh();
                    },
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

class _SetupScrollPage extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;

  const _SetupScrollPage({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
      children: [
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
            'lib/src/assets/logo.png',
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
