import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/assets/app_assets.dart';
import '../../core/constants/support_links.dart';
import '../../core/di/providers.dart';
import '../../core/navigation/router.dart';
import '../../core/services/ankidroid_service.dart';
import '../../core/setup/setup_actions.dart';
import '../../core/support/support_actions.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/blocking_goal.dart';
import '../../core/widgets/brand_widgets.dart';
import '../../core/widgets/setup_panels.dart';
import '../../core/widgets/accessibility_disclosure.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen>
    with WidgetsBindingObserver {
  static const _pageCount = 6;

  /// Page indices for warm/sync hooks.
  static const _permsPage = 3;
  static const _appsPage = 4;

  final _controller = PageController();
  int _page = 0;

  bool _ankiInstalled = false;
  bool _ankiPermission = false;
  bool _hasAccessibility = false;
  bool _hasUsage = false;
  bool _hasBattery = false;
  bool _autoSelectedDueDecks = false;
  bool _appliedDefaults = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
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
    final accessibility = await perm.hasAccessibilityPermission();
    final usage = await perm.hasUsageAccessPermission();
    final battery = await perm.isIgnoringBatteryOptimizations();
    final ankiStatus = await anki.getStatus();
    if (!mounted) return;
    final ankiReady = ankiStatus.installed && ankiStatus.permissionGranted;
    setState(() {
      _hasAccessibility = accessibility;
      _hasUsage = usage;
      _hasBattery = battery;
      _ankiInstalled = ankiStatus.installed;
      _ankiPermission = ankiStatus.permissionGranted;
    });
    ref.invalidate(blockingPermissionsProvider);
    ref.invalidate(protectionStatusProvider);
    if (ankiReady && !hadAnkiReady) {
      ref.invalidate(ankiDroidStatusProvider);
      ref.invalidate(studyCountsProvider);
      _warmDeckData();
      unawaited(_applyAnkiDefaults());
    }
    if (usage && !hadUsage) {
      // Prefetch while the user may still grant usage — apps page is next.
      unawaited(_prefetchAppsWithUsage());
    } else if (usage && _page == _appsPage) {
      unawaited(ref.read(installedAppsProvider.notifier).refresh());
    }
  }

  Future<void> _prefetchAppsWithUsage() async {
    _warmAppData();
    await ref.read(installedAppsProvider.notifier).refresh();
  }

  void _warmAppData() {
    ref.read(installedAppsProvider.future);
  }

  void _warmDeckData() {
    if (!_ankiInstalled || !_ankiPermission) return;
    ref.read(studyScopeProvider.future);
    ref.read(ankiDroidDecksProvider.future);
  }

  /// dueCards mode + decks with learning/reviews; sync to native.
  Future<void> _applyAnkiDefaults() async {
    try {
      await updateStudyMode(ref, StudyMode.dueCardsValue);
      await _autoSelectDecksWithDue();
      await syncBlockRuleToNative(ref);
      _appliedDefaults = true;
    } catch (_) {
      // Non-fatal — Settings can finish setup.
    }
  }

  Future<void> _autoSelectDecksWithDue() async {
    if (_autoSelectedDueDecks) return;
    try {
      final status = await ref.read(ankiDroidStatusProvider.future);
      if (!status.isReady) return;
      final decks = await ref.read(ankiDroidDecksProvider.future);
      if (decks.isEmpty) return;
      final withDue = decks.where((d) => d.obligationDue > 0).toList();
      if (withDue.isEmpty) return;
      _autoSelectedDueDecks = true;
      final svc = ref.read(studyScopeServiceProvider);
      final disabled =
          decks.where((d) => d.obligationDue == 0).map((d) => d.id).toSet();
      await svc.setDisabledDeckIds(disabled);
      ref.invalidate(studyScopeProvider);
      ref.invalidate(studyCountsProvider);
      await syncStudyScopeToNative(ref);
    } catch (_) {
      // Non-fatal.
    }
  }

  Future<void> _finish() async {
    if (!_appliedDefaults) {
      await _applyAnkiDefaults();
    } else {
      await _autoSelectDecksWithDue();
      await syncBlockRuleToNative(ref);
    }
    await markOnboardingComplete(ref);
    if (mounted) context.go('/');
  }

  void _next() {
    // Accessibility is required for blocking; battery is recommended only.
    if (_page == _permsPage && !_hasAccessibility) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enable Accessibility to continue'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    if (_page < _pageCount - 1) {
      _controller.nextPage(
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOut,
      );
    } else {
      unawaited(_finish());
    }
  }

  @override
  Widget build(BuildContext context) {
    final perm = ref.read(permissionServiceProvider);
    final anki = ref.read(ankiDroidServiceProvider);
    final ankiReady = _ankiInstalled && _ankiPermission;
    final unlockGoal = ref.watch(blockRuleProvider).valueOrNull?.cardsRequired ?? 10;
    final counts = ref.watch(studyCountsProvider).valueOrNull;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView(
                controller: _controller,
                onPageChanged: (i) {
                  setState(() => _page = i);
                  if (i == _permsPage) {
                    unawaited(_refresh());
                  }
                  if (i == _appsPage) {
                    _warmAppData();
                    if (_hasUsage) {
                      // Prefer cached prefetch; refresh only if still empty.
                      final apps = ref.read(installedAppsProvider).valueOrNull;
                      if (apps == null || apps.isEmpty) {
                        unawaited(
                          ref.read(installedAppsProvider.notifier).refresh(),
                        );
                      }
                    }
                  }
                },
                children: [
                  const _IntroPage(),
                  _AnkiConnectPage(
                    installed: _ankiInstalled,
                    ready: ankiReady,
                    learnCount: counts?.learnCount,
                    reviewCount: counts?.reviewCount,
                    actionLabel: !_ankiInstalled
                        ? 'Install AnkiDroid'
                        : ankiReady
                            ? 'Connected'
                            : 'Grant access',
                    onAction: () async {
                      if (!_ankiInstalled) {
                        await anki.openAnkiDroid();
                      } else if (!ankiReady) {
                        try {
                          await anki.requestPermission();
                        } on AnkiDroidUnavailable {
                          await anki.openAnkiDroid();
                        }
                      }
                      await _refresh();
                      ref.invalidate(ankiDroidStatusProvider);
                      ref.invalidate(studyCountsProvider);
                      _warmDeckData();
                      if (_ankiInstalled && _ankiPermission) {
                        unawaited(_applyAnkiDefaults());
                      }
                    },
                  ),
                  _SetupScrollPage(
                    title: 'Temporary unlock',
                    subtitle: 'Cards to unlock all blocked apps and sites for a while.',
                    child: UnlockGoalPanel(
                      initial: unlockGoal,
                      showTitle: false,
                    ),
                  ),
                  _BlockingPermissionsPage(
                    hasAccessibility: _hasAccessibility,
                    hasUsage: _hasUsage,
                    hasBattery: _hasBattery,
                    onOpenAccessibility: () async {
                      final ok =
                          await showAccessibilityDisclosureDialog(context);
                      if (!ok || !mounted) return;
                      await perm.openAccessibilitySettings();
                      await _refresh();
                    },
                    onOpenUsage: () async {
                      await perm.openUsageAccessSettings();
                      await _refresh();
                    },
                    onRequestBattery: () async {
                      await perm.requestBatteryOptimizationExemption();
                      await _refresh();
                    },
                  ),
                  _SetupScrollPage(
                    title: 'What to block',
                    subtitle: _hasUsage
                        ? 'Pick apps now. You can also block websites (YouTube Shorts, Reddit, …) anytime under Blocking → Websites.'
                        : 'Suggested apps. You can also block websites anytime under Blocking → Websites.',
                    expandChild: true,
                    child: AppBlockSetupPanel(
                      showUsage: _hasUsage,
                      shrinkWrap: false,
                      padding: EdgeInsets.zero,
                    ),
                  ),
                  const _TrustPage(),
                ],
              ),
            ),
            _PageDots(count: _pageCount, current: _page),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
              child: Row(
                children: [
                  TextButton(
                    onPressed: () => unawaited(_finish()),
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
            accent: 'Unlock later.',
          ),
          const SizedBox(height: 16),
          Text(
            'AnkiDroid reviews unlock your apps and sites.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: AppTheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}

class _AnkiConnectPage extends StatelessWidget {
  final bool installed;
  final bool ready;
  final int? learnCount;
  final int? reviewCount;
  final String actionLabel;
  final Future<void> Function() onAction;

  const _AnkiConnectPage({
    required this.installed,
    required this.ready,
    required this.learnCount,
    required this.reviewCount,
    required this.actionLabel,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final body = !installed
        ? 'Install AnkiDroid to continue.'
        : ready
            ? (learnCount != null && reviewCount != null
                ? '$learnCount learning · $reviewCount to review'
                : 'Connected')
            : 'Reads your real study counts.';

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
            child: const Icon(Icons.sync, size: 48, color: AppTheme.accent),
          ),
          const SizedBox(height: 24),
          Text(
            'Connect AnkiDroid',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 16),
          Text(
            body,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 24),
          if (ready)
            const _GrantedPill(label: 'Connected')
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

class _BlockingPermissionsPage extends StatelessWidget {
  final bool hasAccessibility;
  final bool hasUsage;
  final bool hasBattery;
  final Future<void> Function() onOpenAccessibility;
  final Future<void> Function() onOpenUsage;
  final Future<void> Function() onRequestBattery;

  const _BlockingPermissionsPage({
    required this.hasAccessibility,
    required this.hasUsage,
    required this.hasBattery,
    required this.onOpenAccessibility,
    required this.onOpenUsage,
    required this.onRequestBattery,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Turn on blocking',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Accessibility detects blocked apps and websites instantly and shows the study gate.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppTheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 24),
          _PermissionRow(
            icon: Icons.accessibility_new_outlined,
            title: 'Accessibility (required)',
            granted: hasAccessibility,
            opensSettings: true,
            onGrant: onOpenAccessibility,
          ),
          const SizedBox(height: 12),
          _PermissionRow(
            icon: Icons.visibility_outlined,
            title: 'Usage access (optional)',
            granted: hasUsage,
            opensSettings: true,
            onGrant: onOpenUsage,
          ),
          const SizedBox(height: 12),
          _PermissionRow(
            icon: Icons.battery_charging_full_outlined,
            title: 'Unrestricted battery (recommended)',
            granted: hasBattery,
            opensSettings: false,
            onGrant: onRequestBattery,
          ),
          const SizedBox(height: 8),
          Text(
            'Usage access powers screen-time stats. Battery exemption helps on aggressive OEMs.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppTheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}

class _PermissionRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final bool granted;
  final bool opensSettings;
  final Future<void> Function() onGrant;

  const _PermissionRow({
    required this.icon,
    required this.title,
    required this.granted,
    required this.opensSettings,
    required this.onGrant,
  });

  @override
  Widget build(BuildContext context) {
    return BrandCard(
      color: AppTheme.cardElevated,
      child: Row(
        children: [
          Icon(icon, color: AppTheme.accent),
          const SizedBox(width: 14),
          Expanded(
            child: Text(title, style: Theme.of(context).textTheme.titleSmall),
          ),
          if (granted)
            const Icon(Icons.check_circle, color: AppTheme.success, size: 22)
          else if (opensSettings)
            FilledButton.icon(
              onPressed: onGrant,
              icon: const Icon(Icons.open_in_new, size: 18),
              label: const Text('Open settings'),
            )
          else
            FilledButton(
              onPressed: onGrant,
              child: const Text('Allow'),
            ),
        ],
      ),
    );
  }
}

class _TrustPage extends ConsumerWidget {
  const _TrustPage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const bullets = [
      'Free',
      'Open source code',
      'No ads',
      'No data collected',

    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Made by students, for students.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 28),
          ...bullets.map(
            (b) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  const Icon(Icons.check, color: AppTheme.accent, size: 20),
                  const SizedBox(width: 12),
                  Text(b, style: Theme.of(context).textTheme.titleMedium),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Bugs or feedback?',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppTheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 6),
          InkWell(
            onTap: () => openSupportLink(context, ref, (a) => a.openEmail()),
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                SupportLinks.contactEmail,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: AppTheme.accent,
                    ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GrantedPill extends StatelessWidget {
  final String label;
  const _GrantedPill({this.label = 'Granted'});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.success.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.success.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_circle, color: AppTheme.success, size: 18),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(color: AppTheme.success)),
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
