import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/database/database.dart' as db;
import '../../core/di/providers.dart';
import '../../core/services/ankidroid_service.dart';

/// Review session backed entirely by AnkiDroid's ContentProvider.
///
/// AnkiBlock no longer schedules or renders cards itself — we just fetch
/// a queue from AnkiDroid, display the pre-rendered HTML in a WebView,
/// and ship each answer (1..4) back. AnkiDroid's own scheduler — and its
/// AnkiWeb sync — does the rest.
class ReviewScreen extends ConsumerStatefulWidget {
  /// When set, after `cardLimit` cards are answered a temp unlock is
  /// granted for this package and the app is launched (gate flow).
  final String? unlockPackage;
  final String? unlockAppName;

  /// 0 = no limit; fall back to BlockRule.cardsRequired in unlock mode, 50
  /// in normal mode.
  final int cardLimit;

  const ReviewScreen({
    super.key,
    this.unlockPackage,
    this.unlockAppName,
    this.cardLimit = 0,
  });

  @override
  ConsumerState<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends ConsumerState<ReviewScreen> {
  // Session
  List<AnkiDroidCard> _queue = [];
  int _index = 0;
  bool _loading = true;
  bool _finished = false;
  bool _showingAnswer = false;
  DateTime? _cardStartedAt;
  int? _unlockSessionId;
  int _completedThisSession = 0;
  String? _error;

  late final WebViewController _webView;

  bool get _isUnlockMode =>
      widget.unlockPackage != null && widget.unlockPackage!.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _webView = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.disabled)
      ..setBackgroundColor(Colors.transparent);
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final scopeAsync = await ref.read(studyScopeProvider.future);
    final database = ref.read(databaseProvider);
    final service = ref.read(ankiDroidServiceProvider);

    int limit = widget.cardLimit;
    if (limit <= 0) {
      if (_isUnlockMode) {
        final rule = await database.getBlockRule();
        limit = rule?.cardsRequired ?? 5;
      } else {
        limit = 50;
      }
    }

    try {
      final cards = await service.getStudyableCardsForScope(
        scope: scopeAsync,
        limit: limit,
      );

      int? sessionId;
      if (_isUnlockMode) {
        final rule = await database.getBlockRule();
        final durationMin = rule?.unlockDurationMinutes ?? 10;
        sessionId = await database.insertUnlockSession(
          db.UnlockSessionsCompanion.insert(
            packageName: widget.unlockPackage!,
            expiresAt: DateTime.now()
                .add(Duration(minutes: durationMin))
                .millisecondsSinceEpoch,
            requiredCards: limit,
          ),
        );
      }

      if (!mounted) return;
      setState(() {
        _queue = cards;
        _loading = false;
        _unlockSessionId = sessionId;
        _finished = cards.isEmpty;
      });
      if (cards.isNotEmpty) _renderCurrent();
    } on AnkiDroidUnavailable catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  void _renderCurrent() {
    final card = _queue[_index];
    _cardStartedAt = DateTime.now();
    _showingAnswer = false;
    _loadHtml(card.questionHtml);
  }

  void _loadHtml(String body) {
    _webView.loadHtmlString(_wrapHtml(body));
  }

  /// Wraps AnkiDroid's pre-rendered fragment in a minimal document. Cards
  /// can already reference styles from their note type, but we add a small
  /// reset so things don't render with the WebView's default page styles.
  String _wrapHtml(String body) {
    return '''
<!doctype html>
<html>
<head>
<meta name="viewport" content="width=device-width, initial-scale=1.0, user-scalable=no">
<style>
  :root { color-scheme: light dark; }
  html, body {
    margin: 0; padding: 16px;
    font-family: -apple-system, system-ui, "Segoe UI", Roboto, sans-serif;
    font-size: 18px; line-height: 1.5;
    color: #1a1a1a; background: transparent;
    word-wrap: break-word;
  }
  @media (prefers-color-scheme: dark) {
    body { color: #eee; }
  }
  img { max-width: 100%; height: auto; }
  hr#answer { border: none; border-top: 1px solid #ccc; margin: 16px 0; }
</style>
</head>
<body>$body</body>
</html>
''';
  }

  Future<void> _showAnswer() async {
    final card = _queue[_index];
    setState(() => _showingAnswer = true);
    _loadHtml(card.answerHtml);
  }

  Future<void> _answer(AnkiDroidEase ease) async {
    if (_index >= _queue.length) return;
    final card = _queue[_index];
    final database = ref.read(databaseProvider);
    final service = ref.read(ankiDroidServiceProvider);
    final elapsed = _cardStartedAt == null
        ? Duration.zero
        : DateTime.now().difference(_cardStartedAt!);

    try {
      final ok = await service.answerCard(
        noteId: card.noteId,
        cardOrd: card.cardOrd,
        ease: ease,
        timeTaken: elapsed,
      );
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'AnkiDroid rejected the review. The card was not recorded.'),
          ),
        );
        return;
      }
    } on AnkiDroidUnavailable catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
      return;
    }

    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    await database.incrementCardsReviewed(today);
    _completedThisSession++;
    if (_unlockSessionId != null) {
      await database.incrementCompletedCards(_unlockSessionId!);
    }

    if (!mounted) return;
    if (_index + 1 < _queue.length) {
      setState(() => _index++);
      _renderCurrent();
    } else {
      await _finishSession();
    }
  }

  Future<void> _finishSession() async {
    final database = ref.read(databaseProvider);
    if (_isUnlockMode && _unlockSessionId != null) {
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      await database.incrementUnlocksEarned(today);
      await database.updateUnlockSession(
        db.UnlockSessionsCompanion(
          id: Value(_unlockSessionId!),
          status: const Value(db.UnlockStatus.completed),
        ),
      );

      final pkg = widget.unlockPackage!;
      final perm = ref.read(permissionServiceProvider);
      await perm.grantTempUnlock(pkg);
      await perm.launchApp(pkg);
    }
    if (!mounted) return;
    ref.invalidate(studyCountsProvider);
    setState(() => _finished = true);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Studying')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Studying')),
        body: _ErrorView(message: _error!, onBack: () => context.pop()),
      );
    }
    if (_finished || _queue.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Done')),
        body: _DoneView(
          isUnlockMode: _isUnlockMode,
          appName: widget.unlockAppName,
          completed: _completedThisSession,
          onClose: () => context.pop(),
        ),
      );
    }

    final card = _queue[_index];
    return Scaffold(
      appBar: AppBar(
        title: Text('Card ${_index + 1} / ${_queue.length}'),
      ),
      body: Column(
        children: [
          Expanded(child: WebViewWidget(controller: _webView)),
          const Divider(height: 1),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: _showingAnswer
                  ? _AnswerButtons(
                      buttonCount: card.buttonCount,
                      previews: card.nextReviewTimes,
                      onAnswer: _answer,
                    )
                  : SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _showAnswer,
                        style: FilledButton.styleFrom(
                          padding:
                              const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: const Text('Show answer'),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AnswerButtons extends StatelessWidget {
  final int buttonCount;
  final List<String> previews;
  final void Function(AnkiDroidEase) onAnswer;

  const _AnswerButtons({
    required this.buttonCount,
    required this.previews,
    required this.onAnswer,
  });

  @override
  Widget build(BuildContext context) {
    // AnkiDroid hands us 2, 3, or 4 buttons depending on the card's state.
    // We map them 1..buttonCount onto Again/Hard/Good/Easy in that order.
    const labels = ['Again', 'Hard', 'Good', 'Easy'];
    final colors = [
      Colors.red.shade300,
      Colors.orange.shade300,
      Colors.green.shade300,
      Colors.blue.shade300,
    ];
    const eases = AnkiDroidEase.values;
    final count = buttonCount.clamp(2, 4);
    return Row(
      children: List.generate(count, (i) {
        final ease = eases[i];
        final preview = i < previews.length ? previews[i] : '';
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: i == count - 1 ? 0 : 8),
            child: FilledButton(
              onPressed: () => onAnswer(ease),
              style: FilledButton.styleFrom(
                backgroundColor: colors[i],
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(labels[i],
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  if (preview.isNotEmpty)
                    Text(preview,
                        style: const TextStyle(fontSize: 11)),
                ],
              ),
            ),
          ),
        );
      }),
    );
  }
}

class _DoneView extends StatelessWidget {
  final bool isUnlockMode;
  final String? appName;
  final int completed;
  final VoidCallback onClose;

  const _DoneView({
    required this.isUnlockMode,
    required this.appName,
    required this.completed,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.check_circle_outline,
              size: 96, color: Colors.green),
          const SizedBox(height: 16),
          Text(
            completed == 0
                ? 'Nothing due right now.'
                : 'Reviewed $completed card${completed == 1 ? '' : 's'}.',
            style: Theme.of(context).textTheme.headlineSmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          if (isUnlockMode && completed > 0 && appName != null)
            Text(
              '$appName is unlocked.',
              textAlign: TextAlign.center,
            ),
          const SizedBox(height: 24),
          FilledButton(onPressed: onClose, child: const Text('Done')),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onBack;
  const _ErrorView({required this.message, required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 64, color: Colors.red),
          const SizedBox(height: 16),
          Text(
            'Could not start a study session.',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 24),
          FilledButton(onPressed: onBack, child: const Text('Back')),
        ],
      ),
    );
  }
}
