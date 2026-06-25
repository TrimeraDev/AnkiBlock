import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

Future<bool> openExternalUrl(Uri uri) async {
  try {
    final launched = await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    );
    return launched;
  } catch (e, st) {
    debugPrint('openExternalUrl failed for $uri: $e\n$st');
    return false;
  }
}
