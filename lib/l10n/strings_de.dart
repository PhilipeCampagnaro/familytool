import '../data/german_holidays.dart';
import '../models/grocery_unit.dart';
import '../theme/app_icons.dart';
import 'app_strings.dart';

/// German — the language Aporah was written in. Every string here is the exact
/// copy that used to sit inline in the screen that shows it, so switching to
/// German must be pixel-identical to the app before it had an `l10n/`.
class StringsDe extends AppStrings {
  const StringsDe();

  @override
  String get localeCode => 'de';
  @override
  bool get use24HourClock => true;

  // ---------------------------------------------------------------- dates --
  @override
  List<String> get monthNames => const [
    '',
    'Januar',
    'Februar',
    'März',
    'April',
    'Mai',
    'Juni',
    'Juli',
    'August',
    'September',
    'Oktober',
    'November',
    'Dezember',
  ];
  @override
  List<String> get monthShort => const [
    '',
    'Jan',
    'Feb',
    'Mär',
    'Apr',
    'Mai',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Okt',
    'Nov',
    'Dez',
  ];
  @override
  List<String> get weekdayShort => const ['So', 'Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa'];
  @override
  List<String> get weekdayLong => const [
    'Sonntag',
    'Montag',
    'Dienstag',
    'Mittwoch',
    'Donnerstag',
    'Freitag',
    'Samstag',
  ];
  @override
  List<String> get dayLetters => const ['M', 'D', 'M', 'D', 'F', 'S', 'S'];

  @override
  String dayMonth(int day, int month) => '$day. ${monthNames[month]}';
  @override
  String dayMonthShort(int day, int month) => '$day. ${monthShort[month]}';
  @override
  String todayWithDate(int day, int month) => 'Heute, ${dayMonth(day, month)}';
  @override
  String weekdayWithDate(int weekday, int day, int month) =>
      '${weekdayLong[weekday]}, ${dayMonth(day, month)}';
  @override
  String monthYear(int month, int year) => '${monthNames[month]} $year';
  @override
  String dateRange(String from, String to) => '$from\u00A0– $to';
  @override
  String dayRangeSameMonth(int fromDay, int toDay, int month) => '$fromDay. – $toDay. ${monthNames[month]}';
  @override
  String dayRangeCrossMonth(int fromDay, int fromMonth, int toDay, int toMonth) =>
      '$fromDay. ${monthNames[fromMonth]} – $toDay. ${monthNames[toMonth]}';
  @override
  String weekdayWithDateShort(int weekday, int day, int month) =>
      '${weekdayLong[weekday]}, $day. ${monthShort[month]}';

  // --------------------------------------------------------------- common --
  @override
  String get cancel => 'Abbrechen';
  @override
  String get delete => 'Löschen';
  @override
  String get edit => 'Bearbeiten';
  @override
  String get share => 'Teilen';
  @override
  String get close => 'Schließen';
  @override
  String get doneAction => 'Fertig';
  @override
  String get add => 'Hinzufügen';
  @override
  String get rename => 'Umbenennen';
  @override
  String get remove => 'Entfernen';
  @override
  String get disconnect => 'Trennen';
  @override
  String get undo => 'Rückgängig';
  @override
  String get restored => 'Wiederhergestellt';
  @override
  String get beingRestored => 'Wird wiederhergestellt …';
  @override
  String get reload => 'Erneut laden';

  @override
  String get showFullName => 'Vollständigen Namen anzeigen';

  @override
  String get hideFullName => 'Namen einklappen';

  @override
  String get notes => 'Notizen';
  @override
  String get addNotes => 'Notizen hinzufügen';
  @override
  String get name => 'Name';
  @override
  String get unknown => 'Unbekannt';
  @override
  String get next => 'Weiter';
  @override
  String get skip => 'Überspringen';
  @override
  String get back => 'Zurück';
  @override
  String get letsGo => 'Los geht\'s';
  @override
  String get today => 'Heute';
  @override
  String get allDay => 'Ganztägig';
  @override
  String get place => 'Ort';
  @override
  String get searchPlace => 'Ort oder Geschäft suchen';
  @override
  String get noPlacesFound => 'Keine Orte gefunden';
  @override
  String get quantity => 'Menge';
  @override
  String get unit => 'Einheit';
  @override
  // Die kurzen bleiben kurz: "kg" steht so auf jeder Packung, und eine Zeile
  // unter dem Artikel ist kein Ort für "Kilogramm".
  String unitName(GroceryUnit unit) => switch (unit) {
    GroceryUnit.piece => 'Stück',
    GroceryUnit.gram => 'g',
    GroceryUnit.kilogram => 'kg',
    GroceryUnit.milliliter => 'ml',
    GroceryUnit.liter => 'l',
    GroceryUnit.pack => 'Packung',
    GroceryUnit.can => 'Dose',
    GroceryUnit.bottle => 'Flasche',
    GroceryUnit.bunch => 'Bund',
    GroceryUnit.glass => 'Glas',
  };
  @override
  String get size => 'Größe';
  @override
  String get titleLabel => 'Titel';
  @override
  String get role => 'Rolle';
  @override
  String get nameOptional => 'Name (optional)';
  @override
  String get password => 'Passwort';
  @override
  String get calendar => 'Kalender';
  @override
  String get somethingWentWrong => 'Das hat gerade nicht geklappt.';
  @override
  String get noServerConnection => 'Keine Verbindung zum Server.';
  @override
  String get serverTooSlow => 'Der Server hat zu lange gebraucht. Versuch es bitte noch einmal.';
  @override
  String get notSignedIn => 'Kein angemeldeter Benutzer.';
  @override
  String get householdNotLoaded => 'Dein Haushalt ist noch nicht geladen.';

  // ------------------------------------------------------------------ nav --
  @override
  String get navHome => 'Home';
  @override
  String get navCalendar => 'Kalender';
  @override
  String get navLists => 'Listen';
  @override
  String get navBoard => 'Board';
  @override
  String get navBox => 'Box';
  @override
  String get navExpand => 'Navigation einblenden';

  // ---------------------------------------------------------------- board --
  @override
  String get boardTitle => 'Board';
  @override
  String doneCountSeparator(int count) => 'Erledigt · $count';
  @override
  String get newTask => 'Neues To-do';
  @override
  String get editTask => 'To-do bearbeiten';
  @override
  String get taskPlaceholder => 'Was ist zu tun?';
  @override
  String get dueLabel => 'Fällig';
  @override
  String get dueNone => '—';
  @override
  String get sectionOverdue => 'Überfällig';
  @override
  String get sectionToday => 'Heute';
  @override
  String get sectionTomorrow => 'Morgen';
  @override
  String get sectionThisWeek => 'Diese Woche';
  @override
  String get sectionLater => 'Später';
  @override
  String get sectionUndated => 'Ohne Datum';
  @override
  String get dueThisWeekend => 'Wochenende';
  @override
  String get dueNextWeek => 'Nächste Woche';
  @override
  String get duePickDate => 'Datum wählen …';
  @override
  String get dueTimeLabel => 'Uhrzeit';
  @override
  String get dueNoTime => 'Keine Uhrzeit';
  @override
  String get dueTimeNeedsDate => 'Zuerst ein Datum wählen';
  @override
  String get theTask => 'das To-do';
  @override
  String get deleteTask => 'To-do löschen';
  @override
  String get assigneeLabel => 'Zuständig';
  @override
  String get nobody => 'Niemand';
  @override
  String get me => 'Ich';
  @override
  String get nothingPlanned => 'Nichts geplant';
  @override
  String doneOfTotal(int done, int total) => '$done von $total erledigt';
  @override
  // Das englische Wort, weil es im Deutschen genauso gebraucht wird — "Verlauf"
  // wäre die Alternative, sagt aber nur "Historie" und nicht "dranbleiben".
  String get trackerTitle => 'Tracker';
  @override
  String trackerDaysDone(int done, int total) => '$done von $total Tagen geschafft';

  // ------------------------------------------------------------- Tracker --
  @override
  String get whatToCreate => 'Was möchtest du anlegen?';
  @override
  String get newEntry => 'Neu';
  @override
  String get kindTask => 'To-do';
  // Das englische Wort, wie schon bei [trackerTitle]: im Deutschen genauso
  // gebräuchlich, und "Gewohnheit" klingt nach Ratgeber statt nach Haushalt.
  @override
  String get kindTracker => 'Tracker';
  @override
  String get newTracker => 'Neuer Tracker';
  @override
  String get editTracker => 'Tracker bearbeiten';
  @override
  String get trackerPlaceholder => 'Woran willst du dranbleiben?';
  @override
  String get theTracker => 'den Tracker';
  @override
  String get deleteTracker => 'Tracker löschen';
  @override
  String get trackerRhythm => 'Rhythmus';
  @override
  String get rhythmDaily => 'Jeden Tag';
  @override
  String get rhythmDailyHint => 'Sieben Tage die Woche';
  @override
  String get rhythmWeekdays => 'An bestimmten Tagen';
  @override
  String get rhythmWeekdaysHint => 'Zum Beispiel montags und donnerstags';
  @override
  String get rhythmTimesPerWeek => 'So oft pro Woche';
  @override
  String get rhythmTimesPerWeekHint => 'Egal an welchen Tagen';
  @override
  String get whichDays => 'Welche Tage?';
  @override
  String get howOften => 'Wie oft?';
  @override
  String timesPerWeekValue(int times) => times == 1 ? 'Einmal pro Woche' : '$times-mal pro Woche';
  @override
  String get timesPerWeekExplainer =>
      'Es zählt die Woche, nicht der Tag. Nichts ist an einem bestimmten Tag fällig — gezählt wird, wenn die Woche am Sonntag zu Ende ist.';
  @override
  String get trackersTitle => 'Tracker';
  @override
  String get tasksTitle => 'To-dos';
  @override
  String weekProgressLabel(int done, int target) => '$done von $target diese Woche';
  @override
  String streakDays(int days) => days == 1 ? '1 Tag in Folge' : '$days Tage in Folge';
  @override
  String streakWeeks(int weeks) => weeks == 1 ? '1 Woche in Folge' : '$weeks Wochen in Folge';
  @override
  String get trackerGridEmpty => 'Noch nichts, woran du dranbleibst';
  @override
  String moreTrackers(int count) => count == 1 ? '1 weiterer Tracker' : '$count weitere Tracker';
  @override
  String get trackerHistory => 'Verlauf';
  @override
  String trackerWeeksDone(int done, int total) => '$done von $total Wochen geschafft';
  @override
  String weekDoneOfTarget(int done, int target) => '$done von $target';
  @override
  String get trackerLegendKept => 'geschafft';
  @override
  String get trackerLegendMissed => 'verpasst';
  @override
  String get trackerLegendNotDue => 'nicht geplant';
  @override
  String get trackerBackfillTitle => 'Nachtragen';
  @override
  String get trackerBackfillHint => 'Tippe einen Tag an, um ihn nachzutragen.';
  @override
  String get trackerBackfillOlderHint => 'Ältere Tage lassen sich direkt im Feld antippen.';
  @override
  String trackerDayFilledIn(String day) => '$day nachgetragen';
  @override
  String trackerDayCleared(String day) => '$day zurückgenommen';
  @override
  String get trackerNotDueToday => 'Heute nicht dran';
  @override
  String get trackerStartedOn => 'Gestartet am';
  @override
  String get trackersLoadFailed => 'Tracker konnten nicht geladen werden.';
  @override
  String get trackerSaveFailed => 'Der Tracker konnte nicht gespeichert werden.';
  @override
  String get trackerDeleteFailed => 'Der Tracker konnte nicht gelöscht werden.';
  @override
  String get trackerCheckFailed => 'Der Haken konnte nicht gespeichert werden.';
  @override
  String get trackerRestoreFailed => 'Der Tracker konnte nicht wiederhergestellt werden.';
  @override
  String get pickAtLeastOneDay => 'Wähle mindestens einen Tag aus.';
  @override
  String get trackerCreated => 'Tracker angelegt';
  @override
  String get trackerUpdated => 'Tracker aktualisiert';
  @override
  String get trackerDeleted => 'Tracker gelöscht';
  @override
  String get noOpenTasks => 'Keine offenen To-dos';
  @override
  String get addTask => 'To-do hinzufügen';
  @override
  String get tasksLoadFailed => 'To-dos konnten nicht geladen werden.';
  @override
  String get taskSaveFailed => 'Das To-do konnte nicht gespeichert werden.';
  @override
  String get changeSaveFailed => 'Die Änderung konnte nicht gespeichert werden.';
  @override
  String get saveFailed => 'Konnte nicht gespeichert werden.';
  @override
  String get someDoneTasksNotDeleted => 'Nicht alle erledigten To-dos konnten gelöscht werden.';
  @override
  String get doneTasksDeleteFailed => 'Die erledigten To-dos konnten nicht gelöscht werden.';
  @override
  String get taskDeleteFailed => 'Das To-do konnte nicht gelöscht werden.';
  @override
  String get taskCreated => 'To-do erstellt';
  @override
  String get taskUpdated => 'To-do aktualisiert';
  @override
  String get taskDeleted => 'To-do gelöscht';
  @override
  String get taskRestoreFailed => 'Das To-do konnte nicht wiederhergestellt werden.';

  // ------------------------------------------------------------------ box --
  @override
  String get boxTitle => 'Box';
  @override
  String get searchBoxesAndItems => 'Boxen und Artikel durchsuchen';
  @override
  String get searchBoxesAndItemsLong => 'Nach Boxen und Artikeln suchen';
  @override
  String get boxes => 'Boxen';
  @override
  String get items => 'Artikel';
  @override
  String get noBoxesYet => 'Noch keine Box angelegt.\nLeg eine an, um Verstautes wiederzufinden.';
  @override
  String matchCount(int count) => count == 1 ? '1 Treffer' : '$count Treffer';
  @override
  String itemCount(int count) => count == 1 ? '1 Artikel' : '$count Artikel';
  @override
  String get newBox => 'Neue Box';
  @override
  String get editBox => 'Box bearbeiten';
  @override
  String get boxName => 'Box-Name';
  @override
  String get placeExample => 'z.B. Keller, Dachboden';
  @override
  String get theBox => 'die Box';
  @override
  String get boxLabel => 'Box';
  @override
  String get tapAboveToAddFirst => 'Oben tippen, um das erste Element hinzuzufügen';
  @override
  String get newItem => 'Neuer Artikel';
  @override
  String get editItem => 'Artikel bearbeiten';
  @override
  String get itemName => 'Artikelname';
  @override
  String get sizeExample => 'z.B. EU 38, XL, 500ml';
  @override
  String get itemNotePlaceholder => 'Notizen, Zustand, Ort...';
  @override
  String get deleteItem => 'Artikel löschen';
  @override
  String get addItemPlaceholder => 'Artikel hinzufügen...';
  @override
  String get viewAsCards => 'Als Karten';
  @override
  String get viewAsList => 'Als Liste';
  @override
  String get empty => 'Leer';
  @override
  String emptyWithPlace(String place) => 'Leer · $place';
  @override
  String itemsWithPlace(int count, String place) => '${itemCount(count)} · $place';
  @override
  String get boxesLoadFailed => 'Boxen konnten nicht geladen werden.';
  @override
  String get boxSaveFailed => 'Die Box konnte nicht gespeichert werden.';
  @override
  String get boxDeleteFailed => 'Die Box konnte nicht gelöscht werden.';
  @override
  String get itemSaveFailed => 'Der Artikel konnte nicht gespeichert werden.';
  @override
  String get itemDeleteFailed => 'Der Artikel konnte nicht gelöscht werden.';
  @override
  String get itemDeleted => 'Artikel gelöscht';
  @override
  String get itemRestoreFailed => 'Der Artikel konnte nicht wiederhergestellt werden.';
  @override
  String get itemCreated => 'Artikel erstellt';
  @override
  String get boxCreated => 'Box erstellt';
  @override
  String get boxUpdated => 'Box aktualisiert';
  @override
  String get boxDeleted => 'Box gelöscht';
  @override
  String get boxRestoreFailed => 'Die Box konnte nicht wiederhergestellt werden.';

  // ----------------------------------------------------------------- list --
  @override
  String get listsTitle => 'Listen';
  @override
  String get searchListsAndItems => 'Listen und Artikel durchsuchen';
  @override
  String get searchListsAndItemsLong => 'Nach Listen und Artikeln suchen';
  @override
  String get noListsYet => 'Noch keine Liste angelegt.\nOben tippen, um die erste zu erstellen.';
  @override
  String doneInList(String list) => 'Erledigt · $list';
  @override
  String inList(String list) => 'in $list';
  @override
  String get newList => 'Neue Liste';
  @override
  String get editList => 'Liste bearbeiten';
  @override
  String get whichKindOfList => 'Welche Art von Liste?';
  @override
  String get groceries => 'Lebensmittel';
  @override
  String get otherKind => 'Sonstige';
  @override
  String get listName => 'Listenname';
  @override
  String get theList => 'die Liste';
  @override
  String get allDone => 'Alles erledigt';
  @override
  String remaining(int count) => '$count verbleibend';
  @override
  String get listLabel => 'Liste';
  @override
  String doneWithCount(int count) => 'Erledigt ($count)';
  @override
  String get deleteDone => 'Erledigte löschen';
  @override
  String get allItems => 'Alle Artikel';
  @override
  String get whichList => 'In welche Liste?';
  @override
  String get itemLabel => 'Artikel';
  @override
  String attachmentCount(int count) => count == 1 ? '1 Anhang' : '$count Anhänge';
  @override
  String get searchOnAmazon => 'Bei Amazon suchen';
  @override
  String get photo => 'Foto';
  @override
  String get camera => 'Kamera';
  @override
  String get itemLink => 'Link';
  @override
  String get removeItemLink => 'Link entfernen';
  @override
  String get itemLinkMessage =>
      'Die Seite, auf der es diesen Artikel gibt. Ein Tipp auf den Link öffnet sie im Browser.';
  @override
  String get itemLinkHint => 'z. B. amazon.de/dp/B0C…';
  @override
  String get itemLinkSaved => 'Link gespeichert';
  @override
  String get itemLinkInvalid => 'Das sieht nicht nach einer Web-Adresse aus.';
  @override
  String get listsLoadFailed => 'Listen konnten nicht geladen werden.';
  @override
  String get listSaveFailed => 'Die Liste konnte nicht gespeichert werden.';
  @override
  String get listDeleteFailed => 'Die Liste konnte nicht gelöscht werden.';
  @override
  String get listCreated => 'Liste erstellt';
  @override
  String get listUpdated => 'Liste aktualisiert';
  @override
  String get listDeleted => 'Liste gelöscht';
  @override
  String get listRestoreFailed => 'Die Liste konnte nicht wiederhergestellt werden.';
  @override
  String get someDoneItemsNotDeleted => 'Nicht alle erledigten Artikel konnten gelöscht werden.';
  @override
  String get doneItemsDeleteFailed => 'Die erledigten Artikel konnten nicht gelöscht werden.';

  // ------------------------------------------------------------- calendar --
  @override
  String get calendarTitle => 'Kalender';
  @override
  String get yourDay => 'Dein Tag';
  @override
  String get all => 'Alle';
  @override
  String get newEvent => 'Neuer Termin';
  @override
  String get editEvent => 'Termin bearbeiten';
  @override
  String get startsAt => 'Beginn';
  @override
  String get endsAt => 'Ende';
  @override
  String get eventRepeat => 'Wiederholen';
  @override
  String get repeatNever => 'Nie';
  @override
  String get repeatDaily => 'Täglich';
  @override
  String repeatWeekly(String weekday) => 'Jeden $weekday';
  @override
  String repeatBiweekly(String weekday) => 'Jeden 2. $weekday';
  @override
  String get repeatMonthly => 'Monatlich';
  @override
  String get repeatYearly => 'Jährlich';
  @override
  String get repeatEnds => 'Endet';
  @override
  String get repeatFollowsStart => 'Die Wiederholung richtet sich nach dem Startdatum.';
  @override
  String repeatUntilDate(String date) => 'bis $date';
  @override
  String get repeats => 'Wiederholt sich';
  @override
  String get repeatNotEditable => 'Die Wiederholung lässt sich hier nicht ändern — nur im Kalender selbst.';
  @override
  String get repeatingEvent => 'Terminserie';
  @override
  String get changeRepeatingEventBody =>
      'Soll die Änderung nur für diesen Termin gelten oder für die ganze Serie?';
  @override
  String get deleteRepeatingEventBody => 'Soll nur dieser Termin gelöscht werden oder die ganze Serie?';
  @override
  String get thisEventOnly => 'Nur dieser Termin';
  @override
  String get seriesCannotMoveCalendar =>
      'Eine ganze Serie lässt sich nicht in einen anderen Kalender verschieben. Wähle „Nur dieser Termin".';
  @override
  String get wholeSeries => 'Ganze Serie';
  @override
  String get noEventsThisDay => 'Keine Termine an diesem Tag';
  @override
  String get todosChip => 'To-dos';
  @override
  String get dueRailLabel => 'Fällig';
  @override
  String get addEvent => 'Termin hinzufügen';
  @override
  String get eventsPerCalendar => 'Termine je Kalender';
  @override
  String get publicHoliday => 'Feiertag';
  @override
  String get schoolHoliday => 'Ferien';
  @override
  String germanHolidayName(GermanHoliday holiday) => switch (holiday) {
    GermanHoliday.neujahr => 'Neujahr',
    GermanHoliday.heiligeDreiKoenige => 'Heilige Drei Könige',
    GermanHoliday.frauentag => 'Internationaler Frauentag',
    GermanHoliday.karfreitag => 'Karfreitag',
    GermanHoliday.ostersonntag => 'Ostersonntag',
    GermanHoliday.ostermontag => 'Ostermontag',
    GermanHoliday.tagDerArbeit => 'Tag der Arbeit',
    GermanHoliday.christiHimmelfahrt => 'Christi Himmelfahrt',
    GermanHoliday.pfingstsonntag => 'Pfingstsonntag',
    GermanHoliday.pfingstmontag => 'Pfingstmontag',
    GermanHoliday.fronleichnam => 'Fronleichnam',
    GermanHoliday.mariaeHimmelfahrt => 'Mariä Himmelfahrt',
    GermanHoliday.weltkindertag => 'Weltkindertag',
    GermanHoliday.deutscheEinheit => 'Tag der Deutschen Einheit',
    GermanHoliday.reformationstag => 'Reformationstag',
    GermanHoliday.allerheiligen => 'Allerheiligen',
    GermanHoliday.bussUndBettag => 'Buß- und Bettag',
    GermanHoliday.weihnachtstag1 => '1. Weihnachtstag',
    GermanHoliday.weihnachtstag2 => '2. Weihnachtstag',
  };
  @override
  String eventCount(int count) => count == 1 ? '1 Termin' : '$count Termine';
  @override
  String get eventLabel => 'Termin';
  @override
  String get createListFromEvent => 'Liste zum Termin erstellen';
  @override
  String get createTaskFromEvent => 'To-do zum Termin erstellen';
  @override
  String get createForEvent => 'Neu anlegen';
  @override
  String get alreadyCreated => 'Bereits erstellt';
  @override
  String get linkedToEvent => 'Zum Termin angelegt';
  @override
  String get linkedEventLabel => 'Termin';
  @override
  String get doneLabel => 'Erledigt';
  @override
  String get openInCalendar => 'Im Kalender zeigen';
  @override
  String linkedListCount(int count) => count == 1 ? '1 Liste' : '$count Listen';
  @override
  String linkedTaskCount(int count) => count == 1 ? '1 To-do' : '$count To-dos';
  @override
  String get route => 'Route';
  @override
  String get reminder => 'Erinnerung';
  @override
  String get deleteEvent => 'Termin löschen';
  @override
  String get deleteEventQuestion => 'Termin löschen?';
  @override
  String deleteEventBody(String title) => '„$title" wird endgültig gelöscht.';
  @override
  String get untitledEvent => 'Ohne Titel';
  @override
  String reminderMinutesBefore(int minutes) => '$minutes Minuten vorher';
  @override
  String get calendarLoadFailed => 'Der Kalender konnte nicht geladen werden.';
  @override
  String get eventNeedsTitle => 'Der Termin braucht einen Titel.';
  @override
  String get eventSaveFailed => 'Der Termin konnte nicht gespeichert werden.';
  @override
  String get calendarNotEditable => 'Dieser Kalender lässt sich in aporah nicht bearbeiten.';
  @override
  String get eventDeleteFailed => 'Der Termin konnte nicht gelöscht werden.';
  @override
  String eventBeingCreatedIn(String calendar) => 'Termin wird in $calendar angelegt …';
  @override
  String get eventBeingCreated => 'Termin wird angelegt …';
  @override
  String get eventBeingDeleted => 'Termin wird gelöscht …';
  @override
  String get seriesBeingDeleted => 'Serie wird gelöscht …';
  @override
  String get eventBeingSaved => 'Änderung wird gespeichert …';
  @override
  String eventBeingMovedTo(String calendar) => 'Termin wird nach $calendar verschoben …';
  @override
  String get seriesBeingSaved => 'Serie wird gespeichert …';
  @override
  String get eventCreated => 'Termin erstellt';
  @override
  String get eventUpdated => 'Termin aktualisiert';
  @override
  String get eventDeleted => 'Termin gelöscht';
  @override
  String get eventRestoreFailed => 'Der Termin konnte nicht wiederhergestellt werden.';
  @override
  String get calendarNoLongerAvailable => 'Dieser Kalender ist nicht mehr verfügbar.';
  @override
  String get noWritableCalendar =>
      'Kein beschreibbarer Kalender. Verbinde zuerst einen Kalender in den Einstellungen.';
  @override
  String get noHouseholdFound => 'Kein Haushalt gefunden.';
  @override
  String get eventSaveFailedRemote => 'Der Termin konnte nicht im verbundenen Kalender gespeichert werden.';

  @override
  String get allDayDuration => 'Ganztägig';
  @override
  String durationDays(int days) => '$days Tage';
  @override
  String durationHours(int hours) => '$hours Std';
  @override
  String durationHoursMinutes(int hours, int minutes) => '$hours Std $minutes';
  @override
  String durationMinutes(int minutes) => '$minutes Min';
  @override
  String timeRange(String from, String to) => '$from – $to Uhr';

  // -------------------------------------------------------------- weather --
  @override
  String temperature(int degrees) => '$degrees°';
  @override
  String get weatherAttribution => 'DWD · OpenStreetMap';
  @override
  String get weatherClear => 'Klar';
  @override
  String get weatherPartlyCloudy => 'Heiter';
  @override
  String get weatherCloudy => 'Bewölkt';
  @override
  String get weatherFog => 'Nebel';
  @override
  String get weatherDrizzle => 'Nieselregen';
  @override
  String get weatherRain => 'Regen';
  @override
  String get weatherSnow => 'Schnee';
  @override
  String get weatherStorm => 'Gewitter';

  // ------------------------------------------------------- calendar setup --
  @override
  String get connectCalendars => 'Kalender verbinden';
  @override
  String get calendarAccountsGroup => 'Konten';
  @override
  String get noAccountGroup => 'Ohne Konto';
  @override
  String get connectCalendarsIntro =>
      'Sieh die Termine deiner Familie in der App — Schule, Abfallabfuhr und '
      'private Kalender an einem Ort.';
  @override
  String get connectCalendarsAdminNote => 'Kalender verbindet ein Erwachsener im Haushalt.';
  @override
  String get noCalendarsConnected => 'Noch kein Kalender verbunden.';
  @override
  String noProviderCalendarYet(String provider) =>
      'Noch kein $provider-Kalender.\nTippe auf „Verbinden“, um den ersten hinzuzufügen.';
  @override
  String get loadingEllipsis => 'Wird geladen …';
  @override
  String get notSyncedYet => 'Noch nicht synchronisiert';
  @override
  String get syncedJustNow => 'Gerade synchronisiert';
  @override
  String syncedMinutesAgo(int minutes) => 'Vor $minutes Minuten synchronisiert';
  @override
  String syncedHoursAgo(int hours) => 'Vor $hours Stunden synchronisiert';
  @override
  String syncedDaysAgo(int days) => 'Vor $days Tagen synchronisiert';
  @override
  String get actionNeeded => 'Aktion nötig';
  @override
  String get connected => 'Verbunden';
  @override
  String calendarCount(int count) => count == 1 ? '1 Kalender' : '$count Kalender';
  @override
  String get calendarSettings => 'Kalender bearbeiten';
  @override
  String get calendarColor => 'Farbe';
  @override
  String get renameCalendar => 'Kalender umbenennen';
  @override
  String get renameCalendarBody =>
      'Unter diesem Namen taucht der Kalender in aporah auf — im Kalender, '
      'in den Filtern und hier.';
  @override
  String get householdOnly => 'Nur für euren Haushalt.';
  @override
  String get savingEllipsis => 'Wird gespeichert …';
  @override
  String get nameChanged => 'Name geändert';
  @override
  String get removeCalendarQuestion => 'Kalender entfernen?';
  @override
  String get disconnectQuestion => 'Verbindung trennen?';
  @override
  String removeCalendarBody(String name) => '„$name" verschwindet aus eurem Kalender. ';
  @override
  String get accessRevokedToo => 'Der Zugriff wird auch beim Anbieter widerrufen.';
  @override
  String get accountStaysConnected => 'Das Konto bleibt verbunden — die anderen Kalender darin auch.';
  @override
  String get householdOnlyOthersKeep => 'Nur für euren Haushalt — andere behalten den Kalender.';
  @override
  String get credentialsDeleted => 'Eure Zugangsdaten werden gelöscht.';
  @override
  String get connectionNeedsAttention => 'Die Verbindung braucht Aufmerksamkeit.';
  @override
  String get refreshingEllipsis => 'Wird aktualisiert …';
  @override
  String providerNotSetUp(String provider) => '$provider ist noch nicht eingerichtet.';
  @override
  String get browserCouldNotOpen => 'Der Browser konnte nicht geöffnet werden.';
  @override
  String connectProvider(String provider) => '$provider verbinden';
  @override
  String redirectNotice(String provider) =>
      'Du meldest dich bei $provider an. aporah sieht nur deine Kalender — '
      'nie dein Passwort.';
  @override
  String get openingEllipsis => 'Wird geöffnet …';
  @override
  String signInWithProvider(String provider) => 'Mit $provider anmelden';
  @override
  String get comeBackWhenDone => 'Komm zurück, sobald du im Browser fertig bist.';
  @override
  String get connectedDot => 'Verbunden.';
  @override
  String calendarsFoundPickThem(int count) =>
      '$count Kalender gefunden. Wähl aus, welche in aporah erscheinen sollen.';
  @override
  String get nameYourCalendarBody => 'So heißt der Kalender in aporah. Du kannst ihn jetzt umbenennen.';
  @override
  String get nameEachCalendarBody => 'So heißen die Kalender in aporah. Du kannst sie jetzt umbenennen.';
  @override
  String get whichCalendars => 'Kalender';
  @override
  String get whichCalendarsHint => 'Nur die ausgewählten erscheinen in aporah. Das kannst du später ändern.';
  @override
  String get readOnlyCalendar => 'Nur lesen';
  @override
  String get pickAtLeastOneCalendar => 'Wähl mindestens einen Kalender aus.';
  @override
  String get selectAll => 'Alle auswählen';
  @override
  String get deselectAll => 'Alle abwählen';
  @override
  String calendarsSelected(int count) => count == 1 ? '1 Kalender ausgewählt' : '$count Kalender ausgewählt';
  @override
  String get loadingCalendarsEllipsis => 'Kalender werden geladen …';
  @override
  String get appPasswordHint => 'Nicht dein normales Apple-ID-Passwort.';
  @override
  String get createAppPassword => 'App-spezifisches Passwort erstellen';
  @override
  String get school => 'Schule';
  @override
  String get schoolAddressHint => 'Die Adresse, unter der ihr IServ öffnet.';
  @override
  String get username => 'Benutzername';
  @override
  String get appleId => 'Apple-ID';
  @override
  String get icloudEmailHint => 'name@icloud.com';
  @override
  String get emailAddress => 'E-Mail-Adresse';
  @override
  String get oneAndOneAppPasswordHint =>
      'Am besten ein anwendungsspezifisches Passwort — das gilt nur für den '
      'Kalender und lässt sich einzeln widerrufen.';
  @override
  String get appPasswordPlaceholder => 'Anwendungsspezifisches Passwort';
  @override
  String get iservPassword => 'IServ-Passwort';
  @override
  String get checkingEllipsis => 'Wird geprüft …';
  @override
  String get connect => 'Verbinden';
  @override
  String get bundesland => 'Bundesland';
  @override
  String get holidaysIntro => 'Ihr könnt mehrere Bundesländer auswählen.';
  @override
  String get pickABundesland => 'Wähl ein Bundesland aus.';
  @override
  String schoolHolidaysOf(String state) => 'Schulferien $state';
  @override
  String holidaysSelectedBody(String state) =>
      'Du hast $state ausgewählt. Die Ferientermine erscheinen danach in eurem '
      'Kalender — für alle im Haushalt.';
  @override
  String get wasteIntro =>
      'Restmüll, Bio, Papier und Gelbe Tonne kommen automatisch in euren '
      'Kalender — für alle im Haushalt.';
  @override
  String get houseNumber => 'Hausnummer';
  @override
  String get multipleDistrictsHint =>
      'Diese Straße hat mehrere Abfuhrbezirke. Ohne Auswahl gilt der '
      'Plan der ganzen Straße.';
  @override
  String wasteFor(String street) => 'Abfall $street';
  @override
  String wasteForTown(String town) => 'Abfall $town';
  @override
  String noVendorForTown(String town) =>
      'Für $town kennen wir leider noch keinen Entsorger. Die meisten '
      'veröffentlichen ihre Termine selbst: such auf der Seite eures '
      'Entsorgers nach „Abfuhrkalender" oder „Kalender abonnieren" und setz '
      'den Link hier ein.';
  @override
  String wasteUploadOnlyBody(String town) =>
      '$town gibt seine Abfuhrtermine nicht für den automatischen Abruf durch Apps frei — so holt ihr euren Abfallkalender trotzdem in wenigen Schritten hierher.';
  @override
  String get openTownCalendarPage => 'Abfallkalender der Stadt öffnen';
  @override
  String get wasteUploadOnlyShort => 'Nur als Datei — tippen zum Hinzufügen';
  @override
  List<String> get binFileStepsInApp => [
    'Öffnet unten den Abfallkalender der Stadt.',
    'Wählt eure Straße.',
    'Tippt auf den Download als iCal oder ICS.',
    'aporah erkennt die Datei automatisch und holt sie direkt hierher.',
  ];
  @override
  List<String> get binFileStepsBrowser => [
    'Öffnet unten den Abfallkalender der Stadt.',
    'Wählt eure Straße.',
    'Tippt auf den Download als iCal oder ICS.',
    'Ladet die Datei danach hier mit „Kalenderdatei hochladen“ hoch.',
  ];
  @override
  String get calendarPagePrompt => 'Wählt eure Straße und tippt auf den iCal-Export';
  @override
  String get calendarPageNotCalendar => 'Das ist keine Kalenderdatei. Sucht auf der Seite nach „iCal“ oder „ICS“.';
  @override
  String get calendarPageFailed => 'Die Datei ließ sich nicht laden. Versucht es noch einmal.';
  @override
  String get ok => 'OK';
  @override
  String get wasteUploadOnlyLater => 'Nur als Datei erhältlich — ihr könnt sie später als Kalenderdatei hinzufügen.';
  @override
  String get wasteOnTownPage => 'Termine auf der Seite der Stadt';
  @override
  String get onboardWasteFileTitle => 'Euer Abfallkalender kommt als Datei';
  @override
  String get pdfDistrictLabel => 'Euer Bezirk';
  @override
  String get wasteFileAdded => 'Abfallkalender als Datei hinzugefügt';
  @override
  String wasteOwnPageBody(String town) =>
      '$town gibt seinen Abfallkalender auf der eigenen Seite heraus — so holt ihr ihn in wenigen Schritten hierher.';
  @override
  String get wasteLinkLater =>
      'Hier noch nicht gefunden — ihr könnt den Kalender später als Link oder Datei hinzufügen.';
  @override
  List<String> get binFileStepsPdfInApp => [
    'Öffnet unten den Abfallkalender der Stadt.',
    'Wählt euren Ort oder eure Straße.',
    'Tippt auf den Kalender als iCal, ICS oder PDF.',
    'aporah erkennt die Datei automatisch und holt sie direkt hierher.',
  ];
  @override
  List<String> get binFileStepsPdfBrowser => [
    'Öffnet unten den Abfallkalender der Stadt.',
    'Wählt euren Ort oder eure Straße.',
    'Tippt auf den Kalender als iCal, ICS oder PDF.',
    'Ladet die Datei danach hier mit „Kalenderdatei oder PDF hochladen“ hoch.',
  ];
  @override
  String get townPagePdfOnly =>
      'Dort gibt es den Kalender nur als PDF zum Ausdrucken, und das kann die App nicht einlesen. Die Termine findet ihr auf der Seite der Stadt — und falls es dort doch eine iCal-Datei gibt, holt ihr sie hier herein.';
  @override
  String get townPageDatesOnly =>
      'Dort stehen die Termine vielleicht nur auf der Seite selbst. Schaut nach einem Export als iCal oder ICS.';
  @override
  String get townPageAppOnly =>
      'Dort gibt es die Termine vielleicht nur in der App der Stadt. Schaut auf der Seite nach einem Export als iCal oder ICS.';
  @override
  String get calendarPagePromptPdf =>
      'Wählt eure Straße und ladet den Kalender als iCal oder PDF';
  @override
  String get calendarPageNotCalendarPdf =>
      'Das ist keine Kalenderdatei. Sucht auf der Seite nach „iCal“, „ICS“ oder „PDF“.';
  @override
  String get pdfNotReadableYet =>
      'Das ist ein PDF, und das kann die App nicht einlesen. Bitte wählt eine Kalenderdatei (iCal oder ICS).';
  @override
  String get fileTooLarge =>
      'Diese Datei ist zu groß.';
  @override
  String get pickDistrictFirst =>
      'Bitte wählt euren Bezirk.';
  @override
  String get pdfDistrictIntro =>
      'Der Plan gilt für mehrere Bezirke. Welcher ist eurer? Die nächsten Termine helfen beim Wiedererkennen.';
  @override
  String nextPickups(String dates) =>
      'Nächste: $dates';
  @override
  String get wasteNeedsHouseNumber => 'Bitte mit Hausnummer eingeben — hier gilt der Abfuhrplan pro Haus.';
  @override
  String get houseNumberAsk =>
      'Und die Hausnummer?';
  @override
  String get houseNumberAskHint =>
      'Damit wir den Abfuhrplan für genau euer Haus finden.';
  @override
  String get houseNumberPlaceholder =>
      'z. B. 12a';
  @override
  String get houseNumberInvalid =>
      'Bitte eine Hausnummer wie 12 oder 12a eingeben.';
  @override
  String get houseNumberUnknown =>
      'Diese Hausnummer kennt die Müllabfuhr nicht — bitte prüfen.';
  @override
  String get addressPrivacyNote =>
      'Die Adresse wird nur genutzt, um Müllabfuhr, Ferien und Wetter für euch zu finden.';
  @override
  String get onboardRhythmTitle => 'Noch eine Frage zu eurer Müllabfuhr';
  @override
  String get pickHouseNumberHint => 'Hier gilt der Abfuhrplan pro Haus — bitte eure Hausnummer wählen.';
  @override
  String rhythmQuestion(String bin) => '$bin — wie oft geleert?';
  @override
  String get rhythmHint => 'Steht auf dem Aufkleber eurer Tonne — dieselbe Frage stellt der Kalender der Stadt. Angezeigt wird nur dieser Rhythmus.';
  @override
  String get pickRhythmFirst => 'Bitte wählt noch, wie oft eure Tonne geleert wird.';
  @override
  String get rhythmWeekly => 'wöchentlich';
  @override
  String rhythmEveryWeeks(int n) => 'alle $n Wochen';
  @override
  String get checkingRhythm => 'Abfuhrrhythmus wird geprüft …';
  @override
  String get checkingLinkEllipsis => 'Link wird geprüft …';
  @override
  List<String> get iservLinkSteps => const [
    'In IServ anmelden und den Kalender öffnen.',
    'Unten links auf „Einstellungen" und dann auf „Plugins".',
    'Beim gewünschten Kalender – z. B. Klausuren oder Aufgaben – „Link erstellen".',
    'Den erzeugten Link kopieren und hier einsetzen.',
  ];
  @override
  List<String> get webuntisLinkSteps => const [
    'In WebUntis anmelden und oben auf den eigenen Namen tippen.',
    'Unter „Freigaben" auf „Kalender publizieren" — oder im Stundenplan über '
        'die drei Punkte auf „iCal-Abo verwalten", Format „Standard", '
        '„Link erstellen".',
    'Den erzeugten iCal-Link kopieren und hier einsetzen.',
  ];
  @override
  String get icalLinkNote =>
      'Jeder Kalender, den man abonnieren kann: Verein, Kita, Arbeit. Gesucht ist '
      'die Abo-Adresse (ICS), nicht die Webseite des Kalenders.';
  @override
  String get uploadCalendarFileOrPdf => 'Kalenderdatei oder PDF hochladen';
  @override
  String get uploadCalendarFile => 'Kalenderdatei hochladen';
  @override
  String get uploadCalendarFileHint =>
      'Wenn es keinen Link gibt, sondern nur eine .ics-Datei zum Herunterladen.';
  @override
  String get calendarFileNote =>
      'Eine Datei ist eine Momentaufnahme: Sie enthält genau die Termine, die '
      'beim Hochladen darin standen. Kommt eine neue heraus, ladet ihr sie hier '
      'einfach wieder hoch.';
  @override
  String get checkingFileEllipsis => 'Datei wird geprüft …';
  @override
  String get calendarFileUnreadable => 'Die Datei ließ sich nicht lesen. Bitte wähle eine .ics-Datei.';
  @override
  String calendarFileCoversTo(String date) => 'Die Termine reichen bis zum $date.';
  @override
  String calendarFileChosen(String name) => '$name ausgewählt';
  @override
  String longDate(DateTime at) => '${at.day}. ${monthNames[at.month]} ${at.year}';
  @override
  String get pasteCalendarLink => 'Kalender-Link';
  @override
  String get pasteCalendarLinkHint => 'Wir rufen den Link jetzt ab – so wisst ihr sofort, ob er stimmt.';
  @override
  String get whoseCalendar => 'Für wen ist dieser Zugang?';
  @override
  String get whoseCalendarHint => 'Steht später auf dem Filter im Kalender, z. B. „IServ · Alice".';
  @override
  String get whoseCalendarPlaceholder => 'Name des Kindes';
  @override
  String get linkedCalendarName => 'Name des Kalenders';
  @override
  String get linkedCalendarNameHint => 'Zum Beispiel Klausuren, Aufgaben oder Klassenkalender.';
  @override
  String get nameThisCalendarFirst => 'Gib dem Kalender noch einen Namen.';
  @override
  String get whoseCalendarFirst => 'Sag noch, für wen dieser Zugang ist.';
  @override
  String get schoolCalendars => 'Kalender';
  @override
  String get removeCalendar => 'Kalender entfernen';
  @override
  String get linkStaysAtSchool =>
      ' Der Link bleibt in der Schulplattform bestehen — wir merken ihn uns nur nicht mehr.';
  @override
  String get linkedCalendarsNote =>
      'aporah liest diese Kalender nur. Termine ändert ihr weiterhin in der Schulplattform.';
  @override
  String eventsFoundAtLink(int count) => count == 1 ? '1 Termin gefunden' : '$count Termine gefunden';
  @override
  String get noEventsAtLinkYet =>
      'Der Link funktioniert, enthält aber gerade keine Termine. Das ist in den Ferien normal.';

  @override
  String get calendarLinkIcs => 'Kalender-Link (ICS)';
  @override
  String get calendarLinkHint => 'Endet meist auf .ics — der Link hinter "Kalender abonnieren".';
  @override
  String get pasteLinkHere => 'Setz hier den Kalender-Link ein.';
  @override
  String get noEventsAtThatLink =>
      'Unter diesem Link wurden keine Termine gefunden. Ist es der Link '
      'zum Kalender selbst?';
  @override
  String get yourAddress => 'Adresse';
  @override
  String get yourAddressHint => 'Wir finden euren Entsorger.';
  @override
  String get pickYourAddressFirst => 'Such deine Adresse und tipp sie an.';
  @override
  String get addressPlaceholder => 'Straße Hausnummer, Ort';
  @override
  String get searchingAddresses => 'Adressen werden gesucht …';
  @override
  String get noAddressFound => 'Keine Adresse gefunden.';
  @override
  String get searchingVendor => 'Entsorger wird gesucht …';
  @override
  String get tapToRetry => 'Tippen, um es noch einmal zu versuchen';
  @override
  String foundVendor(String where) => 'Gefunden: $where';
  @override
  String get noVendorFoundTapForLink => 'Kein Entsorger gefunden — tippen für den Kalender-Link';
  @override
  String get askingNearbyVendors => 'Wir fragen die Entsorger der Umgebung …';
  @override
  String get connectionStartFailed => 'Die Verbindung konnte nicht gestartet werden.';
  @override
  String get connectionsLoadFailed => 'Die Verbindungen konnten nicht geladen werden.';
  @override
  String get connectingEllipsis => 'Wird verbunden …';
  @override
  String get calendarConnected => 'Kalender verbunden';
  @override
  String get calendarNameInAporah => 'So heißt der Kalender in aporah. Du kannst ihn später umbenennen.';

  // -------------------------------------------------------- provider meta --
  @override
  String get providerIcalLabel => 'Anderer Kalender';
  @override
  String get providerHolidaysLabel => 'Ferien';
  @override
  String get providerWasteLabel => 'Abfall';
  @override
  String get providerGoogleDesc => 'Google Kalender verbinden.';
  @override
  String get providerOutlookDesc => 'Outlook oder Microsoft 365 verbinden.';
  @override
  String get providerIcloudDesc => 'iCloud mit einem app-spezifischen Passwort verbinden.';
  @override
  String get providerGmxDesc => 'Den GMX Kalender verbinden — Termine gehen auch zurück.';
  @override
  String get providerWebdeDesc => 'Den WEB.DE Kalender verbinden — Termine gehen auch zurück.';
  @override
  String get providerIservDesc => 'Aufgaben, Klausuren und Klassenkalender aus IServ.';
  @override
  String get providerWebuntisDesc =>
      'Den Stundenplan aus WebUntis anzeigen — über den iCal-Link aus dem Profil.';
  @override
  String get providerIcalDesc => 'Jeden abonnierbaren Kalender einsetzen — Verein, Kita, Arbeit.';
  @override
  String get providerHolidaysDesc => 'Schulferien deines Bundeslands anzeigen.';
  @override
  String get providerWasteDesc => 'Abfuhrtermine für deine Adresse anzeigen.';

  // --------------------------------------------------------------- shares --
  @override
  String get shareTitle => 'Teilen';
  @override
  String shareIntro(String resource) => '„$resource" mit Leuten außerhalb eurer Familie teilen. ';
  @override
  String shareIntroSecond(String noun) => 'Sie sehen ausschließlich $noun — sonst nichts von euch.';
  @override
  String get emailOptional => 'E-Mail (optional)';
  @override
  String get createLink => 'Link erstellen';
  @override
  String get sendInvite => 'Einladung senden';
  @override
  String get guests => 'Gäste';
  @override
  String get activeLinks => 'Aktive Links';
  @override
  String get notSharedYet => 'Noch nicht geteilt.\nErstell einen Link, um jemanden hineinzulassen.';
  @override
  String get newLink => 'Neuer Link';
  @override
  String get copied => 'Kopiert';
  @override
  String get copyLink => 'Link kopieren';
  @override
  String get linkShownOnce => 'Dieser Link wird nur jetzt angezeigt — wir speichern ihn nicht.';
  @override
  String usedTimes(int count) => count == 1 ? '1× benutzt' : '$count× benutzt';
  @override
  String get linkExpired => 'abgelaufen';
  @override
  String get linkUsedUp => 'aufgebraucht';
  @override
  String get shareLink => 'Freigabe-Link';
  @override
  String get revoke => 'Zurückziehen';
  @override
  String get guest => 'Gast';
  @override
  String get sharesLoadFailed => 'Die Freigaben konnten nicht geladen werden.';
  @override
  String get shareLinkCreateFailed => 'Der Freigabe-Link konnte nicht erstellt werden.';
  @override
  String get linkRevokeFailed => 'Der Link konnte nicht zurückgezogen werden.';
  @override
  String get guestRemoveFailed => 'Der Gast konnte nicht entfernt werden.';
  @override
  String shareListMessage(String name) => '„$name" in aporah – über diesen Link kommst du rein:';
  @override
  String get sharedOutsideTitle => 'Geteilt mit';
  @override
  String openInvitations(int count, String? until) {
    final what = count == 1 ? 'Offene Einladung' : '$count offene Einladungen';
    return until == null ? what : '$what · gültig bis $until';
  }

  @override
  String get sharedOutsideLabel => 'Mit Leuten außerhalb der Familie geteilt';

  @override
  String whoSeesTitle(String noun) => 'Wer sieht $noun?';

  @override
  String privateCannotShare(String noun) =>
      'Privat: Teilen geht erst, wenn außer dir noch jemand $noun sieht. Ändere dafür »Für wen?«.';

  @override
  String visibilityLockedWhileShared(String noun) =>
      'Solange $noun extern geteilt ist, bleibt »Für wen?« wie es ist — sonst verliert die Familie den Zugriff.';

  @override
  String get visibilityLockedHowTo =>
      'Entferne unten alle Gäste und offenen Einladungen, um es wieder zu ändern.';

  @override
  String get visibilityLockedHowToInShare =>
      'Entferne unter »Teilen« alle Gäste und Links, um es wieder zu ändern.';

  // ----------------------------------------------------------- visibility --
  @override
  String get forWhom => 'Für wen?';
  @override
  String get everyone => 'Alle';
  @override
  String get onlyMe => 'Nur ich';
  @override
  String get selected => 'Ausgewählte';
  @override
  String peopleCount(int count) => '$count Personen';
  @override
  String wholeFamilySees(String noun) => 'Für die ganze Familie — alle können $noun sehen und bearbeiten.';
  @override
  String onlyYouSee(String noun) => 'Nur für dich sichtbar — niemand sonst sieht $noun.';
  @override
  String youAndOthersSee(String names, String noun) => 'Nur du und $names sehen $noun.';
  @override
  String joinNames(List<String> names) =>
      names.length == 1 ? names.first : '${names.sublist(0, names.length - 1).join(', ')} und ${names.last}';

  // ------------------------------------------------------------ icon pick --
  @override
  String get symbol => 'Symbol';
  @override
  String get change => 'Ändern';
  @override
  String get photoUploadFailed => 'Foto konnte nicht hochgeladen werden.';
  @override
  String get photoRemoveFailed => 'Foto konnte nicht entfernt werden.';
  @override
  String get chooseSymbol => 'Symbol wählen';
  @override
  String get uploadImage => 'Bild hochladen';
  @override
  String get searchSymbolOrShop => 'Symbol oder Geschäft suchen';
  @override
  String get matches => 'Treffer';
  @override
  String nothingFoundFor(String query) => 'Nichts gefunden für "$query"';
  @override
  String get suggestionFromName => 'Vorschlag zum Namen';
  @override
  String get shops => 'Geschäfte';
  @override
  String get showLess => 'Weniger anzeigen';
  @override
  String allMoreShops(int count) => 'Alle $count weiteren Geschäfte';
  @override
  String noMatchesFor(String query) => 'Keine Treffer für „$query"';

  // ------------------------------------------------------------- settings --
  @override
  String get settingsTitle => 'Einstellungen';
  @override
  String get searchSettings => 'Einstellungen durchsuchen';
  @override
  String get profile => 'Profil';
  @override
  String get familyMembers => 'Familienmitglieder';
  @override
  String get language => 'Sprache';
  @override
  String get appearance => 'Darstellung';
  @override
  String get appearanceAuto => 'Automatisch';
  @override
  String get appearanceLight => 'Hell';
  @override
  String get appearanceDark => 'Dunkel';
  @override
  String get welcomeTour => 'Willkommenstour';
  @override
  String get repeat => 'Wiederholen';
  @override
  String get signOut => 'Abmelden';
  @override
  String noSettingFoundFor(String query) => 'Keine Einstellung gefunden für „$query"';
  @override
  String get notConnected => 'Nicht verbunden';
  @override
  String get displayName => 'Anzeigename';
  @override
  String get avatarColour => 'Avatar-Farbe';
  @override
  String get removePhoto => 'Foto entfernen';
  @override
  String get removeSymbol => 'Symbol entfernen';
  @override
  String get avatarUploadFailed => 'Das Profilbild konnte nicht hochgeladen werden.';
  @override
  String get avatarRemoveFailed => 'Das Profilbild konnte nicht entfernt werden.';
  @override
  String get adminsManageFamily => 'Admins verwalten die Familie und alle Verbindungen.';
  @override
  String get familyMembersDesc =>
      'Lege die Rolle jedes Familienmitglieds fest. Admins verwalten die Familie; '
      'Kinder sehen eine vereinfachte Ansicht.';
  @override
  String get familyMembersDescAdmin =>
      'Wer zu eurem Haushalt gehört. Einladen und Rollen ändern können nur Admins.';
  @override
  String get nobodyInHouseholdYet =>
      'Noch niemand im Haushalt.\nLade jemanden ein, um Listen, To-dos und Termine zu teilen.';
  @override
  String get inviteMember => 'Mitglied einladen';
  @override
  String pendingWithRole(String role) => '$role · ausstehend';
  @override
  String get inviteFamilyMember => 'Familienmitglied einladen';
  @override
  String get inviteValidity =>
      'Die Einladung ist 14 Tage gültig. Wer sie annimmt, verlässt damit seinen bisherigen Haushalt.';
  @override
  String get inviteSending => 'Einladung wird gesendet …';
  @override
  String get inviteSentTitle => 'Einladung gesendet';
  @override
  String get inviteCreatedTitle => 'Einladung erstellt';
  @override
  String inviteSentTo(String email) => 'Wir haben eine E-Mail an $email geschickt.';
  @override
  String inviteMailNotSent(String email) =>
      'Die E-Mail an $email ließ sich nicht zustellen. Teile den Link unten direkt.';
  @override
  String invitedAsRole(String role) => 'Eingeladen als $role';
  @override
  String inviteValidUntil(String date) => 'Gültig bis $date';
  @override
  String invitedPerson(String who) => '$who eingeladen';
  @override
  String get tapSendToInvite => 'Tipp auf Senden, um die Einladung zu verschicken.';
  @override
  String get youCaps => 'DU';
  @override
  String get removeMemberQuestion => 'Mitglied entfernen?';
  @override
  String removeMemberBody(String name) =>
      '„$name" verliert den Zugriff auf euren Haushalt. '
      'Gemeinsame Inhalte bleiben erhalten, private Inhalte werden gelöscht.';
  @override
  String get languagePageDesc =>
      'Bestimmt die Sprache der App. Menüs, Schaltflächen und Datumsangaben '
      'wechseln sofort mit.';
  @override
  String get setUpProfile => 'Profil einrichten';
  @override
  String get languageGerman => 'Deutsch';
  @override
  String get languageEnglish => 'English';
  @override
  String get languagePortuguese => 'Português';
  @override
  String get languageSpanish => 'Español';
  @override
  String get languageGermanRegion => 'Deutschland';
  @override
  String get languageEnglishRegion => 'United Kingdom';
  @override
  String get languagePortugueseRegion => 'Brasilien';
  @override
  String get languageSpanishRegion => 'Spanien';

  @override
  String get searchTermsProfile => 'profil konto account name anzeigename avatar farbe rolle admin';
  @override
  String get searchTermsFamily =>
      'familie familienmitglieder mitglieder personen einladen rolle rollen kind kinder admin';
  @override
  String get searchTermsCalendar =>
      'kalender termine verbindungen verbinden google outlook icloud iserv ferien abfall schule';
  @override
  String get searchTermsApplePay =>
      'apple pay google wallet samsung pay ausgaben geräte iphone android kurzbefehle automation '
      'benachrichtigungen benachrichtigungszugriff erkennung aktivieren entfernen';
  @override
  String get searchTermsLanguage => 'sprache language deutsch english übersetzung';
  @override
  String get searchTermsDarkMode =>
      'dunkelmodus dark mode darstellung erscheinungsbild hell dunkel nacht theme automatisch system handy';
  @override
  String get searchTermsTour => 'willkommenstour onboarding tour einführung wiederholen hilfe';
  @override
  String get searchTermsSignOut => 'abmelden logout ausloggen konto verlassen wechseln';

  // ----------------------------------------------------------------- roles --
  @override
  String get roleAdmin => 'Admin';
  @override
  String get roleMember => 'Mitglied';
  @override
  String get roleChild => 'Kind';

  // ----------------------------------------------------------- onboarding --
  @override
  String get onboardSetUpFamily => 'Richten wir deine Familie ein';
  @override
  String get onboardSetUpFamilyBody =>
      'Gib eurer Familie einen Namen und ein Bild. Beides kannst du später jederzeit '
      'ändern.';
  @override
  String get onboardJoinExistingFamily => 'Nutzt deine Familie aporah schon?';
  @override
  String get onboardJoinExistingFamilyBody =>
      'Dann richte hier keine neue ein, sondern bitte jemanden aus der Familie, dich '
      'einzuladen.';
  @override
  String get onboardInviteTitle => 'Lade deine Familie ein';
  @override
  String get onboardInviteBody =>
      'Jeder in deiner Familie kann Termine, Boxen und Listen sehen und mitgestalten.';
  @override
  String get adult => 'Erwachsener';
  @override
  String get child => 'Kind';
  @override
  String get onboardAddressTitle => 'Adresse verbinden';
  @override
  String get onboardAddressBody =>
      'Wir schlagen euch passende Kalender vor — z. B. für Müllabfuhr und Schulferien.';
  @override
  String get address => 'Adresse';
  @override
  String get wasteCalendar => 'Müllabfuhr-Kalender';
  @override
  String get holidayCalendar => 'Ferienkalender';
  @override
  String get onboardFindingCalendars => 'Wir suchen Kalender für eure Adresse …';
  @override
  String get onboardFoundForYou => 'Für eure Adresse gefunden';
  @override
  String get onboardNothingForAddress =>
      'Für diese Adresse haben wir keinen Kalender gefunden. Ihr könnt später in den '
      'Einstellungen weitere verbinden.';
  @override
  String get onboardNotFoundHere => 'Für diese Adresse nicht gefunden';
  @override
  String get onboardRenameLater => 'Umbenennen könnt ihr die Kalender später unter Einstellungen → Kalender.';
  @override
  String get onboardConnectMoreHint => 'Google, Outlook, iCloud oder IServ dazunehmen';
  @override
  String get onboardConnectingCalendars => 'Kalender werden verbunden …';
  @override
  String get calendarsConnectFailed => 'Die Kalender ließen sich gerade nicht verbinden.';
  @override
  String get onboardReady => 'Bereit!';
  @override
  String get onboardReadyBody =>
      'Deine Familie ist eingerichtet — du kannst alles später in den Einstellungen anpassen.';
  @override
  String get noInvitesSent => 'Keine Einladungen verschickt';
  @override
  String invitedCount(int count) => '$count eingeladen';

  // ----------------------------------------------------------------- auth --
  @override
  String get frontDoorTagline => 'Alles, was die Familie zusammenhält — an einem Ort.';
  @override
  String get demoMemberMama => 'Mama';
  @override
  String get demoMemberPapa => 'Papa';
  @override
  String get demoMemberKid => 'Lina';
  @override
  String get demoListTitle => 'Einkaufsliste';
  @override
  String get demoListItem => 'Brot';
  @override
  String get demoEventTitle => 'Fußballtraining';
  @override
  String get demoTaskTitle => 'Müll rausbringen';
  @override
  String get demoTrackerTitle => 'Sport';
  @override
  String get emailPlaceholder => 'name@beispiel.de';
  @override
  String get greetingWelcome => 'Willkommen';
  @override
  String get greetingWelcomeBack => 'Willkommen zurück';
  @override
  String get welcomeToAporah => 'Willkommen bei aporah';
  @override
  String get welcomeBack => 'Willkommen zurück';
  @override
  String get signUpBlurb =>
      'Leg dein Konto an. Dein Haushalt wird automatisch erstellt — Familie einladen kannst du danach.';
  @override
  String get signInBlurb =>
      'Gib deine E-Mail-Adresse ein. Wir schicken dir einen Code — ein Passwort brauchst du nicht.';
  @override
  String get yourName => 'Dein Name';
  @override
  String get createAccount => 'Konto erstellen';
  @override
  String get signIn => 'Anmelden';
  @override
  String get haveAccountAlready => 'Ich habe schon ein Konto';
  @override
  String get newHereCreateAccount => 'Neu hier? Konto erstellen';
  @override
  String get almostThere => 'Fast geschafft';
  @override
  String get pleaseEnterName => 'Bitte gib deinen Namen ein.';
  @override
  String get noConnectionTryAgain => 'Keine Verbindung. Bitte versuch es noch einmal.';
  @override
  String get pleaseEnterEmailFirst => 'Bitte gib zuerst deine E-Mail-Adresse ein.';
  @override
  String get tooManyAttempts => 'Zu viele Versuche. Bitte warte einen Moment.';
  @override
  String get emailLooksInvalid => 'Diese E-Mail-Adresse sieht nicht gültig aus.';
  @override
  String get signInFailed => 'Anmeldung fehlgeschlagen. Bitte versuch es noch einmal.';
  @override
  String codeSentTo(String email) =>
      'Wir haben einen Code an $email geschickt. Gib ihn hier ein. Nichts angekommen? Schau auch im Spam-Ordner nach.';
  @override
  String get codeHint => 'Code aus der E-Mail';
  @override
  String get verifyCode => 'Bestätigen';
  @override
  String get resendCode => 'Code erneut senden';
  @override
  String resendCodeIn(int seconds) => 'Neuer Code in $seconds s';
  @override
  String get useOtherEmail => 'Andere E-Mail-Adresse';
  @override
  String get codeInvalid => 'Der Code stimmt nicht oder ist abgelaufen.';
  @override
  String get noAccountForEmail => 'Zu dieser E-Mail-Adresse gibt es noch kein Konto.';

  // ---------------------------------------------------------- incoming links --
  @override
  String get joinHouseholdTitle => 'Einem Haushalt beitreten?';
  @override
  String get joinHouseholdBody =>
      'Du wurdest in einen Haushalt eingeladen. Wenn du beitrittst, wird dein bisheriger Haushalt gelöscht — mit allem, was du dort allein angelegt hast.';
  @override
  String get joinHousehold => 'Beitreten';
  @override
  String joinedHousehold(String name) => 'Willkommen bei $name';
  @override
  String joinNamedHouseholdTitle(String name) => '$name beitreten?';
  @override
  String inviteWelcomeBody(String inviter, String household) =>
      '$inviter hat dich zu $household eingeladen. Ihr teilt euch dann Kalender, Listen und Board.';
  @override
  String inviteWelcomeBodyNoInviter(String household) =>
      'Du wurdest zu $household eingeladen. Ihr teilt euch dann Kalender, Listen und Board.';
  @override
  String inviteJoinNamed(String household) => '$household beitreten';
  @override
  String get inviteSetUpOwn => 'Eigenen Haushalt einrichten';
  @override
  String get inviteInvalid => 'Diese Einladung ist ungültig oder wurde schon verwendet.';
  @override
  String get inviteExpired => 'Diese Einladung ist abgelaufen. Bitte lass dir eine neue schicken.';
  @override
  String get inviteOtherEmail =>
      'Diese Einladung ging an eine andere E-Mail-Adresse. Melde dich mit der Adresse an, an die sie geschickt wurde.';
  @override
  String get inviteLeaveFirst =>
      'Du bist noch in einem Haushalt mit anderen Mitgliedern. Verlass ihn zuerst, dann kannst du beitreten.';
  @override
  String get inviteAcceptFailed =>
      'Die Einladung konnte nicht angenommen werden. Bitte versuch es noch einmal.';
  @override
  String get shareLinkInvalid => 'Dieser Link ist ungültig oder abgelaufen.';

  // --------------------------------------------------------------- family --
  @override
  String get noHouseholdForAccount => 'Zu deinem Konto wurde kein Haushalt gefunden.';
  @override
  String get householdLoadFailed => 'Haushalt konnte nicht geladen werden.';
  @override
  String get enterValidEmail => 'Bitte gib eine gültige E-Mail-Adresse an.';
  @override
  String get inviteSendFailed => 'Die Einladung konnte nicht gesendet werden.';
  @override
  String get roleChangeFailed => 'Die Rolle konnte nicht geändert werden.';
  @override
  String get memberRemoveFailed => 'Das Mitglied konnte nicht entfernt werden.';
  @override
  String get inviteRevokeFailed => 'Die Einladung konnte nicht zurückgezogen werden.';

  // --------------------------------------------------- calendar ownership --

  @override
  String get assignCalendar => 'Zuordnen';
  @override
  String assignCalendarBody(String calendar) =>
      'Zu wem gehört „$calendar“? Der Kalender erscheint dann unter dieser Person in Kalender und Board.';
  @override
  String get assignCalendarFamilyHint => 'Gehört allen im Haushalt';
  @override
  String get assignCalendarNewPerson => 'Andere Person';
  @override
  String get assignCalendarNotVisibility =>
      'Das ändert nichts daran, wer den Kalender sieht — alle im Haushalt sehen ihn weiterhin.';
  @override
  String get assignCalendarFailed => 'Die Zuordnung hat gerade nicht geklappt.';
  @override
  String get family => 'Familie';
  @override
  String get noAccountYet => 'Kein Konto';

  @override
  String get familyName => 'Familienname';
  @override
  String get familyNameHint => 'Wie eure Familie in aporah heißt.';
  @override
  String get renameFamily => 'Familie umbenennen';
  @override
  String get renameFamilyBody => 'Der Name steht auf dem Familien-Chip in Kalender und Board.';
  @override
  String get renamePerson => 'Person umbenennen';
  @override
  String get renamePersonBody =>
      'Der Name steht auf ihrem Chip in Kalender und Board und auf jedem Kalender, der ihr zugeordnet ist.';
  @override
  String get removePersonQuestion => 'Person entfernen?';
  @override
  String removePersonBody(String name) =>
      '„$name" hat kein Konto und steht nur auf den Kalendern, die ihr zugeordnet sind. '
      'Diese Kalender gehören danach wieder der ganzen Familie – getrennt wird nichts.';
  @override
  String get familyRenameFailed => 'Der Name konnte nicht geändert werden.';

  @override
  String homeOverdue(int count) => '$count überfällig';
  @override
  String homeOpenToday(int count) => 'Noch $count offen';
  @override
  String homeTrackersLeft(int count) => 'Noch $count Tracker';
  @override
  String homeNextUp(String time, String title) => '$time · $title';
  @override
  String get homeAllDone => 'Alles erledigt';
  @override
  String homeDayOffset(int days) => switch (days) {
    1 => 'Morgen',
    -1 => 'Gestern',
    > 1 => 'In $days Tagen',
    _ => 'Vor ${-days} Tagen',
  };
  @override
  String get homeHintBackToToday => 'Tippen für heute';
  @override
  String get homeThinking => 'Einen Moment';
  @override
  String get homeHintThinking => 'Dein Tag wird zusammengestellt';
  @override
  String get homeHintSetup => 'Richte aporah für deine Familie ein';
  @override
  String get homeHintOverdue => 'To-dos, deren Datum vorbei ist';
  @override
  String get homeHintOpen => 'To-dos für heute';
  @override
  String get homeHintTrackers => 'Heute noch nicht abgehakt';
  @override
  String get homeHintNext => 'Als Nächstes im Kalender';
  @override
  String get homeHintDone => 'Heute ist nichts mehr offen';
  @override
  String get homeTrackerSection => 'Heute dran';
  @override
  String get homeTrackerEmpty => 'Noch kein Tracker';
  @override
  String get homeTrackerEmptyBody => 'Sport, Lesen, Vitamine — was ihr regelmäßig tut.';
  @override
  String get homeListsSection => 'Listen';
  @override
  String get homeShowAll => 'Alle anzeigen';
  @override
  String homeListOpenItems(int count) => '$count offen';

  @override
  String get firstStepsTitle => 'Erste Schritte';
  @override
  String firstStepsProgress(int done, int total) => '$done von $total';
  @override
  String get firstStepCalendar => 'Kalender verbinden';
  @override
  String get firstStepCalendarBody => 'Schule, Arbeit und Abfuhr an einem Ort.';
  @override
  String get firstStepFamily => 'Familie einladen';
  @override
  String get firstStepFamilyBody => 'Damit alle dasselbe sehen.';
  @override
  String get firstStepTodo => 'Erstes To-do';
  @override
  String get firstStepTodoBody => 'Etwas, das diese Woche erledigt sein muss.';
  @override
  String get firstStepTracker => 'Tracker anlegen';
  @override
  String get firstStepTrackerBody => 'Eine Gewohnheit, die ihr gemeinsam haltet.';
  @override
  String get firstStepList => 'Erste Liste';
  @override
  String get firstStepListBody => 'Der Einkauf ist ein guter Anfang.';

  // ------------------------------------------------------- Ausgaben

  @override
  String get navMore => 'Mehr';
  @override
  String get decimalSeparator => ',';
  @override
  String get thousandsSeparator => '.';
  @override
  String get thousandsSuffix => 'k';
  @override
  String get millionsSuffix => 'Mio.';
  @override
  String money(String amount, String symbol) => '$amount\u00A0$symbol';
  @override
  String percent(int value) => '$value\u00A0%';

  @override
  String get spendTitle => 'Ausgaben';
  @override
  String get spendAdminsOnly => 'Ausgaben sehen nur Admins.';
  @override
  String get spendEmpty => 'In diesem Monat ist noch nichts erfasst.';
  @override
  String get spendEmptyEnrolled =>
      'Noch nichts in diesem Monat. Die nächste Apple-Pay-Zahlung landet automatisch hier.';

  @override
  String get spendByCategory => 'Nach Kategorie';
  @override
  String get spendTopMerchants => 'Nach Geschäft';
  @override
  String get spendByMember => 'Nach Person';

  @override
  String get spendOtherCategories => 'Sonstige';
  @override
  String get spendAllPurchases => 'Alle Ausgaben';
  @override
  String get spendFormerMember => 'Ehemaliges Mitglied';

  @override
  String spendCountShort(int count) => count == 1 ? '1 Zahlung' : '$count Zahlungen';

  @override
  String spendPaymentsWord(int count) => count == 1 ? 'Zahlung' : 'Zahlungen';

  @override
  String get spendChartTrend => 'Verlauf';
  @override
  String get spendChartBars => 'Balken';
  @override
  String get spendChartRing => 'Ring';

  @override
  String get spendRangeWeek => '1 W.';
  @override
  String get spendRangeMonth => '1 M.';
  @override
  String get spendRangeHalfYear => '6 M.';
  @override
  String get spendRangeYear => '1 J.';

  @override
  String get spendRangeThisWeek => 'Diese Woche';
  @override
  String get spendRangeThisMonth => 'Dieser Monat';
  @override
  String get spendRangeLastSixMonths => 'Letzte 6 Monate';
  @override
  String get spendRangeThisYear => 'Dieses Jahr';

  @override
  String get spendRangePick => 'Zeitraum wählen';

  @override
  String spendAveragePerDay(String amount) => 'Durchschn. $amount pro Tag';
  @override
  String spendAveragePerMonth(String amount) => 'Durchschn. $amount pro Monat';

  @override
  String get spendMetricAll => 'Ausgaben';
  @override
  String get spendShowAll => 'Alle anzeigen';

  @override
  String spendShowAllCount(int count) => 'Alle $count anzeigen';

  @override
  String get spendTotal => 'Gesamt';

  @override
  String get spendIslandThinking => 'Ich rechne nach';
  @override
  String get spendIslandThinkingHint => 'Zahlungen werden geladen';

  @override
  String get spendIslandReviewHint => 'Händler oder Betrag fehlt';

  @override
  String get spendIslandNothing => 'Nichts erfasst';

  @override
  String spendIslandUp(int percent) => '$percent\u00A0% mehr ausgegeben';
  @override
  String spendIslandDown(int percent) => '$percent\u00A0% weniger ausgegeben';
  @override
  String get spendIslandVsPrevious => 'gegenüber dem Zeitraum davor';

  @override
  String spendIslandTop(String category) => '$category ist der größte Posten';
  @override
  String spendIslandTopHint(int percent) => '$percent\u00A0% der Ausgaben';

  @override
  String get spendAdd => 'Ausgabe erfassen';
  @override
  String get spendEdit => 'Ausgabe bearbeiten';
  @override
  String get spendAmount => 'Betrag';
  @override
  String get spendDate => 'Datum';
  @override
  String get spendCategory => 'Kategorie';
  @override
  String get spendLabel => 'Ausgabe';
  @override
  String get spendKindLabel => 'Art';
  @override
  String get spendPaidBy => 'Bezahlt von';
  @override
  String get spendCard => 'Karte';
  @override
  String get spendSourceLabel => 'Erfasst';
  @override
  String get spendSourceWallet => 'Apple Pay';
  @override
  String get spendSourceManual => 'Von Hand';
  @override
  String get spendNote => 'Notiz';
  @override
  String get spendCategoryAuto => 'Automatisch';
  @override
  String get spendMerchantPlaceholder => 'Wo? z.\u00A0B. REWE';
  @override
  String get spendNotePlaceholder => 'Notiz (optional)';
  @override
  String get spendKindQuestion => 'Was für eine Ausgabe?';
  @override
  String get spendKindBudget => 'Fix';
  @override
  String get spendKindExtra => 'Extra';
  @override
  String get spendNeedsMerchantAndAmount => 'Händler und Betrag fehlen noch.';
  @override
  String get spendSaved => 'Ausgabe gespeichert';
  @override
  String get spendUpdated => 'Ausgabe aktualisiert';
  @override
  String get spendDeleted => 'Ausgabe gelöscht';

  @override
  String spendReviewTitle(int count) =>
      count == 1 ? 'Eine Zahlung braucht dich kurz' : '$count Zahlungen brauchen dich kurz';
  @override
  String get spendReviewBody =>
      'Apple hat Händler oder Betrag nicht mitgeliefert. Tippe die Zeile an und ergänze sie.';
  @override
  String get spendReviewDetail =>
      'Apple hat Händler oder Betrag nicht mitgeliefert. Tippe oben auf den Stift und ergänze die Zeile.';

  @override
  String get spendLoadFailed => 'Die Ausgaben konnten nicht geladen werden.';
  @override
  String get spendSaveFailed => 'Die Ausgabe konnte nicht gespeichert werden.';
  @override
  String get spendDeleteFailed => 'Die Ausgabe konnte nicht gelöscht werden.';
  @override
  String get spendEnrolFailed => 'Dieses Gerät konnte nicht aktiviert werden.';

  @override
  String get spendWalletTitle => 'Apple Pay automatisch erfassen';
  @override
  String get spendWalletIntro =>
      'Jede Zahlung mit diesem iPhone landet danach von allein hier. Ohne Link, ohne Code — du richtest nur einmal eine Kurzbefehl-Automation ein.';
  @override
  String get spendWalletEnable => 'Dieses iPhone aktivieren';
  @override
  String get spendWalletUnsupported =>
      'Das automatische Erfassen gibt es auf iPhone und Android. Auf anderen Geräten trägst du Ausgaben von Hand ein.';
  @override
  String get spendWalletEnabled => 'Gerät aktiviert';
  @override
  String get spendWalletActive => 'Dieses iPhone ist aktiviert';
  @override
  String get spendWalletInactive => 'Dieses iPhone ist noch nicht aktiviert';
  @override
  String get spendWalletStepsTitle => 'Noch einmal in der Kurzbefehle-App';
  @override
  String get spendWalletStep1 => 'Kurzbefehle öffnen, unten auf „Automation".';
  @override
  String get spendWalletStep2 => 'Auf „+", dann „Wallet" wählen.';
  @override
  String get spendWalletStep3 => 'Karten auswählen und „Sofort ausführen".';
  @override
  String get spendWalletStep4 => 'Als Aktion „Ausgabe erfassen" wählen — sie steht schon in der Liste.';
  @override
  String get spendWalletStep5 =>
      'In der Aktion „Händler" und „Betrag" antippen und die passende Variable der Automation einsetzen — sonst fragt der Kurzbefehl nach und erfasst nichts.';
  @override
  String get spendWalletOpenShortcuts => 'Kurzbefehle öffnen';
  @override
  String get settingsWalletCapture => 'Wallet-Erkennung';
  @override
  String get walletCapturePageDesc =>
      'Zahlungen mit dem Handy landen von allein bei den Ausgaben. Hier aktivierst du dieses Gerät — und nimmst jedes wieder zurück.';
  @override
  String get spendWalletAndroidTitle => 'Zahlungen automatisch erfassen';
  @override
  String get spendWalletAndroidIntro =>
      'Wenn du mit dem Handy bezahlst, meldet dir die Wallet den Betrag. aporah liest genau diese eine Meldung und trägt die Ausgabe ein — ohne Bank, ohne Login, ohne Abtippen.';
  @override
  String get spendWalletAndroidEnable => 'Dieses Gerät aktivieren';
  @override
  String get spendWalletAndroidActive => 'Dieses Gerät erfasst Zahlungen';
  @override
  String get spendWalletAndroidInactive => 'Dieses Gerät ist noch nicht aktiviert';
  @override
  String get spendWalletAndroidDeaf =>
      'Aktiviert, aber ohne Benachrichtigungszugriff — so kommt keine Zahlung an.';
  @override
  String get spendWalletAndroidStepsTitle => 'Zwei Schalter, dann läuft es';
  @override
  String get spendWalletAndroidStep1 => 'Dieses Gerät aktivieren — damit darf es Ausgaben eintragen.';
  @override
  String get spendWalletAndroidStep2 =>
      'In den Systemeinstellungen den Benachrichtigungszugriff für aporah einschalten.';
  @override
  String get spendWalletAndroidStep3 => 'Mit dem Handy bezahlen — die Ausgabe steht danach von allein hier.';
  @override
  String get spendWalletAndroidNoDevicesHint => 'Mit dem Knopf unten aktivierst du dieses Gerät.';
  @override
  String get spendWalletGrantAccess => 'Benachrichtigungszugriff erlauben';
  @override
  String get spendWalletAccessGranted => 'Zugriff erteilt';
  @override
  String get spendWalletDisclosureTitle => 'Was aporah dabei liest';
  @override
  String get spendWalletDisclosureBody =>
      'Android kennt keinen Zugriff auf eine einzelne App: Benachrichtigungszugriff gilt immer für alle. aporah wertet ausschließlich die Zahlungsmeldungen der Wallet-Apps aus — jede andere Benachrichtigung wird sofort verworfen, ohne gelesen, gespeichert oder gezählt zu werden. Das Gerät verlässt nur Händler, Betrag, die letzten Ziffern der Karte und der Zeitpunkt. Nie der Text einer Benachrichtigung.';
  @override
  String get spendWalletAndroidSources => 'Erkannt werden Google Wallet, Google Pay und Samsung Wallet.';
  @override
  String get settingsApplePay => 'Apple Pay';
  @override
  String get applePayPageDesc =>
      'Zahlungen mit Apple Pay landen von allein bei den Ausgaben. Hier aktivierst du dieses iPhone — und nimmst jedes Gerät wieder zurück.';
  @override
  String get spendWalletNoDevices => 'Noch kein Gerät aktiviert';
  @override
  String get spendWalletNoDevicesHint => 'Mit dem Knopf unten aktivierst du dieses iPhone.';
  @override
  String get spendWalletDevicesLabel => 'Aktivierte Geräte';
  @override
  String get spendWalletDeviceUnused => 'Noch nichts erfasst';
  @override
  String spendWalletDeviceLastUsed(String date) => 'Zuletzt am $date';
  @override
  String spendWalletDeviceCount(int count) => count == 0
      ? 'Keins'
      : count == 1
      ? '1 Gerät'
      : '$count Geräte';
  @override
  String get spendWalletRevoke => 'Entfernen';
  @override
  String get spendWalletRenameTitle => 'Gerät umbenennen';
  @override
  String get spendWalletRenameBody =>
      'Unter diesem Namen steht das Gerät in der Liste — damit ihr eure Handys auseinanderhaltet.';
  @override
  String get spendWalletDeviceNameHint => 'z. B. iPhone von Anna';
  @override
  String get spendWalletThisDevice => 'Dieses Gerät';
  @override
  String spendWalletOtherOwner(String name) =>
      'Dieses Gerät erfasst Ausgaben für $name — jede Zahlung wird unter diesem Namen eingetragen. Aktiviere es neu, damit deine Zahlungen dir zugeordnet werden.';

  @override
  String get spendCatGroceries => 'Lebensmittel';
  @override
  String get spendCatDrugstore => 'Drogerie';
  @override
  String get spendCatFuel => 'Tanken';
  @override
  String get spendCatRestaurant => 'Restaurant';
  @override
  String get spendCatCafe => 'Bäckerei & Café';
  @override
  String get spendCatShipping => 'Post & Versand';
  @override
  String get spendCatClothing => 'Kleidung';
  @override
  String get spendCatShopping => 'Shopping';
  @override
  String get spendCatElectronics => 'Elektronik';
  @override
  String get spendCatTransport => 'Unterwegs';
  @override
  String get spendCatEntertainment => 'Unterhaltung';
  @override
  String get spendCatHealth => 'Gesundheit';
  @override
  String get spendCatHome => 'Wohnen';
  @override
  String get spendCatOther => 'Sonstiges';

  @override
  String get spendSearchPlaceholder => 'Geschäft, Kategorie, Person';
  @override
  String get spendSearchAction => 'Ausgaben durchsuchen';
  @override
  String get spendViewCategories => 'Kategorien';
  @override
  String get spendNoMatches => 'Keine Ausgaben passen dazu.';
  @override
  String get spendClearFilter => 'Filter entfernen';
  @override
  String get spendBudget => 'Budget';
  @override
  String get spendBudgets => 'Budgets';
  @override
  String get spendBudgetAdd => 'Neues Budget';
  @override
  String get spendBudgetEdit => 'Budget bearbeiten';
  @override
  String get spendBudgetPerMonth => 'Pro Monat';
  @override
  String get spendBudgetHint =>
      'Wie viel darf diese Kategorie im Monat kosten? Die Ringe zeigen, ob ihr im Plan liegt.';
  @override
  String spendBudgetLastMonth(String amount) => 'Letzter Monat: $amount';
  @override
  String get spendBudgetSaved => 'Budget gespeichert';
  @override
  String get spendBudgetDeleted => 'Budget gelöscht';
  @override
  String get spendBudgetSaveFailed => 'Budget konnte nicht gespeichert werden';
  @override
  String get spendBudgetNeedsAmount => 'Bitte einen Betrag eingeben';
  @override
  String spendBudgetOf(String spent, String limit) => '$spent von $limit';
  @override
  String spendBudgetLeft(String amount) => 'Noch $amount übrig';
  @override
  String spendBudgetOver(String amount) => '$amount drüber';
  @override
  String get spendBudgetOnTrack => 'Im Plan';
  @override
  String get spendBudgetAhead => 'Schneller als geplant';
  @override
  String get spendBudgetExceeded => 'Budget überschritten';
  @override
  String spendBudgetLine(String amount) => 'Budget $amount';

  @override
  String get plusName => 'aporah Plus';
  @override
  String get plusPriceMonthly => '4,99 € / Monat';
  @override
  String get plusPriceYearly => '39,99 € / Jahr';
  @override
  String get plusYearlySaving => 'Spart 33 %';
  @override
  String get plusTrialNote => '14 Tage kostenlos testen. Jederzeit kündbar.';

  @override
  String plusForOnly(String price) => 'Für nur $price.';
  @override
  String get plusUpgrade => 'Plus holen';
  @override
  String get plusNotNow => 'Später';
  @override
  String get plusRestore => 'Kauf wiederherstellen';
  @override
  String get plusActive => 'Plus ist aktiv';
  @override
  String plusActiveUntil(String date) => 'Plus läuft bis $date';
  @override
  String get plusDebugOverride => 'Testmodus: Plan wird simuliert';

  @override
  String get plusFreePlan => 'Kostenlos';

  @override
  String get plusWelcome => 'Willkommen bei Plus!';

  @override
  String get plusPurchasePending => 'Der Kauf wartet noch auf Bestätigung. Plus kommt, sobald er durch ist.';

  @override
  String get plusPurchaseFailed => 'Der Kauf hat nicht geklappt. Bitte versuch es noch einmal.';

  @override
  String get plusStoreUnavailable => 'Der App Store ist gerade nicht erreichbar.';

  @override
  String get plusOwnedElsewhere => 'Dieses Abo gehört schon zu einem anderen Haushalt.';

  @override
  String get plusRestored => 'Plus ist wiederhergestellt.';

  @override
  String get plusRestoreNothing => 'Kein aktives Abo zum Wiederherstellen gefunden.';

  @override
  String get searchTermsPlus => 'plus abo abonnement kaufen wiederherstellen premium';

  @override
  String get paywallCalendarsTitle => 'Alle eure Kalender';
  @override
  String get paywallCalendarsBody => 'Mit Plus verbindet ihr so viele Kalender, wie ihr braucht!';
  @override
  String get paywallTrackersTitle => 'Mehr Routinen';
  @override
  String get paywallTrackersBody =>
      'Kostenlos sind drei Routinen dabei. Mit Plus legt ihr so viele an, wie der Alltag hergibt — '
      'Zähneputzen, Müll rausbringen, Vokabeln, jede für sich nachvollziehbar.';
  @override
  String get paywallBoxesTitle => 'Mehr Boxen';
  @override
  String get paywallBoxesBody =>
      'Eine Box ist kostenlos dabei. Mit Plus bekommt jeder Keller, jeder Dachboden und jeder '
      'Umzugskarton seine eigene — mit Foto, damit ihr nicht raten müsst.';
  @override
  String get paywallMembersTitle => 'Mehr Personen';
  @override
  String get paywallMembersBody =>
      'Bis zu vier Personen sind kostenlos dabei. Mit Plus ist der Haushalt so groß, wie er ist — '
      'auch Oma, die Au-pair oder das dritte Kind.';
  @override
  String get paywallPhotosTitle => 'Fotos und Dateien';
  @override
  String get paywallPhotosBody =>
      'Mit Plus bekommt jede Box, jedes Teil darin und jeder Artikel auf der Liste ein Foto — '
      'die Seriennummer auf der Bohrmaschine, das richtige Kabel von dreien. Ein Bild sagt, was '
      'kein Symbol sagen kann.';
  @override
  String get paywallSpendTitle => 'Ausgaben';
  @override
  String get paywallSpendBody =>
      'Mit Plus steht jede Zahlung mit dem Handy von allein hier — sortiert nach Kategorie, '
      'Geschäft und Person. Dazu ein Budget pro Kategorie, das sagt, was noch übrig ist.';

  @override
  String get debugPlanTitle => 'Plan (Debug)';
  @override
  String debugPlanReal(String plan) => 'Echt: $plan';
  @override
  String debugPlanSimulated(String plan) => '$plan (simuliert)';
  // --- Vorhaben ---------------------------------------------------------
  @override
  String get plannerTitle => 'Vorhaben';
  @override
  String get plannerPrompt =>
      'Sag in einem Satz, was du vorhast. Du bekommst die Anleitung und vor allem die Liste, '
      'mit der du einkaufen gehen kannst.';
  @override
  String get plannerHint => 'Was hast du vor?';
  @override
  String get plannerExamplesLabel => 'ZUM BEISPIEL';
  @override
  List<List<PlannerExample>> get plannerExampleGroups => const [
    [
      (text: 'Kindergeburtstag für 8 Kinder', icon: AppIcons.cake),
      (text: 'Silvesterabend für 10 Personen', icon: AppIcons.confetti),
      (text: 'Grillabend im Garten', icon: AppIcons.flame),
      (text: 'Weihnachtsessen für die Familie', icon: AppIcons.treeEvergreen),
      (text: 'Einschulungsfeier vorbereiten', icon: AppIcons.graduationCap),
      (text: 'Koffer für eine Woche Italien', icon: AppIcons.suitcaseRolling),
    ],
    [
      (text: 'Wocheneinkauf für 5 Tage', icon: AppIcons.shoppingCart),
      (text: 'Vorratsschrank auffüllen', icon: AppIcons.package),
      (text: 'Großputz im Badezimmer', icon: AppIcons.sprayBottle),
      (text: 'Hausapotheke auffrischen', icon: AppIcons.bandaids),
      (text: 'Winterkleidung einmotten', icon: AppIcons.tShirt),
      (text: 'Erstausstattung fürs Baby', icon: AppIcons.baby),
    ],
    [
      (text: 'Hochbeet aus Holz bauen', icon: AppIcons.hammer),
      (text: 'Regal fürs Kinderzimmer bauen', icon: AppIcons.ruler),
      (text: 'Wohnzimmer neu streichen', icon: AppIcons.paintRoller),
      (text: 'Balkon bepflanzen', icon: AppIcons.plant),
      (text: 'Fahrräder frühlingsfit machen', icon: AppIcons.bicycle),
      (text: 'Baumhaus für die Kinder', icon: AppIcons.tree),
    ],
    [
      (text: 'Butter Chicken für 4', icon: AppIcons.cookingPot),
      (text: 'Sonntagsbraten für 6', icon: AppIcons.forkKnife),
      (text: 'Pizzateig für den Familienabend', icon: AppIcons.pizza),
      (text: 'Kuchen für das Schulfest', icon: AppIcons.cake),
      (text: 'Brunch für 6 Gäste', icon: AppIcons.egg),
      (text: 'Eis selber machen', icon: AppIcons.iceCream),
    ],
  ];
  @override
  String get plannerGo => 'Liste vorschlagen';
  @override
  String get plannerWorking => 'Wird zusammengestellt …';
  @override
  String get plannerWhatToBuy => 'WAS DU BRAUCHST';
  @override
  String plannerItemCount(int count) => count == 1 ? '1 Artikel' : '$count Artikel';
  @override
  String get plannerHowTo => 'SO GEHT’S';
  @override
  String get plannerShowMethod => 'Alles anzeigen';
  @override
  String get plannerRecipe => 'REZEPT';
  @override
  String get adLabel => 'Anzeige';
  @override
  String get plannerCreateList => 'Liste erstellen';
  @override
  String get plannerAgain => 'Nochmal fragen';
  @override
  String get plannerEditGoal => 'Anders formulieren';
  @override
  String get plannerTypeInstead => 'Selbst eingeben';
  @override
  String get plannerListCreated => 'Liste angelegt';
  @override
  String get plannerUnavailable => 'Das hat gerade nicht geklappt. Versuch es in einem Moment noch einmal.';

  @override
  String get plannerPasteLink => 'Importieren';

  @override
  String get plannerLinkOnClipboard => 'Link in der Zwischenablage';

  @override
  String get plannerClipboardUnreadable =>
      'Die Zwischenablage konnte nicht gelesen werden.';

  @override
  String get plannerNoRecipeOnPage =>
      'Auf dieser Seite war kein Rezept zu finden. Schreib stattdessen einfach, was es geben soll.';
  @override
  String get plannerNoRecipeInVideo =>
      'Unter diesem Video stehen keine Zutaten. Schreib stattdessen einfach, was es geben soll.';
  @override
  String get plannerUnusable =>
      'Daraus konnten wir keine Liste machen. Formulier es etwas konkreter — ein Gericht, ein '
      'Projekt oder ein Anlass.';
  @override
  String get plannerNotConfigured => 'Vorhaben ist gerade nicht eingerichtet.';
  @override
  String get plannerMonthlyLimit =>
      'Die Vorhaben für diesen Monat sind aufgebraucht. Am Monatsersten geht es weiter.';
  @override
  String get plannerDailyLimit => 'Für heute sind es genug Vorhaben. Morgen geht es weiter.';
  @override
  String plannerLeft(int left, int limit) => 'Noch $left von $limit Vorhaben diesen Monat';
  @override
  String plannerNoneLeft(int day, String month) => 'Keine Vorhaben mehr – ab $day. $month wieder';
  @override
  String plannerMonthlyLimitUntil(int day, String month) =>
      'Die Vorhaben für diesen Monat sind aufgebraucht. Ab dem $day. $month geht es weiter.';
  @override
  String plannerDailyLimitAt(String time, {required bool tomorrow}) => tomorrow
      ? 'Für heute sind es genug Vorhaben. Morgen ab $time geht es weiter.'
      : 'Für den Moment sind es genug Vorhaben. Ab $time geht es weiter.';
  @override
  String get plannerLimitsLifted => 'Limits aufgehoben (Test)';
  @override
  String get debugPlannerLimitsTitle => 'Vorhaben-Limits (Debug)';
  @override
  String get debugPlannerLimitsEnforced => 'Aktiv';
  @override
  String get debugPlannerLimitsLifted => 'Aufgehoben';
  @override
  String get plannerIslandLine => 'Sag, was du vorhast.';
  @override
  String get plannerIslandHint => 'Wir machen die Liste daraus';

  // -------------------------------------------------------- notifications --
  @override
  String get notificationsTitle => 'Mitteilungen';
  @override
  String get notificationsPageDesc => 'Was aporah dir aufs Handy schickt – und wann.';
  @override
  String get searchTermsNotifications =>
      'mitteilungen benachrichtigungen erinnerung push notification tagesüberblick abfall müll tonne budget ausgaben';
  @override
  String get notificationsAllowTitle => 'Mitteilungen erlauben';
  @override
  String get notificationsAllowBody => 'Ohne Erlaubnis kommt keine Erinnerung an.';
  @override
  String get notificationsDeniedBody => 'Mitteilungen sind in den Systemeinstellungen ausgeschaltet.';
  @override
  String get notificationsAllow => 'Erlauben';
  @override
  String get notificationsOpenSettings => 'Einstellungen';
  @override
  String get notificationsQuietTitle => 'Werden still zugestellt';
  @override
  String get notificationsQuietBody => 'Mitteilungen landen ohne Ton in der Mitteilungszentrale.';
  @override
  String get notifyBriefTitle => 'Tagesüberblick';
  @override
  String get notifyBriefSubtitle => 'Was an dem Tag ansteht';
  @override
  String get notifyAbfallTitle => 'Müllabfuhr';
  @override
  String get notifyAbfallSubtitle => 'Damit die Tonne rechtzeitig draußen ist';
  @override
  String get notifyAbfallWhen => 'Wann';
  @override
  String get notifyAbfallAdd => 'Weitere Erinnerung';
  @override
  String notifyAbfallMax(int count) => 'Höchstens $count';
  @override
  String reminderCount(int count) => '$count Erinnerungen';
  @override
  String get abfallDayBefore => 'Am Vortag';
  @override
  String get abfallSameDay => 'Am Abholtag';
  @override
  String get notifyTaskTimesTitle => 'To-dos mit Uhrzeit';
  @override
  String get notifyTaskTimesSubtitle => 'Zur Uhrzeit, die du gesetzt hast';
  @override
  String get notifyBudgetsTitle => 'Budgets';
  @override
  String get notifyBudgetsSubtitle => 'Wenn ein Budget dem Monat vorausläuft oder überschritten ist';
  @override
  String get notifyTime => 'Uhrzeit';
  @override
  String get notificationsEventNote =>
      'Eine Erinnerung an einen Termin stellst du direkt am Termin ein. Sie gilt nur auf diesem Gerät.';
  @override
  String get reminderNone => 'Keine';
  @override
  String get reminderAtStart => 'Zu Beginn';
  @override
  String reminderHoursBefore(int hours) => hours == 1 ? '1 Stunde vorher' : '$hours Stunden vorher';
  @override
  String reminderDaysBefore(int days) => days == 1 ? '1 Tag vorher' : '$days Tage vorher';
  @override
  String reminderDayBefore(String time) => 'Am Vortag um $time';
  @override
  String reminderMorningOf(String time) => 'Am selben Tag um $time';
  @override
  String get firstStepBinReminder => 'Müll-Erinnerung einschalten';
  @override
  String get firstStepBinReminderBody => 'Am Vorabend, bevor die Tonne raus muss.';
  @override
  String get reminderAbfallShared => 'Gilt für alle Abholtermine – wie in den Einstellungen';
  @override
  String get reminderAbfallCustom => 'Andere Uhrzeit…';
  @override
  String reminderCalendarAlready(String label) => 'Dein Kalender erinnert bereits: $label';
  @override
  String get reminderDenied => 'Mitteilungen sind ausgeschaltet – in den Einstellungen erlauben.';
  @override
  String get noticeBriefTitle => 'Dein Tag';
  @override
  String briefEvents(int count) => count == 1 ? '1 Termin' : '$count Termine';
  @override
  String briefFirstAt(String time) => 'ab $time';
  @override
  String briefTasks(int count) => count == 1 ? '1 To-do fällig' : '$count To-dos fällig';
  @override
  String noticeAbfallTitle(String bins) => '$bins schon rausgestellt?';
  @override
  String get noticeAbfallBody => 'Die Abholung ist morgen früh.';
  @override
  String get noticeAbfallBodyToday => 'Die Abholung ist heute.';
  @override
  String noticeTaskDue(String time) => 'Fällig um $time';
  @override
  String noticeBudgetAheadOne(String category) => '$category läuft dem Monat voraus';
  @override
  String noticeBudgetAheadMany(int count) => '$count Budgets laufen dem Monat voraus';
  @override
  String noticeBudgetOverOne(String category) => '$category ist überschritten';
  @override
  String noticeBudgetOverMany(int count) => '$count Budgets sind überschritten';
  @override
  String noticeBudgetAmount(String spent, String limit) => '$spent von $limit';
  @override
  String joinAnd(List<String> parts) =>
      parts.length < 2 ? parts.join() : '${parts.sublist(0, parts.length - 1).join(', ')} und ${parts.last}';
  @override
  String get rateApp => 'aporah bewerten';
  @override
  String get searchTermsRate => 'bewerten bewertung sterne app store rezension rate review';

  // -------------------------------------------------------------- app lock --
  @override
  String get appLockSubtitle => 'Beim Öffnen der App fragen';
  @override
  String get appLockLockedTitle => 'aporah ist gesperrt';
  @override
  String get appLockUnlockReason => 'aporah entsperren';
  @override
  String get appLockEnableReason => 'App-Sperre einschalten';
  @override
  String get appLockDisableReason => 'App-Sperre ausschalten';
  @override
  String unlockWith(String method) => 'Mit $method entsperren';
  @override
  String get biometricFingerprint => 'Fingerabdruck';
  @override
  String get biometricFace => 'Gesichtserkennung';
  @override
  String get biometricGeneric => 'Biometrie';
  @override
  String get biometricPasscode => 'Gerätecode';
  @override
  String get searchTermsAppLock => 'face id touch id optic id fingerabdruck gesicht app-sperre sperre sperren entsperren biometrie sicherheit code datenschutz';
  @override
  String get biometricFaceId => 'Face ID';
  @override
  String get biometricTouchId => 'Touch ID';
  @override
  String get biometricOpticId => 'Optic ID';
}
