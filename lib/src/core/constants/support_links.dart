/// Public URLs for optional support, reviews, and project info.
abstract final class SupportLinks {
  static const kofi = 'https://ko-fi.com/trimeradev';
  static const paypal = 'https://paypal.me/trimera';
  static const website = 'https://trimeradev.github.io/AnkiBlock/';
  static const privacy = 'https://trimeradev.github.io/AnkiBlock/privacy.html';
  static const contactEmail = 'ankiblock@trimera.dev';

  /// Play Store listing package id (used for review links).
  static const playStorePackageId = 'com.anki.ankiblock';

  static Uri get playStoreListing => Uri.parse(
        'https://play.google.com/store/apps/details?id=$playStorePackageId',
      );
}
