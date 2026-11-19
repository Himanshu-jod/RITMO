import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import '../models/routine_activity.dart';

class DatabaseService {
  DatabaseService._();
  static final DatabaseService instance = DatabaseService._();
  Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    final dbPath = await getDatabasesPath();
    _database = await openDatabase(
      p.join(dbPath, 'ritmo.db'),
      version: 2,
      onCreate: (db, version) async => _createSchema(db),
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) await _createV2Tables(db);
      },
    );
    return _database!;
  }

  Future<void> _createSchema(Database db) async {
    await db.execute('''CREATE TABLE activities (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      title TEXT NOT NULL,
      category TEXT NOT NULL,
      hour INTEGER NOT NULL,
      minute INTEGER NOT NULL,
      duration_minutes INTEGER NOT NULL,
      repeat_days TEXT NOT NULL DEFAULT '',
      alarm_enabled INTEGER NOT NULL DEFAULT 1,
      alarm_mode TEXT NOT NULL DEFAULT 'full_screen',
      notes TEXT NOT NULL DEFAULT '',
      is_active INTEGER NOT NULL DEFAULT 1
    )''');
    await db.execute('''CREATE TABLE activity_history (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      activity_id INTEGER NOT NULL,
      occurrence_date TEXT NOT NULL,
      status TEXT NOT NULL,
      completed_at TEXT,
      UNIQUE(activity_id, occurrence_date)
    )''');
    await _createV2Tables(db);
  }

  Future<void> _createV2Tables(DatabaseExecutor db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS focus_sessions (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      started_at TEXT NOT NULL,
      ended_at TEXT,
      planned_seconds INTEGER NOT NULL,
      actual_seconds INTEGER NOT NULL DEFAULT 0,
      status TEXT NOT NULL
    )''');
    await db.execute('''CREATE INDEX IF NOT EXISTS idx_history_date ON activity_history(occurrence_date)''');
  }

  String dateKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  Future<List<RoutineActivity>> getActivities() async {
    final rows = await (await database).query('activities', orderBy: 'hour ASC, minute ASC');
    return rows.map(RoutineActivity.fromMap).toList();
  }

  Future<int> saveActivity(RoutineActivity activity) async {
    final db = await database;
    if (activity.id == 0) return db.insert('activities', activity.toMap()..remove('id'));
    await db.update('activities', activity.toMap(), where: 'id = ?', whereArgs: [activity.id]);
    return activity.id;
  }

  Future<void> deleteActivity(int id) async {
    final db = await database;
    await db.delete('activities', where: 'id = ?', whereArgs: [id]);
    await db.delete('activity_history', where: 'activity_id = ?', whereArgs: [id]);
  }

  Future<void> setCompletion(int activityId, DateTime date, String status) async {
    final db = await database;
    await db.insert('activity_history', {
      'activity_id': activityId,
      'occurrence_date': dateKey(date),
      'status': status,
      'completed_at': status == 'completed' ? DateTime.now().toIso8601String() : null,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<Map<String, String>> getTodayStatuses(DateTime date) async {
    final rows = await (await database).query('activity_history', where: 'occurrence_date = ?', whereArgs: [dateKey(date)]);
    return {for (final row in rows) '${row['activity_id']}': row['status'] as String};
  }

  Future<List<Map<String, Object?>>> getHistory(DateTime start, DateTime end) async {
    return (await database).query('activity_history',
      where: 'occurrence_date >= ? AND occurrence_date <= ?',
      whereArgs: [dateKey(start), dateKey(end)], orderBy: 'occurrence_date ASC');
  }

  Future<void> markOverdueAsMissed(List<RoutineActivity> activities, DateTime now) async {
    final db = await database;
    final today = DateTime(now.year, now.month, now.day);
    for (final activity in activities) {
      if (!activity.isActive || !activity.repeatDays.contains(today.weekday)) continue;
      final due = DateTime(today.year, today.month, today.day, activity.hour, activity.minute)
          .add(Duration(minutes: activity.durationMinutes));
      if (now.isBefore(due)) continue;
      final existing = await db.query('activity_history',
          where: 'activity_id = ? AND occurrence_date = ?',
          whereArgs: [activity.id, dateKey(today)], limit: 1);
      if (existing.isEmpty || existing.first['status'] == 'pending') {
        await setCompletion(activity.id, today, 'missed');
      }
    }
  }

  Future<List<Map<String, Object?>>> getMissedActivities(DateTime date) async {
    final db = await database;
    return db.rawQuery('''SELECT a.*, h.occurrence_date, h.status
      FROM activity_history h JOIN activities a ON a.id = h.activity_id
      WHERE h.occurrence_date = ? AND h.status = 'missed'
      ORDER BY a.hour, a.minute''', [dateKey(date)]);
  }

  Future<int> startFocusSession(int plannedSeconds) async {
    final db = await database;
    return db.insert('focus_sessions', {
      'started_at': DateTime.now().toIso8601String(),
      'planned_seconds': plannedSeconds,
      'actual_seconds': 0,
      'status': 'running',
    });
  }

  Future<void> finishFocusSession(int id, int actualSeconds, String status) async {
    final db = await database;
    await db.update('focus_sessions', {
      'ended_at': DateTime.now().toIso8601String(),
      'actual_seconds': actualSeconds,
      'status': status,
    }, where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Map<String, Object?>>> getFocusSessions(DateTime start, DateTime end) async {
    return (await database).query('focus_sessions',
      where: 'started_at >= ? AND started_at <= ?',
      whereArgs: [start.toIso8601String(), DateTime(end.year, end.month, end.day).add(const Duration(days: 1)).toIso8601String()],
      orderBy: 'started_at DESC');
  }

  Future<Map<String, Object?>?> getActiveFocusSession() async {
    final rows = await (await database).query('focus_sessions', where: "status = 'running'", orderBy: 'id DESC', limit: 1);
    return rows.isEmpty ? null : rows.first;
  }

  Future<Map<String, Object?>> exportAll() async {
    final db = await database;
    return {
      'format': 'ritmo-backup',
      'version': 1,
      'exportedAt': DateTime.now().toIso8601String(),
      'activities': await db.query('activities'),
      'activityHistory': await db.query('activity_history'),
      'focusSessions': await db.query('focus_sessions'),
    };
  }

  Future<void> importAll(Map<String, dynamic> backup) async {
    if (backup['format'] != 'ritmo-backup' || backup['version'] != 1) {
      throw const FormatException('Unsupported RITMO backup file.');
    }
    final activities = backup['activities'];
    final history = backup['activityHistory'];
    final focus = backup['focusSessions'] ?? <dynamic>[];
    if (activities is! List || history is! List || focus is! List) {
      throw const FormatException('Backup file is incomplete or invalid.');
    }
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('activities');
      await txn.delete('activity_history');
      await txn.delete('focus_sessions');
      for (final row in activities) {
        await txn.insert('activities', Map<String, Object?>.from(row as Map));
      }
      for (final row in history) {
        await txn.insert('activity_history', Map<String, Object?>.from(row as Map));
      }
      for (final row in focus) {
        await txn.insert('focus_sessions', Map<String, Object?>.from(row as Map));
      }
    });
  }

  String encodeBackup(Map<String, Object?> backup) => const JsonEncoder.withIndent('  ').convert(backup);
}
