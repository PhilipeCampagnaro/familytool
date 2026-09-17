import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// **A recipe drawn as a recipe.**
///
/// The one place in the app that parses markdown, and it parses a *fixed, tiny*
/// subset of it: a `#` title, `##` headings, `-` bullets, `1.` steps,
/// `**bold**`, `*italic*` and blank-line paragraphs. Nothing else — no tables,
/// no links, no images, no code, no block quotes — and the prompt in
/// `supabase/functions/list-plan` asks for exactly this list and no more, so
/// the two halves are one decision written down twice.
///
/// **Why it exists at all**, when the answer used to be plain prose on purpose:
/// a method is not prose. "Zutaten" and "Zubereitung" are two different things,
/// a quantity list is a list, and 180 °C is the one number in the paragraph you
/// come back to the card to find. Printed as five undifferentiated blocks the
/// reader has to re-read the whole thing to cook from it, which is exactly the
/// moment — standing at the hob — the recipe was kept for. The old rule was
/// right about *chat* markdown (a wall of `###` and bullet soup is a chatbot
/// transcript, not a list the household made) and wrong to conclude that the
/// answer therefore has no structure at all. The answer to that is a subset
/// small enough to draw in the app's own type scale, which is this.
///
/// **Anything outside the subset is printed as it arrived**, asterisks and all.
/// That is deliberate and is the same reasoning the plain-text rule had: a model
/// that ignored the format is a thing we want to *see*, not quietly render into
/// something that looks intentional.
///
/// Not a package. `flutter_markdown` is a full CommonMark implementation with
/// its own theme object, and it would draw the 95% of markdown we forbid in
/// styles that are not the app's.
class MarkdownText extends StatelessWidget {
  final String source;

  /// The paragraph, bullet and step style. Headings are derived from the app's
  /// own scale rather than from this, so a caller cannot accidentally make a
  /// heading smaller than its body.
  final TextStyle? style;

  // ignore: prefer_const_constructors_in_immutables
  MarkdownText(this.source, {super.key, this.style});

  static final _heading = RegExp(r'^\s{0,3}(#{1,4})\s+(.+?)\s*#*$');
  static final _bullet = RegExp(r'^\s{0,4}[-*•]\s+(.+)$');
  static final _numbered = RegExp(r'^\s{0,4}(\d{1,2})[.)]\s+(.+)$');

  @override
  Widget build(BuildContext context) {
    final body = style ?? AppText.body.copyWith(color: AppColors.inkSecondary, height: 1.5);
    final blocks = <Widget>[];
    final paragraph = <String>[];

    // A run of ordinary lines is *one* paragraph, the way markdown reads it:
    // models break a sentence over two lines for their own reasons, and drawing
    // each as its own block puts ragged gaps mid-thought. The blank line is
    // what separates paragraphs, which is what the answer already did.
    void flush() {
      if (paragraph.isEmpty) return;
      final text = paragraph.join(' ');
      paragraph.clear();
      blocks.add(_gap(blocks, 12));
      blocks.add(Text.rich(markdownSpan(text, style: body)));
    }

    for (final raw in source.split('\n')) {
      final line = raw.trimRight();
      if (line.trim().isEmpty) {
        flush();
        continue;
      }
      if (_heading.firstMatch(line) case final m?) {
        flush();
        // **`#` is the answer's one title, `##` its sections**, and they are
        // drawn a size apart because that difference is the whole structure:
        // one emoji lives on the title and the sections carry none, so if the
        // two render identically the reader sees a picture stuck to the first
        // section instead of a heading over all of them.
        final top = m.group(1)!.length == 1;
        blocks.add(_gap(blocks, top ? 20 : 18));
        blocks.add(
          Text.rich(
            markdownSpan(
              m.group(2)!,
              style: (top ? AppText.cardTitle : AppText.rowTitle).copyWith(
                color: AppColors.ink,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        );
        continue;
      }
      if (_bullet.firstMatch(line) case final m?) {
        flush();
        blocks.add(_gap(blocks, 7));
        blocks.add(_marked(_dot(body), m.group(1)!, body));
        continue;
      }
      if (_numbered.firstMatch(line) case final m?) {
        flush();
        blocks.add(_gap(blocks, 10));
        blocks.add(
          _marked(Text('${m.group(1)}.', style: body.copyWith(color: AppColors.muted)), m.group(2)!, body),
        );
        continue;
      }
      paragraph.add(line.trim());
    }
    flush();

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: blocks);
  }

  /// The space *above* a block, and nothing above the first one — a leading gap
  /// would push the whole method away from the label that opened it.
  Widget _gap(List<Widget> blocks, double height) => SizedBox(height: blocks.isEmpty ? 0 : height);

  /// A bullet or a number in the gutter, with the text hanging beside it rather
  /// than wrapping back underneath it.
  Widget _marked(Widget mark, String text, TextStyle body) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SizedBox(width: 22, child: mark),
      Expanded(child: Text.rich(markdownSpan(text, style: body))),
    ],
  );

  /// Sized and lowered against the *first line* of the text beside it: a dot
  /// centred in its own box sits at the middle of a three-line item, which
  /// reads as a mark for the second line.
  Widget _dot(TextStyle body) {
    final line = (body.fontSize ?? 15) * (body.height ?? 1.3);
    return Padding(
      padding: EdgeInsets.only(top: (line - 4) / 2, left: 4),
      child: Container(
        width: 4,
        height: 4,
        decoration: BoxDecoration(color: AppColors.mutedLight, shape: BoxShape.circle),
      ),
    );
  }
}

/// The overview steps of a plan, as a block [MarkdownText] can draw.
///
/// **A step is a titled block, and the whole method has one title over them.**
/// The first entry is `# 🎨 Wohnzimmer streichen`; every entry after it is
/// `## Wände reinigen` and a sentence or two under it. This only has to join
/// them into one document and let the heading rules do the rest — blocks are
/// separated by a blank line, which is what makes the sentence under a title a
/// paragraph rather than a continuation of it.
///
/// **There is exactly one emoji in an answer and it is on the `#` line.** Three
/// shapes came before it: a numbered ladder (a grey circle saying "1 of 5"
/// twice, once in the circle and once in the order they were already in), a row
/// of bullets with an emoji per sentence, and a titled block with an emoji per
/// title. The first two had no shape for the eye to come back to; the third had
/// the shape and kept the mistakes, because five emoji are five chances to be
/// wrong about a household's own errand and the model spends them on whatever
/// the *topic* is — seven paintbrushes down a plan about painting. Titles carry
/// the structure. One picture, over the lot, is the most a model can be trusted
/// to get right.
///
/// **A plain sentence still draws.** Steps written before 2026-09-16 are stored
/// on the list, so they arrive untitled; they become ordinary paragraphs rather
/// than losing their text to a format that came later. Leading numbering the
/// model added anyway is dropped either way — "1." above a title is furniture
/// the title already replaced.
String stepsAsMarkdown(List<String> steps) => [
  for (final step in steps) step.trim().replaceFirst(RegExp(r'^\s{0,4}\d{1,2}[.)]\s+'), ''),
].where((step) => step.isNotEmpty).join('\n\n');

/// One line of inline markdown as a span — `**bold**` and `*italic*` (and their
/// `__`/`_` spellings), everything else literal.
///
/// Public because a caller sometimes has one line rather than a block and wants
/// nothing from here but the bold — a heading it is drawing itself, a row's
/// title.
TextSpan markdownSpan(String text, {required TextStyle style}) {
  final spans = <TextSpan>[];
  var at = 0;
  for (final m in _inline.allMatches(text)) {
    if (m.start > at) spans.add(TextSpan(text: text.substring(at, m.start)));
    final bold = m.group(1) ?? m.group(2);
    spans.add(
      bold != null
          ? TextSpan(
              text: bold,
              style: const TextStyle(fontWeight: FontWeight.w600),
            )
          : TextSpan(
              text: m.group(3) ?? m.group(4),
              style: const TextStyle(fontStyle: FontStyle.italic),
            ),
    );
    at = m.end;
  }
  if (at < text.length) spans.add(TextSpan(text: text.substring(at)));
  return TextSpan(style: style, children: spans);
}

/// Bold before italic, so `**x**` is not read as an empty italic wrapping `*x*`.
/// Lazy and non-greedy, and a marker with nothing between it is left alone —
/// `**` on its own is a model misbehaving, and printing it is how that shows.
final _inline = RegExp(r'\*\*(.+?)\*\*|__(.+?)__|\*(.+?)\*|_(.+?)_');
