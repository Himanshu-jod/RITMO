// ignore_for_file: deprecated_member_use
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models/routine_activity.dart';
import 'services/alarm_service.dart';
import 'services/database_service.dart';

const _bg = Color(0xFF090B12);
const _panel = Color(0xFF151925);
const _blue = Color(0xFF8BA7FF);
const _muted = Color(0xFF9299AA);
const _green = Color(0xFF72D6B0);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AlarmService.instance.initialize();
  runApp(const RitmoApp());
}

class RitmoApp extends StatelessWidget {
  const RitmoApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'RITMO', debugShowCheckedModeBanner: false,
    theme: ThemeData.dark(useMaterial3: true).copyWith(
      scaffoldBackgroundColor: _bg,
      colorScheme: const ColorScheme.dark(primary: _blue, surface: _panel),
      textTheme: ThemeData.dark().textTheme.apply(bodyColor: Colors.white, displayColor: Colors.white),
    ),
    home: const HomeScreen(),
  );
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<RoutineActivity> activities = [];
  List<Map<String, Object?>> missedToday = [];
  List<Map<String, Object?>> weeklyHistory = [];
  List<Map<String, Object?>> weeklyFocus = [];
  Map<String, String> statuses = {};
  int tab = 0;
  bool loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final data = await DatabaseService.instance.getActivities();
    await DatabaseService.instance.markOverdueAsMissed(data, DateTime.now());
    final state = await DatabaseService.instance.getTodayStatuses(DateTime.now());
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 6));
    final history = await DatabaseService.instance.getHistory(start, now);
    final focus = await DatabaseService.instance.getFocusSessions(start, now);
    final missed = await DatabaseService.instance.getMissedActivities(now);
    if (!mounted) return;
    setState(() {
      activities = data; statuses = state; weeklyHistory = history;
      weeklyFocus = focus; missedToday = missed; loading = false;
    });
    for (final activity in data) { await AlarmService.instance.schedule(activity); }
  }

  List<RoutineActivity> get todaysActivities => activities
      .where((a) => a.isActive && a.repeatDays.contains(DateTime.now().weekday))
      .toList()..sort((a,b) => (a.hour * 60 + a.minute).compareTo(b.hour * 60 + b.minute));
  int get completed => todaysActivities.where((a) => statuses['${a.id}'] == 'completed').length;
  double get progress => todaysActivities.isEmpty ? 0 : completed / todaysActivities.length;

  Future<void> _addOrEdit([RoutineActivity? activity]) async {
    final result = await showModalBottomSheet<RoutineActivity>(
      context: context, isScrollControlled: true, backgroundColor: _panel,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (_) => ActivityEditor(activity: activity),
    );
    if (result == null) return;
    final id = await DatabaseService.instance.saveActivity(result);
    final saved = result.id == 0 ? RoutineActivity(
      id: id, title: result.title, category: result.category, hour: result.hour,
      minute: result.minute, durationMinutes: result.durationMinutes,
      repeatDays: result.repeatDays, alarmEnabled: result.alarmEnabled,
      alarmMode: result.alarmMode, notes: result.notes, isActive: result.isActive,
    ) : result;
    await AlarmService.instance.schedule(saved);
    await _load();
  }

  Future<void> _complete(RoutineActivity activity, String status) async {
    await DatabaseService.instance.setCompletion(activity.id, DateTime.now(), status);
    await _load();
  }

  Future<void> _delete(RoutineActivity activity) async {
    await AlarmService.instance.cancel(activity.id);
    await DatabaseService.instance.deleteActivity(activity.id);
    await _load();
  }

  Future<void> _recover(Map<String, Object?> row) async {
    final activity = RoutineActivity.fromMap(row);
    final picked = await showTimePicker(context: context, initialTime: TimeOfDay.now(), helpText: 'Choose a new time for ${activity.title}');
    if (picked == null) return;
    final conflict = activities.where((a) => a.id != activity.id && a.isActive).any((a) {
      final aStart = a.hour * 60 + a.minute;
      final bStart = picked.hour * 60 + picked.minute;
      return (aStart - bStart).abs() < a.durationMinutes;
    });
    if (conflict && mounted) {
      final proceed = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
        backgroundColor: _panel, title: const Text('Possible schedule conflict'),
        content: const Text('This time overlaps another activity. Reschedule anyway?'),
        actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Choose another time')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Reschedule'))],
      ));
      if (proceed != true) return;
    }
    // Recovery deliberately changes the routine's scheduled time; it never silently moves other activities.
    final updated = activity.copyWith(hour: picked.hour, minute: picked.minute);
    await DatabaseService.instance.saveActivity(updated);
    await DatabaseService.instance.setCompletion(activity.id, DateTime.now(), 'rescheduled');
    await AlarmService.instance.schedule(updated);
    await _load();
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Activity rescheduled. Future repeats use this new time too.')));
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      _todayPage(), _schedulePage(), const FocusPage(), _insightsPage(), const SettingsPage(),
    ];
    return Scaffold(
      body: SafeArea(child: loading ? const Center(child: CircularProgressIndicator()) : IndexedStack(index: tab, children: pages)),
      floatingActionButton: tab <= 1 ? FloatingActionButton(
        onPressed: () => _addOrEdit(), backgroundColor: _blue, foregroundColor: _bg,
        child: const Icon(Icons.add_rounded, size: 30),
      ) : null,
      bottomNavigationBar: _GlassNav(index: tab, onChanged: (v) async {
        setState(() => tab = v);
        if (v == 0 || v == 3) await _load();
      }),
    );
  }

  Widget _todayPage() {
    final upcoming = todaysActivities.where((a) => statuses['${a.id}'] != 'completed' && statuses['${a.id}'] != 'rescheduled').toList();
    final next = upcoming.isEmpty ? null : upcoming.first;
    return ListView(padding: const EdgeInsets.fromLTRB(20, 18, 20, 100), children: [
      Row(children: [
        const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('RITMO', style: TextStyle(fontSize: 13, letterSpacing: 3, color: _blue, fontWeight: FontWeight.w800)), SizedBox(height: 7), Text('Your day, in rhythm.', style: TextStyle(fontSize: 25, fontWeight: FontWeight.w700))]),
        const Spacer(), _roundIcon(Icons.calendar_month_rounded),
      ]),
      const SizedBox(height: 8), Text(DateFormat('EEEE, d MMMM').format(DateTime.now()), style: const TextStyle(color: _muted)),
      const SizedBox(height: 24),
      _glassCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [const Text('DAILY PROGRESS', style: TextStyle(fontSize: 11, letterSpacing: 1.6, color: _muted, fontWeight: FontWeight.w700)), const Spacer(), Text('${(progress * 100).round()}%', style: const TextStyle(color: _blue, fontWeight: FontWeight.w700))]),
        const SizedBox(height: 14), ClipRRect(borderRadius: BorderRadius.circular(20), child: LinearProgressIndicator(value: progress, minHeight: 8, backgroundColor: Colors.white10, color: _blue)),
        const SizedBox(height: 12), Text('$completed of ${todaysActivities.length} activities completed', style: const TextStyle(color: _muted, fontSize: 12)),
      ])),
      if (missedToday.isNotEmpty) ...[
        const SizedBox(height: 14),
        _glassCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [const Icon(Icons.replay_circle_filled_rounded, color: Color(0xFFFFC477)), const SizedBox(width: 9), const Expanded(child: Text('ROUTINE RECOVERY', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1.1, fontSize: 11))), Text('${missedToday.length} missed', style: const TextStyle(color: Color(0xFFFFC477), fontSize: 11))]),
          const SizedBox(height: 8),
          const Text('You can move a missed activity to a new time. Other activities will not be changed automatically.', style: TextStyle(color: _muted, fontSize: 12, height: 1.4)),
          const SizedBox(height: 8),
          ...missedToday.map((row) => ListTile(contentPadding: EdgeInsets.zero, title: Text(row['title'] as String), subtitle: Text('Originally ${_formatTime(row['hour'] as int, row['minute'] as int)}', style: const TextStyle(color: _muted, fontSize: 11)), trailing: TextButton(onPressed: () => _recover(row), child: const Text('Recover')))),
        ])),
      ],
      const SizedBox(height: 14),
      _glassCard(child: Row(children: [
        Container(width: 46, height: 46, decoration: BoxDecoration(color: _blue.withValues(alpha: .13), borderRadius: BorderRadius.circular(15)), child: const Icon(Icons.alarm_rounded, color: _blue)),
        const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('UP NEXT', style: TextStyle(fontSize: 10, letterSpacing: 1.4, color: _muted)), const SizedBox(height: 4), Text(next?.title ?? 'You are all caught up', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16))])),
        if (next != null) Text(_time(next), style: const TextStyle(color: _blue, fontWeight: FontWeight.w700, fontSize: 17)),
      ])),
      const SizedBox(height: 25),
      Row(children: [const Text("Today's timeline", style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700)), const Spacer(), Text('${todaysActivities.length} ACTIVITIES', style: const TextStyle(color: _muted, fontSize: 10, letterSpacing: 1))]),
      const SizedBox(height: 14),
      if (todaysActivities.isEmpty) _emptyState() else ...todaysActivities.map(_activityTile),
    ]);
  }

  Widget _schedulePage() => ListView(padding: const EdgeInsets.fromLTRB(20, 20, 20, 100), children: [
    const Text('Your schedule', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
    const SizedBox(height: 6), const Text('Build a routine that works for you.', style: TextStyle(color: _muted)),
    const SizedBox(height: 22),
    if (activities.isEmpty) _emptyState() else ...activities.map((a) => _activityTile(a, showActions: true)),
  ]);

  Widget _activityTile(RoutineActivity a, {bool showActions = false}) {
    final status = statuses['${a.id}'];
    final done = status == 'completed';
    final color = _categoryColor(a.category);
    return Padding(padding: const EdgeInsets.only(bottom: 10), child: _glassCard(child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
      Container(width: 4, height: 58, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(8))),
      const SizedBox(width: 12),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(_time(a), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)), const SizedBox(height: 5), Text('${a.durationMinutes} min', style: const TextStyle(color: _muted, fontSize: 11))]),
      const SizedBox(width: 14),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(a.title, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, decoration: done ? TextDecoration.lineThrough : null, color: done ? _muted : Colors.white)), const SizedBox(height: 5), Text(a.category, style: const TextStyle(color: _muted, fontSize: 11))])),
      if (showActions) PopupMenuButton<String>(icon: const Icon(Icons.more_horiz, color: _muted), onSelected: (v) { if (v == 'edit') _addOrEdit(a); if (v == 'delete') _delete(a); }, itemBuilder: (_) => const [PopupMenuItem(value: 'edit', child: Text('Edit')), PopupMenuItem(value: 'delete', child: Text('Delete'))]),
      if (!showActions) IconButton(onPressed: () => _complete(a, done ? 'pending' : 'completed'), icon: Icon(done ? Icons.check_circle : Icons.radio_button_unchecked, color: done ? _green : _muted)),
    ])));
  }

  Widget _insightsPage() {
    final completedCount = weeklyHistory.where((r) => r['status'] == 'completed').length;
    final missedCount = weeklyHistory.where((r) => r['status'] == 'missed').length;
    final skippedCount = weeklyHistory.where((r) => r['status'] == 'skipped').length;
    final total = completedCount + missedCount + skippedCount;
    final consistency = total == 0 ? 0.0 : completedCount / total;
    final focusSeconds = weeklyFocus.fold<int>(0, (sum, row) => sum + ((row['actual_seconds'] as int?) ?? 0));
    final daily = <DateTime, int>{};
    for (var i = 6; i >= 0; i--) {
      final day = DateTime.now().subtract(Duration(days: i));
      final key = DatabaseService.instance.dateKey(day);
      daily[day] = weeklyHistory.where((r) => r['occurrence_date'] == key && r['status'] == 'completed').length;
    }
    final maxValue = daily.values.fold<int>(1, (a, b) => a > b ? a : b);
    return ListView(padding: const EdgeInsets.fromLTRB(20, 20, 20, 100), children: [
      const Text('Your insights', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
      const SizedBox(height: 6), const Text('A clearer view of your consistency.', style: TextStyle(color: _muted)),
      const SizedBox(height: 22),
      _glassCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('7-DAY CONSISTENCY', style: TextStyle(color: _muted, fontSize: 11, letterSpacing: 1.4)), const SizedBox(height: 12), Text('${(consistency * 100).round()}%', style: const TextStyle(fontSize: 42, fontWeight: FontWeight.w800, color: _blue)), const SizedBox(height: 5), Text('$completedCount completed · $missedCount missed · $skippedCount skipped', style: const TextStyle(color: _muted, fontSize: 12))])),
      const SizedBox(height: 12),
      _glassCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('DAILY COMPLETIONS', style: TextStyle(color: _muted, fontSize: 11, letterSpacing: 1.4)), const SizedBox(height: 18), Row(crossAxisAlignment: CrossAxisAlignment.end, mainAxisAlignment: MainAxisAlignment.spaceAround, children: daily.entries.map((entry) => Column(children: [Container(width: 23, height: 94, alignment: Alignment.bottomCenter, decoration: BoxDecoration(color: Colors.white.withValues(alpha: .045), borderRadius: BorderRadius.circular(8)), child: FractionallySizedBox(heightFactor: entry.value / maxValue, child: Container(decoration: BoxDecoration(color: _blue, borderRadius: BorderRadius.circular(8))))), const SizedBox(height: 7), Text(DateFormat('EE').format(entry.key), style: const TextStyle(color: _muted, fontSize: 10)), Text('${entry.value}', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700))])).toList())])),
      const SizedBox(height: 12),
      _glassCard(child: Row(children: [const Icon(Icons.timer_outlined, color: _blue, size: 30), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('FOCUS TIME · LAST 7 DAYS', style: TextStyle(color: _muted, fontSize: 10, letterSpacing: 1)), const SizedBox(height: 5), Text(_durationLabel(focusSeconds), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800))]))])),
      const SizedBox(height: 12),
      _glassCard(child: const Text('Reports are calculated from your locally stored activity history and focus sessions. Future activities are not counted as missed.', style: TextStyle(color: _muted, height: 1.5, fontSize: 12))),
    ]);
  }

  Widget _emptyState() => _glassCard(child: Column(children: [const Icon(Icons.event_available_rounded, color: _blue, size: 38), const SizedBox(height: 12), const Text('Make room for a better routine', style: TextStyle(fontWeight: FontWeight.w700)), const SizedBox(height: 6), const Text('Add your first activity and RITMO will help you stay on track.', textAlign: TextAlign.center, style: TextStyle(color: _muted, fontSize: 12)), const SizedBox(height: 14), OutlinedButton.icon(onPressed: () => _addOrEdit(), icon: const Icon(Icons.add), label: const Text('Add activity'))]));
}

class ActivityEditor extends StatefulWidget {
  const ActivityEditor({super.key, this.activity});
  final RoutineActivity? activity;
  @override
  State<ActivityEditor> createState() => _ActivityEditorState();
}

class _ActivityEditorState extends State<ActivityEditor> {
  late final TextEditingController title;
  late final TextEditingController notes;
  late TimeOfDay time;
  late int duration;
  late String category;
  late String mode;
  late bool alarm;
  late Set<int> days;
  static const labels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  @override
  void initState() {
    super.initState(); final a = widget.activity;
    title = TextEditingController(text: a?.title ?? ''); notes = TextEditingController(text: a?.notes ?? '');
    time = TimeOfDay(hour: a?.hour ?? 6, minute: a?.minute ?? 0); duration = a?.durationMinutes ?? 30;
    category = a?.category ?? 'Personal'; mode = a?.alarmMode ?? 'full_screen'; alarm = a?.alarmEnabled ?? true;
    days = (a?.repeatDays ?? [1,2,3,4,5,6,7]).toSet();
  }
  @override
  void dispose() { title.dispose(); notes.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => Padding(padding: EdgeInsets.fromLTRB(20, 22, 20, MediaQuery.of(context).viewInsets.bottom + 24), child: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Row(children: [Text(widget.activity == null ? 'New activity' : 'Edit activity', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)), const Spacer(), IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close))]),
    const SizedBox(height: 18), _fieldLabel('ACTIVITY NAME'), TextField(controller: title, decoration: _input('e.g. Morning workout')),
    const SizedBox(height: 16), _fieldLabel('CATEGORY'), DropdownButtonFormField<String>(initialValue: category, dropdownColor: _panel, decoration: _input('Choose category'), items: ['Personal','Workout','Study','Work','Break','Health','Other'].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(), onChanged: (v) => setState(() => category = v ?? category)),
    const SizedBox(height: 16), _fieldLabel('START TIME'), OutlinedButton.icon(onPressed: () async { final picked = await showTimePicker(context: context, initialTime: time); if (picked != null) setState(() => time = picked); }, icon: const Icon(Icons.schedule), label: Text(time.format(context)), style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 50), alignment: Alignment.centerLeft)),
    const SizedBox(height: 16), _fieldLabel('DURATION'), DropdownButtonFormField<int>(initialValue: duration, dropdownColor: _panel, decoration: _input('Duration'), items: [5,10,15,20,25,30,45,60,75,90,120,180].map((e) => DropdownMenuItem(value: e, child: Text('$e minutes'))).toList(), onChanged: (v) => setState(() => duration = v ?? duration)),
    const SizedBox(height: 18), _fieldLabel('REPEAT'), Wrap(spacing: 7, children: List.generate(7, (i) => ChoiceChip(label: Text(labels[i]), selected: days.contains(i+1), onSelected: (v) => setState(() { if (v) { days.add(i+1); } else { days.remove(i+1); } })))),
    const SizedBox(height: 16), SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Enable alarm'), subtitle: const Text('Alert me when this activity starts', style: TextStyle(color: _muted, fontSize: 12)), value: alarm, onChanged: (v) => setState(() => alarm = v)),
    if (alarm) SegmentedButton<String>(segments: const [ButtonSegment(value: 'full_screen', label: Text('Full screen'), icon: Icon(Icons.alarm)), ButtonSegment(value: 'notification', label: Text('Notification'), icon: Icon(Icons.notifications))], selected: {mode}, onSelectionChanged: (v) => setState(() => mode = v.first)),
    const SizedBox(height: 20), SizedBox(width: double.infinity, child: FilledButton(onPressed: _save, style: FilledButton.styleFrom(backgroundColor: _blue, foregroundColor: _bg, padding: const EdgeInsets.all(16)), child: const Text('Save activity', style: TextStyle(fontWeight: FontWeight.w800)))),
  ])));

  void _save() {
    if (title.text.trim().isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter an activity name.'))); return; }
    if (days.isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Select at least one repeat day.'))); return; }
    final a = widget.activity;
    Navigator.pop(context, RoutineActivity(id: a?.id ?? 0, title: title.text.trim(), category: category, hour: time.hour, minute: time.minute, durationMinutes: duration, repeatDays: days.toList()..sort(), alarmEnabled: alarm, alarmMode: mode, notes: notes.text));
  }
  Widget _fieldLabel(String value) => Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(value, style: const TextStyle(fontSize: 10, color: _muted, letterSpacing: 1.5, fontWeight: FontWeight.w700)));
  InputDecoration _input(String hint) => InputDecoration(hintText: hint, filled: true, fillColor: Colors.white.withValues(alpha: .035), border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Colors.white.withValues(alpha: .08))), enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Colors.white.withValues(alpha: .08))));
}

class FocusPage extends StatefulWidget { const FocusPage({super.key}); @override State<FocusPage> createState() => _FocusPageState(); }
class _FocusPageState extends State<FocusPage> with WidgetsBindingObserver {
  static const _prefsKey = 'ritmo_focus_state_v1';
  int selectedMinutes = 25;
  int remainingSeconds = 25 * 60;
  int? sessionId;
  DateTime? endsAt;
  bool running = false;
  Timer? ticker;
  bool loading = true;

  @override
  void initState() { super.initState(); WidgetsBinding.instance.addObserver(this); _restore(); }
  @override
  void dispose() { ticker?.cancel(); WidgetsBinding.instance.removeObserver(this); super.dispose(); }
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) { if (state == AppLifecycleState.resumed) _tick(); }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw != null) {
      try {
        final data = jsonDecode(raw) as Map<String, dynamic>;
        sessionId = data['sessionId'] as int?;
        selectedMinutes = (data['selectedMinutes'] as int?) ?? 25;
        remainingSeconds = (data['remainingSeconds'] as int?) ?? selectedMinutes * 60;
        running = data['running'] == true;
        final end = data['endsAt'] as String?;
        endsAt = end == null ? null : DateTime.parse(end);
        if (running && endsAt != null) _startTicker();
      } catch (_) { await prefs.remove(_prefsKey); }
    }
    if (mounted) setState(() => loading = false);
    if (running) unawaited(_tick());
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode({
      'sessionId': sessionId, 'selectedMinutes': selectedMinutes,
      'remainingSeconds': remainingSeconds, 'running': running,
      'endsAt': endsAt?.toIso8601String(),
    }));
  }

  void _startTicker() {
    ticker?.cancel();
    ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  Future<void> _tick() async {
    if (!running || endsAt == null) return;
    final left = endsAt!.difference(DateTime.now()).inSeconds;
    if (left <= 0) {
      ticker?.cancel();
      remainingSeconds = 0; running = false; endsAt = null;
      if (sessionId != null) await DatabaseService.instance.finishFocusSession(sessionId!, selectedMinutes * 60, 'completed');
      sessionId = null;
      await _persist();
    } else {
      remainingSeconds = left;
    }
    if (mounted) setState(() {});
  }

  Future<void> _start() async {
    sessionId ??= await DatabaseService.instance.startFocusSession(selectedMinutes * 60);
    remainingSeconds = remainingSeconds <= 0 ? selectedMinutes * 60 : remainingSeconds;
    endsAt = DateTime.now().add(Duration(seconds: remainingSeconds));
    running = true; await _persist(); _startTicker(); if (mounted) setState(() {});
  }

  Future<void> _pause() async {
    if (endsAt != null) remainingSeconds = endsAt!.difference(DateTime.now()).inSeconds.clamp(0, selectedMinutes * 60).toInt();
    running = false; endsAt = null; ticker?.cancel(); await _persist(); if (mounted) setState(() {});
  }

  Future<void> _reset() async {
    ticker?.cancel();
    if (sessionId != null) await DatabaseService.instance.finishFocusSession(sessionId!, selectedMinutes * 60 - remainingSeconds, 'abandoned');
    sessionId = null; running = false; endsAt = null; remainingSeconds = selectedMinutes * 60;
    final prefs = await SharedPreferences.getInstance(); await prefs.remove(_prefsKey);
    if (mounted) setState(() {});
  }

  String get clock => '${(remainingSeconds ~/ 60).toString().padLeft(2, '0')}:${(remainingSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) => loading ? const Center(child: CircularProgressIndicator()) : Center(child: SingleChildScrollView(padding: const EdgeInsets.all(24), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
    const Text('FOCUS MODE', style: TextStyle(color: _muted, letterSpacing: 2, fontSize: 11)),
    const SizedBox(height: 24),
    Container(width: 238, height: 238, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: _blue.withValues(alpha: .55), width: 2), color: _panel, boxShadow: [BoxShadow(color: _blue.withValues(alpha: .08), blurRadius: 35)]), child: Center(child: Text(clock, style: const TextStyle(fontSize: 54, fontWeight: FontWeight.w300)))),
    const SizedBox(height: 22), Text(running ? 'Stay with this session.' : 'Make this time count.', style: const TextStyle(color: _muted)),
    const SizedBox(height: 20), Wrap(spacing: 8, children: [15,25,45,60].map((v) => ChoiceChip(label: Text('$v min'), selected: selectedMinutes == v, onSelected: running || sessionId != null ? null : (_) => setState(() { selectedMinutes = v; remainingSeconds = v * 60; }))).toList()),
    const SizedBox(height: 22), Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      if (sessionId != null) OutlinedButton.icon(onPressed: _reset, icon: const Icon(Icons.stop_rounded), label: const Text('Reset')),
      const SizedBox(width: 10),
      FilledButton.icon(onPressed: running ? _pause : _start, style: FilledButton.styleFrom(backgroundColor: _blue, foregroundColor: _bg, padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14)), icon: Icon(running ? Icons.pause_rounded : Icons.play_arrow_rounded), label: Text(running ? 'Pause session' : sessionId == null ? 'Start focus' : 'Resume')),
    ]),
    const SizedBox(height: 18), const Text('Timer state is saved locally and restored if you leave or reopen RITMO.', textAlign: TextAlign.center, style: TextStyle(color: _muted, fontSize: 11)),
  ])));
}

class SettingsPage extends StatefulWidget { const SettingsPage({super.key}); @override State<SettingsPage> createState() => _SettingsPageState(); }
class _SettingsPageState extends State<SettingsPage> {
  bool busy = false;
  Future<void> _export() async {
    setState(() => busy = true);
    try {
      final data = await DatabaseService.instance.exportAll();
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/ritmo-backup-${DateFormat('yyyyMMdd-HHmm').format(DateTime.now())}.json');
      await file.writeAsString(DatabaseService.instance.encodeBackup(data));
      await Share.shareXFiles([XFile(file.path)], text: 'RITMO offline backup');
      _message('Backup file created. Save it somewhere safe.');
    } catch (e) { _message('Backup export failed: $e'); }
    if (mounted) setState(() => busy = false);
  }
  Future<void> _import() async {
    setState(() => busy = true);
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['json'], withData: true);
      if (result == null) { if (mounted) setState(() => busy = false); return; }
      final picked = result.files.single;
      final content = picked.bytes != null ? utf8.decode(picked.bytes!) : await File(picked.path!).readAsString();
      final decoded = jsonDecode(content);
      if (decoded is! Map<String, dynamic>) throw const FormatException('Invalid JSON backup.');
      if (!mounted) return;
      final confirm = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
        backgroundColor: _panel, title: const Text('Restore backup?'),
        content: const Text('Restoring replaces the activities and history currently stored on this phone.'),
        actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Restore'))],
      ));
      if (confirm == true) {
        final previousActivities = await DatabaseService.instance.getActivities();
        for (final activity in previousActivities) { await AlarmService.instance.cancel(activity.id); }
        await DatabaseService.instance.importAll(decoded);
        final activities = await DatabaseService.instance.getActivities();
        for (final activity in activities) { await AlarmService.instance.schedule(activity); }
        _message('Backup restored successfully.');
      }
    } catch (e) { _message('Could not restore backup: $e'); }
    if (mounted) setState(() => busy = false);
  }
  void _message(String text) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text))); }

  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(20), children: [
    const Text('Settings', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
    const SizedBox(height: 20),
    _glassCard(child: const Column(children: [
      ListTile(leading: Icon(Icons.notifications_active_outlined, color: _blue), title: Text('Alarm permissions'), subtitle: Text('Manage notification and exact alarm access', style: TextStyle(color: _muted, fontSize: 12))),
      Divider(color: Colors.white10),
      ListTile(leading: Icon(Icons.storage_outlined, color: _blue), title: Text('Offline storage'), subtitle: Text('Your routine data stays on this device', style: TextStyle(color: _muted, fontSize: 12))),
      Divider(color: Colors.white10),
      ListTile(leading: Icon(Icons.info_outline, color: _blue), title: Text('About RITMO'), subtitle: Text('Plan. Execute. Improve.', style: TextStyle(color: _muted, fontSize: 12))),
    ])),
    const SizedBox(height: 14),
    _glassCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('LOCAL BACKUP', style: TextStyle(color: _muted, fontSize: 11, letterSpacing: 1.4, fontWeight: FontWeight.w700)),
      const SizedBox(height: 7), const Text('Export or restore your activities, completion history and focus sessions. No cloud account is used.', style: TextStyle(color: _muted, fontSize: 12, height: 1.4)),
      const SizedBox(height: 14),
      SizedBox(width: double.infinity, child: OutlinedButton.icon(onPressed: busy ? null : _export, icon: const Icon(Icons.ios_share_rounded), label: const Text('Export backup'))),
      const SizedBox(height: 8),
      SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: busy ? null : _import, style: FilledButton.styleFrom(backgroundColor: _blue, foregroundColor: _bg), icon: const Icon(Icons.restore_rounded), label: const Text('Restore backup'))),
      if (busy) const Padding(padding: EdgeInsets.only(top: 12), child: LinearProgressIndicator()),
    ])),
  ]);
}

class _GlassNav extends StatelessWidget {
  const _GlassNav({required this.index, required this.onChanged}); final int index; final ValueChanged<int> onChanged;
  @override Widget build(BuildContext context) { const items = [(Icons.today_rounded,'Today'),(Icons.calendar_month_rounded,'Schedule'),(Icons.center_focus_strong,'Focus'),(Icons.insights_rounded,'Insights'),(Icons.settings_rounded,'Settings')]; return SafeArea(top: false, child: Container(margin: const EdgeInsets.fromLTRB(14, 0, 14, 10), padding: const EdgeInsets.symmetric(vertical: 9), decoration: BoxDecoration(color: const Color(0xE6191E2B), borderRadius: BorderRadius.circular(24), border: Border.all(color: Colors.white.withValues(alpha: .1)), boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 25)]), child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: List.generate(items.length, (i) => InkWell(onTap: () => onChanged(i), borderRadius: BorderRadius.circular(15), child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(items[i].$1, color: index == i ? _blue : _muted, size: 21), const SizedBox(height: 3), Text(items[i].$2, style: TextStyle(fontSize: 9, color: index == i ? _blue : _muted, fontWeight: index == i ? FontWeight.w700 : FontWeight.normal))]))))))); }
}

Widget _glassCard({required Widget child}) => Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: _panel.withValues(alpha: .88), borderRadius: BorderRadius.circular(22), border: Border.all(color: Colors.white.withValues(alpha: .075)), boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 18, offset: Offset(0,8))]), child: child);
Widget _roundIcon(IconData icon) => Container(width: 42, height: 42, decoration: BoxDecoration(color: _panel, borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.white12)), child: Icon(icon, color: _blue));
String _time(RoutineActivity a) => _formatTime(a.hour, a.minute);
String _formatTime(int hour, int minute) => DateFormat('h:mm a').format(DateTime(2020, 1, 1, hour, minute));
String _durationLabel(int seconds) => seconds < 60 ? '$seconds sec' : '${seconds ~/ 3600}h ${(seconds % 3600) ~/ 60}m';
Color _categoryColor(String category) => switch (category) { 'Workout' => const Color(0xFF70D6B0), 'Study' => const Color(0xFF8BA7FF), 'Work' => const Color(0xFFC29BFF), 'Break' => const Color(0xFFFFC477), 'Health' => const Color(0xFFFF8FA3), _ => _blue };
