import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/presets.dart';
import '../models/profile.dart';
import '../state/app_store.dart';
import '../utils/format.dart';
import 'profile_editor_screen.dart';

class ProfilesScreen extends StatelessWidget {
  const ProfilesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();

    return Scaffold(
      appBar: AppBar(title: const Text('Profiles')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          ...store.profiles.map((p) {
            final selected = p.id == store.activeProfileId;
            return Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: Color(p.colorValue),
                  radius: 12,
                ),
                title: Text(p.name),
                subtitle: Text(
                  '${formatMinutesOfDay(p.startMinutes)} – ${formatMinutesOfDay(p.endMinutes)}',
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (selected)
                      const Padding(
                        padding: EdgeInsets.only(right: 4),
                        child: Icon(Icons.check_circle_rounded, size: 20),
                      ),
                    PopupMenuButton<String>(
                      onSelected: (value) async {
                        switch (value) {
                          case 'activate':
                            await _activateProfile(context, store, p);
                          case 'edit':
                            if (!context.mounted) return;
                            await Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) =>
                                    ProfileEditorScreen(profileId: p.id),
                              ),
                            );
                          case 'duplicate':
                            await _duplicateProfile(context, store, p.id);
                          case 'delete':
                            final ok = await store.deleteProfile(p.id);
                            if (!context.mounted) return;
                            if (!ok) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Keep at least one profile.'),
                                ),
                              );
                            }
                        }
                      },
                      itemBuilder: (_) => [
                        if (!selected)
                          const PopupMenuItem(
                            value: 'activate',
                            child: Text('Set active'),
                          ),
                        const PopupMenuItem(
                          value: 'edit',
                          child: Text('Edit'),
                        ),
                        const PopupMenuItem(
                          value: 'duplicate',
                          child: Text('Duplicate'),
                        ),
                        const PopupMenuItem(
                          value: 'delete',
                          child: Text('Delete'),
                        ),
                      ],
                    ),
                  ],
                ),
                onTap: () => _activateProfile(context, store, p),
                onLongPress: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => ProfileEditorScreen(profileId: p.id),
                    ),
                  );
                },
              ),
            );
          }),
          const SizedBox(height: 12),
          Text('Add from preset', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ActionChip(
                label: const Text('Blank'),
                onPressed: () => _addPreset(context, store, null),
              ),
              ...ProfilePresets.all().map(
                (preset) => ActionChip(
                  label: Text(preset.name),
                  onPressed: () => _addPreset(context, store, preset),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

Future<void> _activateProfile(
  BuildContext context,
  AppStore store,
  Profile profile,
) async {
  if (profile.id == store.activeProfileId) return;

  if (store.hasOpenDaySession) {
    final confirmed = await _confirmResetForSwitch(
      context,
      fromName: store.activeProfile?.name ?? 'current profile',
      toName: profile.name,
    );
    if (confirmed != true) return;
    await store.switchProfileResettingDay(profile.id);
    return;
  }

  await store.setActiveProfile(profile.id);
}

Future<void> _duplicateProfile(
  BuildContext context,
  AppStore store,
  String id,
) async {
  if (store.hasOpenDaySession) {
    final confirmed = await _confirmResetForSwitch(
      context,
      fromName: store.activeProfile?.name ?? 'current profile',
      toName: 'the duplicated profile',
    );
    if (confirmed != true) return;
    await store.endDay();
  }
  await store.duplicateProfile(id);
}

Future<void> _addPreset(
  BuildContext context,
  AppStore store,
  Profile? preset,
) async {
  if (store.hasOpenDaySession) {
    final toName = preset?.name ?? 'Blank';
    final confirmed = await _confirmResetForSwitch(
      context,
      fromName: store.activeProfile?.name ?? 'current profile',
      toName: toName,
    );
    if (confirmed != true) return;
    await store.endDay();
  }
  if (preset == null) {
    await store.addBlankProfile();
  } else {
    await store.addProfileFromPreset(preset);
  }
}

Future<bool?> _confirmResetForSwitch(
  BuildContext context, {
  required String fromName,
  required String toName,
}) {
  return showDialog<bool>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: const Text('Switch profile?'),
        content: Text(
          'A day is still active on $fromName, and the timer is still counting.\n\n'
          'Switch to $toName? This ends the current day, stops the timer, '
          'and resets the counter. Logged time stays in Reports under $fromName.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('End day & switch'),
          ),
        ],
      );
    },
  );
}
