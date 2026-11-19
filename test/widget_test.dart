import 'package:flutter_test/flutter_test.dart';
import 'package:ritmo/models/routine_activity.dart';

void main() {
  test('activity serializes and restores repeat days', () {
    const activity = RoutineActivity(
      id: 7,
      title: 'Morning workout',
      category: 'Workout',
      hour: 6,
      minute: 0,
      durationMinutes: 45,
      repeatDays: [1, 2, 3, 4, 5],
      alarmEnabled: true,
      alarmMode: 'full_screen',
    );
    final restored = RoutineActivity.fromMap(activity.toMap());
    expect(restored.title, 'Morning workout');
    expect(restored.repeatDays, [1, 2, 3, 4, 5]);
    expect(restored.hour, 6);
  });

  test('copyWith changes only requested schedule fields', () {
    const activity = RoutineActivity(
      id: 12,
      title: 'Study',
      category: 'Study',
      hour: 9,
      minute: 30,
      durationMinutes: 60,
      repeatDays: [1, 2, 3, 4, 5],
      alarmEnabled: true,
      alarmMode: 'notification',
    );
    final recovered = activity.copyWith(hour: 11, minute: 15);
    expect(recovered.hour, 11);
    expect(recovered.minute, 15);
    expect(recovered.title, 'Study');
    expect(recovered.repeatDays, [1, 2, 3, 4, 5]);
  });
}
