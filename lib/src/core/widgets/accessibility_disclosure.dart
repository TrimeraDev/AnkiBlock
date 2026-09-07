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
            'To block apps and websites in real time, AnkiBlock uses Android\'s '
            'Accessibility service to detect which app is in the foreground and '
            'to read the address bar in supported browsers — solely to enforce '
            'the blocks you configure and show your flashcard study gate.\n\n'
            'AnkiBlock does not read passwords, messages, or page content. '
            'No browsing data or other information leaves your device — it is '
            'never sent off-device or sold.\n\n'
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
