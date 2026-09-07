import 'dart:math';

/// Short, easy-to-write word list for generated accountability passphrases.
const kSettingsPasswordWordCount = 4;

const _words = [
  'amber', 'anchor', 'apple', 'arrow', 'atlas', 'badge', 'baker', 'beach',
  'berry', 'blade', 'blaze', 'bloom', 'breeze', 'brick', 'brook', 'cabin',
  'candle', 'canyon', 'cedar', 'charm', 'cider', 'cliff', 'cloud', 'coral',
  'crown', 'daisy', 'delta', 'diver', 'dolphin', 'eagle', 'ember', 'fable',
  'falcon', 'fern', 'flame', 'flint', 'forest', 'frost', 'galaxy', 'garden',
  'glacier', 'globe', 'granite', 'harbor', 'hazel', 'heron', 'honey', 'ivory',
  'jade', 'jelly', 'jewel', 'kite', 'lagoon', 'lance', 'lemon', 'linen',
  'lotus', 'maple', 'marble', 'meadow', 'melon', 'mercury', 'mint', 'mist',
  'moon', 'moss', 'nebula', 'nectar', 'noble', 'north', 'ocean', 'olive',
  'onyx', 'orbit', 'otter', 'panda', 'pearl', 'pebble', 'piano', 'pilot',
  'pine', 'plaza', 'prism', 'quartz', 'quiet', 'rabbit', 'raven', 'river',
  'robin', 'rocket', 'sage', 'sail', 'sandal', 'shadow', 'shield', 'silver',
  'spark', 'sparrow', 'spruce', 'stone', 'storm', 'summit', 'sunset', 'swift',
  'thistle', 'tiger', 'timber', 'topaz', 'torch', 'tower', 'trail', 'tulip',
  'velvet', 'violet', 'walnut', 'willow', 'winter', 'wren', 'zenith',
];

const _recoveryAlphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
const int kRecoveryCodeLength = 12;

/// Generates a random word passphrase like "candle forest marble quiet".
String generateSettingsPassphrase({Random? random, int wordCount = kSettingsPasswordWordCount}) {
  final rng = random ?? Random.secure();
  final picks = <String>[];
  for (var i = 0; i < wordCount; i++) {
    picks.add(_words[rng.nextInt(_words.length)]);
  }
  return picks.join(' ');
}

/// Generates a recovery code formatted as ABCD-EFGH-IJKL.
String generateRecoveryCode({Random? random}) {
  final rng = random ?? Random.secure();
  final chars = List<String>.generate(
    kRecoveryCodeLength,
    (_) => _recoveryAlphabet[rng.nextInt(_recoveryAlphabet.length)],
  );
  return '${chars.sublist(0, 4).join()}-'
      '${chars.sublist(4, 8).join()}-'
      '${chars.sublist(8, 12).join()}';
}
