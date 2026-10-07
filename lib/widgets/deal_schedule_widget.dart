import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import '../models/deal_schedule.dart';

/// Widget for scheduling deals with date range or day of week options
class DealScheduleWidget extends StatefulWidget {
  final DealSchedule? initialSchedule;
  final Function(DealSchedule?) onScheduleChanged;

  const DealScheduleWidget({
    super.key,
    this.initialSchedule,
    required this.onScheduleChanged,
  });

  @override
  State<DealScheduleWidget> createState() => _DealScheduleWidgetState();
}

class _DealScheduleWidgetState extends State<DealScheduleWidget> {
  bool _isScheduled = false;
  ScheduleType _scheduleType = ScheduleType.dateRange;
  DateTime? _startDate;
  DateTime? _endDate;
  DayOfWeek? _selectedDay;
  final Set<DayOfWeek> _selectedDays = <DayOfWeek>{};
  bool _isRecurring = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialSchedule != null && widget.initialSchedule!.isScheduled) {
      _isScheduled = true;
      _scheduleType = widget.initialSchedule!.type;
      _startDate = widget.initialSchedule!.startDate;
      _endDate = widget.initialSchedule!.endDate;
      _selectedDay = widget.initialSchedule!.dayOfWeek;
      _selectedDays.addAll(
        widget.initialSchedule!.dayOfWeeks.isNotEmpty
            ? widget.initialSchedule!.dayOfWeeks
            : (widget.initialSchedule!.dayOfWeek == null
                ? const <DayOfWeek>[]
                : [widget.initialSchedule!.dayOfWeek!]),
      );
      _isRecurring = widget.initialSchedule!.isRecurring;
    }
  }

  void _notifyChange() {
    if (!_isScheduled) {
      widget.onScheduleChanged(null);
      return;
    }

    final schedule = DealSchedule(
      type: _scheduleType,
      startDate: _startDate,
      endDate: _endDate,
        dayOfWeek: _selectedDays.length == 1
          ? _selectedDays.first
          : _selectedDay,
        dayOfWeeks: _selectedDays.toList(),
      isRecurring: _isRecurring,
    );
    widget.onScheduleChanged(schedule);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Row(
          children: [
            const Text(
              'Schedule Deal',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const Spacer(),
            Switch(
              value: _isScheduled,
              onChanged: (value) {
                setState(() {
                  _isScheduled = value;
                  _notifyChange();
                });
              },
            ),
          ],
        ),
        if (_isScheduled) ...[
          const SizedBox(height: 16),
          // Schedule type selector
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    setState(() {
                      _scheduleType = ScheduleType.dateRange;
                      _selectedDay = null;
                      _selectedDays.clear();
                      _isRecurring = false;
                      _notifyChange();
                    });
                  },
                  style: OutlinedButton.styleFrom(
                    backgroundColor: _scheduleType == ScheduleType.dateRange
                        ? Colors.blue.shade50
                        : null,
                    foregroundColor: _scheduleType == ScheduleType.dateRange
                        ? Colors.blue
                        : Colors.grey,
                  ),
                  child: const Text('Date Range'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    setState(() {
                      _scheduleType = ScheduleType.dayOfWeek;
                      _startDate = null;
                      _endDate = null;
                      _notifyChange();
                    });
                  },
                  style: OutlinedButton.styleFrom(
                    backgroundColor: _scheduleType == ScheduleType.dayOfWeek
                        ? Colors.blue.shade50
                        : null,
                    foregroundColor: _scheduleType == ScheduleType.dayOfWeek
                        ? Colors.blue
                        : Colors.grey,
                  ),
                  child: const Text('Day of Week'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Date Range Picker
          if (_scheduleType == ScheduleType.dateRange) ...[
            _buildDateRangeSection(),
          ],

          // Day of Week Selector
          if (_scheduleType == ScheduleType.dayOfWeek) ...[
            _buildDayOfWeekSection(),
          ],
        ],
      ],
    );
  }

  Widget _buildDateRangeSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Select Date Range',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 12),
        InkWell(
          onTap: () => _showDateRangePicker(),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(Icons.date_range, color: Colors.blue),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _startDate != null && _endDate != null
                            ? '${_formatDate(_startDate!)} - ${_formatDate(_endDate!)}'
                            : 'Tap to select dates',
                        style: TextStyle(
                          color: _startDate != null
                              ? Colors.black87
                              : Colors.grey,
                        ),
                      ),
                      if (_startDate != null && _endDate != null)
                        Text(
                          '${_endDate!.difference(_startDate!).inDays + 1} days',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                    ],
                  ),
                ),
                const Icon(Icons.arrow_forward_ios, size: 16),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDayOfWeekSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Select Day of Week',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: DayOfWeek.values.map((day) {
            return FilterChip(
              label: Text(day.displayName),
              selected: _selectedDays.contains(day),
              onSelected: (selected) {
                setState(() {
                  if (selected) {
                    _selectedDays.add(day);
                  } else {
                    _selectedDays.remove(day);
                  }
                  _selectedDay = _selectedDays.length == 1
                      ? _selectedDays.first
                      : null;
                  _notifyChange();
                });
              },
            );
          }).toList(),
        ),
        if (_selectedDays.isNotEmpty) ...[
          const SizedBox(height: 16),
          CheckboxListTile(
            title: const Text('Recurring'),
            subtitle: Text(
              _isRecurring
                  ? 'Deal available every selected day'
                  : 'Deal available only on the selected day(s)',
            ),
            value: _isRecurring,
            onChanged: (value) {
              setState(() {
                _isRecurring = value ?? false;
                _notifyChange();
              });
            },
          ),
        ],
      ],
    );
  }

  void _showDateRangePicker() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DateRangePickerDialog(
        initialStartDate: _startDate,
        initialEndDate: _endDate,
        onSave: (startDate, endDate) {
          setState(() {
            _startDate = startDate;
            _endDate = endDate;
            _notifyChange();
          });
        },
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day} ${_getMonthName(date.month)} ${date.year}';
  }

  String _getMonthName(int month) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return months[month - 1];
  }
}

/// Custom date range picker dialog with scrollable wheels
class DateRangePickerDialog extends StatefulWidget {
  final DateTime? initialStartDate;
  final DateTime? initialEndDate;
  final Function(DateTime startDate, DateTime endDate) onSave;

  const DateRangePickerDialog({
    super.key,
    this.initialStartDate,
    this.initialEndDate,
    required this.onSave,
  });

  @override
  State<DateRangePickerDialog> createState() => _DateRangePickerDialogState();
}

class _DateRangePickerDialogState extends State<DateRangePickerDialog> {
  late DateTime _startDate;
  late DateTime _endDate;
  bool _selectingStartDate = true;

  @override
  void initState() {
    super.initState();
    // Normalize to midnight for date comparison
    final now = DateTime(
      DateTime.now().year,
      DateTime.now().month,
      DateTime.now().day,
    );

    _startDate = widget.initialStartDate != null
        ? DateTime(
            widget.initialStartDate!.year,
            widget.initialStartDate!.month,
            widget.initialStartDate!.day,
          )
        : now;

    // Ensure end date is at least 1 day after start date
    final minimumEndDate = DateTime(
      _startDate.year,
      _startDate.month,
      _startDate.day + 1,
    );

    if (widget.initialEndDate != null) {
      final normalizedEndDate = DateTime(
        widget.initialEndDate!.year,
        widget.initialEndDate!.month,
        widget.initialEndDate!.day,
      );
      if (normalizedEndDate.isAfter(minimumEndDate) ||
          normalizedEndDate.isAtSameMomentAs(minimumEndDate)) {
        _endDate = normalizedEndDate;
      } else {
        _endDate = minimumEndDate;
      }
    } else {
      _endDate = minimumEndDate;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(20),
              ),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Select Date Range',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _buildDateButton(
                        'Start Date',
                        _startDate,
                        _selectingStartDate,
                        () {
                          setState(() => _selectingStartDate = true);
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildDateButton(
                        'End Date',
                        _endDate,
                        !_selectingStartDate,
                        () {
                          setState(() => _selectingStartDate = false);
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Date Picker
          Expanded(
            child: CupertinoDatePicker(
              mode: CupertinoDatePickerMode.date,
              initialDateTime: _selectingStartDate ? _startDate : _endDate,
              minimumDate: _selectingStartDate
                  ? DateTime(
                      DateTime.now().year,
                      DateTime.now().month,
                      DateTime.now().day,
                    )
                  : DateTime(
                      _startDate.year,
                      _startDate.month,
                      _startDate.day + 1,
                    ),
              onDateTimeChanged: (DateTime newDate) {
                setState(() {
                  if (_selectingStartDate) {
                    _startDate = newDate;
                    // Ensure end date is after start date
                    final minimumEnd = DateTime(
                      _startDate.year,
                      _startDate.month,
                      _startDate.day + 1,
                    );
                    if (_endDate.isBefore(minimumEnd)) {
                      _endDate = minimumEnd;
                    }
                  } else {
                    _endDate = newDate;
                  }
                });
              },
            ),
          ),

          // Save Button
          Container(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 70),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.shade300,
                  blurRadius: 4,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  widget.onSave(_startDate, _endDate);
                  Navigator.pop(context);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  elevation: 0,
                ),
                child: const Text(
                  'Save Date Range',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDateButton(
    String label,
    DateTime date,
    bool isSelected,
    VoidCallback onTap,
  ) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? Colors.blue : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? Colors.blue : Colors.grey.shade300,
            width: 2,
          ),
        ),
        child: Column(
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: isSelected ? Colors.white : Colors.grey,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${date.day}',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: isSelected ? Colors.white : Colors.black,
              ),
            ),
            Text(
              '${_getMonthName(date.month)} ${date.year}',
              style: TextStyle(
                fontSize: 12,
                color: isSelected ? Colors.white : Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getMonthName(int month) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return months[month - 1];
  }
}
