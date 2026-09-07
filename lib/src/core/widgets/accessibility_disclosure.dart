import 'package:flutter/material.dart';

/// Google Play–compliant prominent disclosure before enabling Accessibility.
Future<bool> showAccessibilityDisclosureDialog(BuildContext context) async {
  final accepted = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) {
      return AlertDialog(
        title: const Text('Enable Accessibility for blocking'),
        content: SingleChildScrollView(
          child: Text(
            'To block apps in real time, AnkiBlock uses Android\'s Accessibility '
            'service to detect which app is in the foreground and show your '
            'flashcard study gate.\n\n'
            'AnkiBlock does this only to enforce the blocks you set up. It does '
            'not read passwords, messages, or other screen content, and this '
            'data stays on your device — it is never sent off-device or sold.\n\n'
            'On the next screen, find AnkiBlock and turn the service on.',
            style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(height: 1.4),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Accept & continue'),
          ),
        ],
      );
    },
  );
  return accepted == true;
}
