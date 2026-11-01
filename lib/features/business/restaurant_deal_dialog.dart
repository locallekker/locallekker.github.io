import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:logger/logger.dart';

import '../../core/constants/deal_categories.dart';
import '../../models/deal_schedule.dart';
import '../../models/discount.dart';
import '../../models/restaurant_deal.dart';
import '../../services/discount_service.dart';
import '../../services/supabase_service.dart';
import '../../widgets/restaurant_deal_badge.dart';

/// Create/edit dialog for restaurant deals (partners and admins).
/// Saves the deal itself and returns `true` when saved.
class RestaurantDealDialog extends StatefulWidget {
  final String trustedPartnerId;
  final Discount? existing;
  final String? lockedDealCategory;

  const RestaurantDealDialog({
    super.key,
    required this.trustedPartnerId,
    this.existing,
    this.lockedDealCategory,
  });

  @override
  State<RestaurantDealDialog> createState() => _RestaurantDealDialogState();
}

class _Field {
  final String key;
  final String label;
  final bool money;
  final bool integer;
  final bool multiline;
  final String? hint;

  const _Field(
    this.key,
    this.label, {
    this.money = false,
    this.integer = false,
    this.multiline = false,
    this.hint,
  });

  bool get numeric => money || integer;
}

class _RestaurantDealDialogState extends State<RestaurantDealDialog> {
  static const Color _kBrandGreen = Color(0xFF3C8C44);
  static const List<int> _graceOptions = [0, 30, 60, 90, 120, 180, 240];

  static const Map<RestaurantDealType, List<_Field>> _fields = {
    RestaurantDealType.foodPercent: [
      _Field('percentage', '% off food', integer: true),
      _Field('excluded_label', 'Not included', hint: 'e.g. drinks'),
    ],
    RestaurantDealType.bogo: [
      _Field('item_name', 'Item', hint: 'e.g. burgers'),
      _Field('item_price', 'Price of one item', money: true),
      _Field('buy_qty', 'Buy how many', integer: true),
      _Field('free_qty', 'Get how many free', integer: true),
      _Field('max_free', 'Max free per bill (0 = no limit)', integer: true),
    ],
    RestaurantDealType.setMenu: [
      _Field('menu_name', 'Set menu name', hint: 'e.g. 3-course lunch'),
      _Field('set_price', 'Set menu price', money: true),
      _Field('normal_price', 'Normal price if ordered separately', money: true),
      _Field('menu_details', 'What\'s included', multiline: true),
    ],
    RestaurantDealType.kidsFree: [
      _Field('kids_per_adult', 'Free kids per paying adult', integer: true),
      _Field('kid_meal_value', 'Kids meal price', money: true),
      _Field('max_free', 'Max free per bill (0 = no limit)', integer: true),
    ],
    RestaurantDealType.happyHour: [
      _Field('percentage', '% off', integer: true),
      _Field('item_label', 'Which items', hint: 'e.g. cocktails and draught'),
    ],
    RestaurantDealType.freeItem: [
      _Field('free_item_name', 'Free item', hint: 'e.g. dessert'),
      _Field('free_item_value', 'Free item price', money: true),
      _Field('qualifying_label', 'With every', hint: 'e.g. main meal'),
      _Field('free_per_qualifying', 'Free items per qualifying item', integer: true),
      _Field('max_free', 'Max free per bill (0 = no limit)', integer: true),
    ],
    RestaurantDealType.group: [
      _Field('min_party_size', 'Minimum people at the table', integer: true),
      _Field('percentage', '% off the bill', integer: true),
    ],
    RestaurantDealType.birthday: [
      _Field('free_item_name', 'Birthday treat', hint: 'e.g. dessert and a drink'),
      _Field('free_item_value', 'Treat value', money: true),
      _Field('percentage', '% off the bill', integer: true),
      _Field('window_days', 'Days before/after birthday', integer: true),
    ],
  };

  static const Map<String, String> _defaults = {
    'buy_qty': '1',
    'free_qty': '1',
    'max_free': '0',
    'kids_per_adult': '1',
    'free_per_qualifying': '1',
    'min_party_size': '6',
    'window_days': '3',
  };

  final Logger _logger = Logger();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final Map<String, TextEditingController> _controllers = {};

  late RestaurantDealType _type;
  String _birthdayReward = 'free_item';
  bool _bogoPriceAtCheckout = false;
  final Set<DayOfWeek> _days = {};
  final List<DealTimeSlot> _slots = [];
  int _graceMinutes = DealSchedule.defaultClaimGraceMinutes;
  DateTime? _startDate;
  DateTime? _endDate;
  late String _category;

  String? _existingImageUrl;
  XFile? _pickedImage;
  Uint8List? _pickedBytes;
  bool _saving = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _type = existing?.restaurantType ?? RestaurantDealType.foodPercent;
    _titleController.text = existing?.name ?? '';
    _descriptionController.text = existing?.description ?? '';
    _existingImageUrl = existing?.imageUrl;
    _category =
        widget.lockedDealCategory ??
        (existing != null && kDealCategories.contains(existing.dealCategory)
            ? existing.dealCategory
            : kLocalEatsCategory);

    final data = existing?.customData ?? const <String, dynamic>{};
    _bogoPriceAtCheckout = data['pricing_mode'] == 'checkout';
    _birthdayReward = data['reward'] == 'percent' ? 'percent' : 'free_item';
    for (final fields in _fields.values) {
      for (final field in fields) {
        _controllers.putIfAbsent(field.key, () {
          final value = data[field.key];
          String text;
          if (value is num) {
            text = field.money
                ? value.toStringAsFixed(2)
                : (value == value.roundToDouble()
                      ? value.toInt().toString()
                      : value.toString());
          } else {
            text = value?.toString() ?? _defaults[field.key] ?? '';
          }
          return TextEditingController(text: text);
        });
      }
    }

    final scheduleData = existing?.scheduleData;
    if (scheduleData != null && scheduleData['type'] == 'weekly') {
      final schedule = DealSchedule.fromJson(scheduleData);
      _days.addAll(schedule.dayOfWeeks);
      _slots.addAll(schedule.timeSlots);
      _graceMinutes = schedule.timeSlots.isEmpty
          ? DealSchedule.defaultClaimGraceMinutes
          : schedule.claimGraceMinutes;
      _startDate = schedule.startDate;
      _endDate = schedule.endDate;
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  List<_Field> get _visibleFields {
    final fields = _fields[_type]!;
    if (_type == RestaurantDealType.bogo && _bogoPriceAtCheckout) {
      return fields.where((field) => field.key != 'item_price').toList();
    }
    if (_type != RestaurantDealType.birthday) return fields;
    return fields.where((f) {
      if (f.key == 'percentage') return _birthdayReward == 'percent';
      if (f.key == 'free_item_name' || f.key == 'free_item_value') {
        return _birthdayReward == 'free_item';
      }
      return true;
    }).toList();
  }

  Map<String, dynamic> _customData() {
    final data = <String, dynamic>{};
    for (final field in _visibleFields) {
      final raw = _controllers[field.key]!.text.trim();
      if (field.numeric) {
        final value = double.tryParse(raw.replaceAll(',', '.'));
        if (value != null) {
          data[field.key] = field.integer ? value.floor() : (value * 100).round() / 100;
        }
      } else if (raw.isNotEmpty) {
        data[field.key] = raw;
      }
    }
    if (_type == RestaurantDealType.birthday) data['reward'] = _birthdayReward;
    if (_type == RestaurantDealType.bogo) {
      data['pricing_mode'] = _bogoPriceAtCheckout ? 'checkout' : 'fixed';
    }
    return data;
  }

  DealSchedule _schedule() => DealSchedule(
    type: ScheduleType.weekly,
    startDate: _startDate,
    endDate: _endDate,
    dayOfWeeks: DayOfWeek.values.where(_days.contains).toList(),
    timeSlots: [..._slots]..sort((a, b) => a.startMinutes.compareTo(b.startMinutes)),
    claimGraceMinutes: _slots.isEmpty ? 0 : _graceMinutes,
  );

  Future<void> _pickImage() async {
    try {
      final image = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (image == null) return;
      final bytes = await image.readAsBytes();
      setState(() {
        _pickedImage = image;
        _pickedBytes = bytes;
      });
    } catch (e) {
      _showMessage('Failed to pick image: $e');
    }
  }

  Future<String> _uploadImage() async {
    final storage = SupabaseService.instance.client.storage.from(
      'business-bills',
    );
    final fileName =
        '${DateTime.now().millisecondsSinceEpoch}_${_pickedImage!.name}';
    final userId = SupabaseService.instance.getCurrentUser()?.id;

    Future<String> uploadTo(String path) async {
      await storage.uploadBinary(path, _pickedBytes!);
      return storage.getPublicUrl(path);
    }

    try {
      return await uploadTo('deal_images/${widget.trustedPartnerId}/$fileName');
    } catch (e) {
      if (userId == null || userId == widget.trustedPartnerId) rethrow;
      _logger.w('Partner-folder upload failed ($e), retrying own folder');
      return uploadTo('deal_images/$userId/$fileName');
    }
  }

  Future<void> _addSlot() async {
    final start = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 16, minute: 0),
      helpText: 'Starts at',
    );
    if (start == null || !mounted) return;
    final end = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: (start.hour + 2).clamp(0, 23), minute: start.minute),
      helpText: 'Ends at',
    );
    if (end == null) return;
    final startMinutes = start.hour * 60 + start.minute;
    final endMinutes = end.hour * 60 + end.minute;
    if (endMinutes <= startMinutes) {
      _showMessage('The end time must be after the start time (same day).');
      return;
    }
    setState(
      () => _slots.add(
        DealTimeSlot(startMinutes: startMinutes, endMinutes: endMinutes),
      ),
    );
  }

  Future<void> _pickDate({required bool start}) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: (start ? _startDate : _endDate) ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 3),
    );
    if (picked == null) return;
    setState(() => start ? _startDate = picked : _endDate = picked);
  }

  Future<void> _save() async {
    if (_saving) return;
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      _showMessage('Please enter a deal title.');
      return;
    }
    final schedule = _schedule();
    final customData = _customData();
    final config = RestaurantDealConfig(_type, customData);
    final error = config.validate(schedule: schedule);
    if (error != null) {
      _showMessage(error);
      return;
    }
    if (_startDate != null && _endDate != null && _endDate!.isBefore(_startDate!)) {
      _showMessage('The end date must be after the start date.');
      return;
    }

    setState(() => _saving = true);
    try {
      var imageUrl = _existingImageUrl;
      if (_pickedBytes != null) imageUrl = await _uploadImage();

      final service = DiscountService();
      final headline = config.headline;
      final itemName = headline.length > 120 ? headline.substring(0, 120) : headline;
      final percentage = config.percentage;
      final description = _descriptionController.text.trim();

      if (_isEdit) {
        await service.updateDiscount(
          widget.existing!.id,
          name: title,
          description: description,
          itemName: itemName,
          itemPrice: 0,
          percentage: percentage,
          dealType: _type.key,
          customData: customData,
          scheduleData: schedule.toJson(),
          dealCategory: _category,
          imageUrl: imageUrl,
          updateImageUrl: true,
        );
      } else {
        await service.createDiscount(
          trustedPartnerId: widget.trustedPartnerId,
          name: title,
          description: description,
          itemName: itemName,
          itemPrice: 0,
          percentage: percentage,
          dealType: _type.key,
          customData: customData,
          scheduleData: schedule.toJson(),
          imageUrl: imageUrl,
          dealCategory: _category,
        );
      }
      DiscountService.invalidateActiveDealsCache();
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      _logger.e('Failed to save restaurant deal: $e');
      _showMessage('Failed to save deal: $e');
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final preview = RestaurantDealConfig(_type, _customData());
    return AlertDialog(
      title: Text(_isEdit ? 'Edit Restaurant Deal' : 'New Restaurant Deal'),
      contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButtonFormField<RestaurantDealType>(
                initialValue: _type,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Deal type',
                  border: OutlineInputBorder(),
                ),
                items: RestaurantDealType.values
                    .map(
                      (t) => DropdownMenuItem(
                        value: t,
                        child: Row(
                          children: [
                            Icon(RestaurantDealBadge.iconFor(t), size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '${t.label} – ${t.helpText}',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                    .toList(),
                onChanged: _saving
                    ? null
                    : (t) => setState(() => _type = t ?? _type),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _titleController,
                maxLength: 80,
                decoration: const InputDecoration(
                  labelText: 'Deal title',
                  hintText: 'e.g. Tuesday Burger Special',
                  border: OutlineInputBorder(),
                ),
              ),
              TextField(
                controller: _descriptionController,
                maxLength: 300,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Short description (optional)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              if (_type == RestaurantDealType.bogo) ...[
                CheckboxListTile(
                  title: const Text('Fixed price'),
                  subtitle: const Text('All qualifying items have the same price.'),
                  contentPadding: EdgeInsets.zero,
                  value: !_bogoPriceAtCheckout,
                  onChanged: _saving
                      ? null
                      : (_) => setState(() => _bogoPriceAtCheckout = false),
                ),
                CheckboxListTile(
                  title: const Text('Price entered at checkout'),
                  subtitle: const Text(
                    'The partner enters each qualifying item price after scanning '
                    'the member QR. The cheapest qualifying items are free. '
                    'Redeem and pay in store.',
                  ),
                  contentPadding: EdgeInsets.zero,
                  value: _bogoPriceAtCheckout,
                  onChanged: _saving
                      ? null
                      : (_) => setState(() => _bogoPriceAtCheckout = true),
                ),
                const SizedBox(height: 12),
              ],
              if (_type == RestaurantDealType.birthday) ...[
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'free_item', label: Text('Free treat')),
                    ButtonSegment(value: 'percent', label: Text('% off bill')),
                  ],
                  selected: {_birthdayReward},
                  onSelectionChanged: (s) => setState(() => _birthdayReward = s.first),
                ),
                const SizedBox(height: 12),
              ],
              ..._visibleFields.map(_buildField),
              _preview(preview),
              const SizedBox(height: 16),
              _scheduleSection(),
              const SizedBox(height: 16),
              InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Deal category',
                  border: OutlineInputBorder(),
                ),
                child: widget.lockedDealCategory != null
                    ? Text(widget.lockedDealCategory!)
                    : DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _category,
                          isDense: true,
                          isExpanded: true,
                          items: kDealCategories
                              .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                              .toList(),
                          onChanged: (c) => setState(() => _category = c ?? _category),
                        ),
                      ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _saving ? null : _pickImage,
                icon: const Icon(Icons.image),
                label: Text(
                  _pickedImage != null || (_existingImageUrl?.isNotEmpty ?? false)
                      ? 'Change image'
                      : 'Add image (optional)',
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _saving ? null : _save,
          style: ElevatedButton.styleFrom(
            backgroundColor: _kBrandGreen,
            foregroundColor: Colors.white,
          ),
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text('Save'),
        ),
      ],
    );
  }

  Widget _buildField(_Field field) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: _controllers[field.key],
        onChanged: (_) => setState(() {}),
        maxLines: field.multiline ? 3 : 1,
        keyboardType: field.money
            ? const TextInputType.numberWithOptions(decimal: true)
            : field.integer
            ? TextInputType.number
            : TextInputType.text,
        inputFormatters: field.money
            ? [FilteringTextInputFormatter.allow(RegExp(r'^\d{0,6}([.,]\d{0,2})?'))]
            : field.integer
            ? [FilteringTextInputFormatter.digitsOnly]
            : null,
        decoration: InputDecoration(
          labelText: field.label,
          hintText: field.hint,
          prefixText: field.money ? 'R ' : null,
          suffixText: field.key == 'percentage' ? '%' : null,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }

  Widget _preview(RestaurantDealConfig config) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Members will see:',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
          ),
          const SizedBox(height: 6),
          RestaurantDealBadge(
            dealType: _type.key,
            customData: config.data,
            scheduleData: _schedule().toJson(),
          ),
        ],
      ),
    );
  }

  static String _graceLabel(int minutes) {
    if (minutes == 0) return 'No extra time';
    if (minutes < 60) return '$minutes minutes';
    final hours = minutes ~/ 60;
    final rest = minutes % 60;
    final h = hours == 1 ? '1 hour' : '$hours hours';
    return rest == 0 ? h : '$h $rest min';
  }

  Widget _scheduleSection() {
    String fmt(DateTime? d) => d == null ? 'Any' : '${d.day}/${d.month}/${d.year}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'When is this deal available?',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
        ),
        const SizedBox(height: 4),
        Text(
          'No days selected = every day.',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: DayOfWeek.values
              .map(
                (d) => FilterChip(
                  label: Text(d.shortName),
                  selected: _days.contains(d),
                  onSelected: (on) =>
                      setState(() => on ? _days.add(d) : _days.remove(d)),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Text(
                _type == RestaurantDealType.happyHour
                    ? 'Happy hour times (required)'
                    : 'Times (optional – all day if none)',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            TextButton.icon(
              onPressed: _saving ? null : _addSlot,
              icon: const Icon(Icons.add_alarm),
              label: const Text('Add time'),
            ),
          ],
        ),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: _slots
              .map(
                (s) => InputChip(
                  label: Text(s.label),
                  onDeleted: () => setState(() => _slots.remove(s)),
                ),
              )
              .toList(),
        ),
        if (_slots.isNotEmpty) ...[
          const SizedBox(height: 8),
          DropdownButtonFormField<int>(
            initialValue: _graceOptions.contains(_graceMinutes) ? _graceMinutes : 120,
            decoration: const InputDecoration(
              labelText: 'Members can still claim after the time ends for',
              helperText: 'Bills are usually paid after ordering',
              border: OutlineInputBorder(),
            ),
            items: _graceOptions
                .map(
                  (m) => DropdownMenuItem(
                    value: m,
                    child: Text(_graceLabel(m)),
                  ),
                )
                .toList(),
            onChanged: (m) => setState(() => _graceMinutes = m ?? _graceMinutes),
          ),
        ],
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => _pickDate(start: true),
                onLongPress: () => setState(() => _startDate = null),
                child: Text('From: ${fmt(_startDate)}'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton(
                onPressed: () => _pickDate(start: false),
                onLongPress: () => setState(() => _endDate = null),
                child: Text('Until: ${fmt(_endDate)}'),
              ),
            ),
          ],
        ),
        if (_startDate != null || _endDate != null)
          TextButton(
            onPressed: () => setState(() {
              _startDate = null;
              _endDate = null;
            }),
            child: const Text('Clear dates'),
          ),
        Text(
          'Times are South African time.',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
        ),
      ],
    );
  }
}
