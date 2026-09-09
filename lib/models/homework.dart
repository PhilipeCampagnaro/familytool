import '../l10n/l10n.dart';

/// One homework out of WebUntis — **not** a calendar event, and never rendered
/// as one.
///
/// A due date is not an appointment. It has no time, it does not occupy the day,
/// and twenty of them in a week grid would bury the lessons they belong to. So
/// homework travels beside the events rather than among them, and shows up in
/// two places that are both views of the same fact: a badge on the lesson it is
/// due in, and a row on Board.
///
/// Read-only, always. [done] is the pupil's own tick in Untis — the one truth
/// about whether the Vokabeln are learnt. Writing our own copy of it beside
/// theirs would give a household two answers to one question.
class Homework {
  /// Stable across refreshes — the calendar id plus Untis's own homework id.
  final String id;

  /// The timetable calendar it came in on. Homework is filtered and coloured
  /// with its calendar exactly like an event, which is what makes one child's
  /// homework separable from another's.
  final String calendarId;

  /// The `uid` of the lesson it is due in, or empty when the due date falls
  /// outside the fortnight most schools publish — roughly half of them at any
  /// moment. Empty is the ordinary case, not a failure.
  final String eventUid;

  /// Untis's subject shorthand — 'MA', 'BI', 'GE'. Empty for the lessons that
  /// come back without one (about a fifth of them), which is why [teacher]
  /// exists as the other half of the label.
  final String subject;

  /// 'Meyer (MYE)' — full name and Kürzel together, as the homework payload
  /// sends it. The timetable only ever carries the Kürzel, so this is the
  /// nicer of the two sources for anything a person reads.
  final String teacher;

  /// Midnight-normalised local date. A `date` in Postgres and a date in Untis:
  /// no hour to get wrong, and therefore no timezone that could move it a day.
  final DateTime dueOn;

  final String text;
  final String remark;

  /// Ticked off by the pupil in Untis.
  final bool done;

  const Homework({
    required this.id,
    required this.calendarId,
    required this.dueOn,
    required this.text,
    this.eventUid = '',
    this.subject = '',
    this.teacher = '',
    this.remark = '',
    this.done = false,
  });

  /// Null for a row that cannot be rendered — no date, or no text to show —
  /// rather than a `Homework` that would draw an empty line in a list.
  static Homework? fromMap(Map<String, dynamic> map) {
    final due = DateTime.tryParse(map['due_on'] as String? ?? '');
    final text = (map['text'] as String? ?? '').trim();
    if (due == null || text.isEmpty) return null;

    return Homework(
      id: map['id'] as String? ?? '',
      calendarId: map['calendar_id'] as String? ?? '',
      eventUid: map['event_uid'] as String? ?? '',
      subject: (map['subject'] as String? ?? '').trim(),
      teacher: (map['teacher'] as String? ?? '').trim(),
      dueOn: DateTime(due.year, due.month, due.day),
      text: text,
      remark: (map['remark'] as String? ?? '').trim(),
      done: map['completed'] == true,
    );
  }

  /// What the household calls this lesson: the subject if Untis named one, the
  /// teacher if it did not, and the generic word if neither survived. Something
  /// always renders — a badge with an empty label is worse than a generic one.
  String get label {
    if (subject.isNotEmpty) return subject;
    if (teacher.isNotEmpty) return teacher;
    return L.s.homework;
  }

  /// The first line, for a badge or a one-line row. Untis homework runs to
  /// whole paragraphs — one is a materials list with an emoji per line — and
  /// the rest of it belongs in the sheet that has room for it.
  String get summary => text.split('\n').first.trim();
}
