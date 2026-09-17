import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/media_picker.dart';
import '../state/family_state.dart';
import '../theme/app_icons.dart';
import '../theme/tokens.dart';
import 'avatar.dart';
import 'glyph_tile.dart';
import 'icon_picker.dart';

/// The household's own face — its picture if an admin has uploaded one, its
/// initials on its tone colour if not — and, for an admin, the tap that
/// changes it.
///
/// It is a widget of its own rather than a private one on the family page
/// because the household's picture is shown in **two** places that both let you
/// change it: the leading slot of the family-name row, and the rename sheet
/// that row opens. A house glyph in that sheet was wrong twice over — a family
/// is people, not a building, and the picture the household already has was
/// sitting one tap away without being drawn.
///
/// It is not in the page's masthead either. That slot is the page's *identity*
/// — "Familie", the members — and once the household's name got a card of its
/// own, the two halves of one thing were on opposite ends of the page: the name
/// in a row you tap, the face in the header above it. They belong to the same
/// edit, so they sit in the same row.
///
/// The same menu a profile picture gets — Foto, Kamera, Entfernen — and the
/// same optimistic swap, because it is the same operation on a different row.
/// What differs is who may: an admin, checked here so the tap simply isn't
/// offered, and checked again by `avatars_write_family_picture` in Storage,
/// which is what actually decides.
///
/// Without a picture the circle is the household's initials on a tone derived
/// from its id — a complete answer that every family starts with, and what the
/// "Familie" chip in Kalender and Board falls back to as well.
///
/// [ringColor] is what the little camera badge is ringed in, so it separates
/// from whatever is behind it: the card's surface on the family page, the
/// sheet's own background in the rename sheet.
class FamilyAvatarButton extends ConsumerStatefulWidget {
  final bool canEdit;
  final double size;
  final Color? ringColor;

  const FamilyAvatarButton({super.key, required this.canEdit, this.size = 40, this.ringColor});

  @override
  ConsumerState<FamilyAvatarButton> createState() => _FamilyAvatarButtonState();
}

class _FamilyAvatarButtonState extends ConsumerState<FamilyAvatarButton> {
  final _avatarKey = GlobalKey();

  /// The freshly picked file, held while it uploads and for as long as this
  /// widget is alive. Handing straight back to the signed URL would blink the
  /// picture back to initials while that URL is fetched.
  File? _uploading;

  Future<void> _pick(AttachmentSource source) async {
    final picked = await pickAttachment(source, maxDimension: avatarMaxDimension);
    if (picked == null || !picked.isImage) return;

    final file = File(picked.path);
    setState(() => _uploading = file);
    final ok = await ref.read(familyProvider.notifier).setFamilyAvatar(file);
    if (!mounted) return;
    if (!ok) setState(() => _uploading = null);
  }

  /// The app's one picture menu — a family has a photograph or its initials,
  /// and no third thing to pick. It puts up the system's own sheet first and
  /// falls back to the dropdown, which is what lets this widget be opened from
  /// inside a sheet whose header carries native glass buttons.
  Future<void> _menu(Household household) async {
    final choice = await showPictureMenu(
      context,
      anchorKey: _avatarKey,
      hasPhoto: household.avatarPath != null || _uploading != null,
    );
    if (choice == null || !mounted) return;
    switch (choice) {
      case PictureChoice.photo:
        await _pick(AttachmentSource.photos);
      case PictureChoice.camera:
        await _pick(AttachmentSource.camera);
      case PictureChoice.remove:
        setState(() => _uploading = null);
        ref.read(familyProvider.notifier).removeFamilyAvatar();
    }
  }

  @override
  Widget build(BuildContext context) {
    final household = ref.watch(familyProvider).household;
    // Every caller only draws this once the household is known, so this is a
    // guard rather than a state anybody sees — it keeps the row the same
    // height if it ever is.
    if (household == null) return GlyphTile(icon: AppIcons.users, size: widget.size);

    final tone = AppTones.list[household.tone % AppTones.list.length];
    final avatar = Avatar(
      size: widget.size,
      bg: tone.bg,
      fg: tone.fg,
      initials: household.initials,
      fontSize: widget.size * 0.35,
      imageUrl: household.avatarUrl,
      imageFile: _uploading,
    );

    if (!widget.canEdit) return avatar;

    final badge = widget.size * 0.45;
    return GestureDetector(
      key: _avatarKey,
      onTap: () => _menu(household),
      // The badge overhangs the circle, so the tap has to be caught outside the
      // avatar's own bounds as well.
      behavior: HitTestBehavior.opaque,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          avatar,
          // Bottom-right, the corner every camera-roll and profile editor puts
          // it in. A ring in the background colour behind it separates it from
          // whatever the picture happens to be.
          Positioned(
            right: -2,
            bottom: -2,
            child: Container(
              width: badge,
              height: badge,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                shape: BoxShape.circle,
                border: Border.all(color: widget.ringColor ?? AppColors.surface, width: 2),
              ),
              child: AppIcon(AppIcons.camera, size: badge * 0.5, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}
