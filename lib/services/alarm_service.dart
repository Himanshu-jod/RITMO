import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import '../models/routine_activity.dart';
import 'database_service.dart';

@pragma('vm:entry-point')
void ritmoNotificationBackgroundResponse(NotificationResponse response) {
  WidgetsFlutterBinding.ensureInitialized();
  unawaited(AlarmService.handleNotificationAction(response));
}

class AlarmService {
  AlarmService._();
  static final AlarmService instance = AlarmService._();
  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> initialize({bool requestPermissions = true}) async {
    if (_initialized) return;
    tzdata.initializeTimeZones();
    try {
      final zone = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(zone.identifier));
    } catch (_) {}
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(
      const InitializationSettings(android: android),
      onDidReceiveNotificationResponse: handleNotificationAction,
      onDidReceiveBackgroundNotificationResponse: ritmoNotificationBackgroundResponse,
    );
    if (requestPermissions) {
      final androidPlugin = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.requestNotificationsPermission();
      await androidPlugin?.requestExactAlarmsPermission();
    }
    _initialized = true;
  }

  static Future<void> handleNotificationAction(NotificationResponse response) async {
    await AlarmService.instance.initialize(requestPermissions: false);
    final raw = response.payload;
    if (raw == null || raw.isEmpty) return;
    final parts = raw.split('|');
    final activityId = int.tryParse(parts.first);
    if (activityId == null) return;
    final action = response.actionId ?? 'open';
    final now = DateTime.now();
    if (action == 'done') {
      await DatabaseService.instance.setCompletion(activityId, now, 'completed');
      return;
    }
    if (action == 'dismiss') return;
    final minutes = switch (action) {
      'snooze_10' => 10,
      'snooze_15' => 15,
      _ => 5,
    };
    if (action.startsWith('snooze_')) {
      await AlarmService.instance._scheduleSnooze(
        id: 700000 + activityId * 10 + minutes,
        title: parts.length > 1 ? parts.sublist(1).join('|') : 'Your activity',
        when: tz.TZDateTime.from(now.add(Duration(minutes: minutes)), tz.local),
        activityId: activityId,
      );
    }
  }

  Future<void> schedule(RoutineActivity activity) async {
    await cancel(activity.id);
    if (!activity.isActive || !activity.alarmEnabled) return;
    final now = tz.TZDateTime.now(tz.local);
    if (activity.repeatDays.isEmpty) {
      var scheduled = tz.TZDateTime(tz.local, now.year, now.month, now.day, activity.hour, activity.minute);
      if (!scheduled.isAfter(now)) scheduled = scheduled.add(const Duration(days: 1));
      await _scheduleOne(activity.id, activity.title, scheduled, activity.alarmMode);
      return;
    }
    for (final weekday in activity.repeatDays) {
      final scheduled = _nextWeekdayTime(now, weekday, activity.hour, activity.minute);
      await _scheduleOne(activity.id * 10 + weekday, activity.title, scheduled, activity.alarmMode, activityId: activity.id, repeatWeekly: true);
    }
  }

  tz.TZDateTime _nextWeekdayTime(tz.TZDateTime now, int weekday, int hour, int minute) {
    var days = (weekday - now.weekday) % 7;
    var candidate = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute).add(Duration(days: days));
    if (!candidate.isAfter(now)) candidate = candidate.add(const Duration(days: 7));
    return candidate;
  }

  AndroidNotificationDetails _details(String mode) => AndroidNotificationDetails(
    'ritmo_alarms', 'RITMO Alarms',
    channelDescription: 'Scheduled routine alarms',
    importance: Importance.max,
    priority: Priority.max,
    category: AndroidNotificationCategory.alarm,
    fullScreenIntent: mode == 'full_screen',
    ongoing: false,
    autoCancel: true,
    playSound: true,
    enableVibration: true,
    audioAttributesUsage: AudioAttributesUsage.alarm,
    actions: const [
      AndroidNotificationAction('snooze_5', 'Snooze 5m', showsUserInterface: false, cancelNotification: true),
      AndroidNotificationAction('snooze_10', 'Snooze 10m', showsUserInterface: false, cancelNotification: true),
      AndroidNotificationAction('snooze_15', 'Snooze 15m', showsUserInterface: false, cancelNotification: true),
    ],
  );

  Future<void> _scheduleOne(int id, String title, tz.TZDateTime when, String mode,
      {int? activityId, bool repeatWeekly = false}) async {
    final actualActivityId = activityId ?? id;
    await _plugin.zonedSchedule(
      id, 'Time for $title', 'Your scheduled activity is starting now.',
      when, NotificationDetails(android: _details(mode)),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      matchDateTimeComponents: repeatWeekly ? DateTimeComponents.dayOfWeekAndTime : null,
      payload: '$actualActivityId|$title',
    );
  }

  Future<void> _scheduleSnooze({required int id, required String title, required tz.TZDateTime when, required int activityId}) async {
    await _plugin.zonedSchedule(
      id, 'Snoozed: $title', 'Your activity reminder is ringing again.',
      when, NotificationDetails(android: _details('full_screen')),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      payload: '$activityId|$title',
    );
  }

  Future<void> cancel(int id) async {
    await _plugin.cancel(id);
    for (var day = 1; day <= 7; day++) {
      await _plugin.cancel(id * 10 + day);
    }
    for (final minutes in [5, 10, 15]) {
      await _plugin.cancel(700000 + id * 10 + minutes);
    }
  }
}
