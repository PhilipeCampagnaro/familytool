import '../data/german_holidays.dart';
import '../models/grocery_unit.dart';
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
        '', 'Januar', 'Februar', 'März', 'April', 'Mai', 'Juni',
        'Juli', 'August', 'September', 'Oktober', 'November', 'Dezember',
      ];
  @override
  List<String> get monthShort => const [
        '', 'Jan', 'Feb', 'Mär', 'Apr', 'Mai', 'Jun',
        'Jul', 'Aug', 'Sep', 'Okt', 'Nov', 'Dez',
      ];
  @override
  List<String> get weekdayShort => const ['So', 'Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa'];
  @override
  List<String> get weekdayLong =>
      const ['Sonntag', 'Montag', 'Dienstag', 'Mittwoch', 'Donnerstag', 'Freitag', 'Samstag'];
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
  String dayRangeSameMonth(int fromDay, int toDay, int month) =>
      '$fromDay. – $toDay. ${monthNames[month]}';
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
  String get reload => 'Erneut laden';
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
  String get emailAddress => 'E-Mail-Adresse';
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

  @override
  String get startNotDesigned => 'Noch nicht gestaltet';

  // ---------------------------------------------------------------- board --
  @override
  String get boardTitle => 'Board';
  @override
  String doneCountSeparator(int count) => 'Erledigt · $count';
  @override
  String get newTask => 'Neue Aufgabe';
  @override
  String get editTask => 'Aufgabe bearbeiten';
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
  String get theTask => 'die Aufgabe';
  @override
  String get deleteTask => 'Aufgabe löschen';
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
  String get kindTask => 'Aufgabe';
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
  String timesPerWeekValue(int times) =>
      times == 1 ? 'Einmal pro Woche' : '$times-mal pro Woche';
  @override
  String get timesPerWeekExplainer =>
      'Es zählt die Woche, nicht der Tag. Nichts ist an einem bestimmten Tag fällig — gezählt wird, wenn die Woche am Sonntag zu Ende ist.';
  @override
  String get trackersTitle => 'Tracker';
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
  String get trackerBackfillHint => 'Tippe einen Tag an, um ihn nachzutragen.';
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
  String get noOpenTasks => 'Keine offenen Aufgaben';
  @override
  String get addTask => 'Aufgabe hinzufügen';
  @override
  String get tasksLoadFailed => 'Aufgaben konnten nicht geladen werden.';
  @override
  String get taskSaveFailed => 'Die Aufgabe konnte nicht gespeichert werden.';
  @override
  String get changeSaveFailed => 'Die Änderung konnte nicht gespeichert werden.';
  @override
  String get saveFailed => 'Konnte nicht gespeichert werden.';
  @override
  String get someDoneTasksNotDeleted => 'Nicht alle erledigten Aufgaben konnten gelöscht werden.';
  @override
  String get doneTasksDeleteFailed => 'Die erledigten Aufgaben konnten nicht gelöscht werden.';
  @override
  String get taskDeleteFailed => 'Die Aufgabe konnte nicht gelöscht werden.';
  @override
  String get taskCreated => 'Aufgabe erstellt';
  @override
  String get taskUpdated => 'Aufgabe aktualisiert';
  @override
  String get taskDeleted => 'Aufgabe gelöscht';
  @override
  String get taskRestoreFailed => 'Die Aufgabe konnte nicht wiederhergestellt werden.';

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
  String get files => 'Dateien';
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
  String get repeats => 'Wiederholt sich';
  @override
  String get repeatNotEditable =>
      'Die Wiederholung lässt sich hier nicht ändern — nur im Kalender selbst.';
  @override
  String get repeatingEvent => 'Terminserie';
  @override
  String get changeRepeatingEventBody =>
      'Soll die Änderung nur für diesen Termin gelten oder für die ganze Serie?';
  @override
  String get deleteRepeatingEventBody =>
      'Soll nur dieser Termin gelöscht werden oder die ganze Serie?';
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
  String get createTaskFromEvent => 'Aufgabe zum Termin erstellen';
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
  String linkedTaskCount(int count) => count == 1 ? '1 Aufgabe' : '$count Aufgaben';
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
  String get calendarNotEditable => 'Dieser Kalender lässt sich in Aporah nicht bearbeiten.';
  @override
  String get eventDeleteFailed => 'Der Termin konnte nicht gelöscht werden.';
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
  String get eventSaveFailedRemote =>
      'Der Termin konnte nicht im verbundenen Kalender gespeichert werden.';

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
  String get connectCalendarsIntro =>
      'Sieh die Termine deiner Familie in der App — Schule, Abfallabfuhr und '
      'private Kalender an einem Ort.';
  @override
  String get connectCalendarsAdminNote =>
      'Kalender verbindet ein Erwachsener im Haushalt.';
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
  String get renameCalendar => 'Kalender umbenennen';
  @override
  String get renameCalendarBody =>
      'Unter diesem Namen taucht der Kalender in Aporah auf — im Kalender, '
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
  String get accountStaysConnected =>
      'Das Konto bleibt verbunden — die anderen Kalender darin auch.';
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
      'Du meldest dich bei $provider an. Aporah sieht nur deine Kalender — '
      'nie dein Passwort.';
  @override
  String get openingEllipsis => 'Wird geöffnet …';
  @override
  String signInWithProvider(String provider) => 'Mit $provider anmelden';
  @override
  String get comeBackWhenDone =>
      'Komm zurück, sobald du im Browser fertig bist.';
  @override
  String get connectedDot => 'Verbunden.';
  @override
  String calendarsFoundPickThem(int count) =>
      '$count Kalender gefunden. Wähl aus, welche in Aporah erscheinen sollen.';
  @override
  String get nameYourCalendarBody =>
      'So heißt der Kalender in Aporah. Du kannst ihn jetzt umbenennen.';
  @override
  String get nameEachCalendarBody =>
      'So heißen die Kalender in Aporah. Du kannst sie jetzt umbenennen.';
  @override
  String get whichCalendars => 'Kalender';
  @override
  String get whichCalendarsHint =>
      'Nur die ausgewählten erscheinen in Aporah. Das kannst du später ändern.';
  @override
  String get readOnlyCalendar => 'Nur lesen';
  @override
  String get pickAtLeastOneCalendar => 'Wähl mindestens einen Kalender aus.';
  @override
  String get selectAll => 'Alle auswählen';
  @override
  String get deselectAll => 'Alle abwählen';
  @override
  String calendarsSelected(int count) =>
      count == 1 ? '1 Kalender ausgewählt' : '$count Kalender ausgewählt';
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
    'Unter „Freigaben" auf „Kalender publizieren".',
    'Den erzeugten iCal-Link kopieren und hier einsetzen.',
  ];
  @override
  String get pasteCalendarLink => 'Kalender-Link';
  @override
  String get pasteCalendarLinkHint =>
      'Wir rufen den Link jetzt ab – so wisst ihr sofort, ob er stimmt.';
  @override
  String get whoseCalendar => 'Für wen ist dieser Zugang?';
  @override
  String get whoseCalendarHint =>
      'Steht später auf dem Filter im Kalender, z. B. „IServ · Alice".';
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
  String get addAnotherCalendar => 'Kalender hinzufügen';
  @override
  String get addAnotherCalendarBody =>
      'Für jeden Kalender gibt es in der Schulplattform einen eigenen Link. '
      'Alle Links dieses Zugangs landen unter einem Filter im Kalender.';
  @override
  String get schoolCalendars => 'Kalender';
  @override
  String get removeCalendar => 'Kalender entfernen';
  @override
  String get linkStaysAtSchool =>
      ' Der Link bleibt in der Schulplattform bestehen — wir merken ihn uns nur nicht mehr.';
  @override
  String get connectWithLogin => 'Stattdessen mit Zugangsdaten anmelden';
  @override
  String get connectWithLoginBody =>
      'Nur sinnvoll, wenn eure Schule CalDAV freigegeben hat. Aufgaben und '
      'Klausuren stehen dort nicht – dafür braucht es die Links oben.';
  @override
  String get linkedCalendarsNote =>
      'Aporah liest diese Kalender nur. Termine ändert ihr weiterhin in der Schulplattform.';
  @override
  String eventsFoundAtLink(int count) =>
      count == 1 ? '1 Termin gefunden' : '$count Termine gefunden';
  @override
  String get noEventsAtLinkYet =>
      'Der Link funktioniert, enthält aber gerade keine Termine. Das ist in den Ferien normal.';
  @override
  List<String> get webuntisSecretSteps => const [
    'Dein Kind meldet sich in WebUntis an und tippt oben auf seinen Namen.',
    'Unter „Freigaben" bei „Zugriff über Untis Mobile" auf „Anzeigen".',
    'Den QR-Code hier scannen – oder die vier Zeilen darunter abtippen.',
  ];
  @override
  String get scanUntisCode => 'QR-Code scannen';
  @override
  String get scanUntisCodeBody =>
      'Wir holen damit den Stundenplan direkt aus WebUntis – mit Vertretung und '
      'Entfall. Das Passwort deines Kindes braucht es dafür nicht.';
  @override
  String get scanAgain => 'Neu scannen';
  @override
  String get codeScanned => 'QR-Code gescannt';
  @override
  String get enterManually => 'Stattdessen abtippen';
  @override
  String get untisServerField => 'Url';
  @override
  String get untisSchoolField => 'Schule';
  @override
  String get untisUserField => 'Benutzer';
  @override
  String get untisKeyField => 'Schlüssel';
  @override
  String get untisFieldsHint => 'Genau so, wie es unter dem QR-Code steht.';
  @override
  String get untisFieldsMissing => 'Bitte Url, Schule, Benutzer und Schlüssel eintragen.';
  @override
  String get checkingAccessEllipsis => 'Zugang wird geprüft …';
  @override
  String get cameraNotAvailable =>
      'Auf diesem Gerät lässt sich nichts scannen. Tipp die vier Zeilen unter dem QR-Code ab.';
  @override
  String get cameraDenied =>
      'Aporah darf nicht auf die Kamera. Das lässt sich in den Einstellungen ändern – '
      'oder tipp die vier Zeilen unter dem QR-Code ab.';
  @override
  String get notAnUntisCode => 'Das ist kein WebUntis-Code. Ist es der aus „Zugriff über Untis Mobile"?';
  @override
  String get untisCalendarName => 'Name des Stundenplans';
  @override
  String untisCalendarNameSuggestion(String pupil) => 'Stundenplan $pupil';
  @override
  String get untisCalendarNameHint => 'Steht später auf dem Filter im Kalender.';
  @override
  String get untisConnectedNote =>
      'Aporah liest den Stundenplan nur – und immer frisch, samt Vertretung und Entfall. '
      'Geändert wird er weiterhin in der Schule.';
  @override
  String lessonsFound(int count) =>
      count == 1 ? '1 Stunde in den nächsten zwei Wochen' : '$count Stunden in den nächsten zwei Wochen';
  @override
  String get noLessonsYet =>
      'Der Zugang funktioniert, es steht aber gerade kein Unterricht an. In den Ferien ist das normal.';
  @override
  String get connectWithLink => 'Stattdessen einen Kalender-Link einsetzen';
  @override
  String get connectWithLinkBody =>
      'Nötig, wenn eure Schule den Zugriff über Untis Mobile abgeschaltet hat. '
      'Der Link zeigt den Stundenplan, aber keine Vertretung.';
  @override
  String get untisKeyStaysValid =>
      ' Der Zugangsschlüssel wird bei uns gelöscht. In WebUntis bleibt er gültig — '
      'dort lässt er sich unter „Freigaben" neu vergeben.';
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
  String get calendarNameInAporah =>
      'So heißt der Kalender in Aporah. Du kannst ihn später umbenennen.';

  // -------------------------------------------------------- provider meta --
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
  String get providerIservDesc => 'Aufgaben, Klausuren und Klassenkalender aus IServ.';
  @override
  String get providerWebuntisDesc => 'Den Stundenplan aus WebUntis anzeigen.';
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
  String get editingAllowed => 'Bearbeiten erlaubt';
  @override
  String get canCheckAndAdd => 'Kann abhaken und ergänzen';
  @override
  String get canOnlyView => 'Kann nur ansehen';
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
  String get mayEdit => 'Darf bearbeiten';
  @override
  String get viewOnly => 'Nur ansehen';
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
  String wholeFamilySees(String noun) =>
      'Für die ganze Familie — alle können $noun sehen und bearbeiten.';
  @override
  String onlyYouSee(String noun) => 'Nur für dich sichtbar — niemand sonst sieht $noun.';
  @override
  String youAndOthersSee(String names, String noun) => 'Nur du und $names sehen $noun.';
  @override
  String joinNames(List<String> names) => names.length == 1
      ? names.first
      : '${names.sublist(0, names.length - 1).join(', ')} und ${names.last}';

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
  String get darkMode => 'Dunkelmodus';
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
      'Noch niemand im Haushalt.\nLade jemanden ein, um Listen, Aufgaben und Termine zu teilen.';
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
  String get languageGermanRegion => 'Deutschland';
  @override
  String get languageEnglishRegion => 'United Kingdom';

  @override
  String get searchTermsProfile => 'profil konto account name anzeigename avatar farbe rolle admin';
  @override
  String get searchTermsFamily =>
      'familie familienmitglieder mitglieder personen einladen rolle rollen kind kinder admin';
  @override
  String get searchTermsCalendar =>
      'kalender termine verbindungen verbinden google outlook icloud iserv ferien abfall schule';
  @override
  String get searchTermsLanguage => 'sprache language deutsch english übersetzung';
  @override
  String get searchTermsDarkMode =>
      'dunkelmodus dark mode darstellung erscheinungsbild hell dunkel nacht theme';
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
      'In wenigen Schritten lädst du deine Familie ein und verbindest die Kalender, '
      'die für euren Alltag wichtig sind.';
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
  String get onboardRenameLater =>
      'Umbenennen könnt ihr die Kalender später unter Einstellungen → Kalender.';
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
  String get welcomeToAporah => 'Willkommen bei Aporah';
  @override
  String get welcomeBack => 'Willkommen zurück';
  @override
  String get signUpBlurb =>
      'Leg dein Konto an. Dein Haushalt wird automatisch erstellt — Familie einladen kannst du danach.';
  @override
  String get signInBlurb => 'Melde dich mit deiner E-Mail-Adresse an.';
  @override
  String get yourName => 'Dein Name';
  @override
  String get atLeast8Chars => 'Mindestens 8 Zeichen.';
  @override
  String get createAccount => 'Konto erstellen';
  @override
  String get signIn => 'Anmelden';
  @override
  String get haveAccountAlready => 'Ich habe schon ein Konto';
  @override
  String get newHereCreateAccount => 'Neu hier? Konto erstellen';
  @override
  String get forgotPassword => 'Passwort vergessen?';
  @override
  String get almostThere => 'Fast geschafft';
  @override
  String confirmMailSent(String email) =>
      'Wir haben dir eine E-Mail an $email geschickt. Klick den Link darin, dann kannst du dich anmelden.';
  @override
  String get toSignIn => 'Zur Anmeldung';
  @override
  String get pleaseEnterName => 'Bitte gib deinen Namen ein.';
  @override
  String get noConnectionTryAgain => 'Keine Verbindung. Bitte versuch es noch einmal.';
  @override
  String get pleaseEnterEmailFirst => 'Bitte gib zuerst deine E-Mail-Adresse ein.';
  @override
  String get resetMailSent => 'Wir haben dir eine E-Mail zum Zurücksetzen geschickt.';
  @override
  String get wrongCredentials => 'E-Mail-Adresse oder Passwort stimmt nicht.';
  @override
  String get confirmEmailFirst => 'Bitte bestätige zuerst deine E-Mail-Adresse.';
  @override
  String get accountExists => 'Für diese E-Mail-Adresse gibt es schon ein Konto.';
  @override
  String get passwordTooShort => 'Das Passwort ist zu kurz.';
  @override
  String get passwordLeaked =>
      'Dieses Passwort taucht in bekannten Daten-Leaks auf. Bitte wähl ein anderes.';
  @override
  String get tooManyAttempts => 'Zu viele Versuche. Bitte warte einen Moment.';
  @override
  String get emailLooksInvalid => 'Diese E-Mail-Adresse sieht nicht gültig aus.';
  @override
  String get signInFailed => 'Anmeldung fehlgeschlagen. Bitte versuch es noch einmal.';

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

  // --------------------------------------------------------------- homework --
  @override
  String get homework => 'Hausaufgabe';
  @override
  String homeworkCount(int count) => count == 1 ? 'Hausaufgabe' : '$count Hausaufgaben';
  @override
  String get homeworkDue => 'Fällig';
  @override
  String get homeworkDone => 'Erledigt';
  @override
  String get homeworkSetBy => 'Aufgegeben von';

  @override
  String get untisPupilName => 'Wessen Stundenplan ist das?';
  @override
  String get untisPupilNameHint => 'Der Name erscheint als Filter in Kalender und Board.';
  @override
  String get untisPupilMissing => 'Zu wem gehört dieser Stundenplan?';

  @override
  String get assignCalendar => 'Zuordnen';
  @override
  String assignCalendarBody(String calendar) => 'Zu wem gehört „$calendar“? Der Kalender erscheint dann unter dieser Person in Kalender und Board.';
  @override
  String get assignCalendarFamilyHint => 'Gehört allen im Haushalt';
  @override
  String get assignCalendarNewPerson => 'Andere Person';
  @override
  String get assignCalendarNewPersonHint => 'Name, z. B. Mia';
  @override
  String get assignCalendarNotVisibility => 'Das ändert nichts daran, wer den Kalender sieht — alle im Haushalt sehen ihn weiterhin.';
  @override
  String get assignCalendarFailed => 'Die Zuordnung hat gerade nicht geklappt.';
  @override
  String get family => 'Familie';
  @override
  String get noAccountYet => 'Kein Konto';

  @override
  String get familyName => 'Familienname';
  @override
  String get familyNameHint => 'Wie eure Familie in Aporah heißt.';
  @override
  String get renameFamily => 'Familie umbenennen';
  @override
  String get renameFamilyBody => 'Der Name steht auf dem Familien-Chip in Kalender und Board.';
  @override
  String get familyRenameFailed => 'Der Name konnte nicht geändert werden.';
}
