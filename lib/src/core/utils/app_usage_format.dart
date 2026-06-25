/// Formats screen-time duration for app list rows.
String formatAppUsageDuration(Duration d) {
  if (d == Duration.zero) return 'No usage';
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  if (h > 0) return '${h}h ${m}m';
  if (m > 0) return '${m}m';
  return '<1m';
}

/// Label shown under usage totals in app lists.
const kAppUsagePeriodLabel = 'this week';
