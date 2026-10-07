/// Model for deal scheduling
class DealSchedule {
  final ScheduleType type;
  final DateTime? startDate;
  final DateTime? endDate;
  final DayOfWeek? dayOfWeek;
  final List<DayOfWeek> dayOfWeeks;
  final bool isRecurring;

  DealSchedule({
    required this.type,
    this.startDate,
    this.endDate,
    this.dayOfWeek,
    this.dayOfWeeks = const [],
    this.isRecurring = false,
  });

  Map<String, dynamic> toJson() {
    return {
      'type': type.name,
      'start_date': startDate?.toIso8601String(),
      'end_date': endDate?.toIso8601String(),
      'day_of_week': dayOfWeek?.index,
      'day_of_weeks': dayOfWeeks.map((day) => day.index).toList(),
      'is_recurring': isRecurring,
    };
  }

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
    );
  }

  bool get isScheduled => type != ScheduleType.none;

  /// Check if deal is available based on schedule
  bool isAvailableNow() {
    final now = DateTime.now();

    switch (type) {
      case ScheduleType.none:
        return true;

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
}

enum ScheduleType { none, dateRange, dayOfWeek }

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
}
