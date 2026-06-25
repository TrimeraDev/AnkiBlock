import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_review/in_app_review.dart';

import '../constants/support_links.dart';
import '../utils/external_links.dart';

/// Opens Ko-fi, PayPal, Play Store, and website links from settings.
class SupportLinkActions {
  Future<bool> openKofi() => openExternalUrl(Uri.parse(SupportLinks.kofi));

  Future<bool> openPayPal() => openExternalUrl(Uri.parse(SupportLinks.paypal));

  /// Native in-app review dialog when available; store listing as fallback.
  Future<bool> requestAppReview() async {
    final review = InAppReview.instance;
    try {
      if (await review.isAvailable()) {
        await review.requestReview();
        return true;
      }
      await review.openStoreListing();
      return true;
    } catch (_) {
      return openPlayStoreListing();
    }
  }

  Future<bool> openPlayStoreListing() =>
      openExternalUrl(SupportLinks.playStoreListing);

  Future<bool> openWebsite() => openExternalUrl(Uri.parse(SupportLinks.website));

  Future<bool> openPrivacy() => openExternalUrl(Uri.parse(SupportLinks.privacy));

  Future<bool> openEmail() => openExternalUrl(
        Uri(
          scheme: 'mailto',
          path: SupportLinks.contactEmail,
        ),
      );
}

final supportLinkActionsProvider = Provider<SupportLinkActions>((ref) {
  return SupportLinkActions();
});

Future<void> showLinkOpenError(BuildContext context) async {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('Could not open link')),
  );
}

Future<void> openSupportLink(
  BuildContext context,
  WidgetRef ref,
  Future<bool> Function(SupportLinkActions actions) open,
) async {
  final ok = await open(ref.read(supportLinkActionsProvider));
  if (!ok && context.mounted) {
    await showLinkOpenError(context);
  }
}
