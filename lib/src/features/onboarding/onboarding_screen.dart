import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/di/providers.dart';
import '../../core/navigation/router.dart';
import '../../core/services/ankidroid_service.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen>
    with WidgetsBindingObserver {
  static const _pageCount = 5;

  final _controller = PageController();
  int _page = 0;

  // AnkiDroid
  bool _ankiInstalled = false;
  bool _ankiPermission = false;

  // App-blocker
  bool _hasUsage = false;
  bool _hasOverlay = false;
  bool _hasNotification = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
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

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView(
                controller: _controller,
                onPageChanged: (i) => setState(() => _page = i),
                children: [
                  const _IntroPage(
                    icon: Icons.school_outlined,
                    title: 'Welcome to AnkiBlock',
                    body:
                        'Block distracting apps and unlock them by studying flashcards. '
                        'AnkiBlock uses your AnkiDroid collection — install AnkiDroid '
                        'first if you do not already have it.',
                  ),
                  _PermissionPage(
                    icon: Icons.sync,
                    title: 'Connect AnkiDroid',
                    body: !_ankiInstalled
                        ? 'AnkiDroid is required. Tap "Install" to open the Play Store.'
                        : !_ankiPermission
                            ? 'AnkiDroid is installed. Grant the database '
                                'permission so AnkiBlock can read your decks.'
                            : 'AnkiBlock is connected to your AnkiDroid collection.',
                    granted: ankiReady,
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
                        'AnkiBlock needs Usage Access to detect when you open a blocked app. '
                        'It does not collect or upload any data.',
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
                        'This lets the study gate appear instantly when you open a blocked app, '
                        'without you having to launch AnkiBlock manually.',
                    granted: _hasOverlay,
                    actionLabel: 'Open settings',
                    onAction: () async {
                      await perm.openOverlaySettings();
                      await _refresh();
                    },
                  ),
                  _PermissionPage(
                    icon: Icons.notifications_outlined,
                    title: 'Notifications (optional)',
                    body:
                        'Get reminders when reviews are due and when an unlock is about to expire.',
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
                  FilledButton(
                    onPressed: _next,
                    child: Text(_page == _pageCount - 1 ? 'Done' : 'Next'),
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

class _IntroPage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;

  const _IntroPage({
    required this.icon,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 96),
          const SizedBox(height: 24),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 16),
          Text(
            body,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge,
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
  final String actionLabel;
  final Future<void> Function() onAction;

  const _PermissionPage({
    required this.icon,
    required this.title,
    required this.body,
    required this.granted,
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
          Icon(icon, size: 96),
          const SizedBox(height: 24),
          Text(
            title,
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
        color: Colors.green.shade100,
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle, color: Colors.green, size: 18),
          SizedBox(width: 6),
          Text('Granted', style: TextStyle(color: Colors.green)),
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
            color: selected
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).dividerColor,
            borderRadius: BorderRadius.circular(4),
          ),
        );
      }),
    );
  }
}
