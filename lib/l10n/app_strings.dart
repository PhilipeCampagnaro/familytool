library;

import '../data/german_holidays.dart';
import '../models/grocery_unit.dart';

/// Every user-facing string in Aporah, declared once here and answered by
/// [StringsDe] and [StringsEn].
///
/// **Why a global rather than `AppLocalizations.of(context)`:** a third of the
/// app's copy lives where there is no `BuildContext` — validation messages on
/// the notifiers in `lib/state/`, the duration and reminder labels on
/// `CalendarEvent`, the failure text the repositories raise. Threading a
/// context into those would mean rewriting them as widgets' business.
/// [AppColors.palette] already solves the same problem the same way (see the
/// comment above the assignment in `main.dart`), so language follows colour:
/// `L.strings` is swapped in `AporahApp.build` before anything below it builds,
/// and the rebuild that swaps it is the one `ref.watch` already triggered.
///
/// Because this is an abstract class, the analyzer refuses to compile a
/// language that has forgotten a string — which is the whole point of not
/// using a map.
abstract class AppStrings {
  const AppStrings();

  /// `'de'` / `'en'` — matches `AppLanguage.name` and the `Locale` handed to
  /// `MaterialApp`.
  String get localeCode;

  /// German prints `14:30 Uhr`, English prints `2:30 PM`. Also decides what
  /// `showTimePicker` comes up as.
  bool get use24HourClock;

  // ---------------------------------------------------------------- dates --
  /// 1-based: `monthNames[1]` is January. Index 0 is an empty string so the
  /// month number indexes directly.
  List<String> get monthNames;
  List<String> get monthShort;

  /// 0-based on `DateTime.weekday % 7`, so index 0 is Sunday.
  List<String> get weekdayShort;
  List<String> get weekdayLong;

  /// Single letters under the month grid, Monday first.
  List<String> get dayLetters;

  /// `13. August` (de) vs `13 August` (en) — the ordinal dot is German-only.
  String dayMonth(int day, int month);
  String dayMonthShort(int day, int month);

  /// The date line above the day list: `Heute, 13. August` / `Today, 13 August`.
  String todayWithDate(int day, int month);
  String weekdayWithDate(int weekday, int day, int month);

  /// `August 2026` — same order both ways, but kept here so a language that
  /// wants it reversed can have it.
  String monthYear(int month, int year);

  /// Two dates as one span — `1. Mär – 14. Apr`. The dash is an en dash with
  /// its own spacing in both languages, which is why it is here and not joined
  /// at the call site.
  String dateRange(String from, String to);

  /// Board's week label: `10. – 16. August` / `10 – 16 August`.
  String dayRangeSameMonth(int fromDay, int toDay, int month);

  /// Across a month boundary: `31. Juli – 6. August` / `31 July – 6 August`.
  String dayRangeCrossMonth(int fromDay, int fromMonth, int toDay, int toMonth);

  /// Board's day heading: `Donnerstag, 13. Aug` / `Thursday, 13 Aug`.
  String weekdayWithDateShort(int weekday, int day, int month);

  // --------------------------------------------------------------- common --
  String get cancel;
  String get delete;
  String get edit;
  String get share;
  String get close;
  String get doneAction;
  String get add;
  String get rename;
  String get remove;
  String get disconnect;
  String get reload;

  /// The caret on a detail screen's name, which unfolds a name too long for one
  /// line ([ExpandableTitle]). Spoken, not drawn — the control is a glyph, and
  /// VoiceOver would otherwise announce the name with no hint that there is
  /// more of it behind a tap.
  String get showFullName;
  String get hideFullName;

  /// The action on a delete confirmation, and what the chip says once the
  /// restore has come back. Shared by all four screens — a per-entity wording
  /// would only repeat the noun the same chip already named.
  String get undo;
  String get restored;
  String get notes;
  String get addNotes;
  String get name;
  String get unknown;
  String get next;
  String get skip;
  String get letsGo;
  String get today;
  String get allDay;
  String get place;
  String get searchPlace;
  String get noPlacesFound;
  String get quantity;

  /// What the quantity counts, and the title of the picker that changes it.
  String get unit;
  String unitName(GroceryUnit unit);
  String get size;
  String get titleLabel;
  String get role;
  String get nameOptional;
  String get password;
  String get calendar;
  String get somethingWentWrong;
  String get noServerConnection;
  String get serverTooSlow;
  String get notSignedIn;
  String get householdNotLoaded;

  // ------------------------------------------------------------------ nav --
  String get navHome;
  String get navCalendar;
  String get navLists;
  String get navBoard;
  String get navBox;

  /// VoiceOver label for the collapsed nav button on Kalender — the only thing
  /// left of the bar once the agenda is scrolled, and the way back to it.
  String get navExpand;


  // ---------------------------------------------------------------- board --
  String get boardTitle;
  String doneCountSeparator(int count);
  String get newTask;
  String get editTask;
  String get taskPlaceholder;
  String get dueLabel;

  /// What the "Fällig" row shows when a task has no date. A dash rather than
  /// "Kein Datum": the row is answering, not offering, and an empty answer that
  /// reads as a word invites a second look at whether it is one.
  String get dueNone;

  /// The Board's sections, in [BoardSection] order.
  String get sectionOverdue;
  String get sectionToday;
  String get sectionTomorrow;
  String get sectionThisWeek;
  String get sectionLater;
  String get sectionUndated;

  /// Due-date picker. The shortcuts carry most of the traffic; "Datum wählen"
  /// opens the calendar behind them. [duePickDate] is also the row that opens
  /// the calendar in the Kalender's repeat sheet — the same offer, and a second
  /// string saying it would only be the same words twice.
  String get dueThisWeekend;
  String get dueNextWeek;
  String get duePickDate;

  /// The optional hour on a to-do, at the bottom of the due-date sheet and as
  /// its own row in the task sheet. Most to-dos never get one — it is for the
  /// school run and the bin, not for "Geschenk kaufen" — which is why it is the
  /// last thing the sheet asks and never a required answer.
  String get dueTimeLabel;

  /// The row that takes the hour away again. Not "Keine Uhrzeit" as an *answer*
  /// the way [sectionUndated] is one: no hour is simply the absence of one, so
  /// the row only appears once there is something to remove.
  String get dueNoTime;

  /// Why the hour row is greyed out. An hour with no day names nothing, and the
  /// database refuses the pair outright (`tasks_due_time_needs_date`) — so the
  /// row says what to do rather than letting somebody pick a time that could
  /// not be saved.
  String get dueTimeNeedsDate;

  String get theTask;
  String get deleteTask;
  String get assigneeLabel;
  String get nobody;
  String get me;
  String get nothingPlanned;
  String doneOfTotal(int done, int total);

  /// Names the Board header's grid of days. It is a chart nobody asked for and
  /// nothing else on the screen explains, so it says what it is.
  String get trackerTitle;

  /// The Board tracker grid's spoken summary: how many of the days it draws
  /// were finished. It stands in for a label per square — at nearly two hundred
  /// of them, stepping through the grid cell by cell is not a way anybody can
  /// read it.
  String trackerDaysDone(int done, int total);

  // -------------------------------------------------------------- tracker --
  //
  // A tracker is the Board's second kind of row: a rhythm the household keeps,
  // beside the one-off tasks. The vocabulary is deliberately its own rather
  // than borrowed from the Kalender's recurrence card — [repeatDaily] and
  // friends describe an appointment that comes round, and a rename there must
  // not quietly relabel what a family is trying to stick to.

  /// The create sheet's first question, above the segmented control. Both
  /// answers are nouns for a thing, not verbs for an act: the user is choosing
  /// what to make, and "To-do" against "Tracker" is the whole distinction.
  String get whatToCreate;

  /// The create sheet's title while it can still become either kind. Short on
  /// purpose: the segmented control directly beneath it is the answer, and a
  /// title that named one of the two would contradict the control every time
  /// somebody switched.
  String get newEntry;
  String get kindTask;
  String get kindTracker;

  String get newTracker;
  String get editTracker;

  /// Deliberately not "Was ist zu tun?" — that is the task's placeholder, and
  /// the difference between the two sheets has to survive the one field they
  /// both have.
  String get trackerPlaceholder;

  String get theTracker;
  String get deleteTracker;

  /// The row a tracker has where a task has "Fällig am", and the three rhythms
  /// behind it.
  ///
  /// The hints matter more here than on most pickers: [rhythmWeekdays] and
  /// [rhythmTimesPerWeek] are two different *kinds* of promise, and a household
  /// that reads them as two ways of saying the same thing will pick the wrong
  /// one and find it nags on days they never chose.
  String get trackerRhythm;
  String get rhythmDaily;
  String get rhythmDailyHint;
  String get rhythmWeekdays;
  String get rhythmWeekdaysHint;
  String get rhythmTimesPerWeek;
  String get rhythmTimesPerWeekHint;
  String get whichDays;
  String get howOften;

  /// "4-mal pro Woche". Both languages special-case one, because "1-mal" and
  /// "1 times" are the kind of wrong that makes a careful app look careless.
  String timesPerWeekValue(int times);

  /// Why a weekly tracker never says "heute dran": the week is what counts, and
  /// it can only be missed once Sunday has passed. Worth a sentence, because it
  /// is the one rule a user cannot infer from the row.
  String get timesPerWeekExplainer;

  /// The Board's tracker card, above the dated sections.
  String get trackersTitle;

  /// "2 von 4 diese Woche" — a weekly tracker's whole state, since it is never
  /// due on any particular day.
  String weekProgressLabel(int done, int target);

  /// The streak, counted in whatever period the rhythm uses. Separate strings
  /// rather than one with a unit, because a plural rule is not a word that can
  /// be swapped in.
  String streakDays(int days);
  String streakWeeks(int weeks);

  /// What the header grid says before the household keeps anything. Without it
  /// the change lands as a wall of blank squares where a filled chart used to
  /// be, which reads as lost data rather than as a chart waiting for its first
  /// tracker.
  String get trackerGridEmpty;

  /// The row that folds the rest of the household's trackers into the Board's
  /// card — "3 weitere Tracker". Counting them in the label rather than saying
  /// "Alle anzeigen" is the point: it tells you there is something there before
  /// you tap, which "Alle" does not.
  String moreTrackers(int count);

  // ------------------------------------------------- one tracker's screen --
  //
  // Opened by tapping a tracker on the Board. Everything here reports on that
  // one rhythm, which is what separates it from the header grid: there
  // "geschafft" is an average over the household's trackers, here it is a fact
  // about this one.

  /// Heads the chart card. Not "Statistik": the card is a record of what
  /// happened, and a family app that starts grading a household on its habits
  /// stops being pleasant very quickly.
  String get trackerHistory;

  /// "8 von 12 Wochen geschafft" — the weekly-count answer to
  /// [trackerDaysDone], counted in the period that rhythm actually promises.
  String trackerWeeksDone(int done, int total);

  /// "3 von 4" beside one week's bar. Bare on purpose: the row it sits on
  /// already says which week, where [weekProgressLabel] has to say "diese
  /// Woche" because nothing around it does.
  String weekDoneOfTarget(int done, int target);

  /// The three readings of a square, spelled out under the chart. Colour alone
  /// cannot distinguish "nicht geplant" from "verpasst" for everybody who has
  /// to read it, and those two are the pair that matters.
  String get trackerLegendKept;
  String get trackerLegendMissed;
  String get trackerLegendNotDue;

  /// Names the seven-day strip: what it is *for*, not what it shows. "Letzte 7
  /// Tage" would describe a picture; the household came here to correct a day.
  String get trackerBackfillTitle;

  /// Says the squares can be tapped. Back-filling is the reason the chart is
  /// interactive at all, and an affordance nobody finds is one that isn't
  /// there.
  String get trackerBackfillHint;

  /// The same news for the quarter grid, phrased so the two lines on the screen
  /// are not the identical sentence twice. The strip covers the week people
  /// actually forget in; the grid is where anything older is corrected.
  String get trackerBackfillOlderHint;

  /// What the chip says after a day was filled in or taken back. It names the
  /// day, because the thing that was tapped is a small circle among seven and a
  /// mis-tap is otherwise invisible — that is also why it carries an undo.
  String trackerDayFilledIn(String day);
  String trackerDayCleared(String day);

  /// The check-off row's label when today is not one of the rhythm's days —
  /// where a due day offers the circle. A Montag tracker on a Mittwoch is not
  /// behind on anything, and an empty circle would say it was.
  String get trackerNotDueToday;

  /// When the tracker started. It is the left edge of every chart on the
  /// screen, so it is worth stating rather than leaving as the point the
  /// squares happen to begin.
  String get trackerStartedOn;

  String get trackersLoadFailed;
  String get trackerSaveFailed;
  String get trackerDeleteFailed;
  String get trackerCheckFailed;
  String get trackerRestoreFailed;

  /// Refused at the sheet rather than by the database: a tracker on no days at
  /// all is not a rhythm somebody is part-way through typing.
  String get pickAtLeastOneDay;

  String get trackerCreated;
  String get trackerUpdated;
  String get trackerDeleted;

  String get noOpenTasks;
  String get addTask;
  String get tasksLoadFailed;
  String get taskSaveFailed;
  String get changeSaveFailed;
  String get saveFailed;
  String get someDoneTasksNotDeleted;
  String get doneTasksDeleteFailed;
  String get taskDeleteFailed;

  /// Confirmation chips (`showConfirmChip`) — the short past-tense counterpart
  /// to the failure messages above.
  String get taskCreated;
  String get taskUpdated;
  String get taskDeleted;
  String get taskRestoreFailed;

  // ------------------------------------------------------------------ box --
  String get boxTitle;
  String get searchBoxesAndItems;
  String get searchBoxesAndItemsLong;
  String get boxes;
  String get items;
  String get noBoxesYet;
  String matchCount(int count);
  String itemCount(int count);
  String get newBox;
  String get editBox;
  String get boxName;
  String get placeExample;
  String get theBox;
  String get boxLabel;
  String get tapAboveToAddFirst;
  String get newItem;
  String get editItem;
  String get itemName;
  String get sizeExample;
  String get itemNotePlaceholder;
  String get deleteItem;
  String get addItemPlaceholder;
  String get empty;
  String emptyWithPlace(String place);
  String itemsWithPlace(int count, String place);
  String get boxesLoadFailed;
  String get boxSaveFailed;
  String get boxDeleteFailed;
  String get itemSaveFailed;
  String get itemDeleteFailed;
  String get itemDeleted;
  String get itemRestoreFailed;
  String get itemCreated;
  String get boxCreated;
  String get boxUpdated;
  String get boxDeleted;
  String get boxRestoreFailed;

  // ----------------------------------------------------------------- list --
  String get listsTitle;
  String get searchListsAndItems;
  String get searchListsAndItemsLong;
  String get noListsYet;
  String doneInList(String list);
  String inList(String list);
  String get newList;
  String get editList;
  String get whichKindOfList;
  String get groceries;
  String get otherKind;
  String get listName;
  String get theList;
  String get allDone;
  String remaining(int count);
  String get listLabel;
  String doneWithCount(int count);
  String get deleteDone;
  String get allItems;
  String get itemLabel;
  String attachmentCount(int count);
  String get searchOnAmazon;
  String get photo;
  String get camera;

  /// The shop page an article is about — the row in the item menu, the title of
  /// its sheet, the hint in the field and the note under it. A link is *set* in
  /// the sheet and taken off again with [removeItemLink]: an empty field leaves
  /// the sheet's check greyed rather than counting as a removal, so a cleared
  /// field can't quietly throw the link away. [itemLinkInvalid] is what a
  /// string that is no web address gets.
  String get itemLink;
  String get removeItemLink;
  String get itemLinkMessage;
  String get itemLinkHint;
  String get itemLinkSaved;
  String get itemLinkInvalid;
  String get listsLoadFailed;
  String get listSaveFailed;
  String get listDeleteFailed;
  String get listCreated;
  String get listUpdated;
  String get listDeleted;
  String get listRestoreFailed;
  String get someDoneItemsNotDeleted;
  String get doneItemsDeleteFailed;

  // ------------------------------------------------------------- calendar --
  String get calendarTitle;

  /// The label over Home's chip row, where Kalender prints the visible month.
  /// Home is one day rather than a grid of them, so it names that instead — see
  /// `_MonthYearRow`.
  String get yourDay;
  String get all;

  /// The filter row's last chip, the one that lays the Board's to-dos over the
  /// calendar. Plural where every other chip in that row is a name, because it
  /// stands for a whole kind of thing rather than for somebody.
  ///
  /// The same word in both languages: "To-do" is what the Board calls one
  /// ([kindTask]), in German as much as in English, and a chip reading
  /// "Aufgaben" over rows that say "To-do" would be two names for one thing.
  String get todosChip;

  /// The rail beside a to-do in the agenda, where an appointment prints its
  /// clock time. A due date is a day and carries no time, so there is nothing to
  /// print there — and "Ganztägig" would be a lie of a different kind, since the
  /// to-do does not occupy the day, it is merely owed by the end of it.
  String get dueRailLabel;
  String get newEvent;
  String get editEvent;
  String get startsAt;
  String get endsAt;

  /// The repeat card in the event form, and the "Wiederholt sich" the detail
  /// sheet prints on an occurrence of a series.
  ///
  /// [repeatWeekly] and [repeatBiweekly] are handed the start's own weekday
  /// name, because the rule has no day of its own — see [EventRepeat].
  /// [repeatMonthly] and [repeatYearly] stay unqualified for the same reason:
  /// the day of the month is the one the appointment already starts on.
  /// Deliberately its own string rather than the settings "Wiederholen" that
  /// happens to read the same in both languages today. That one replays the
  /// welcome tour; a rename there must not quietly relabel a recurrence rule.
  String get eventRepeat;
  String get repeatNever;
  String get repeatDaily;
  String repeatWeekly(String weekday);
  String repeatBiweekly(String weekday);
  String get repeatMonthly;
  String get repeatYearly;
  String get repeatEnds;

  /// The line under the repeat sheet's start row, saying why the start is
  /// standing there at all: every rule but "Täglich" is read off it.
  String get repeatFollowsStart;

  /// The end date as the form's repeat row carries it, after the rule and a
  /// middle dot: "Jeden Montag · bis 15. Nov".
  String repeatUntilDate(String date);
  String get repeats;

  /// Why the repeat card has nothing to tap on an event that already repeats: a
  /// provider hands back expanded occurrences and never the rule behind them,
  /// so the app can show that an appointment comes round without being able to
  /// say how often.
  String get repeatNotEditable;

  /// The two-way question asked before a repeating appointment is changed or
  /// deleted, and the two answers.
  String get repeatingEvent;
  String get changeRepeatingEventBody;
  String get deleteRepeatingEventBody;
  String get thisEventOnly;

  /// Why "ganze Serie" and a different calendar cannot both be true — see
  /// `CalendarNotifier.saveEvent`.
  String get seriesCannotMoveCalendar;
  String get wholeSeries;
  String get noEventsThisDay;
  String get addEvent;
  String get eventsPerCalendar;

  /// The two day-off keys in the month grid's legend, and the two washes they
  /// explain. **Striped** is a [publicHoliday] — one of the Feiertage
  /// [lib/data/german_holidays.dart] works out from the household's Bundesland;
  /// **flat** is a [schoolHoliday], a day inside the subscribed Ferien feed.
  /// Each key only appears once its wash can.
  String get publicHoliday;
  String get schoolHoliday;

  /// The name of one Feiertag, as the day detail prints it. German first,
  /// because that is the name it has; the English side is the customary
  /// translation rather than an official one.
  String germanHolidayName(GermanHoliday holiday);
  String eventCount(int count);
  String get eventLabel;

  /// The two rows of the event sheet's "hang something off this appointment"
  /// card. They name the *destination* tab ("Liste", "To-do"), not the verb,
  /// because the row already reads as an action and the question the user has
  /// is which of the two screens it lands on.
  String get createListFromEvent;
  String get createTaskFromEvent;

  /// Heads the card those two rows sit in, so the sheet's two link cards are
  /// told apart by a word as well as by the tile under it.
  ///
  /// Deliberately **not** a third "zum Termin": the rows under it already say
  /// it twice, and the heading's whole job is to be the short thing you read
  /// first. It is the verb to [linkedToEvent]'s participle — "Neu anlegen"
  /// over the card that makes one, "Zum Termin angelegt" over the card of what
  /// already exists.
  String get createForEvent;

  /// The right-hand word on those rows once the thing exists, which is what
  /// greys them out — one list and one task per appointment, and the card above
  /// is holding the one that was made. Without it the row is grey for no stated
  /// reason, which reads as broken rather than as done.
  String get alreadyCreated;

  /// Both directions of the link between an appointment and the lists and tasks
  /// hung off it.
  ///
  /// [linkedToEvent] heads the event sheet's card of what already exists, so
  /// that "Liste zum Termin erstellen" stops being offered for a list that is
  /// already there. [linkedEventLabel] is the same fact read from the other end,
  /// on the task or the list, where the word has to name the *destination* —
  /// tapping it leaves for Kalender.
  String get linkedToEvent;
  String get linkedEventLabel;

  /// Bare "Erledigt". The app had the word only inside a longer phrase, and a
  /// linked task's row needs it on its own.
  String get doneLabel;
  String get openInCalendar;
  String linkedListCount(int count);
  String linkedTaskCount(int count);
  String get route;
  String get reminder;
  String get deleteEvent;
  String get deleteEventQuestion;
  String deleteEventBody(String title);
  String get untitledEvent;
  String reminderMinutesBefore(int minutes);
  String get calendarLoadFailed;
  String get eventNeedsTitle;
  String get eventSaveFailed;
  String get calendarNotEditable;
  String get eventDeleteFailed;
  /// The pending chip's line while a create is still in flight. Two phases,
  /// because the wait has two: `calendar-write` goes out to Google, Outlook or
  /// the CalDAV server, and then `calendar-events` re-reads every connected
  /// calendar — the app stores no events, so the new one cannot appear until
  /// that second call brings it back.
  ///
  /// The named form is what the user sees; [eventBeingCreated] only covers the
  /// case where the calendar has gone from under the draft.
  String eventBeingCreatedIn(String calendar);
  String get eventBeingCreated;

  String get eventCreated;
  String get eventUpdated;
  String get eventDeleted;
  String get eventRestoreFailed;
  String get calendarNoLongerAvailable;
  String get noWritableCalendar;
  String get noHouseholdFound;
  String get eventSaveFailedRemote;

  /// `Ganztägig`, `3 Tage`, `2 Std 30`, `45 Min`.
  String get allDayDuration;
  String durationDays(int days);
  String durationHours(int hours);
  String durationHoursMinutes(int hours, int minutes);
  String durationMinutes(int minutes);

  /// The `–` range under an event, with the German trailing `Uhr`.
  String timeRange(String from, String to);

  // -------------------------------------------------------------- weather --
  /// `18°`. Both languages print Celsius — Open-Meteo is asked for metric and
  /// the app is German-market — so this exists to keep the degree sign in one
  /// place, not because the two disagree today.
  String temperature(int degrees);

  /// The eight WMO buckets in `WeatherCondition`. Day and night share a label:
  /// a clear night is still "Klar", and only the icon changes.
  String get weatherClear;
  String get weatherPartlyCloudy;
  String get weatherCloudy;
  String get weatherFog;
  String get weatherDrizzle;
  String get weatherRain;
  String get weatherSnow;
  String get weatherStorm;

  // ------------------------------------------------------- calendar setup --
  String get connectCalendars;

  /// The two groups the provider list is split into: the accounts a household
  /// signs in to or pastes a link from, and the calendars that need no account
  /// at all — the Bundesland's Ferien, the street's Abfuhr, a published link.
  ///
  /// Not "öffentlich": the vendorless tile takes any calendar link, and a
  /// Verein's tokenised one is no more public than a mailbox. What is true of
  /// all three is that there is nothing to sign in to.
  String get calendarAccountsGroup;
  String get noAccountGroup;
  String get connectCalendarsIntro;
  String get connectCalendarsAdminNote;
  String get noCalendarsConnected;

  /// The empty state on a provider's own page, where the button under it is the
  /// only thing to do — so it names that button rather than describing the void.
  String noProviderCalendarYet(String provider);
  String get loadingEllipsis;
  String get notSyncedYet;
  String get syncedJustNow;
  String syncedMinutesAgo(int minutes);
  String syncedHoursAgo(int hours);
  String syncedDaysAgo(int days);
  String get actionNeeded;
  String get connected;
  String calendarCount(int count);

  /// The sheet a connected calendar's row opens: its name, whose day it is,
  /// and the way to take it away. Names the *calendar*, not an action, because
  /// it is all three at once.
  String get calendarSettings;

  String get renameCalendar;
  String get renameCalendarBody;
  String get householdOnly;
  String get savingEllipsis;
  String get nameChanged;
  String get removeCalendarQuestion;
  String get disconnectQuestion;
  String removeCalendarBody(String name);
  String get accessRevokedToo;

  /// Removing *one* calendar out of a connected account — the account, and the
  /// other calendars on it, are untouched.
  String get accountStaysConnected;
  String get householdOnlyOthersKeep;
  String get credentialsDeleted;
  String get connectionNeedsAttention;
  String get refreshingEllipsis;
  String providerNotSetUp(String provider);
  String get browserCouldNotOpen;
  String connectProvider(String provider);
  String redirectNotice(String provider);
  String get openingEllipsis;
  String signInWithProvider(String provider);
  String get comeBackWhenDone;
  String get connectedDot;
  String calendarsFoundPickThem(int count);
  String get nameYourCalendarBody;

  /// The same line for an account whose calendars were picked one by one, so
  /// the naming step is naming several of them.
  String get nameEachCalendarBody;
  String get whichCalendars;
  String get whichCalendarsHint;
  String get readOnlyCalendar;
  String get pickAtLeastOneCalendar;
  String get selectAll;
  String get deselectAll;
  String calendarsSelected(int count);
  String get loadingCalendarsEllipsis;
  String get appPasswordHint;
  String get createAppPassword;
  String get school;
  String get schoolAddressHint;
  String get username;
  String get appleId;
  String get icloudEmailHint;

  // -- GMX and WEB.DE
  //
  // One system, two brands: 1&1 Mail & Media runs both on the same CalDAV
  // server. The copy differs only in the name, and the password note is the one
  // sentence that matters — an application password is revocable on its own and
  // opens a calendar, where the account password opens the whole mailbox.
  String get emailAddress;
  String get oneAndOneAppPasswordHint;
  String get appPasswordPlaceholder;
  String get iservPassword;
  String get checkingEllipsis;
  String get connect;
  String get bundesland;
  String get holidaysIntro;
  String get pickABundesland;
  String schoolHolidaysOf(String state);
  String holidaysSelectedBody(String state);
  String get wasteIntro;
  String get houseNumber;
  String get multipleDistrictsHint;
  String wasteFor(String street);
  String wasteForTown(String town);
  String noVendorForTown(String town);
  String get checkingLinkEllipsis;

  // -- calendars connected by a pasted link (IServ, WebUntis, any iCal feed)
  //
  // The link is created wherever the calendar lives and copied over by hand:
  // neither IServ nor WebUntis offers a way to list or mint one from outside,
  // so these strings walk the user through where to click. They name real menu
  // items in a German school platform, so the English side translates the
  // sentence and keeps the menu path recognisable. The generic tile has no menu
  // path and gets [icalLinkNote] instead.
  List<String> get iservLinkSteps;
  List<String> get webuntisLinkSteps;

  /// Shown in place of the numbered steps on the generic iCal tile, which has
  /// no menu path to name — the link comes from whatever published it.
  String get icalLinkNote;

  // -- a calendar handed over as a file rather than as a link
  //
  // The case these exist for is a German waste vendor outside the six in
  // `abfall.ts`: it publishes `abfuhr2027.ics` as a download and offers nothing
  // to subscribe to, so the household has the calendar and no link. Same for a
  // Verein that mails the fixture list round.
  //
  // The copy has one job beyond naming the button, and it is [calendarFileNote]
  // and [calendarFileCoversTo]: a file is a snapshot and stops on a particular
  // day, where a link keeps itself current. Saying so at the moment of choosing
  // is the difference between a calendar that quietly goes empty next January
  // and one the household knows to replace.
  String get uploadCalendarFile;
  String get uploadCalendarFileHint;
  String get calendarFileNote;
  String get checkingFileEllipsis;
  String get calendarFileUnreadable;

  /// "Die Datei reicht bis zum 31. Dezember 2026." — over the naming step, and
  /// again under the calendar's row in Settings.
  String calendarFileCoversTo(String date);

  /// What was picked, on the step it was picked from: "abfuhr2027.ics".
  String calendarFileChosen(String name);

  /// A full date in this language's own order — "31. Dezember 2026" against
  /// "December 31, 2026". Here rather than in a formatter beside [formatTime]
  /// because the order *is* the translation, and a shared function would have
  /// to ask the language which way round it goes anyway.
  String longDate(DateTime at);
  String get pasteCalendarLink;
  String get pasteCalendarLinkHint;
  String get whoseCalendar;
  String get whoseCalendarHint;
  String get whoseCalendarPlaceholder;
  String get linkedCalendarName;
  String get linkedCalendarNameHint;
  String get nameThisCalendarFirst;
  String get whoseCalendarFirst;
  String get addAnotherCalendar;
  String get addAnotherCalendarBody;
  String get schoolCalendars;
  String get removeCalendar;
  String get linkStaysAtSchool;
  String get connectWithLogin;
  String get connectWithLoginBody;
  String get linkedCalendarsNote;
  String eventsFoundAtLink(int count);
  String get noEventsAtLinkYet;

  String get calendarLinkIcs;
  String get calendarLinkHint;
  String get pasteLinkHere;
  String get noEventsAtThatLink;
  String get yourAddress;
  String get yourAddressHint;
  String get pickYourAddressFirst;
  String get addressPlaceholder;
  String get searchingAddresses;
  String get noAddressFound;
  String get searchingVendor;
  String get tapToRetry;
  String foundVendor(String where);
  String get noVendorFoundTapForLink;
  String get askingNearbyVendors;
  String get connectionStartFailed;
  String get connectionsLoadFailed;
  String get connectingEllipsis;
  String get calendarConnected;
  String get calendarNameInAporah;

  // --------------------------------------------------------- provider meta --
  /// The other four provider names are brands and stay as they are.
  String get providerIcalLabel;
  String get providerHolidaysLabel;
  String get providerWasteLabel;
  String get providerGoogleDesc;
  String get providerOutlookDesc;
  String get providerIcloudDesc;
  String get providerGmxDesc;
  String get providerWebdeDesc;
  String get providerIservDesc;
  String get providerWebuntisDesc;
  String get providerIcalDesc;
  String get providerHolidaysDesc;
  String get providerWasteDesc;

  // --------------------------------------------------------------- shares --
  String get shareTitle;
  String shareIntro(String resource);
  String shareIntroSecond(String noun);
  String get emailOptional;
  String get editingAllowed;
  String get canCheckAndAdd;
  String get canOnlyView;
  String get createLink;
  String get sendInvite;
  String get guests;
  String get activeLinks;
  String get notSharedYet;
  String get newLink;
  String get copied;
  String get copyLink;
  String get linkShownOnce;
  String get mayEdit;
  String get viewOnly;
  String usedTimes(int count);
  String get linkExpired;
  String get linkUsedUp;
  String get shareLink;
  String get revoke;
  String get guest;
  String get sharesLoadFailed;
  String get shareLinkCreateFailed;
  String get linkRevokeFailed;
  String get guestRemoveFailed;

  // ----------------------------------------------------------- visibility --
  String get forWhom;
  String get everyone;
  String get onlyMe;
  String get selected;

  /// The `custom` badge once the names no longer fit — "3 Personen".
  String peopleCount(int count);
  String wholeFamilySees(String noun);
  String onlyYouSee(String noun);
  String youAndOthersSee(String names, String noun);

  /// `a, b und c` / `a, b and c`.
  String joinNames(List<String> names);

  // ------------------------------------------------------------ icon pick --
  String get symbol;
  String get change;
  String get chooseSymbol;

  /// The empty photo row on a box / box-item sheet. It says "upload" rather
  /// than "Foto" because the row with a picture on it is the one called
  /// "Foto" — this one is the invitation, not the thing.
  String get uploadImage;

  /// A box, a box item or a list article can carry a photograph instead of a
  /// symbol — see `data/repositories/photo_repository.dart`. Both failures are
  /// snacked and neither is fatal: the row falls back to its symbol.
  String get photoUploadFailed;
  String get photoRemoveFailed;
  String get searchSymbolOrShop;
  String get matches;
  String nothingFoundFor(String query);
  String get suggestionFromName;
  String get shops;
  String get showLess;
  String allMoreShops(int count);
  String noMatchesFor(String query);

  // ------------------------------------------------------------- settings --
  String get settingsTitle;
  String get searchSettings;
  String get profile;
  String get familyMembers;
  String get language;
  String get darkMode;

  String get welcomeTour;
  String get repeat;
  String get signOut;
  String noSettingFoundFor(String query);
  String get notConnected;
  String get displayName;
  String get avatarColour;
  String get removePhoto;
  String get avatarUploadFailed;
  String get avatarRemoveFailed;
  String get adminsManageFamily;
  String get familyMembersDesc;
  String get familyMembersDescAdmin;
  String get nobodyInHouseholdYet;
  String get inviteMember;
  String pendingWithRole(String role);
  String get inviteFamilyMember;
  String get inviteValidity;

  /// The confirmation the invite sheet turns into once the invitation exists.
  String get inviteSending;
  String get inviteSentTitle;
  String get inviteCreatedTitle;
  String inviteSentTo(String email);
  String inviteMailNotSent(String email);
  String invitedAsRole(String role);
  String inviteValidUntil(String date);

  /// The toast the onboarding step shows once an invitation has actually gone
  /// out. Names the person rather than saying "Einladung gesendet", because the
  /// step sends several in a row and the chip is the only thing that says
  /// *which* one landed.
  String invitedPerson(String who);

  /// Shown under the onboarding invite card while an address sits unsent in the
  /// field, next to the "Weiter" it is holding.
  String get tapSendToInvite;

  String get youCaps;
  String get removeMemberQuestion;
  String removeMemberBody(String name);
  String get languagePageDesc;
  String get setUpProfile;
  String get languageGerman;
  String get languageEnglish;
  String get languageGermanRegion;
  String get languageEnglishRegion;

  /// Search keywords behind each settings row — typed, not shown.
  String get searchTermsProfile;
  String get searchTermsFamily;
  String get searchTermsCalendar;
  String get searchTermsApplePay;
  String get searchTermsLanguage;
  String get searchTermsDarkMode;
  String get searchTermsTour;
  String get searchTermsSignOut;

  // ----------------------------------------------------------------- roles --
  String get roleAdmin;
  String get roleMember;
  String get roleChild;

  // ----------------------------------------------------------- onboarding --
  String get onboardSetUpFamily;
  String get onboardSetUpFamilyBody;
  String get onboardInviteTitle;
  String get onboardInviteBody;
  String get adult;
  String get child;
  String get onboardAddressTitle;
  String get onboardAddressBody;
  String get address;
  String get wasteCalendar;
  String get holidayCalendar;
  String get onboardFindingCalendars;
  String get onboardFoundForYou;
  String get onboardNothingForAddress;
  String get onboardNotFoundHere;
  String get onboardRenameLater;
  String get onboardConnectMoreHint;
  String get onboardConnectingCalendars;
  String get calendarsConnectFailed;
  String get onboardReady;
  String get onboardReadyBody;
  String get noInvitesSent;
  String invitedCount(int count);

  // ----------------------------------------------------------------- auth --
  String get welcomeToAporah;
  String get welcomeBack;
  String get signUpBlurb;
  String get signInBlurb;
  String get yourName;
  String get atLeast8Chars;
  String get createAccount;
  String get signIn;
  String get haveAccountAlready;
  String get newHereCreateAccount;
  String get forgotPassword;
  String get almostThere;
  String confirmMailSent(String email);
  String get toSignIn;
  String get pleaseEnterName;
  String get noConnectionTryAgain;
  String get pleaseEnterEmailFirst;
  String get resetMailSent;
  String get wrongCredentials;
  String get confirmEmailFirst;
  String get accountExists;
  String get passwordTooShort;
  String get passwordLeaked;
  String get tooManyAttempts;
  String get emailLooksInvalid;
  String get signInFailed;

  // ----------------------------------------------------------------- family --
  String get noHouseholdForAccount;
  String get householdLoadFailed;
  String get enterValidEmail;
  String get inviteSendFailed;
  String get roleChangeFailed;
  String get memberRemoveFailed;
  String get inviteRevokeFailed;

  // --------------------------------------------------- calendar ownership --

  /// Settings → a connected calendar → "Zuordnen": whose calendar this is, i.e.
  /// which person's chip it appears under.
  ///
  /// Never say "sichtbar" in any of these. Assigning a calendar to somebody does
  /// not hide it from anybody — every calendar stays visible to the whole
  /// household, and a household that read this as a privacy control would file
  /// their calendars wrong and then wonder why everyone could still see them.
  String get assignCalendar;
  String assignCalendarBody(String calendar);

  /// The "Familie" row, which is the one that could be misread as a person.
  String get assignCalendarFamilyHint;

  /// The last row of the owner card: the field for somebody with no account, a
  /// kindergarten child most often. It is the field's own hint now that the row
  /// carries no heading, so it names the person rather than the typing —
  /// "Andere Person", not "Name eingeben".
  String get assignCalendarNewPerson;

  /// The line under the picker that says what it is not.
  String get assignCalendarNotVisibility;

  String get assignCalendarFailed;

  /// Falls back for the household's own name while it is still loading.
  String get family;

  /// Somebody who is in the household but has no login — a schoolchild whose
  /// calendar was assigned to them, a pre-schooler with a Kindergarten
  /// calendar. Shown wherever they sit beside people who *do* have an account,
  /// because otherwise the two are indistinguishable.
  String get noAccountYet;

  /// Settings → Familienmitglieder: the household's own name, which is also the
  /// label on the "Familie" chip in Kalender and on the Board.
  String get familyName;
  String get familyNameHint;
  String get renameFamily;
  String get renameFamilyBody;
  String get familyRenameFailed;

  // ------------------------------------------------------------------- Home

  /// The Home island — the one line above the filter chips that used to read
  /// only "Dein Tag". It says the single most pressing thing about **today**,
  /// and these are in priority order: an overdue to-do outranks an open one,
  /// which outranks an unticked tracker, which outranks the next appointment.
  String homeOverdue(int count);
  String homeOpenToday(int count);
  String homeTrackersLeft(int count);

  /// The next appointment still to come today: its clock time and its name.
  String homeNextUp(String time, String title);

  /// Today had something to do and all of it is done. Not the same as having
  /// nothing at all, which falls back to [yourDay].
  String get homeAllDone;

  /// What the island says on a day that is not today: how much is on it. The
  /// date itself comes from [weekdayWithDateShort].
  String homeDayEntries(int count);
  String get homeDayEmpty;

  /// What the island says while the day is still arriving — the state before
  /// every one of the above, and the only one that is about the app rather than
  /// about the household.
  String get homeThinking;
  String get homeHintThinking;

  /// The quiet second line under each of those, naming what is being counted.
  /// "Noch 1 offen" is a number without a noun on its own, and the island is
  /// the one place in the app where the reader has no row, no icon and no
  /// section heading to tell them which of four kinds of thing it means.
  String get homeHintSetup;
  String get homeHintOverdue;
  String get homeHintOpen;
  String get homeHintTrackers;
  String get homeHintNext;
  String get homeHintDone;

  // The sections below the day card.
  String get homeOpenSection;
  String get homeTrackerSection;
  String get homeListsSection;
  String get homeShowAll;

  /// The day card's fold, on a day with more entries than it shows at once.
  String homeMoreEntries(int count);

  /// How many articles on a shopping list are still unticked.
  String homeListOpenItems(int count);

  // ------------------------------------------------------- First steps

  /// The setup checklist, shown in the island and its card until every step is
  /// done. Each step is derived from live state, so none of these is a label on
  /// a stored flag.
  String get firstStepsTitle;
  String firstStepsProgress(int done, int total);
  String get firstStepCalendar;
  String get firstStepCalendarBody;
  String get firstStepFamily;
  String get firstStepFamilyBody;
  String get firstStepTodo;
  String get firstStepTodoBody;
  String get firstStepTracker;
  String get firstStepTrackerBody;
  String get firstStepList;
  String get firstStepListBody;

  // ------------------------------------------------------- Ausgaben

  /// The fifth tab: the shelf that holds Boxen and Ausgaben.
  String get navMore;

  /// Number formatting, which follows the interface language rather than the
  /// phone — the same rule as `formatTime` and the month names. German writes
  /// `1.234,56 €`, English `€1,234.56`, and the symbol changes sides.
  String get decimalSeparator;
  String get thousandsSeparator;

  /// What a chart axis shortens a thousand and a million to. German writes
  /// `99,9k` like English but says `1,4 Mio.` where English says `1.4M`.
  String get thousandsSuffix;
  String get millionsSuffix;
  String money(String amount, String symbol);
  String percent(int value);

  String get spendTitle;
  String get spendAdminsOnly;
  String get spendEmpty;
  String get spendEmptyEnrolled;

  /// The three ways the breakdown card cuts the money up. They are the rows of
  /// one menu as well as the card's own heading, so they read as a parallel set
  /// — "Nach …" all three times — rather than as three unrelated titles.
  String get spendByCategory;
  String get spendTopMerchants;
  String get spendByMember;

  String get spendOtherCategories;
  String get spendAllPurchases;
  String get spendFormerMember;

  /// How many payments — short, because it sits under a name in a row rather
  /// than in a sentence.
  String spendCountShort(int count);

  /// The same noun with the number taken off it, for the donut's hole, where
  /// the count is set under its own label rather than beside it. Still takes
  /// the count, because the word is the one that agrees with it.
  String spendPaymentsWord(int count);

  /// What the three chart segments are called. Never drawn: the segments carry
  /// a glyph each, and these are what VoiceOver reads instead.
  String get spendChartTrend;
  String get spendChartBars;
  String get spendChartRing;

  /// The range slicer's four segments. Abbreviated hard — they sit four across
  /// a phone — and the long form is [spendRangeThisWeek] and its three
  /// neighbours, which caption the total instead.
  String get spendRangeWeek;
  String get spendRangeMonth;
  String get spendRangeHalfYear;
  String get spendRangeYear;

  String get spendRangeThisWeek;
  String get spendRangeThisMonth;
  String get spendRangeLastSixMonths;
  String get spendRangeThisYear;

  /// The calendar button beside the slicer, and the title of the picker it
  /// opens.
  String get spendRangePick;

  /// The bar chart's caption — the dashed line drawn through it, in words.
  /// Which of the two depends on whether the bars are days or months.
  String spendAveragePerDay(String amount);
  String spendAveragePerMonth(String amount);

  /// "Alle Ausgaben" — the unfiltered metric, beside the two `spendKind`
  /// labels in the picker on the total.
  String get spendMetricAll;

  /// The card's way to the page listing every row of a breakdown rather than
  /// the five it can hold.
  String get spendShowAll;

  /// The same link where the card also had a count to lose — the payments list,
  /// whose heading said how many there were before the link took the slot. One
  /// phrase rather than a count and a link side by side, which on a phone is
  /// three pieces of furniture in a heading that holds two.
  String spendShowAllCount(int count);

  // -- The status island under the page title. One sentence, and a second line
  //    saying what it counts — the same pair Home's day island prints.

  String get spendIslandThinking;
  String get spendIslandThinkingHint;

  /// The line under "2 Zahlungen brauchen dich kurz". The title itself is
  /// [spendReviewTitle], shared with the rows that fold out of it.
  String get spendIslandReviewHint;

  String get spendIslandNothing;

  String spendIslandUp(int percent);
  String spendIslandDown(int percent);
  String get spendIslandVsPrevious;

  /// Which category is carrying the range, and how much of it.
  String spendIslandTop(String category);
  String spendIslandTopHint(int percent);

  String get spendAdd;
  String get spendEdit;
  String get spendAmount;
  String get spendDate;
  String get spendCategory;

  /// The detail sheet's header — the word for one payment, not the page's
  /// plural and not the merchant's own name, which has the body's full width
  /// right below it.
  String get spendLabel;

  /// The same question [spendKindQuestion] asks, as a label on a line that is
  /// only being read.
  String get spendKindLabel;
  String get spendPaidBy;
  String get spendCard;

  /// How the row arrived. Apple Pay is a brand and stays itself in both
  /// languages; the other value is a person at a keyboard.
  String get spendSourceLabel;
  String get spendSourceWallet;
  String get spendSourceManual;
  String get spendNote;

  /// The category picker's first row, and the form's default: the database
  /// names the category from the merchant. Not a category of its own — see
  /// `private.classify_merchant`.
  String get spendCategoryAuto;
  String get spendMerchantPlaceholder;
  String get spendNotePlaceholder;
  String get spendKindQuestion;
  String get spendKindBudget;
  String get spendKindExtra;
  String get spendNeedsMerchantAndAmount;
  String get spendDeleted;

  /// Rows the Apple Pay automation filed with an empty merchant or a zero
  /// amount — a known, unresolved defect in Apple's own Transaction trigger.
  String spendReviewTitle(int count);
  String get spendReviewBody;

  /// The same defect explained inside the payment itself, where "tap the row"
  /// is advice for somebody who already has.
  String get spendReviewDetail;

  String get spendLoadFailed;
  String get spendSaveFailed;
  String get spendDeleteFailed;
  String get spendEnrolFailed;

  String get spendWalletTitle;
  String get spendWalletIntro;

  /// The card's own action, and deliberately not "Fertig": tapping it does
  /// not finish anything, it enrols this phone and reveals the four steps in
  /// Shortcuts that are the other half of the setup.
  String get spendWalletEnable;
  String get spendWalletUnsupported;
  String get spendWalletEnabled;
  String get spendWalletActive;
  String get spendWalletInactive;
  String get spendWalletStepsTitle;
  String get spendWalletStep1;
  String get spendWalletStep2;
  String get spendWalletStep3;
  String get spendWalletStep4;
  String get spendWalletOpenShortcuts;

  /// The Apple Pay row in Settings and the page behind it, which holds the
  /// whole of setup: activating *this* phone, the steps that finish the job in
  /// Shortcuts, the phones the household has enrolled and taking one back.
  /// Ausgaben keeps one row that leads there.
  String get settingsApplePay;
  String get applePayPageDesc;
  String get spendWalletNoDevices;
  String get spendWalletNoDevicesHint;
  String get spendWalletDevicesLabel;
  String get spendWalletDeviceUnused;
  String spendWalletDeviceLastUsed(String date);
  String spendWalletDeviceCount(int count);
  String get spendWalletRevoke;

  String get spendCatGroceries;
  String get spendCatDrugstore;
  String get spendCatFuel;
  String get spendCatRestaurant;
  String get spendCatCafe;
  String get spendCatShipping;
  String get spendCatClothing;
  String get spendCatShopping;
  String get spendCatElectronics;
  String get spendCatTransport;
  String get spendCatEntertainment;
  String get spendCatHealth;
  String get spendCatHome;
  String get spendCatOther;
}
