import 'package:flutter/material.dart';
import 'package:home_widget/home_widget.dart';
import 'package:provider/provider.dart';

import '../models/profile.dart';
import '../state/app_store.dart';
import '../utils/format.dart';
import 'profiles_screen.dart';
import 'report_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _handleWidgetLaunch(HomeWidget.initiallyLaunchedFromHomeWidget());
      HomeWidget.widgetClicked.listen(_onWidgetUri);
    });
  }

  void _onWidgetUri(Uri? uri) {
    if (!mounted) return;
    _handleWidgetLaunch(Future.value(uri));
  }

  Future<void> _handleWidgetLaunch(Future<Uri?> future) async {
    final uri = await future;
    if (!mounted || uri == null) return;
    // Action / day buttons run in the background isolate (no app open).
    // Only rename needs the UI keyboard.
    final host = uri.host;
    if (host == 'rename' || uri.path.contains('rename')) {
      final store = context.read<AppStore>();
      if (!store.currentCanBeNamed) return;
      await _editEventName(context, store.currentActivity!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final profile = store.activeProfile;
    final current = store.currentActivity;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Plainday'),
        actions: [
          IconButton(
            tooltip: 'Reports',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const ReportScreen(),
                ),
              );
            },
            icon: const Icon(Icons.bar_chart_rounded),
          ),
          IconButton(
            tooltip: 'Profiles',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const ProfilesScreen(),
                ),
              );
            },
            icon: const Icon(Icons.tune_rounded),
          ),
        ],
      ),
      body: profile == null
          ? const Center(child: Text('No profile yet'))
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (store.showNotificationBanner) ...[
                      _NotificationBanner(
                        onEnable: () async {
                          await store.requestNotificationPermission();
                          await store.notifications.showTestNotification();
                          final msg = await store.refreshReminders();
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Test sent. $msg')),
                          );
                        },
                        onDismiss: () => store.dismissNotificationBanner(),
                      ),
                      const SizedBox(height: 12),
                    ],
                    _ProfileHeader(
                      profile: profile,
                      dayStarted: store.dayStarted,
                    ),
                    const SizedBox(height: 20),
                    StreamBuilder<int>(
                      stream: Stream.periodic(
                        const Duration(seconds: 1),
                        (i) => i,
                      ),
                      builder: (context, _) {
                        // Pick up native widget actions while the app is open.
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          context.read<AppStore>().pullRemoteChanges();
                        });
                        return _ActiveCard(
                          current: current,
                          dayStarted: store.dayStarted,
                          needsName: current != null &&
                              store.currentCanBeNamed &&
                              store.usesButtonLabel(current),
                          onEditName: current == null || !store.currentCanBeNamed
                              ? null
                              : () => _editEventName(context, current),
                        );
                      },
                    ),
                    if (store.breakPrompt != null) ...[
                      const SizedBox(height: 12),
                      _BreakSuggestion(
                        prompt: store.breakPrompt!,
                        breaks: profile.breaks,
                        suggested: store.suggestedBreak,
                        onGo: (breakId) => store.goToBreak(breakWindowId: breakId),
                        onReturn: () => store.returnFromBreak(),
                      ),
                    ],
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: store.dayStarted
                                ? null
                                : () async {
                                    await store.startDay();
                                    if (!context.mounted) return;
                                    final msg = await store.refreshReminders();
                                    if (!context.mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text(msg)),
                                    );
                                  },
                            child: const Text('Start day'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: store.dayStarted
                                ? () => store.endDay()
                                : null,
                            child: const Text('End day'),
                          ),
                        ),
                      ],
                    ),
                    if (store.dayStarted) ...[
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () async {
                            final exact =
                                await store.notifications.canScheduleExact();
                            if (!exact && context.mounted) {
                              await store.notifications.openExactAlarmSettings();
                              await store.notifications.openBatterySettings();
                            }
                            final msg = await store.refreshReminders();
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(msg),
                                duration: const Duration(seconds: 6),
                                action: SnackBarAction(
                                  label: 'Alarms',
                                  onPressed: () {
                                    store.notifications.openExactAlarmSettings();
                                  },
                                ),
                              ),
                            );
                          },
                          icon: const Icon(Icons.notifications_active_outlined),
                          label: const Text('Refresh reminders'),
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    Text(
                      'Actions',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: profile.buttons.isEmpty
                          ? Center(
                              child: Text(
                                'No buttons on this profile.\nAdd a preset with actions.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: scheme.onSurface.withValues(
                                    alpha: 0.6,
                                  ),
                                ),
                              ),
                            )
                          : ListView.separated(
                              itemCount: profile.buttons.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: 10),
                              itemBuilder: (context, index) {
                                final button = profile.buttons[index];
                                final isCurrent =
                                    current?.buttonId == button.id &&
                                    current!.isRunning;
                                return SizedBox(
                                  height: 64,
                                  child: FilledButton(
                                    style: FilledButton.styleFrom(
                                      backgroundColor: isCurrent
                                          ? scheme.primary
                                          : Color(profile.colorValue),
                                      foregroundColor: Colors.white,
                                    ),
                                    onPressed: () async {
                                      if (isCurrent) {
                                        await store.endCurrent();
                                      } else {
                                        await store.startFromButton(button);
                                      }
                                    },
                                    child: Text(
                                      isCurrent
                                          ? 'End ${current.label}'
                                          : button.label,
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Future<void> _editEventName(
    BuildContext context,
    ActivityEntry entry,
  ) async {
    final store = context.read<AppStore>();
    final stillDefault = store.usesButtonLabel(entry);
    final button = store.buttonForEntry(entry);
    final controller = TextEditingController(
      text: stillDefault ? '' : entry.label,
    );
    try {
      final name = await showDialog<String>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: Text(stillDefault ? 'Add name' : 'Rename'),
            content: TextField(
              controller: controller,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: 'Name',
                hintText: button != null
                    ? 'Name this ${button.label.toLowerCase()}'
                    : 'Name this activity',
              ),
              onSubmitted: (value) {
                final trimmed = value.trim();
                if (trimmed.isEmpty) return;
                FocusScope.of(context).unfocus();
                Navigator.pop(context, trimmed);
              },
            ),
            actions: [
              TextButton(
                onPressed: () {
                  FocusScope.of(context).unfocus();
                  Navigator.pop(context);
                },
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  final trimmed = controller.text.trim();
                  if (trimmed.isEmpty) return;
                  FocusScope.of(context).unfocus();
                  Navigator.pop(context, trimmed);
                },
                child: const Text('Save'),
              ),
            ],
          );
        },
      );
      if (name == null || !context.mounted) return;
      await context.read<AppStore>().renameActivity(entry.id, name);
    } finally {
      // Defer dispose until after focus/IME teardown (avoids disposed-controller crash).
      WidgetsBinding.instance.addPostFrameCallback((_) {
        controller.dispose();
      });
    }
  }
}

class _NotificationBanner extends StatelessWidget {
  const _NotificationBanner({
    required this.onEnable,
    required this.onDismiss,
  });

  final Future<void> Function() onEnable;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.secondaryContainer.withValues(alpha: 0.7),
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
        child: Row(
          children: [
            Expanded(
              child: Text(
                'Enable reminders for start/end day, breaks, and stand-ups.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
            TextButton(
              onPressed: () => onEnable(),
              child: const Text('Enable'),
            ),
            IconButton(
              onPressed: onDismiss,
              icon: const Icon(Icons.close_rounded),
              tooltip: 'Dismiss',
            ),
          ],
        ),
      ),
    );
  }
}

class _BreakSuggestion extends StatefulWidget {
  const _BreakSuggestion({
    required this.prompt,
    required this.breaks,
    required this.suggested,
    required this.onGo,
    required this.onReturn,
  });

  final BreakPrompt prompt;
  final List<BreakWindow> breaks;
  final BreakWindow? suggested;
  final Future<void> Function(String? breakId) onGo;
  final VoidCallback onReturn;

  @override
  State<_BreakSuggestion> createState() => _BreakSuggestionState();
}

class _BreakSuggestionState extends State<_BreakSuggestion> {
  String? _selectedId;

  @override
  void initState() {
    super.initState();
    _selectedId = widget.suggested?.id;
  }

  @override
  void didUpdateWidget(covariant _BreakSuggestion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.suggested?.id != oldWidget.suggested?.id &&
        (_selectedId == null ||
            !widget.breaks.any((b) => b.id == _selectedId))) {
      _selectedId = widget.suggested?.id;
    }
  }

  BreakWindow? get _selected {
    for (final b in widget.breaks) {
      if (b.id == _selectedId) return b;
    }
    return widget.suggested;
  }

  @override
  Widget build(BuildContext context) {
    final isReturn = widget.prompt == BreakPrompt.returnFromBreak;
    if (isReturn) {
      return FilledButton.tonal(
        onPressed: widget.onReturn,
        child: const Text('Return from break'),
      );
    }

    final selected = _selected;
    final label = selected == null ? 'Go to break' : 'Go to ${selected.label}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.breaks.length > 1) ...[
          DropdownButtonFormField<String>(
            initialValue: _selectedId ?? widget.breaks.first.id,
            decoration: const InputDecoration(
              labelText: 'Break',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            items: [
              if (widget.suggested != null)
                DropdownMenuItem(
                  value: widget.suggested!.id,
                  child: Text(
                    'Next · ${widget.suggested!.label} '
                    '(${formatMinutesOfDay(widget.suggested!.startMinutes)})',
                  ),
                ),
              ...widget.breaks
                  .where((b) => b.id != widget.suggested?.id)
                  .map(
                    (b) => DropdownMenuItem(
                      value: b.id,
                      child: Text(
                        '${b.label} (${formatMinutesOfDay(b.startMinutes)})',
                      ),
                    ),
                  ),
            ],
            onChanged: (v) => setState(() => _selectedId = v),
          ),
          const SizedBox(height: 8),
        ],
        FilledButton.tonal(
          onPressed: () => widget.onGo(_selectedId ?? selected?.id),
          child: Text(label),
        ),
      ],
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({
    required this.profile,
    required this.dayStarted,
  });

  final Profile profile;
  final bool dayStarted;

  @override
  Widget build(BuildContext context) {
    final start = formatMinutesOfDay(profile.startMinutes);
    final end = formatMinutesOfDay(profile.endMinutes);
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: Color(profile.colorValue),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                profile.name,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              Text(
                '$start – $end · ${dayStarted ? 'Day on' : 'Day off'}',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.65),
                    ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ActiveCard extends StatelessWidget {
  const _ActiveCard({
    required this.current,
    required this.dayStarted,
    required this.needsName,
    this.onEditName,
  });

  final ActivityEntry? current;
  final bool dayStarted;
  final bool needsName;
  final VoidCallback? onEditName;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label =
        current?.label ?? (dayStarted ? 'Nothing running' : 'Start your day');
    final elapsed = current == null
        ? '00:00:00'
        : _formatDuration(current!.elapsedSeconds());

    return Material(
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onEditName,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      label,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  if (onEditName != null)
                    Icon(
                      Icons.edit_outlined,
                      size: 18,
                      color: scheme.onSurface.withValues(alpha: 0.55),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                elapsed,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
              ),
              if (needsName) ...[
                const SizedBox(height: 10),
                Text(
                  'Tap to add a name',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: scheme.primary,
                      ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _formatDuration(int totalSeconds) {
    final h = totalSeconds ~/ 3600;
    final m = (totalSeconds % 3600) ~/ 60;
    final s = totalSeconds % 60;
    return '${h.toString().padLeft(2, '0')}:'
        '${m.toString().padLeft(2, '0')}:'
        '${s.toString().padLeft(2, '0')}';
  }
}
