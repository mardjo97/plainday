import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../models/profile.dart';
import '../state/app_store.dart';
import '../utils/format.dart';

class ProfileEditorScreen extends StatefulWidget {
  const ProfileEditorScreen({super.key, required this.profileId});

  final String profileId;

  @override
  State<ProfileEditorScreen> createState() => _ProfileEditorScreenState();
}

class _ProfileEditorScreenState extends State<ProfileEditorScreen> {
  static const _uuid = Uuid();
  Profile? _draft;
  TextEditingController? _nameController;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_draft != null) return;
    final store = context.read<AppStore>();
    final found = store.profiles.where((p) => p.id == widget.profileId);
    _draft = found.isEmpty ? store.profiles.first : found.first;
    _nameController = TextEditingController(text: _draft!.name);
  }

  @override
  void dispose() {
    _nameController?.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final draft = _draft;
    final nameController = _nameController;
    if (draft == null || nameController == null) return;
    final updated = draft.copyWith(
      name: nameController.text.trim().isEmpty
          ? draft.name
          : nameController.text.trim(),
    );
    await context.read<AppStore>().updateProfile(updated);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _pickTime({
    required int initialMinutes,
    required ValueChanged<int> onPicked,
  }) async {
    final tod = TimeOfDay(hour: initialMinutes ~/ 60, minute: initialMinutes % 60);
    final picked = await showTimePicker(context: context, initialTime: tod);
    if (picked == null) return;
    onPicked(picked.hour * 60 + picked.minute);
  }

  @override
  Widget build(BuildContext context) {
    final draft = _draft;
    final nameController = _nameController;
    if (draft == null || nameController == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit profile'),
        actions: [
          TextButton(onPressed: _save, child: const Text('Save')),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        children: [
          TextField(
            controller: nameController,
            decoration: const InputDecoration(
              labelText: 'Name',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 20),
          Text('Schedule', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _pickTime(
                    initialMinutes: draft.startMinutes,
                    onPicked: (m) => setState(
                      () => _draft = draft.copyWith(startMinutes: m),
                    ),
                  ),
                  child: Text('Start ${formatMinutesOfDay(draft.startMinutes)}'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _pickTime(
                    initialMinutes: draft.endMinutes,
                    onPicked: (m) => setState(
                      () => _draft = draft.copyWith(endMinutes: m),
                    ),
                  ),
                  child: Text('End ${formatMinutesOfDay(draft.endMinutes)}'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [
              for (final day in weekdayLabels.entries)
                FilterChip(
                  label: Text(day.value),
                  selected: draft.activeDays.contains(day.key),
                  onSelected: (selected) {
                    final days = List<int>.from(draft.activeDays);
                    if (selected) {
                      days.add(day.key);
                    } else {
                      days.remove(day.key);
                    }
                    days.sort();
                    setState(() => _draft = draft.copyWith(activeDays: days));
                  },
                ),
            ],
          ),
          const SizedBox(height: 24),
          Text('Rules', style: Theme.of(context).textTheme.titleLarge),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('One active timer'),
            value: draft.rules.oneActiveTimer,
            onChanged: (v) => setState(
              () => _draft = draft.copyWith(
                rules: draft.rules.copyWith(oneActiveTimer: v),
              ),
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Resume previous when ending'),
            value: draft.rules.resumePreviousOnEnd,
            onChanged: (v) => setState(
              () => _draft = draft.copyWith(
                rules: draft.rules.copyWith(resumePreviousOnEnd: v),
              ),
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Silence when inactive'),
            value: draft.rules.silenceWhenInactive,
            onChanged: (v) => setState(
              () => _draft = draft.copyWith(
                rules: draft.rules.copyWith(silenceWhenInactive: v),
              ),
            ),
          ),
          const SizedBox(height: 16),
          _SectionHeader(
            title: 'Buttons',
            onAdd: () {
              setState(() {
                _draft = draft.copyWith(
                  buttons: [
                    ...draft.buttons,
                    ProfileButton(
                      id: _uuid.v4(),
                      label: 'Task',
                      requiresName: true,
                    ),
                  ],
                );
              });
            },
          ),
          ...draft.buttons.asMap().entries.map((entry) {
            final i = entry.key;
            final button = entry.value;
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                title: Text(button.label),
                subtitle: Text(
                  [
                    if (button.isBreak)
                      button.breakId == null
                          ? 'break · next upcoming'
                          : 'break · linked',
                    if (button.requiresName) 'can be named',
                    if (button.pausesOthers) 'pauses others',
                  ].join(' · '),
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () {
                    final next = List<ProfileButton>.from(draft.buttons)
                      ..removeAt(i);
                    setState(() => _draft = draft.copyWith(buttons: next));
                  },
                ),
                onTap: () => _editButton(i, button),
              ),
            );
          }),
          const SizedBox(height: 16),
          _SectionHeader(
            title: 'Breaks',
            onAdd: () {
              setState(() {
                _draft = draft.copyWith(
                  breaks: [
                    ...draft.breaks,
                    BreakWindow(
                      id: _uuid.v4(),
                      label: 'Break',
                      startMinutes: 12 * 60 + 30,
                      endMinutes: 13 * 60,
                    ),
                  ],
                );
              });
            },
          ),
          ...draft.breaks.asMap().entries.map((entry) {
            final i = entry.key;
            final b = entry.value;
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                title: Text(b.label),
                subtitle: Text(
                  '${formatMinutesOfDay(b.startMinutes)} – ${formatMinutesOfDay(b.endMinutes)}',
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () {
                    final next = List<BreakWindow>.from(draft.breaks)
                      ..removeAt(i);
                    setState(() => _draft = draft.copyWith(breaks: next));
                  },
                ),
                onTap: () => _editBreak(i, b),
              ),
            );
          }),
          const SizedBox(height: 16),
          _SectionHeader(
            title: 'Reminders',
            onAdd: () {
              setState(() {
                _draft = draft.copyWith(
                  reminders: [
                    ...draft.reminders,
                    ProfileReminder(
                      id: _uuid.v4(),
                      label: 'Stand up',
                      kind: ReminderKind.interval,
                      intervalMinutes: 30,
                    ),
                  ],
                );
              });
            },
          ),
          ...draft.reminders.asMap().entries.map((entry) {
            final i = entry.key;
            final r = entry.value;
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: SwitchListTile(
                title: Text(r.label),
                subtitle: Text(
                  [
                    reminderKindLabel(r.kind),
                    if (r.intervalMinutes != null) 'every ${r.intervalMinutes}m',
                    if (r.offsetMinutes != 0) 'offset ${r.offsetMinutes}m',
                  ].join(' · '),
                ),
                value: r.enabled,
                onChanged: (v) {
                  final next = List<ProfileReminder>.from(draft.reminders);
                  next[i] = r.copyWith(enabled: v);
                  setState(() => _draft = draft.copyWith(reminders: next));
                },
                secondary: IconButton(
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () => _editReminder(i, r),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Future<void> _editButton(int index, ProfileButton button) async {
    final draft = _draft;
    if (draft == null) return;
    final labelController = TextEditingController(text: button.label);
    var pauses = button.pausesOthers;
    var requiresName = button.requiresName;
    var isBreak = button.isBreak;
    String? breakId = button.breakId;

    final result = await showDialog<ProfileButton>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setLocal) {
            return AlertDialog(
              title: const Text('Button'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: labelController,
                    decoration: const InputDecoration(
                      labelText: 'Label',
                      hintText: 'Task, Meeting, Break…',
                    ),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Break'),
                    subtitle: const Text(
                      'Used for break suggestions and return-from-break.',
                    ),
                    value: isBreak,
                    onChanged: (v) => setLocal(() {
                      isBreak = v;
                      if (v) {
                        requiresName = false;
                      } else {
                        breakId = null;
                      }
                    }),
                  ),
                  if (isBreak) ...[
                    DropdownButtonFormField<String?>(
                      initialValue: breakId,
                      decoration: const InputDecoration(
                        labelText: 'Linked break',
                      ),
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('Next upcoming break'),
                        ),
                        ...draft.breaks.map(
                          (b) => DropdownMenuItem<String?>(
                            value: b.id,
                            child: Text(
                              '${b.label} (${formatMinutesOfDay(b.startMinutes)}–${formatMinutesOfDay(b.endMinutes)})',
                            ),
                          ),
                        ),
                      ],
                      onChanged: (v) => setLocal(() => breakId = v),
                    ),
                  ],
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Pauses others'),
                    value: pauses,
                    onChanged: (v) => setLocal(() => pauses = v),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Can be named'),
                    subtitle: const Text(
                      'Show Add name / Edit name for this activity.',
                    ),
                    value: requiresName,
                    onChanged: (v) => setLocal(() => requiresName = v),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    Navigator.pop(
                      context,
                      button.copyWith(
                        label: labelController.text.trim().isEmpty
                            ? button.label
                            : labelController.text.trim(),
                        pausesOthers: pauses,
                        requiresName: requiresName,
                        isBreak: isBreak,
                        breakId: breakId,
                        clearBreakId: !isBreak || breakId == null,
                      ),
                    );
                  },
                  child: const Text('Done'),
                ),
              ],
            );
          },
        );
      },
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      labelController.dispose();
    });
    if (result == null) return;
    final current = _draft;
    if (current == null) return;
    final next = List<ProfileButton>.from(current.buttons);
    next[index] = result;
    setState(() => _draft = current.copyWith(buttons: next));
  }

  Future<void> _editBreak(int index, BreakWindow breakWindow) async {
    final labelController = TextEditingController(text: breakWindow.label);
    var start = breakWindow.startMinutes;
    var end = breakWindow.endMinutes;

    final result = await showDialog<BreakWindow>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setLocal) {
            return AlertDialog(
              title: const Text('Break'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: labelController,
                    decoration: const InputDecoration(labelText: 'Label'),
                  ),
                  const SizedBox(height: 12),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('Start ${formatMinutesOfDay(start)}'),
                    onTap: () async {
                      final tod = TimeOfDay(
                        hour: start ~/ 60,
                        minute: start % 60,
                      );
                      final picked =
                          await showTimePicker(context: context, initialTime: tod);
                      if (picked != null) {
                        setLocal(() => start = picked.hour * 60 + picked.minute);
                      }
                    },
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('End ${formatMinutesOfDay(end)}'),
                    onTap: () async {
                      final tod = TimeOfDay(hour: end ~/ 60, minute: end % 60);
                      final picked =
                          await showTimePicker(context: context, initialTime: tod);
                      if (picked != null) {
                        setLocal(() => end = picked.hour * 60 + picked.minute);
                      }
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    Navigator.pop(
                      context,
                      breakWindow.copyWith(
                        label: labelController.text.trim().isEmpty
                            ? breakWindow.label
                            : labelController.text.trim(),
                        startMinutes: start,
                        endMinutes: end,
                      ),
                    );
                  },
                  child: const Text('Done'),
                ),
              ],
            );
          },
        );
      },
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      labelController.dispose();
    });
    if (result == null) return;
    final current = _draft;
    if (current == null) return;
    final next = List<BreakWindow>.from(current.breaks);
    next[index] = result;
    setState(() => _draft = current.copyWith(breaks: next));
  }

  Future<void> _editReminder(int index, ProfileReminder reminder) async {
    final draft = _draft;
    if (draft == null) return;
    final labelController = TextEditingController(text: reminder.label);
    var kind = reminder.kind;
    var offset = reminder.offsetMinutes;
    var interval = reminder.intervalMinutes ?? 30;
    String? breakId = reminder.breakId;

    final result = await showDialog<ProfileReminder>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setLocal) {
            return AlertDialog(
              title: const Text('Reminder'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: labelController,
                      decoration: const InputDecoration(labelText: 'Label'),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<ReminderKind>(
                      initialValue: kind,
                      items: ReminderKind.values
                          .map(
                            (k) => DropdownMenuItem(
                              value: k,
                              child: Text(reminderKindLabel(k)),
                            ),
                          )
                          .toList(),
                      onChanged: (v) {
                        if (v == null) return;
                        setLocal(() => kind = v);
                      },
                      decoration: const InputDecoration(labelText: 'Kind'),
                    ),
                    if (kind == ReminderKind.interval) ...[
                      const SizedBox(height: 12),
                      TextFormField(
                        initialValue: '$interval',
                        decoration: const InputDecoration(
                          labelText: 'Interval (minutes)',
                        ),
                        keyboardType: TextInputType.number,
                        onChanged: (v) {
                          interval = int.tryParse(v) ?? interval;
                        },
                      ),
                    ],
                    if (kind == ReminderKind.atProfileStart ||
                        kind == ReminderKind.atProfileEnd ||
                        kind == ReminderKind.relativeToBreak) ...[
                      const SizedBox(height: 12),
                      TextFormField(
                        initialValue: '$offset',
                        decoration: const InputDecoration(
                          labelText: 'Offset (minutes)',
                        ),
                        keyboardType: TextInputType.number,
                        onChanged: (v) {
                          offset = int.tryParse(v) ?? offset;
                        },
                      ),
                    ],
                    if (kind == ReminderKind.relativeToBreak &&
                        draft.breaks.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: breakId ?? draft.breaks.first.id,
                        items: draft.breaks
                            .map(
                              (b) => DropdownMenuItem(
                                value: b.id,
                                child: Text(b.label),
                              ),
                            )
                            .toList(),
                        onChanged: (v) => setLocal(() => breakId = v),
                        decoration: const InputDecoration(labelText: 'Break'),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    Navigator.pop(
                      context,
                      reminder.copyWith(
                        label: labelController.text.trim().isEmpty
                            ? reminder.label
                            : labelController.text.trim(),
                        kind: kind,
                        offsetMinutes: offset,
                        intervalMinutes:
                            kind == ReminderKind.interval ? interval : null,
                        clearInterval: kind != ReminderKind.interval,
                        breakId: kind == ReminderKind.relativeToBreak
                            ? breakId
                            : null,
                        clearBreakId: kind != ReminderKind.relativeToBreak,
                      ),
                    );
                  },
                  child: const Text('Done'),
                ),
              ],
            );
          },
        );
      },
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      labelController.dispose();
    });
    if (result == null) return;
    final current = _draft;
    if (current == null) return;
    final next = List<ProfileReminder>.from(current.reminders);
    next[index] = result;
    setState(() => _draft = current.copyWith(reminders: next));
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.onAdd});

  final String title;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleLarge),
        ),
        IconButton(onPressed: onAdd, icon: const Icon(Icons.add_rounded)),
      ],
    );
  }
}
