/// Helpers for building the human-readable names that appear on deal
/// requests and receipts (member names for the trusted partner, and the
/// trusted partner / business name for the member).
///
/// These intentionally degrade gracefully: a member whose profile has not
/// been fully completed (e.g. a newly activated TP-key member) often has an
/// empty `name`/`surname` but always has an `email`, so we fall back to the
/// email before showing a generic placeholder.
library;

/// Builds a member display name from [name]/[surname], falling back to
/// [email] and finally [fallback] when nothing usable is available.
String buildMemberDisplayName({
  String? name,
  String? surname,
  String? email,
  String fallback = 'Member',
}) {
  final full = [name, surname]
      .map((s) => (s ?? '').trim())
      .where((s) => s.isNotEmpty)
      .join(' ')
      .trim();
  if (full.isNotEmpty) return full;

  final mail = (email ?? '').trim();
  if (mail.isNotEmpty) return mail;

  return fallback;
}

/// Returns a non-empty trusted partner / business name, using [fallback]
/// only when [businessName] is null or blank.
String buildBusinessDisplayName(
  String? businessName, {
  String fallback = 'Trusted Partner',
}) {
  final name = (businessName ?? '').trim();
  return name.isNotEmpty ? name : fallback;
}
