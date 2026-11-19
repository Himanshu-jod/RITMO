class RoutineActivity {
  const RoutineActivity({
    required this.id,
    required this.title,
    required this.category,
    required this.hour,
    required this.minute,
    required this.durationMinutes,
    required this.repeatDays,
    required this.alarmEnabled,
    required this.alarmMode,
    this.notes = '',
    this.isActive = true,
  });

  final int id;
  final String title;
  final String category;
  final int hour;
  final int minute;
  final int durationMinutes;
  /// ISO weekdays: Monday = 1 ... Sunday = 7. Empty means one-time (today).
  final List<int> repeatDays;
  final bool alarmEnabled;
  final String alarmMode;
  final String notes;
  final bool isActive;

  DateTime timeOn(DateTime date) => DateTime(date.year, date.month, date.day, hour, minute);

  Map<String, Object?> toMap() => {
    'id': id,
    'title': title,
    'category': category,
    'hour': hour,
    'minute': minute,
    'duration_minutes': durationMinutes,
    'repeat_days': repeatDays.join(','),
    'alarm_enabled': alarmEnabled ? 1 : 0,
    'alarm_mode': alarmMode,
    'notes': notes,
    'is_active': isActive ? 1 : 0,
  };

  factory RoutineActivity.fromMap(Map<String, Object?> map) {
    final rawDays = (map['repeat_days'] as String?) ?? '';
    return RoutineActivity(
      id: map['id'] as int,
      title: map['title'] as String,
      category: map['category'] as String,
      hour: map['hour'] as int,
      minute: map['minute'] as int,
      durationMinutes: map['duration_minutes'] as int,
      repeatDays: rawDays.isEmpty ? [] : rawDays.split(',').map(int.parse).toList(),
      alarmEnabled: (map['alarm_enabled'] as int) == 1,
      alarmMode: map['alarm_mode'] as String,
      notes: (map['notes'] as String?) ?? '',
      isActive: (map['is_active'] as int) == 1,
    );
  }

  RoutineActivity copyWith({
    String? title, String? category, int? hour, int? minute,
    int? durationMinutes, List<int>? repeatDays, bool? alarmEnabled,
    String? alarmMode, String? notes, bool? isActive,
  }) => RoutineActivity(
    id: id, title: title ?? this.title, category: category ?? this.category,
    hour: hour ?? this.hour, minute: minute ?? this.minute,
    durationMinutes: durationMinutes ?? this.durationMinutes,
    repeatDays: repeatDays ?? this.repeatDays,
    alarmEnabled: alarmEnabled ?? this.alarmEnabled,
    alarmMode: alarmMode ?? this.alarmMode, notes: notes ?? this.notes,
    isActive: isActive ?? this.isActive,
  );
}
