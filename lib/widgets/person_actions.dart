import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/l10n.dart';
import '../state/calendar_connections_state.dart';
import '../theme/tokens.dart';
import '../theme/app_icons.dart';
import 'anchored_menu.dart';
import 'avatar.dart';
import 'error_note.dart';
import 'rename_sheet.dart';

/// Renaming and removing somebody in the household who has no account — the
/// child a school calendar was assigned to, typed into the owner picker.
///
/// Reached from two places, the owner picker and Settings → Familie, and they
/// have to be the same errand: such a person exists only as the name written
/// on their calendars, so both rewrite those through
/// [CalendarConnectionsNotifier.renamePerson] and neither has a row of its own
/// to edit.

/// The face such a person wears everywhere — keyed on the name, because there
/// is no profile to have stored a tone.
Widget personFace(String name, {double size = 40}) {
  final tone = AppTones.list[name.hashCode.abs() % AppTones.list.length];
  return Avatar(
    size: size,
    bg: tone.bg,
    fg: tone.fg,
    initials: name.isEmpty ? '?' : name.substring(0, 1).toUpperCase(),
    fontSize: size * 0.35,
  );
}

Future<bool> showRenamePersonSheet({required BuildContext context, required WidgetRef ref, required String name}) {
  return showRenameSheet(
    context: context,
    leading: personFace(name, size: 44),
    title: L.s.renamePerson,
    headline: name,
    message: L.s.renamePersonBody,
    initialName: name,
    fieldHint: name,
    busyLabel: L.s.savingEllipsis,
    successLabel: L.s.nameChanged,
    errorText: (_) => L.s.saveFailed,
    onConfirm: (next) => ref.read(calendarConnectionsProvider.notifier).renamePerson(name, next),
  );
}

/// Asks first, because it moves calendars: everything assigned to [name] goes
/// back to the household. Nothing is disconnected, and the dialog says so.
void confirmRemovePerson({required BuildContext context, required WidgetRef ref, required String name}) {
  showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(L.s.removePersonQuestion),
      content: Text(L.s.removePersonBody(name)),
      actions: [
        TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: Text(L.s.cancel)),
        TextButton(
          onPressed: () async {
            Navigator.of(dialogContext).pop();
            try {
              await ref.read(calendarConnectionsProvider.notifier).renamePerson(name, null);
            } catch (_) {
              if (context.mounted) showErrorSnack(context, L.s.saveFailed);
            }
          },
          child: Text(L.s.remove, style: AppText.rowTitle.copyWith(color: AppColors.danger)),
        ),
      ],
    ),
  );
}

/// The row's "…": the same two things as its swipe, in the app's one menu —
/// there so a row that can be renamed and removed looks like every other such
/// row, rather than wearing a bin that deletes on a single tap.
class PersonMoreButton extends StatefulWidget {
  final VoidCallback onRename;
  final VoidCallback onRemove;

  const PersonMoreButton({super.key, required this.onRename, required this.onRemove});

  @override
  State<PersonMoreButton> createState() => _PersonMoreButtonState();
}

class _PersonMoreButtonState extends State<PersonMoreButton> {
  final _anchor = GlobalKey();

  @override
  Widget build(BuildContext context) {
    return RowMoreButton(
      key: _anchor,
      onTap: () => showAnchoredMenu(
        context: context,
        anchorKey: _anchor,
        items: [
          AnchoredMenuItem(label: L.s.rename, icon: AppIcons.pencilSimple, symbol: 'pencil', onSelected: widget.onRename),
          AnchoredMenuItem(
            label: L.s.remove,
            icon: AppIcons.trash,
            symbol: 'trash',
            destructive: true,
            onSelected: widget.onRemove,
          ),
        ],
      ),
    );
  }
}
