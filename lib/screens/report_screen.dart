import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/profile.dart';
import '../state/app_store.dart';
import '../utils/format.dart';

class ReportScreen extends StatefulWidget {
  const ReportScreen({super.key});

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _shareCsv({required bool week}) async {
    final store = context.read<AppStore>();
    final csv = store.buildCsv(week: week);
    final dir = await getTemporaryDirectory();
    final name = week ? 'plainday-week.csv' : 'plainday-today.csv';
    final file = File('${dir.path}/$name');
    await file.writeAsString(csv);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path)],
        subject: week ? 'Plainday week export' : 'Plainday today export',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reports'),
        actions: [
          IconButton(
            tooltip: 'Export CSV',
            onPressed: () => _shareCsv(week: _tabs.index == 1),
            icon: const Icon(Icons.ios_share_rounded),
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'Today'),
            Tab(text: 'This week'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _ReportPane(
            store: store,
            totals: store.todayTotalsSeconds(),
            entries: store.todayEntries,
            emptyLabel: 'No activity logged yet today.',
          ),
          _WeekPane(
            store: store,
            totals: store.weekTotalsSeconds(),
            daily: store.weekDailyTotalsSeconds(),
            entries: store.weekEntries,
          ),
        ],
      ),
    );
  }
}

class _ReportPane extends StatelessWidget {
  const _ReportPane({
    required this.store,
    required this.totals,
    required this.entries,
    required this.emptyLabel,
  });

  final AppStore store;
  final Map<ActivityKind, int> totals;
  final List<ActivityEntry> entries;
  final String emptyLabel;

  @override
  Widget build(BuildContext context) {
    final byProfile = _totalsByProfile(store, entries);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      children: [
        Text('By profile', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        if (byProfile.isEmpty)
          Text(emptyLabel)
        else
          ...byProfile.entries.map(
            (e) => _ProfileTotalRow(
              color: Color(store.profileColorFor(e.key)),
              name: store.profileNameFor(e.key),
              seconds: e.value,
            ),
          ),
        const SizedBox(height: 24),
        Text('By type', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        if (totals.isEmpty)
          Text(emptyLabel)
        else
          ...ActivityKind.values
              .where((k) => !activityKindIsDayMarker(k) && (totals[k] ?? 0) > 0)
              .map(
                (k) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Expanded(child: Text('${activityKindLabel(k)}s')),
                      Text(formatDurationSeconds(totals[k] ?? 0)),
                    ],
                  ),
                ),
              ),
        const SizedBox(height: 24),
        Text('Timeline', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        if (entries.isEmpty)
          Text(emptyLabel)
        else
          ...entries.map((e) => _EntryTile(store: store, entry: e)),
      ],
    );
  }
}

class _WeekPane extends StatelessWidget {
  const _WeekPane({
    required this.store,
    required this.totals,
    required this.daily,
    required this.entries,
  });

  final AppStore store;
  final Map<ActivityKind, int> totals;
  final Map<DateTime, int> daily;
  final List<ActivityEntry> entries;

  @override
  Widget build(BuildContext context) {
    final maxDay = daily.values.fold<int>(0, (a, b) => a > b ? a : b);
    final byProfile = _totalsByProfile(store, entries);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      children: [
        Text('By profile', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        if (byProfile.isEmpty)
          const Text('No activity this week yet.')
        else
          ...byProfile.entries.map(
            (e) => _ProfileTotalRow(
              color: Color(store.profileColorFor(e.key)),
              name: store.profileNameFor(e.key),
              seconds: e.value,
            ),
          ),
        const SizedBox(height: 24),
        Text('By type', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        if (totals.isEmpty)
          const Text('No activity this week yet.')
        else
          ...ActivityKind.values
              .where((k) => !activityKindIsDayMarker(k) && (totals[k] ?? 0) > 0)
              .map(
                (k) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Expanded(child: Text('${activityKindLabel(k)}s')),
                      Text(formatDurationSeconds(totals[k] ?? 0)),
                    ],
                  ),
                ),
              ),
        const SizedBox(height: 24),
        Text('By day', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        ...daily.entries.map((e) {
          final fraction = maxDay == 0 ? 0.0 : e.value / maxDay;
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        weekdayLabels[e.key.weekday] ?? '${e.key.day}',
                      ),
                    ),
                    Text(formatDurationSeconds(e.value)),
                  ],
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: fraction,
                    minHeight: 8,
                  ),
                ),
              ],
            ),
          );
        }),
        const SizedBox(height: 24),
        Text('Entries', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        if (entries.isEmpty)
          const Text('Nothing logged this week.')
        else
          ...entries
              .take(40)
              .map((e) => _EntryTile(store: store, entry: e, showWeekday: true)),
      ],
    );
  }
}

class _ProfileTotalRow extends StatelessWidget {
  const _ProfileTotalRow({
    required this.color,
    required this.name,
    required this.seconds,
  });

  final Color color;
  final String name;
  final int seconds;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(name)),
          Text(formatDurationSeconds(seconds)),
        ],
      ),
    );
  }
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({
    required this.store,
    required this.entry,
    this.showWeekday = false,
  });

  final AppStore store;
  final ActivityEntry entry;
  final bool showWeekday;

  @override
  Widget build(BuildContext context) {
    final marker = activityKindIsDayMarker(entry.kind);
    final running = entry.isRunning ? ' · running' : '';
    final paused = entry.isPaused ? ' · paused' : '';
    final profileName = store.profileNameFor(entry.profileId);
    final color = Color(store.profileColorFor(entry.profileId));
    final time = _stamp(entry.startedAt);
    final when = showWeekday
        ? '${weekdayLabels[entry.startedAt.weekday]} · $time'
        : time;

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: marker
          ? Icon(
              entry.kind == ActivityKind.dayStart
                  ? Icons.play_circle_outline
                  : Icons.stop_circle_outlined,
              color: color,
            )
          : Container(
              width: 10,
              height: 10,
              margin: const EdgeInsets.only(top: 6),
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
      title: Text(entry.label),
      subtitle: Text('$profileName · $when$running$paused'),
      trailing: Text(
        marker ? '—' : formatDurationSeconds(entry.elapsedSeconds()),
      ),
    );
  }

  String _stamp(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

Map<String, int> _totalsByProfile(AppStore store, List<ActivityEntry> entries) {
  final now = DateTime.now();
  final totals = <String, int>{};
  for (final e in entries) {
    if (activityKindIsDayMarker(e.kind)) continue;
    totals[e.profileId] =
        (totals[e.profileId] ?? 0) + e.elapsedSeconds(now: now);
  }
  final sorted = totals.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  return {for (final e in sorted) e.key: e.value};
}
