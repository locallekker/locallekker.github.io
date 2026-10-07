import 'package:shared_preferences/shared_preferences.dart';

/// Tracks when the member last opened a curated category section so newer
/// deals can be flagged on the entry banner.
class CategoryNotice {
  final String _key;

  const CategoryNotice(this._key);

  /// Returns the last-seen timestamp, seeding it to "now" on first use so
  /// pre-existing deals are not announced as new.
  Future<DateTime> loadLastSeen() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_key);
    final parsed = stored == null ? null : DateTime.tryParse(stored);
    if (parsed != null) return parsed;
    final now = DateTime.now().toUtc();
    await prefs.setString(_key, now.toIso8601String());
    return now;
  }

  Future<void> markSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, DateTime.now().toUtc().toIso8601String());
  }
}

class FreshLocalNotice {
  static const _notice = CategoryNotice('fresh_local_last_seen_at');

  static Future<DateTime> loadLastSeen() => _notice.loadLastSeen();

  static Future<void> markSeen() => _notice.markSeen();
}

class LocalSipsNotice {
  static const _notice = CategoryNotice('local_sips_last_seen_at');

  static Future<DateTime> loadLastSeen() => _notice.loadLastSeen();

  static Future<void> markSeen() => _notice.markSeen();
}

class LocalEatsNotice {
  static const _notice = CategoryNotice('local_eats_last_seen_at');

  static Future<DateTime> loadLastSeen() => _notice.loadLastSeen();

  static Future<void> markSeen() => _notice.markSeen();
}

class LocallyActiveNotice {
  static const _notice = CategoryNotice('locally_active_last_seen_at');

  static Future<DateTime> loadLastSeen() => _notice.loadLastSeen();

  static Future<void> markSeen() => _notice.markSeen();
}
