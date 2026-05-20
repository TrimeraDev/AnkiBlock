import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/database/database.dart' as db;
import '../../core/di/providers.dart';
import '../../core/services/ankidroid_service.dart';
import '../../core/services/card_html_processor.dart';
import '../../core/theme/app_theme.dart';

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
  bool _htmlLoading = false;
  DateTime? _cardStartedAt;
  int? _unlockSessionId;
  int _completedThisSession = 0;
  String? _error;

  late final WebViewController _webView;
  late final CardHtmlProcessor _htmlProcessor;

  bool get _isUnlockMode =>
      widget.unlockPackage != null && widget.unlockPackage!.isNotEmpty;

  @override
  void initState() {
    super.initState();
    // Anki card templates frequently embed inline JS (MathJax bootstrap,
    // cloze toggles, type-in-the-answer comparison helpers). The HTML is
    // sourced from the user's own AnkiDroid collection — same trust level
    // as AnkiDroid itself — so we enable JS unrestrictedly.
    _webView = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(AppTheme.surface);
    _htmlProcessor = CardHtmlProcessor(ref.read(ankiDroidServiceProvider));
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
    _loadHtml(card.questionHtml, revealAnswer: false);
  }

  /// HTML to show after "Show answer". Stacks front + back when Anki's answer
  /// template doesn't already include the question, and surfaces a message when
  /// AnkiDroid returns an empty back side.
  String _revealedHtml(AnkiDroidCard card) {
    final q = card.questionHtml.trim();
    final a = card.answerHtml.trim();
    if (a.isEmpty) {
      if (q.isEmpty) {
        return '<p>No card content returned from AnkiDroid.</p>';
      }
      return '$q<hr id="answer"><p><em>Answer was empty in AnkiDroid. '
          'Try reviewing this card in AnkiDroid once to refresh its template.</em></p>';
    }
    if (q.isEmpty || _answerLikelyIncludesFront(q, a)) return a;
    return '$q<hr id="answer">$a';
  }

  bool _answerLikelyIncludesFront(String question, String answer) {
    final snippet = _plainTextSnippet(question, 48);
    if (snippet.length < 8) return answer.length >= question.length;
    return answer.contains(snippet);
  }

  String _plainTextSnippet(String html, int maxLen) {
    final plain = html
        .replaceAll(RegExp(r'<[^>]+>'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (plain.length <= maxLen) return plain;
    return plain.substring(0, maxLen);
  }

  Future<void> _loadHtml(String body, {required bool revealAnswer}) async {
    if (mounted) setState(() => _htmlLoading = true);
    final card = _queue[_index];
    // Inline any AnkiDroid media references before handing the HTML to the
    // WebView. If the media folder isn't connected, [process] is a no-op
    // and we fall back to broken-image icons.
    final result = await _htmlProcessor.processWithReport(
      body,
      cardMediaFiles: card.mediaFiles,
    );
    if (kDebugMode && result.report.hasMissing && mounted) {
      final names = CardHtmlProcessor.filenamesInHtml(body);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Missing media: ${result.report.missing.take(3).join(", ")}'
            '${result.report.missing.length > 3 ? "…" : ""}. '
            'Check AnkiDroid sync → Media folder.',
          ),
          duration: const Duration(seconds: 4),
        ),
      );
      assert(names.isNotEmpty || card.mediaFiles.isNotEmpty);
    }
    final processed = result.html;
    if (!mounted) return;
    await _webView.loadHtmlString(_wrapHtml(processed, revealAnswer: revealAnswer));
    if (!mounted) return;
    // Many note types hide the back in CSS/JS until AnkiDroid's reviewer
    // toggles them — we are not in that activity, so force visibility.
    if (revealAnswer) {
      await _webView.runJavaScript(_revealAnswerJs);
    }
    if (mounted) setState(() => _htmlLoading = false);
  }

  /// Unhide answer regions that Anki templates keep `display:none` until tapped
  /// inside AnkiDroid's own reviewer (type-in-the-answer, etc.).
  static const _revealAnswerJs = '''
(function() {
  var ids = ['answer', 'ans', 'answers', 'back'];
  for (var i = 0; i < ids.length; i++) {
    var el = document.getElementById(ids[i]);
    if (el) {
      el.style.setProperty('display', 'block', 'important');
      el.style.setProperty('visibility', 'visible', 'important');
      el.hidden = false;
      el.removeAttribute('hidden');
    }
  }
  document.querySelectorAll('#answer, #ans, .answer').forEach(function(el) {
    el.style.setProperty('display', 'block', 'important');
    el.style.setProperty('visibility', 'visible', 'important');
    el.hidden = false;
  });
})();
''';

  /// Wraps AnkiDroid's pre-rendered fragment in a minimal document.
  ///
  /// Note-type CSS from Anki often sets light grey text (or night-mode
  /// colours on a white WebView). We override those so cards stay readable
  /// inside AnkiBlock's light shell.
  String _wrapHtml(String body, {required bool revealAnswer}) {
    final revealCss = revealAnswer
        ? '''
  /* Back side is often hidden until AnkiDroid's reviewer reveals it. */
  #answer, #ans, #answers, #back, .answer {
    display: block !important;
    visibility: visible !important;
    opacity: 1 !important;
  }
'''
        : '';
    return '''
<!doctype html>
<html>
<head>
<meta name="viewport" content="width=device-width, initial-scale=1.0, user-scalable=no">
<meta name="color-scheme" content="light">
<style>
  html, body {
    margin: 0;
    padding: 16px;
    font-family: -apple-system, system-ui, "Segoe UI", Roboto, sans-serif;
    font-size: 18px;
    line-height: 1.5;
    color: #1b1b1b !important;
    background: #ffffff !important;
    word-wrap: break-word;
    -webkit-text-fill-color: #1b1b1b !important;
  }
  /* Anki wraps content in .card; templates often set a faint text colour. */
  .card, .card * {
    color: #1b1b1b !important;
    background-color: transparent !important;
    -webkit-text-fill-color: #1b1b1b !important;
  }
  /* Cloze deletions should stay visually distinct (beat .card *). */
  .cloze, .card .cloze {
    color: #1565c0 !important;
    -webkit-text-fill-color: #1565c0 !important;
    font-weight: 600;
  }
  a, a * {
    color: #1565c0 !important;
    -webkit-text-fill-color: #1565c0 !important;
  }
  img { max-width: 100%; height: auto; }
  audio, video { max-width: 100%; }
  hr#answer {
    border: none;
    border-top: 1px solid #d6d2ca;
    margin: 16px 0;
  }
$revealCss
</style>
</head>
<body>$body</body>
</html>
''';
  }

  Future<void> _showAnswer() async {
    final card = _queue[_index];
    setState(() => _showingAnswer = true);
    await _loadHtml(_revealedHtml(card), revealAnswer: true);
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
        _unlockSessionId!,
        const db.UnlockSessionsCompanion(
          status: Value(db.UnlockStatus.completed),
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
          Expanded(
            child: Stack(
              children: [
                WebViewWidget(controller: _webView),
                if (_htmlLoading)
                  const Center(child: CircularProgressIndicator()),
              ],
            ),
          ),
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
