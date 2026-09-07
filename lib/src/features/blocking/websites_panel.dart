import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/blocking/website_rule.dart';
import '../../core/database/database.dart';
import '../../core/di/providers.dart';
import '../../core/services/apps_service.dart';
import '../../core/setup/setup_actions.dart';
import '../../core/theme/app_theme.dart';

/// Website rules tab for [BlockingScreen].
class WebsitesBlockingPanel extends ConsumerStatefulWidget {
  const WebsitesBlockingPanel({super.key});

  @override
  ConsumerState<WebsitesBlockingPanel> createState() =>
      _WebsitesBlockingPanelState();
}

class _WebsitesBlockingPanelState extends ConsumerState<WebsitesBlockingPanel> {
  BrowserCompatibility? _browserCompatibility;
  bool _browsersExpanded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadBrowsers());
  }

  Future<void> _loadBrowsers() async {
    final compat =
        await ref.read(appsServiceProvider).getBrowserCompatibility();
    if (!mounted) return;
    setState(() => _browserCompatibility = compat);
  }

  @override
  Widget build(BuildContext context) {
    final sitesAsync = ref.watch(blockedWebsitesProvider);
    final rule = ref.watch(blockRuleProvider).valueOrNull;
    final sites = (sitesAsync.valueOrNull ?? const <BlockedWebsite>[])
        .toList()
      ..sort((a, b) => a.pattern.compareTo(b.pattern));
    final activePatterns =
        sites.where((s) => s.isBlocked).map((s) => s.pattern).toSet();
    final blockUnsupported = rule?.blockUnsupportedBrowsers ?? false;
    final compat = _browserCompatibility;

    return Column(
      children: [
        Expanded(
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                      child: Text(
                        'Block domains and paths in supported browsers. '
                        'youtube.com also covers m.youtube.com and www. '
                        'Example: youtube.com/shorts or reddit.com',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppTheme.onSurfaceVariant,
                            ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final p in kSuggestedWebsitePatterns)
                            ActionChip(
                              label: Text(p),
                              onPressed: activePatterns.contains(p)
                                  ? null
                                  : () => addBlockedWebsite(
                                        ref,
                                        pattern: p,
                                        isRegex: false,
                                      ),
                            ),
                        ],
                      ),
                    ),
                    SwitchListTile(
                      title: const Text('Block unsupported browsers'),
                      subtitle: const Text(
                        'When on, browsers we cannot read the address bar in '
                        'are blocked entirely while website rules exist.',
                      ),
                      value: blockUnsupported,
                      onChanged: (v) => updateBlockUnsupportedBrowsers(ref, v),
                    ),
                    ListTile(
                      dense: true,
                      title: Text(
                        _browsersExpanded
                            ? 'Hide browser compatibility'
                            : 'Browser compatibility',
                      ),
                      subtitle: compat == null
                          ? const Text('Loading…')
                          : Text(
                              '${compat.supportedInstalled.length} supported on device'
                              '${compat.unsupportedInstalled.isEmpty ? '' : ' · ${compat.unsupportedInstalled.length} unsupported'}',
                            ),
                      trailing: Icon(
                        _browsersExpanded
                            ? Icons.expand_less
                            : Icons.expand_more,
                      ),
                      onTap: () => setState(
                        () => _browsersExpanded = !_browsersExpanded,
                      ),
                    ),
                    if (_browsersExpanded) ...[
                      _BrowserSection(
                        title: 'Supported on your device',
                        icon: Icons.check_circle_outline,
                        iconColor: AppTheme.primary,
                        emptyMessage:
                            'No supported browsers detected. Install Chrome, Ecosia, Firefox, or another supported browser.',
                        entries: compat?.supportedInstalled ?? const [],
                      ),
                      _BrowserSection(
                        title: 'Unsupported on your device',
                        icon: Icons.warning_amber_outlined,
                        iconColor: Theme.of(context).colorScheme.error,
                        emptyMessage:
                            'No other link-opening apps found, or all installed browsers are supported.',
                        entries: compat?.unsupportedInstalled ?? const [],
                      ),
                      if ((compat?.supportedCatalog ?? const []).isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                          child: Text(
                            'All supported browser types: '
                            '${compat!.supportedCatalog.join(', ')}.',
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: AppTheme.onSurfaceVariant,
                                    ),
                          ),
                        ),
                    ],
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: Text(
                        'Private / in-app browsers may not be covered. '
                        'You can also block a browser as an app.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppTheme.onSurfaceVariant,
                            ),
                      ),
                    ),
                    const Divider(height: 1),
                  ],
                ),
              ),
              if (sites.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Text(
                      'No website rules yet.\nTap a suggestion or add one.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: AppTheme.onSurfaceVariant,
                          ),
                    ),
                  ),
                )
              else
                SliverList.separated(
                  itemCount: sites.length,
                  separatorBuilder: (_, __) => const Divider(height: 0),
                  itemBuilder: (context, i) {
                    final site = sites[i];
                    return ListTile(
                      title: Text(site.pattern),
                      subtitle: Text(
                        [
                          if (site.isRegex) 'Regex',
                          if (site.label != site.pattern) site.label,
                        ].where((s) => s.isNotEmpty).join(' · '),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Switch(
                            value: site.isBlocked,
                            onChanged: (v) => toggleWebsiteBlocked(
                              ref,
                              id: site.id,
                              blocked: v,
                              context: context,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline),
                            tooltip: 'Remove',
                            onPressed: () => deleteWebsiteRule(
                              ref,
                              id: site.id,
                              context: context,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
            ],
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: FilledButton.icon(
              onPressed: () => _showAddSheet(context),
              icon: const Icon(Icons.add),
              label: const Text('Add website rule'),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _showAddSheet(BuildContext context) async {
    final patternCtrl = TextEditingController();
    final previewCtrl = TextEditingController(text: 'm.youtube.com/shorts/abc');
    var isRegex = false;
    String? error;
    String? preview;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModal) {
            void recompute() {
              error = validateWebsitePattern(
                patternCtrl.text,
                isRegex: isRegex,
              );
              final rules = [
                if (error == null && patternCtrl.text.trim().isNotEmpty)
                  WebsiteRule(
                    pattern: patternCtrl.text.trim(),
                    isRegex: isRegex,
                  ),
              ];
              final match = matchWebsiteRules(previewCtrl.text, rules);
              preview = match == null
                  ? 'No match'
                  : 'Matches (${match.label})';
            }

            recompute();

            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Add website rule',
                    style: Theme.of(ctx).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: patternCtrl,
                    decoration: InputDecoration(
                      labelText: isRegex ? 'Regular expression' : 'Pattern',
                      hintText: isRegex
                          ? r'youtube\.com/shorts'
                          : 'youtube.com/shorts',
                      errorText: error,
                    ),
                    onChanged: (_) => setModal(recompute),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Use regex'),
                    subtitle: const Text(
                      'Advanced: match anywhere in host/path/query',
                    ),
                    value: isRegex,
                    onChanged: (v) => setModal(() {
                      isRegex = v;
                      recompute();
                    }),
                  ),
                  TextField(
                    controller: previewCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Preview URL',
                      hintText: 'm.youtube.com/shorts/abc',
                    ),
                    onChanged: (_) => setModal(recompute),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    preview ?? '',
                    style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                          color: preview == 'No match'
                              ? AppTheme.onSurfaceVariant
                              : AppTheme.primary,
                        ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: error != null || patternCtrl.text.trim().isEmpty
                        ? null
                        : () async {
                            await addBlockedWebsite(
                              ref,
                              pattern: patternCtrl.text.trim(),
                              isRegex: isRegex,
                            );
                            if (ctx.mounted) Navigator.of(ctx).pop();
                          },
                    child: const Text('Add rule'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
    patternCtrl.dispose();
    previewCtrl.dispose();
  }
}

class _BrowserSection extends StatelessWidget {
  const _BrowserSection({
    required this.title,
    required this.icon,
    required this.iconColor,
    required this.emptyMessage,
    required this.entries,
  });

  final String title;
  final IconData icon;
  final Color iconColor;
  final String emptyMessage;
  final List<BrowserEntry> entries;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: iconColor),
              const SizedBox(width: 8),
              Text(
                title,
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (entries.isEmpty)
            Text(
              emptyMessage,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppTheme.onSurfaceVariant,
                  ),
            )
          else
            ...entries.map(
              (e) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  e.appName,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
