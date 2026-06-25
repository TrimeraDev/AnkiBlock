import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/database/database.dart';
import '../../core/di/providers.dart';
import '../../core/services/apps_service.dart';
import '../../core/setup/setup_actions.dart';
import '../../core/theme/app_theme.dart';

class BlockingScreen extends ConsumerStatefulWidget {
  const BlockingScreen({super.key});

  @override
  ConsumerState<BlockingScreen> createState() => _BlockingScreenState();
}

class _BlockingScreenState extends ConsumerState<BlockingScreen> {
  String _query = '';
  bool _hideSystem = true;
  _SortMode _sort = _SortMode.usage;

  @override
  Widget build(BuildContext context) {
    final appsAsync = ref.watch(installedAppsProvider);
    final blockedAsync = ref.watch(blockedAppsProvider);
    final loadingApps = appsAsync.isLoading;
    final refreshingApps = appsAsync.isLoading && appsAsync.hasValue;

    return Scaffold(
      appBar: AppBar(
        title: const Text('App Blocking'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        actions: [
          IconButton(
            icon: loadingApps
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: loadingApps
                ? null
                : () => ref.read(installedAppsProvider.notifier).refresh(),
          ),
          PopupMenuButton<_SortMode>(
            icon: const Icon(Icons.sort),
            onSelected: (m) => setState(() => _sort = m),
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: _SortMode.usage,
                child: Text('Sort by screen time'),
              ),
              PopupMenuItem(value: _SortMode.name, child: Text('Sort by name')),
            ],
          ),
        ],
      ),
      body: appsAsync.when(
        // Cached list stays visible while a background refresh runs.
        skipLoadingOnRefresh: true,
        loading: () => const _BlockingLoadingBody(),
        error: (e, _) => _ErrorView(
            error: e,
            onRetry: () {
              ref.read(installedAppsProvider.notifier).refresh();
            }),
        data: (apps) {
          final blockedRecords = (blockedAsync.valueOrNull ?? const <BlockedApp>[])
              .where((b) => b.isBlocked)
              .toList();
          final blockedSet =
              blockedRecords.map((b) => b.packageName).toSet();

          bool matchesQuery(InstalledApp a) {
            if (_query.isEmpty) return true;
            final q = _query.toLowerCase();
            return a.appName.toLowerCase().contains(q) ||
                a.packageName.toLowerCase().contains(q);
          }

          final filtered = apps.where((a) {
            if (_hideSystem && a.isSystem) return false;
            return matchesQuery(a);
          }).toList();

          final installedPackages = apps.map((a) => a.packageName).toSet();
          final blockedNotInstalled = blockedRecords
              .where((b) => !installedPackages.contains(b.packageName))
              .map(
                (b) => InstalledApp(
                  packageName: b.packageName,
                  appName: b.displayName,
                  isSystem: false,
                ),
              )
              .where(matchesQuery)
              .toList();

          int compareApps(InstalledApp a, InstalledApp b) {
            switch (_sort) {
              case _SortMode.usage:
                final c = b.usage.compareTo(a.usage);
                if (c != 0) return c;
                return a.appName
                    .toLowerCase()
                    .compareTo(b.appName.toLowerCase());
              case _SortMode.name:
                return a.appName
                    .toLowerCase()
                    .compareTo(b.appName.toLowerCase());
            }
          }

          final blockedApps = [
            ...filtered.where((a) => blockedSet.contains(a.packageName)),
            ...blockedNotInstalled,
          ]..sort(compareApps);

          final otherApps = filtered
              .where((a) => !blockedSet.contains(a.packageName))
              .toList()
            ..sort(compareApps);

          final listEntries = <_BlockingListEntry>[];
          if (blockedApps.isNotEmpty) {
            listEntries.add(_BlockingListEntry.header(
              'Blocked (${blockedApps.length})',
            ));
            for (final app in blockedApps) {
              listEntries.add(_BlockingListEntry.app(app));
            }
            if (otherApps.isNotEmpty && _query.isEmpty) {
              listEntries.add(const _BlockingListEntry.header('All apps'));
            }
          }
          for (final app in otherApps) {
            listEntries.add(_BlockingListEntry.app(app));
          }

          final suggested = filtered
              .where((a) => kSuggestedBlockPackages.contains(a.packageName))
              .toList();

          return Column(
            children: [
              if (refreshingApps)
                const LinearProgressIndicator(minHeight: 2),
              _SearchBar(
                onChanged: (v) => setState(() => _query = v),
                hideSystem: _hideSystem,
                onToggleHideSystem: (v) => setState(() => _hideSystem = v),
              ),
              if (suggested.isNotEmpty && _query.isEmpty)
                _SuggestedBanner(
                  apps: suggested,
                  blockedSet: blockedSet,
                  onBlockAll: () => _blockAll(suggested),
                ),
              Expanded(
                child: ListView.separated(
                  itemCount: listEntries.length,
                  separatorBuilder: (_, __) => const Divider(height: 0),
                  itemBuilder: (context, i) {
                    final entry = listEntries[i];
                    return entry.map(
                      header: (title) => _SectionHeader(title: title),
                      app: (app) {
                        final isBlocked = blockedSet.contains(app.packageName);
                        return _AppTile(
                          app: app,
                          isBlocked: isBlocked,
                          onChanged: (v) => _toggleBlock(app, v),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _toggleBlock(InstalledApp app, bool blocked) async {
    final db = ref.read(databaseProvider);
    final existing = await db.getBlockedApp(app.packageName);
    if (existing == null) {
      await db.insertBlockedApp(BlockedAppsCompanion.insert(
        packageName: app.packageName,
        displayName: app.appName,
        isBlocked: Value(blocked),
      ));
    } else {
      await db.setBlocked(app.packageName, blocked);
    }
    await _syncNative();
  }

  Future<void> _blockAll(List<InstalledApp> apps) async {
    final db = ref.read(databaseProvider);
    for (final app in apps) {
      final existing = await db.getBlockedApp(app.packageName);
      if (existing == null) {
        await db.insertBlockedApp(BlockedAppsCompanion.insert(
          packageName: app.packageName,
          displayName: app.appName,
          isBlocked: const Value(true),
        ));
      } else {
        await db.setBlocked(app.packageName, true);
      }
    }
    await _syncNative();
  }

  Future<void> _syncNative() async {
    await syncBlockedPackagesToNative(ref);
  }
}

enum _SortMode { usage, name }

sealed class _BlockingListEntry {
  const _BlockingListEntry();

  const factory _BlockingListEntry.header(String title) =
      _BlockingListHeaderEntry;
  const factory _BlockingListEntry.app(InstalledApp app) =
      _BlockingListAppEntry;

  T map<T>({
    required T Function(String title) header,
    required T Function(InstalledApp app) app,
  });
}

final class _BlockingListHeaderEntry extends _BlockingListEntry {
  const _BlockingListHeaderEntry(this.title);
  final String title;

  @override
  T map<T>({
    required T Function(String title) header,
    required T Function(InstalledApp app) app,
  }) =>
      header(title);
}

final class _BlockingListAppEntry extends _BlockingListEntry {
  const _BlockingListAppEntry(this.app);
  final InstalledApp app;

  @override
  T map<T>({
    required T Function(String title) header,
    required T Function(InstalledApp app) app,
  }) =>
      app(this.app);
}

class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

/// Full-screen loading state while native code gathers installed apps,
/// icons, and usage stats (can take a second or two on a cold start).
class _BlockingLoadingBody extends StatelessWidget {
  const _BlockingLoadingBody();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Semantics(
              label: 'Loading app list',
              child: const SizedBox(
                width: 48,
                height: 48,
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Loading app list',
              style: theme.textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              'Gathering installed apps, icons, and this week\'s screen time. '
              'This can take a moment.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: 200,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: const LinearProgressIndicator(minHeight: 4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchBar extends StatelessWidget {
  final ValueChanged<String> onChanged;
  final bool hideSystem;
  final ValueChanged<bool> onToggleHideSystem;

  const _SearchBar({
    required this.onChanged,
    required this.hideSystem,
    required this.onToggleHideSystem,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              onChanged: onChanged,
              decoration: InputDecoration(
                hintText: 'Search apps',
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Tooltip(
            message: hideSystem ? 'Show system apps' : 'Hide system apps',
            child: IconButton(
              icon: Icon(hideSystem ? Icons.visibility_off : Icons.visibility),
              onPressed: () => onToggleHideSystem(!hideSystem),
            ),
          ),
        ],
      ),
    );
  }
}

class _SuggestedBanner extends StatelessWidget {
  final List<InstalledApp> apps;
  final Set<String> blockedSet;
  final VoidCallback onBlockAll;

  const _SuggestedBanner({
    required this.apps,
    required this.blockedSet,
    required this.onBlockAll,
  });

  @override
  Widget build(BuildContext context) {
    final unblocked =
        apps.where((a) => !blockedSet.contains(a.packageName)).toList();
    if (unblocked.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome, size: 18),
              const SizedBox(width: 8),
              Text(
                'Suggested to block (${unblocked.length})',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            unblocked.map((a) => a.appName).join(', '),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.tonal(
              onPressed: onBlockAll,
              child: const Text('Block all'),
            ),
          ),
        ],
      ),
    );
  }
}

class _AppTile extends StatelessWidget {
  final InstalledApp app;
  final bool isBlocked;
  final ValueChanged<bool> onChanged;

  const _AppTile({
    required this.app,
    required this.isBlocked,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final usageText = _formatDuration(app.usage);
    final isSuggested = kSuggestedBlockPackages.contains(app.packageName);
    return ListTile(
      leading: SizedBox(
        width: 40,
        height: 40,
        child: app.icon != null
            ? ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.memory(app.icon!, gaplessPlayback: true),
              )
            : const Icon(Icons.android),
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              app.appName,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (isSuggested) ...[
            const SizedBox(width: 6),
            const Icon(Icons.auto_awesome, size: 14, color: AppTheme.accent),
          ],
        ],
      ),
      subtitle: Text(app.packageName),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                usageText,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                'this week',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(width: 8),
          Switch(value: isBlocked, onChanged: onChanged),
        ],
      ),
    );
  }

  static String _formatDuration(Duration d) {
    if (d == Duration.zero) return 'No usage';
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    if (h > 0) return '${h}h ${m}m';
    return '${m}m';
  }
}

class _ErrorView extends StatelessWidget {
  final Object error;
  final VoidCallback onRetry;
  const _ErrorView({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final msg = error.toString();
    final isPermission = msg.toLowerCase().contains('permission') ||
        msg.toLowerCase().contains('usage');
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            isPermission ? Icons.lock_outline : Icons.error_outline,
            size: 48,
          ),
          const SizedBox(height: 12),
          Text(
            isPermission
                ? 'Usage Access permission needed to show screen time.'
                : 'Failed to load apps:\n$msg',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            children: [
              if (isPermission)
                ElevatedButton(
                  onPressed: () => context.push('/permissions'),
                  child: const Text('Open permissions'),
                ),
              OutlinedButton(
                onPressed: onRetry,
                child: const Text('Retry'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
