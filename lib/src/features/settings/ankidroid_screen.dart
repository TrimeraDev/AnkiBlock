import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/di/providers.dart';
import '../../core/services/ankidroid_service.dart';

/// Connection page for the AnkiDroid bridge.
///
/// Manages the install / permission / "we are connected" states. Per-deck
/// scope selection lives on [/decks] — this screen just links there once
/// the connection is healthy.
class AnkiDroidScreen extends ConsumerWidget {
  const AnkiDroidScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statusAsync = ref.watch(ankiDroidStatusProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('AnkiDroid sync'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: !Platform.isAndroid
          ? const _UnsupportedPlatform()
          : statusAsync.when(
              data: (status) => _Body(status: status),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
            ),
    );
  }
}

class _UnsupportedPlatform extends StatelessWidget {
  const _UnsupportedPlatform();
  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(24),
      child: Center(
        child: Text(
          'AnkiDroid sync is only available on Android.',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  final AnkiDroidStatus status;
  const _Body({required this.status});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      children: [
        const _SectionHeader(label: 'Connection'),
        _StatusTile(status: status),
        if (!status.installed) ...[
          ListTile(
            leading: const Icon(Icons.download_outlined),
            title: const Text('Install AnkiDroid'),
            subtitle: const Text(
              'Opens the Play Store. After installing, come back here.',
            ),
            onTap: () => ref.read(ankiDroidServiceProvider).openAnkiDroid(),
          ),
        ] else if (!status.permissionGranted) ...[
          ListTile(
            leading: const Icon(Icons.lock_open),
            title: const Text('Grant database access'),
            subtitle: const Text(
              'AnkiBlock needs the AnkiDroid READ_WRITE_DATABASE permission '
              'to read your decks and due counts.',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _grant(context, ref),
          ),
          ListTile(
            leading: const Icon(Icons.open_in_new),
            title: const Text('Open AnkiDroid'),
            subtitle: const Text(
              'If the permission dialog never appears, open AnkiDroid once '
              'to initialize its database, then come back.',
            ),
            onTap: () => ref.read(ankiDroidServiceProvider).openAnkiDroid(),
          ),
        ] else ...[
          const _SectionHeader(label: 'Decks'),
          ListTile(
            leading: const Icon(Icons.folder_outlined),
            title: const Text('Manage deck scope'),
            subtitle: const Text(
              'Choose which AnkiDroid decks count toward your queue and gate.',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/decks'),
          ),
          ListTile(
            leading: const Icon(Icons.open_in_new),
            title: const Text('Open AnkiDroid'),
            subtitle: const Text(
              'Study cards, add decks, edit notes, and sync with AnkiWeb.',
            ),
            onTap: () => ref.read(ankiDroidServiceProvider).openAnkiDroid(),
          ),
        ],
        const Divider(),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 24),
          child: Text(
            'How it works\n\n'
            'AnkiBlock talks to AnkiDroid via its public ContentProvider. '
            'All studying happens in AnkiDroid — AnkiBlock reads your due '
            'counts and opens the native reviewer when you tap Study or hit '
            'a blocked-app gate.',
            style: TextStyle(color: Colors.grey),
          ),
        ),
      ],
    );
  }

  Future<void> _grant(BuildContext context, WidgetRef ref) async {
    final service = ref.read(ankiDroidServiceProvider);
    try {
      final granted = await service.requestPermission();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            granted
                ? 'Connected to AnkiDroid.'
                : 'Permission denied. You can grant it later in Android settings.',
          ),
        ),
      );
    } on AnkiDroidUnavailable catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    }
    ref.invalidate(ankiDroidStatusProvider);
    ref.invalidate(ankiDroidDecksProvider);
    ref.invalidate(studyCountsProvider);
  }
}

class _StatusTile extends ConsumerWidget {
  final AnkiDroidStatus status;
  const _StatusTile({required this.status});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (icon, color, title, subtitle) = switch (status) {
      AnkiDroidStatus(installed: false) => (
        Icons.cancel_outlined,
        Colors.grey,
        'AnkiDroid not installed',
        'Install it from the Play Store to enable AnkiBlock.',
      ),
      AnkiDroidStatus(installed: true, permissionGranted: false) => (
        Icons.lock_outline,
        Colors.orange,
        'Permission required',
        'AnkiDroid is installed but has not granted us database access yet.',
      ),
      AnkiDroidStatus(installed: true, permissionGranted: true) => (
        Icons.check_circle_outline,
        Colors.green,
        'Connected',
        'AnkiBlock can read your decks and open the AnkiDroid reviewer.',
      ),
    };
    return ListTile(
      leading: Icon(icon, color: color, size: 32),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: IconButton(
        icon: const Icon(Icons.refresh),
        tooltip: 'Re-check',
        onPressed: () {
          ref.invalidate(ankiDroidStatusProvider);
          ref.invalidate(ankiDroidDecksProvider);
          ref.invalidate(studyCountsProvider);
        },
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        label.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Colors.grey[600],
              letterSpacing: 1,
            ),
      ),
    );
  }
}
