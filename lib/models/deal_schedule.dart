/// Model for deal scheduling
class DealSchedule {
  /// South Africa has no daylight saving, so SAST is always UTC+2.
  static const Duration sastOffset = Duration(hours: 2);
  static const int defaultClaimGraceMinutes = 120;

  final ScheduleType type;
  final DateTime? startDate;
  final DateTime? endDate;
  final DayOfWeek? dayOfWeek;
  final List<DayOfWeek> dayOfWeeks;
  final bool isRecurring;

  /// Weekly schedules only: optional serving windows (SAST) and how long after
  /// a window ends the bill can still be claimed.
  final List<DealTimeSlot> timeSlots;
  final int claimGraceMinutes;

  DealSchedule({
    required this.type,
    this.startDate,
    this.endDate,
    this.dayOfWeek,
    this.dayOfWeeks = const [],
    this.isRecurring = false,
    this.timeSlots = const [],
    this.claimGraceMinutes = 0,
  });

  Map<String, dynamic> toJson() {
    if (type == ScheduleType.weekly) {
      return {
        'type': type.name,
        if (startDate != null) 'start_date': _dateOnly(startDate!),
        if (endDate != null) 'end_date': _dateOnly(endDate!),
        'day_of_weeks': dayOfWeeks.map((day) => day.index).toList(),
        'time_slots': timeSlots.map((slot) => slot.toJson()).toList(),
        'claim_grace_minutes': claimGraceMinutes,
      };
    }
    return {
      'type': type.name,
      'start_date': startDate?.toIso8601String(),
      'end_date': endDate?.toIso8601String(),
      'day_of_week': dayOfWeek?.index,
      'day_of_weeks': dayOfWeeks.map((day) => day.index).toList(),
      'is_recurring': isRecurring,
    };
  }

  static String _dateOnly(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  factory DealSchedule.fromJson(Map<String, dynamic> json) {
    final rawDays = json['day_of_weeks'];
    final parsedDays = rawDays is List
      ? rawDays
        .whereType<num>()
        .where((index) => index >= 0 && index < DayOfWeek.values.length)
        .map((index) => DayOfWeek.values[index.toInt()])
        .toList()
      : <DayOfWeek>[];
    final legacyDay = json['day_of_week'] is num &&
        (json['day_of_week'] as num).toInt() >= 0 &&
        (json['day_of_week'] as num).toInt() < DayOfWeek.values.length
      ? DayOfWeek.values[(json['day_of_week'] as num).toInt()]
      : null;

    return DealSchedule(
      type: ScheduleType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => ScheduleType.none,
      ),
      startDate: json['start_date'] != null
          ? DateTime.parse(json['start_date'])
          : null,
      endDate: json['end_date'] != null
          ? DateTime.parse(json['end_date'])
          : null,
        dayOfWeek: legacyDay,
        dayOfWeeks: parsedDays.isNotEmpty
          ? parsedDays
          : (legacyDay == null ? const [] : [legacyDay]),
      isRecurring: json['is_recurring'] ?? false,
      timeSlots: json['time_slots'] is List
          ? (json['time_slots'] as List)
              .whereType<Map>()
              .map((m) => DealTimeSlot.tryParse(Map<String, dynamic>.from(m)))
              .whereType<DealTimeSlot>()
              .toList()
          : const [],
      claimGraceMinutes: (json['claim_grace_minutes'] is num)
          ? (json['claim_grace_minutes'] as num).toInt().clamp(0, 360)
          : 0,
    );
  }

  bool get isScheduled => type != ScheduleType.none;

  /// Check if deal is available based on schedule
  bool isAvailableNow() => isAvailableAt(DateTime.now());

  bool isAvailableAt(DateTime moment) {
    final now = moment;

    switch (type) {
      case ScheduleType.none:
        return true;

      case ScheduleType.weekly:
        return _isWeeklyAvailableAt(moment);

      case ScheduleType.dateRange:
        if (startDate == null || endDate == null) return true;
        final isAfterStart =
            now.isAfter(startDate!) || now.isAtSameMomentAs(startDate!);
        final isBeforeEnd =
            now.isBefore(endDate!) || now.isAtSameMomentAs(endDate!);
        return isAfterStart && isBeforeEnd;

      case ScheduleType.dayOfWeek:
        final selectedDays = dayOfWeeks.isNotEmpty
            ? dayOfWeeks
            : (dayOfWeek == null ? const <DayOfWeek>[] : [dayOfWeek!]);
        if (selectedDays.isEmpty) return true;
        return selectedDays.any((day) => now.weekday - 1 == day.index);
    }
  }

  /// Mirrors public.restaurant_deal_is_available in the database.
  bool _isWeeklyAvailableAt(DateTime moment) {
    final local = sastWallClock(moment);
    final grace = Duration(minutes: claimGraceMinutes);
    final slots = timeSlots.isEmpty
        ? const [DealTimeSlot(startMinutes: 0, endMinutes: 24 * 60)]
        : timeSlots;
    final candidates = {_day(local), _day(local.subtract(grace))};

    for (final day in candidates) {
      if (startDate != null && day.isBefore(_day(startDate!))) continue;
      if (endDate != null && day.isAfter(_day(endDate!))) continue;
      if (dayOfWeeks.isNotEmpty &&
          !dayOfWeeks.any((d) => d.index == day.weekday - 1)) {
        continue;
      }
      for (final slot in slots) {
        final from = day.add(Duration(minutes: slot.startMinutes));
        final until = day.add(Duration(minutes: slot.endMinutes)).add(grace);
        if (!local.isBefore(from) && local.isBefore(until)) return true;
      }
    }
    return false;
  }

  /// SAST wall-clock time, represented as a UTC DateTime so date maths is
  /// unaffected by the device's own time zone.
  static DateTime sastWallClock(DateTime moment) =>
      moment.toUtc().add(sastOffset);

  static DateTime _day(DateTime d) => DateTime.utc(d.year, d.month, d.day);

  /// Short, member-friendly summary, e.g. "Mon–Fri · 16:00–18:00".
  String describe() {
    final parts = <String>[];
    if (dayOfWeeks.isNotEmpty && dayOfWeeks.length < 7) {
      final sorted = [...dayOfWeeks]..sort((a, b) => a.index.compareTo(b.index));
      parts.add(sorted.map((d) => d.shortName).join(', '));
    } else {
      parts.add('Every day');
    }
    if (timeSlots.isNotEmpty) {
      parts.add(timeSlots.map((s) => s.label).join(', '));
    }
    if (startDate != null || endDate != null) {
      String fmt(DateTime d) => '${d.day}/${d.month}/${d.year}';
      if (startDate != null && endDate != null) {
        parts.add('${fmt(startDate!)} – ${fmt(endDate!)}');
      } else if (endDate != null) {
        parts.add('until ${fmt(endDate!)}');
      } else {
        parts.add('from ${fmt(startDate!)}');
      }
    }
    return parts.join(' · ');
  }
}

/// A serving window within a day, in minutes after midnight (SAST).
class DealTimeSlot {
  final int startMinutes;
  final int endMinutes;

  const DealTimeSlot({required this.startMinutes, required this.endMinutes});

  static int? parseTime(String? value) {
    if (value == null) return null;
    final match = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(value.trim());
    if (match == null) return null;
    final h = int.parse(match.group(1)!);
    final m = int.parse(match.group(2)!);
    if (m > 59 || h > 24 || (h == 24 && m != 0)) return null;
    return h * 60 + m;
  }

  static String formatTime(int minutes) =>
      '${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}';

  static DealTimeSlot? tryParse(Map<String, dynamic> json) {
    final start = parseTime(json['start']?.toString());
    final end = parseTime(json['end']?.toString());
    if (start == null || end == null || end <= start) return null;
    return DealTimeSlot(startMinutes: start, endMinutes: end);
  }

  Map<String, dynamic> toJson() => {
    'start': formatTime(startMinutes),
    'end': formatTime(endMinutes),
  };

  String get label => '${formatTime(startMinutes)}–${formatTime(endMinutes)}';
}

enum ScheduleType { none, dateRange, dayOfWeek, weekly }

enum DayOfWeek {
  monday,
  tuesday,
  wednesday,
  thursday,
  friday,
  saturday,
  sunday,
}

extension DayOfWeekExtension on DayOfWeek {
  String get displayName {
    switch (this) {
      case DayOfWeek.monday:
        return 'Monday';
      case DayOfWeek.tuesday:
        return 'Tuesday';
      case DayOfWeek.wednesday:
        return 'Wednesday';
      case DayOfWeek.thursday:
        return 'Thursday';
      case DayOfWeek.friday:
        return 'Friday';
      case DayOfWeek.saturday:
        return 'Saturday';
      case DayOfWeek.sunday:
        return 'Sunday';
    }
  }

  String get shortName => displayName.substring(0, 3);
}
