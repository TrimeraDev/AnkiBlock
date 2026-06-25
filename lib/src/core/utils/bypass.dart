/// Emergency bypass helpers for the study gate.
int bypassesRemaining({
  required bool bypassEnabled,
  required int bypassDailyCap,
  required int bypassesUsed,
}) {
  if (!bypassEnabled) return 0;
  return (bypassDailyCap - bypassesUsed).clamp(0, bypassDailyCap);
}

bool canUseBypass({
  required bool bypassEnabled,
  required int bypassDailyCap,
  required int bypassesUsed,
}) =>
    bypassesRemaining(
      bypassEnabled: bypassEnabled,
      bypassDailyCap: bypassDailyCap,
      bypassesUsed: bypassesUsed,
    ) >
    0;
