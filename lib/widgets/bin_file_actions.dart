import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../models/calendar_connection.dart';
import '../services/calendar_page_browser.dart';
import '../services/external_links.dart';
import '../theme/app_icons.dart';
import '../theme/tokens.dart';
import 'app_sheet.dart';
import 'glass.dart';

/// **The one layout for a waste calendar that comes in as a file**, wherever it
/// is asked for — the Kalender sheet's Abfall step, the upload sheet it hands
/// over to, and the onboarding's address step. A town we read connects on its
/// own and never shows this; every other town, whatever its page hands out,
/// shows exactly this and nothing else.
///
/// The way there, numbered, then two buttons: the town's own page (blue, the
/// one to take) and a file already on the phone (glass, with the upload arrow).
/// **One upload button for every kind of file** — an iCal today, a PDF plan
/// once `pdfUploadAvailable` says the server reads one — so a new format is a
/// new label, never a third button.
///
/// On iOS the page opens inside the app ([onFetchFromPage]), because Safari
/// hands the town's .ics straight to Apple Calendar and leaves nothing to
/// upload; elsewhere it opens in the browser, which saves the file where the
/// picker finds it.
class BinFileActions extends StatelessWidget {
  final String? page;

  /// What the page hands out, per the atlas. It changes the instructions, never
  /// the buttons: it is a reading of the page, and a town that the atlas saw
  /// printing a PDF may well offer an iCal export by now.
  final TownPageFormat? format;

  final bool enabled;

  /// The page opened in the app, on iOS; the caller takes the file it returns.
  final Future<void> Function(String page) onFetchFromPage;

  /// Null where the device has no file picker, and the button goes.
  final VoidCallback? onUpload;

  /// Drawn on the onboarding's surface rather than a sheet's.
  final bool onSurface;

  const BinFileActions({
    super.key,
    required this.page,
    this.format,
    this.enabled = true,
    required this.onFetchFromPage,
    this.onUpload,
    this.onSurface = false,
  });

  @override
  Widget build(BuildContext context) {
    final page = this.page;
    final inApp = page != null && calendarPageBrowserAvailable;
    final pdf = format == TownPageFormat.pdf;
    final steps = pdf && pdfUploadAvailable
        ? (inApp ? L.s.binFileStepsPdfInApp : L.s.binFileStepsPdfBrowser)
        : inApp
        ? L.s.binFileStepsInApp
        : L.s.binFileStepsBrowser;
    // Where the page is not a file at all — yet — a sentence says so before
    // the steps, rather than numbering a route that ends in nothing.
    final note = switch (format) {
      TownPageFormat.pdf when !pdfUploadAvailable => L.s.townPagePdfOnly,
      TownPageFormat.html => L.s.townPageDatesOnly,
      TownPageFormat.app => L.s.townPageAppOnly,
      _ => null,
    };
    final upload = onUpload;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (note != null) ...[
          Text(note, style: AppText.body.copyWith(color: AppColors.muted)),
          const SizedBox(height: 14),
        ],
        // The card says what will happen on the town's page before anybody is
        // on it — where there is a file to fetch there. A page with none gets
        // the sentence above and the button, not steps that end in nothing.
        if (page != null && note == null) ...[
          SectionCard(
            radius: AppRadii.card,
            onSurface: onSurface,
            children: dividedRows(inset: true, onSurface: onSurface, [
              for (final (index, line) in steps.indexed) _StepRow(number: index + 1, text: line),
            ]),
          ),
          const SizedBox(height: 18),
        ],
        if (page != null) ...[
          GlassAccentButton(
            label: L.s.openTownCalendarPage,
            icon: AppIcons.arrowSquareOut,
            expand: true,
            enabled: enabled,
            onTap: () => inApp ? onFetchFromPage(page) : openExternalUrl(page),
          ),
          const SizedBox(height: 12),
        ],
        if (upload != null)
          GlassPillButton(
            // Any town, whatever the atlas says its page offers: a PDF the
            // household already keeps is as good an answer as the town's iCal.
            label: pdfUploadAvailable ? L.s.uploadCalendarFileOrPdf : L.s.uploadCalendarFile,
            icon: AppIcons.uploadSimple,
            expand: true,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            onTap: () {
              if (enabled) upload();
            },
          ),
      ],
    );
  }
}

/// One numbered step of the card — a settings row's geometry (the leading slot
/// a GlyphTile would fill, the same padding), with the number where the icon
/// goes and the line allowed to wrap.
class _StepRow extends StatelessWidget {
  final int number;
  final String text;

  const _StepRow({required this.number, required this.text});

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
      child: Row(
        children: [
          SizedBox(
            width: 34,
            height: 34,
            child: Center(
              child: Container(
                width: 26,
                height: 26,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: accent.withValues(alpha: 0.12), shape: BoxShape.circle),
                child: Text('$number', style: AppText.rowTitle.copyWith(color: accent, fontWeight: FontWeight.w600)),
              ),
            ),
          ),
          const SizedBox(width: 13),
          Expanded(child: Text(text, style: AppText.rowTitle)),
        ],
      ),
    );
  }
}
