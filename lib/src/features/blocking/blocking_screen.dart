import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/database/database.dart';
import '../../core/di/providers.dart';
import '../../core/services/apps_service.dart';

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

    return Scaffold(
      appBar: AppBar(
        title: const Text('App Blocking'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () => ref.invalidate(installedAppsProvider),
          ),
          PopupMenuButton<_SortMode>(
            icon: const Icon(Icons.sort),
            onSelected: (m) => setState(() => _sort = m),
            itemBuilder: (_) => const [
              PopupMenuItem(
                  value: _SortMode.usage, child: Text('Sort by usage')),
              PopupMenuItem(value: _SortMode.name, child: Text('Sort by name')),
            ],
          ),
        ],
      ),
      body: appsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _ErrorView(
            error: e,
            onRetry: () {
              ref.invalidate(installedAppsProvider);
            }),
        data: (apps) {
          final blockedSet = (blockedAsync.valueOrNull ?? const <BlockedApp>[])
              .where((b) => b.isBlocked)
              .map((b) => b.packageName)
              .toSet();

          final filtered = apps.where((a) {
            if (_hideSystem && a.isSystem) return false;
            if (_query.isEmpty) return true;
            final q = _query.toLowerCase();
            return a.appName.toLowerCase().contains(q) ||
                a.packageName.toLowerCase().contains(q);
          }).toList();

          filtered.sort((a, b) {
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
          });

          final suggested = filtered
              .where((a) => kSuggestedBlockPackages.contains(a.packageName))
              .toList();

          return Column(
            children: [
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
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const Divider(height: 0),
                  itemBuilder: (context, i) {
                    final app = filtered[i];
                    final isBlocked = blockedSet.contains(app.packageName);
                    return _AppTile(
                      app: app,
                      isBlocked: isBlocked,
                      onChanged: (v) => _toggleBlock(app, v),
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
    final db = ref.read(databaseProvider);
    final all = await db.watchAllBlockedApps().first;
    final active = all
        .where((b) => b.isBlocked)
        .map((b) => (pkg: b.packageName, name: b.displayName))
        .toList();
    final svc = ref.read(appsServiceProvider);
    await svc.setBlockedPackages(active);
    if (active.isNotEmpty) {
      await svc.startAppMonitor();
    } else {
      await svc.stopAppMonitor();
    }
  }
}

enum _SortMode { usage, name }

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
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(12),
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
            const Icon(Icons.auto_awesome, size: 14, color: Colors.amber),
          ],
        ],
      ),
      subtitle: Text(
        '${app.packageName}\n$usageText (last 7d)',
      ),
      isThreeLine: true,
      trailing: Switch(value: isBlocked, onChanged: onChanged),
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
