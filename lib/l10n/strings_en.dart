import '../data/german_holidays.dart';
import '../models/grocery_unit.dart';
import '../theme/app_icons.dart';
import 'app_strings.dart';

/// English. Written for a family living in Germany who prefer an English
/// interface, so German proper nouns stay German where translating them would
/// stop them matching the real world: the Bundesland names, the bin names the
/// waste vendors publish, and shop names.
class StringsEn extends AppStrings {
  const StringsEn();

  @override
  String get localeCode => 'en';
  @override
  bool get use24HourClock => false;

  // ---------------------------------------------------------------- dates --
  @override
  List<String> get monthNames => const [
    '',
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  @override
  List<String> get monthShort => const [
    '',
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  @override
  List<String> get weekdayShort => const ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
  @override
  List<String> get weekdayLong => const [
    'Sunday',
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
  ];
  @override
  List<String> get dayLetters => const ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  // No ordinal dot: `13 August`, not `13. August`.
  @override
  String dayMonth(int day, int month) => '$day ${monthNames[month]}';
  @override
  String dayMonthShort(int day, int month) => '$day ${monthShort[month]}';
  @override
  String todayWithDate(int day, int month) => 'Today, ${dayMonth(day, month)}';
  @override
  String weekdayWithDate(int weekday, int day, int month) =>
      '${weekdayLong[weekday]}, ${dayMonth(day, month)}';
  @override
  String monthYear(int month, int year) => '${monthNames[month]} $year';
  @override
  String dateRange(String from, String to) => '$from\u00A0– $to';
  @override
  String dayRangeSameMonth(int fromDay, int toDay, int month) => '$fromDay – $toDay ${monthNames[month]}';
  @override
  String dayRangeCrossMonth(int fromDay, int fromMonth, int toDay, int toMonth) =>
      '$fromDay ${monthNames[fromMonth]} – $toDay ${monthNames[toMonth]}';
  @override
  String weekdayWithDateShort(int weekday, int day, int month) =>
      '${weekdayLong[weekday]}, $day ${monthShort[month]}';

  // --------------------------------------------------------------- common --
  @override
  String get cancel => 'Cancel';
  @override
  String get delete => 'Delete';
  @override
  String get edit => 'Edit';
  @override
  String get share => 'Share';
  @override
  String get close => 'Close';
  @override
  String get doneAction => 'Done';
  @override
  String get add => 'Add';
  @override
  String get rename => 'Rename';
  @override
  String get remove => 'Remove';
  @override
  String get disconnect => 'Disconnect';
  @override
  String get undo => 'Undo';
  @override
  String get restored => 'Restored';
  @override
  String get beingRestored => 'Restoring …';
  @override
  String get reload => 'Reload';

  @override
  String get showFullName => 'Show full name';

  @override
  String get hideFullName => 'Collapse name';

  @override
  String get notes => 'Notes';
  @override
  String get addNotes => 'Add notes';
  @override
  String get name => 'Name';
  @override
  String get unknown => 'Unknown';
  @override
  String get next => 'Next';
  @override
  String get skip => 'Skip';
  @override
  String get letsGo => 'Let\'s go';
  @override
  String get today => 'Today';
  @override
  String get allDay => 'All day';
  @override
  String get place => 'Place';
  @override
  String get searchPlace => 'Search a place or business';
  @override
  String get noPlacesFound => 'No places found';
  @override
  String get quantity => 'Quantity';
  @override
  String get unit => 'Unit';
  @override
  // Metric either way: this is a household shopping in Germany, so the packet
  // says 500 g whichever language the app is in.
  String unitName(GroceryUnit unit) => switch (unit) {
    GroceryUnit.piece => 'Piece',
    GroceryUnit.gram => 'g',
    GroceryUnit.kilogram => 'kg',
    GroceryUnit.milliliter => 'ml',
    GroceryUnit.liter => 'l',
    GroceryUnit.pack => 'Pack',
    GroceryUnit.can => 'Can',
    GroceryUnit.bottle => 'Bottle',
    GroceryUnit.bunch => 'Bunch',
    GroceryUnit.glass => 'Jar',
  };
  @override
  String get size => 'Size';
  @override
  String get titleLabel => 'Title';
  @override
  String get role => 'Role';
  @override
  String get nameOptional => 'Name (optional)';
  @override
  String get password => 'Password';
  @override
  String get calendar => 'Calendar';
  @override
  String get somethingWentWrong => 'That didn\'t work just now.';
  @override
  String get noServerConnection => 'No connection to the server.';
  @override
  String get serverTooSlow => 'The server took too long. Please try again.';
  @override
  String get notSignedIn => 'Nobody is signed in.';
  @override
  String get householdNotLoaded => 'Your household hasn\'t loaded yet.';

  // ------------------------------------------------------------------ nav --
  @override
  String get navHome => 'Home';
  @override
  String get navCalendar => 'Calendar';
  @override
  String get navLists => 'Lists';
  @override
  String get navBoard => 'Board';
  @override
  String get navBox => 'Box';
  @override
  String get navExpand => 'Show navigation';

  // ---------------------------------------------------------------- board --
  @override
  String get boardTitle => 'Board';
  @override
  String doneCountSeparator(int count) => 'Done · $count';
  @override
  String get newTask => 'New to-do';
  @override
  String get editTask => 'Edit to-do';
  @override
  String get taskPlaceholder => 'What needs doing?';
  @override
  String get dueLabel => 'Due';
  @override
  String get dueNone => '—';
  @override
  String get sectionOverdue => 'Overdue';
  @override
  String get sectionToday => 'Today';
  @override
  String get sectionTomorrow => 'Tomorrow';
  @override
  String get sectionThisWeek => 'This week';
  @override
  String get sectionLater => 'Later';
  @override
  String get sectionUndated => 'No date';
  @override
  String get dueThisWeekend => 'Weekend';
  @override
  String get dueNextWeek => 'Next week';
  @override
  String get duePickDate => 'Pick a date …';
  @override
  String get dueTimeLabel => 'Time';
  @override
  String get dueNoTime => 'No time';
  @override
  String get dueTimeNeedsDate => 'Pick a date first';
  @override
  String get theTask => 'the to-do';
  @override
  String get deleteTask => 'Delete to-do';
  @override
  String get assigneeLabel => 'Assigned to';
  @override
  String get nobody => 'Nobody';
  @override
  String get me => 'Me';
  @override
  String get nothingPlanned => 'Nothing planned';
  @override
  String doneOfTotal(int done, int total) => '$done of $total done';
  @override
  String get trackerTitle => 'Tracker';
  @override
  String trackerDaysDone(int done, int total) => '$done of $total days completed';

  // ------------------------------------------------------------- Tracker --
  @override
  String get whatToCreate => 'What are you adding?';
  @override
  String get newEntry => 'New';
  @override
  String get kindTask => 'To-do';
  @override
  String get kindTracker => 'Tracker';
  @override
  String get newTracker => 'New tracker';
  @override
  String get editTracker => 'Edit tracker';
  @override
  String get trackerPlaceholder => 'What do you want to keep up?';
  @override
  String get theTracker => 'the tracker';
  @override
  String get deleteTracker => 'Delete tracker';
  @override
  String get trackerRhythm => 'Rhythm';
  @override
  String get rhythmDaily => 'Every day';
  @override
  String get rhythmDailyHint => 'Seven days a week';
  @override
  String get rhythmWeekdays => 'On certain days';
  @override
  String get rhythmWeekdaysHint => 'Every Monday and Thursday, say';
  @override
  String get rhythmTimesPerWeek => 'So many times a week';
  @override
  String get rhythmTimesPerWeekHint => 'Whichever days suit';
  @override
  String get whichDays => 'Which days?';
  @override
  String get howOften => 'How often?';
  @override
  String timesPerWeekValue(int times) => times == 1 ? 'Once a week' : '$times times a week';
  @override
  String get timesPerWeekExplainer =>
      'The week counts, not the day. Nothing falls due on a particular day — it is counted when the week closes on Sunday.';
  @override
  String get trackersTitle => 'Trackers';
  @override
  String get tasksTitle => 'To-dos';
  @override
  String weekProgressLabel(int done, int target) => '$done of $target this week';
  @override
  String streakDays(int days) => days == 1 ? '1 day in a row' : '$days days in a row';
  @override
  String streakWeeks(int weeks) => weeks == 1 ? '1 week in a row' : '$weeks weeks in a row';
  @override
  String get trackerGridEmpty => 'Nothing you are keeping up yet';
  @override
  String moreTrackers(int count) => count == 1 ? '1 more tracker' : '$count more trackers';
  @override
  String get trackerHistory => 'History';
  @override
  String trackerWeeksDone(int done, int total) => '$done of $total weeks completed';
  @override
  String weekDoneOfTarget(int done, int target) => '$done of $target';
  @override
  String get trackerLegendKept => 'kept';
  @override
  String get trackerLegendMissed => 'missed';
  @override
  String get trackerLegendNotDue => 'not planned';
  @override
  String get trackerBackfillTitle => 'Fill in';
  @override
  String get trackerBackfillHint => 'Tap a day to fill it in afterwards.';
  @override
  String get trackerBackfillOlderHint => 'Older days can be tapped in the grid.';
  @override
  String trackerDayFilledIn(String day) => '$day filled in';
  @override
  String trackerDayCleared(String day) => '$day cleared';
  @override
  String get trackerNotDueToday => 'Not due today';
  @override
  String get trackerStartedOn => 'Started on';
  @override
  String get trackersLoadFailed => 'Trackers could not be loaded.';
  @override
  String get trackerSaveFailed => 'The tracker could not be saved.';
  @override
  String get trackerDeleteFailed => 'The tracker could not be deleted.';
  @override
  String get trackerCheckFailed => 'The tick could not be saved.';
  @override
  String get trackerRestoreFailed => 'The tracker could not be restored.';
  @override
  String get pickAtLeastOneDay => 'Pick at least one day.';
  @override
  String get trackerCreated => 'Tracker added';
  @override
  String get trackerUpdated => 'Tracker updated';
  @override
  String get trackerDeleted => 'Tracker deleted';
  @override
  String get noOpenTasks => 'No open to-dos';
  @override
  String get addTask => 'Add to-do';
  @override
  String get tasksLoadFailed => 'To-dos couldn\'t be loaded.';
  @override
  String get taskSaveFailed => 'The to-do couldn\'t be saved.';
  @override
  String get changeSaveFailed => 'The change couldn\'t be saved.';
  @override
  String get saveFailed => 'Couldn\'t be saved.';
  @override
  String get someDoneTasksNotDeleted => 'Not all completed to-dos could be deleted.';
  @override
  String get doneTasksDeleteFailed => 'The completed to-dos couldn\'t be deleted.';
  @override
  String get taskDeleteFailed => 'The to-do couldn\'t be deleted.';
  @override
  String get taskCreated => 'To-do created';
  @override
  String get taskUpdated => 'To-do updated';
  @override
  String get taskDeleted => 'To-do deleted';
  @override
  String get taskRestoreFailed => 'The to-do couldn\'t be restored.';

  // ------------------------------------------------------------------ box --
  @override
  String get boxTitle => 'Box';
  @override
  String get searchBoxesAndItems => 'Search boxes and items';
  @override
  String get searchBoxesAndItemsLong => 'Search for boxes and items';
  @override
  String get boxes => 'Boxes';
  @override
  String get items => 'Items';
  @override
  String get noBoxesYet => 'No boxes yet.\nCreate one to find what you\'ve packed away.';
  @override
  String matchCount(int count) => count == 1 ? '1 match' : '$count matches';
  @override
  String itemCount(int count) => count == 1 ? '1 item' : '$count items';
  @override
  String get newBox => 'New box';
  @override
  String get editBox => 'Edit box';
  @override
  String get boxName => 'Box name';
  @override
  String get placeExample => 'e.g. basement, attic';
  @override
  String get theBox => 'the box';
  @override
  String get boxLabel => 'Box';
  @override
  String get tapAboveToAddFirst => 'Tap above to add the first item';
  @override
  String get newItem => 'New item';
  @override
  String get editItem => 'Edit item';
  @override
  String get itemName => 'Item name';
  @override
  String get sizeExample => 'e.g. EU 38, XL, 500ml';
  @override
  String get itemNotePlaceholder => 'Notes, condition, place...';
  @override
  String get deleteItem => 'Delete item';
  @override
  String get addItemPlaceholder => 'Add item...';
  @override
  String get empty => 'Empty';
  @override
  String emptyWithPlace(String place) => 'Empty · $place';
  @override
  String itemsWithPlace(int count, String place) => '${itemCount(count)} · $place';
  @override
  String get boxesLoadFailed => 'Boxes couldn\'t be loaded.';
  @override
  String get boxSaveFailed => 'The box couldn\'t be saved.';
  @override
  String get boxDeleteFailed => 'The box couldn\'t be deleted.';
  @override
  String get itemSaveFailed => 'The item couldn\'t be saved.';
  @override
  String get itemDeleteFailed => 'The item couldn\'t be deleted.';
  @override
  String get itemDeleted => 'Item deleted';
  @override
  String get itemRestoreFailed => 'The item couldn\'t be restored.';
  @override
  String get itemCreated => 'Item created';
  @override
  String get boxCreated => 'Box created';
  @override
  String get boxUpdated => 'Box updated';
  @override
  String get boxDeleted => 'Box deleted';
  @override
  String get boxRestoreFailed => 'The box couldn\'t be restored.';

  // ----------------------------------------------------------------- list --
  @override
  String get listsTitle => 'Lists';
  @override
  String get searchListsAndItems => 'Search lists and items';
  @override
  String get searchListsAndItemsLong => 'Search for lists and items';
  @override
  String get noListsYet => 'No lists yet.\nTap above to create the first one.';
  @override
  String doneInList(String list) => 'Done · $list';
  @override
  String inList(String list) => 'in $list';
  @override
  String get newList => 'New list';
  @override
  String get editList => 'Edit list';
  @override
  String get whichKindOfList => 'What kind of list?';
  @override
  String get groceries => 'Groceries';
  @override
  String get otherKind => 'Other';
  @override
  String get listName => 'List name';
  @override
  String get theList => 'the list';
  @override
  String get allDone => 'All done';
  @override
  String remaining(int count) => '$count left';
  @override
  String get listLabel => 'List';
  @override
  String doneWithCount(int count) => 'Done ($count)';
  @override
  String get deleteDone => 'Delete completed';
  @override
  String get allItems => 'All items';
  @override
  String get itemLabel => 'Item';
  @override
  String attachmentCount(int count) => count == 1 ? '1 attachment' : '$count attachments';
  @override
  String get searchOnAmazon => 'Search on Amazon';
  @override
  String get photo => 'Photo';
  @override
  String get camera => 'Camera';
  @override
  String get itemLink => 'Link';
  @override
  String get removeItemLink => 'Remove link';
  @override
  String get itemLinkMessage =>
      'The page this article can be bought on. Tapping the link opens it in the browser.';
  @override
  String get itemLinkHint => 'e.g. amazon.co.uk/dp/B0C…';
  @override
  String get itemLinkSaved => 'Link saved';
  @override
  String get itemLinkInvalid => 'That doesn\'t look like a web address.';
  @override
  String get listsLoadFailed => 'Lists couldn\'t be loaded.';
  @override
  String get listSaveFailed => 'The list couldn\'t be saved.';
  @override
  String get listDeleteFailed => 'The list couldn\'t be deleted.';
  @override
  String get listCreated => 'List created';
  @override
  String get listUpdated => 'List updated';
  @override
  String get listDeleted => 'List deleted';
  @override
  String get listRestoreFailed => 'The list couldn\'t be restored.';
  @override
  String get someDoneItemsNotDeleted => 'Not all completed items could be deleted.';
  @override
  String get doneItemsDeleteFailed => 'The completed items couldn\'t be deleted.';

  // ------------------------------------------------------------- calendar --
  @override
  String get calendarTitle => 'Calendar';
  @override
  String get yourDay => 'Your day';
  @override
  String get all => 'All';
  @override
  String get newEvent => 'New event';
  @override
  String get editEvent => 'Edit event';
  @override
  String get startsAt => 'Starts';
  @override
  String get endsAt => 'Ends';
  @override
  String get eventRepeat => 'Repeat';
  @override
  String get repeatNever => 'Never';
  @override
  String get repeatDaily => 'Daily';
  @override
  String repeatWeekly(String weekday) => 'Every $weekday';
  @override
  String repeatBiweekly(String weekday) => 'Every other $weekday';
  @override
  String get repeatMonthly => 'Monthly';
  @override
  String get repeatYearly => 'Yearly';
  @override
  String get repeatEnds => 'Ends';
  @override
  String get repeatFollowsStart => 'The repeat follows the start date.';
  @override
  String repeatUntilDate(String date) => 'until $date';
  @override
  String get repeats => 'Repeats';
  @override
  String get repeatNotEditable => "The repeat rule can't be changed here — only in the calendar itself.";
  @override
  String get repeatingEvent => 'Repeating event';
  @override
  String get changeRepeatingEventBody => 'Apply this change to this event only, or to the whole series?';
  @override
  String get deleteRepeatingEventBody => 'Delete this event only, or the whole series?';
  @override
  String get thisEventOnly => 'This event only';
  @override
  String get seriesCannotMoveCalendar =>
      'A whole series can\'t be moved to another calendar. Choose “This event only”.';
  @override
  String get wholeSeries => 'Whole series';
  @override
  String get noEventsThisDay => 'No events on this day';
  @override
  String get todosChip => 'To-dos';
  @override
  String get dueRailLabel => 'Due';
  @override
  String get addEvent => 'Add event';
  @override
  String get eventsPerCalendar => 'Events per calendar';
  @override
  String get publicHoliday => 'Public holiday';
  @override
  String get schoolHoliday => 'School holidays';
  @override
  String germanHolidayName(GermanHoliday holiday) => switch (holiday) {
    GermanHoliday.neujahr => 'New Year\'s Day',
    GermanHoliday.heiligeDreiKoenige => 'Epiphany',
    GermanHoliday.frauentag => 'International Women\'s Day',
    GermanHoliday.karfreitag => 'Good Friday',
    GermanHoliday.ostersonntag => 'Easter Sunday',
    GermanHoliday.ostermontag => 'Easter Monday',
    GermanHoliday.tagDerArbeit => 'Labour Day',
    GermanHoliday.christiHimmelfahrt => 'Ascension Day',
    GermanHoliday.pfingstsonntag => 'Whit Sunday',
    GermanHoliday.pfingstmontag => 'Whit Monday',
    GermanHoliday.fronleichnam => 'Corpus Christi',
    GermanHoliday.mariaeHimmelfahrt => 'Assumption Day',
    GermanHoliday.weltkindertag => 'World Children\'s Day',
    GermanHoliday.deutscheEinheit => 'German Unity Day',
    GermanHoliday.reformationstag => 'Reformation Day',
    GermanHoliday.allerheiligen => 'All Saints\' Day',
    GermanHoliday.bussUndBettag => 'Repentance Day',
    GermanHoliday.weihnachtstag1 => 'Christmas Day',
    GermanHoliday.weihnachtstag2 => 'Boxing Day',
  };
  @override
  String eventCount(int count) => count == 1 ? '1 event' : '$count events';
  @override
  String get eventLabel => 'Event';
  @override
  String get createListFromEvent => 'Create a list for this event';
  @override
  String get createTaskFromEvent => 'Create a to-do for this event';
  @override
  String get createForEvent => 'Create new';
  @override
  String get alreadyCreated => 'Already created';
  @override
  String get linkedToEvent => 'Created for this event';
  @override
  String get linkedEventLabel => 'Event';
  @override
  String get doneLabel => 'Done';
  @override
  String get openInCalendar => 'Show in calendar';
  @override
  String linkedListCount(int count) => count == 1 ? '1 list' : '$count lists';
  @override
  String linkedTaskCount(int count) => count == 1 ? '1 to-do' : '$count to-dos';
  @override
  String get route => 'Route';
  @override
  String get reminder => 'Reminder';
  @override
  String get deleteEvent => 'Delete event';
  @override
  String get deleteEventQuestion => 'Delete event?';
  @override
  String deleteEventBody(String title) => '“$title” will be deleted for good.';
  @override
  String get untitledEvent => 'Untitled';
  @override
  String reminderMinutesBefore(int minutes) => '$minutes minutes before';
  @override
  String get calendarLoadFailed => 'The calendar couldn\'t be loaded.';
  @override
  String get eventNeedsTitle => 'The event needs a title.';
  @override
  String get eventSaveFailed => 'The event couldn\'t be saved.';
  @override
  String get calendarNotEditable => 'This calendar can\'t be edited in Aporah.';
  @override
  String get eventDeleteFailed => 'The event couldn\'t be deleted.';
  @override
  String eventBeingCreatedIn(String calendar) => 'Adding event to $calendar …';
  @override
  String get eventBeingCreated => 'Adding event …';
  @override
  String get eventBeingDeleted => 'Deleting event …';
  @override
  String get seriesBeingDeleted => 'Deleting series …';
  @override
  String get eventBeingSaved => 'Saving change …';
  @override
  String eventBeingMovedTo(String calendar) => 'Moving event to $calendar …';
  @override
  String get seriesBeingSaved => 'Saving series …';
  @override
  String get eventCreated => 'Event created';
  @override
  String get eventUpdated => 'Event updated';
  @override
  String get eventDeleted => 'Event deleted';
  @override
  String get eventRestoreFailed => 'The event couldn\'t be restored.';
  @override
  String get calendarNoLongerAvailable => 'This calendar is no longer available.';
  @override
  String get noWritableCalendar => 'No calendar to write to. Connect a calendar in Settings first.';
  @override
  String get noHouseholdFound => 'No household found.';
  @override
  String get eventSaveFailedRemote => 'The event couldn\'t be saved to the connected calendar.';

  @override
  String get allDayDuration => 'All day';
  @override
  String durationDays(int days) => '$days days';
  @override
  String durationHours(int hours) => '${hours}h';
  @override
  String durationHoursMinutes(int hours, int minutes) => '${hours}h $minutes';
  @override
  String durationMinutes(int minutes) => '$minutes min';
  // No trailing "Uhr" — English says "9:00 AM – 10:30 AM".
  @override
  String timeRange(String from, String to) => '$from – $to';

  // -------------------------------------------------------------- weather --
  @override
  String temperature(int degrees) => '$degrees°';
  @override
  String get weatherClear => 'Clear';
  @override
  String get weatherPartlyCloudy => 'Partly cloudy';
  @override
  String get weatherCloudy => 'Cloudy';
  @override
  String get weatherFog => 'Fog';
  @override
  String get weatherDrizzle => 'Drizzle';
  @override
  String get weatherRain => 'Rain';
  @override
  String get weatherSnow => 'Snow';
  @override
  String get weatherStorm => 'Thunderstorm';

  // ------------------------------------------------------- calendar setup --
  @override
  String get connectCalendars => 'Connect calendars';
  @override
  String get calendarAccountsGroup => 'Accounts';
  @override
  String get noAccountGroup => 'No account needed';
  @override
  String get connectCalendarsIntro =>
      'See your family\'s events in the app — school, waste collection and '
      'private calendars in one place.';
  @override
  String get connectCalendarsAdminNote => 'An adult in the household connects the calendars.';
  @override
  String get noCalendarsConnected => 'No calendar connected yet.';
  @override
  String noProviderCalendarYet(String provider) =>
      'No $provider calendar yet.\nTap "Connect" to add your first one.';
  @override
  String get loadingEllipsis => 'Loading …';
  @override
  String get notSyncedYet => 'Not synced yet';
  @override
  String get syncedJustNow => 'Synced just now';
  @override
  String syncedMinutesAgo(int minutes) => 'Synced $minutes minutes ago';
  @override
  String syncedHoursAgo(int hours) => 'Synced $hours hours ago';
  @override
  String syncedDaysAgo(int days) => 'Synced $days days ago';
  @override
  String get actionNeeded => 'Action needed';
  @override
  String get connected => 'Connected';
  @override
  String calendarCount(int count) => count == 1 ? '1 calendar' : '$count calendars';
  @override
  String get calendarSettings => 'Edit calendar';
  @override
  String get calendarColor => 'Colour';
  @override
  String get renameCalendar => 'Rename calendar';
  @override
  String get renameCalendarBody =>
      'This is the name the calendar appears under in Aporah — in the calendar, '
      'in the filters and here.';
  @override
  String get householdOnly => 'For your household only.';
  @override
  String get savingEllipsis => 'Saving …';
  @override
  String get nameChanged => 'Name changed';
  @override
  String get removeCalendarQuestion => 'Remove calendar?';
  @override
  String get disconnectQuestion => 'Disconnect?';
  @override
  String removeCalendarBody(String name) => '“$name” will disappear from your calendar. ';
  @override
  String get accessRevokedToo => 'Access will be revoked at the provider as well.';
  @override
  String get accountStaysConnected => 'The account stays connected — and so do the other calendars in it.';
  @override
  String get householdOnlyOthersKeep => 'For your household only — others keep the calendar.';
  @override
  String get credentialsDeleted => 'Your credentials will be deleted.';
  @override
  String get connectionNeedsAttention => 'The connection needs attention.';
  @override
  String get refreshingEllipsis => 'Refreshing …';
  @override
  String providerNotSetUp(String provider) => '$provider isn\'t set up yet.';
  @override
  String get browserCouldNotOpen => 'The browser couldn\'t be opened.';
  @override
  String connectProvider(String provider) => 'Connect $provider';
  @override
  String redirectNotice(String provider) =>
      'You sign in at $provider. Aporah only ever sees your calendars — '
      'never your password.';
  @override
  String get openingEllipsis => 'Opening …';
  @override
  String signInWithProvider(String provider) => 'Sign in with $provider';
  @override
  String get comeBackWhenDone => 'Come back once you\'re done in the browser.';
  @override
  String get connectedDot => 'Connected.';
  @override
  String calendarsFoundPickThem(int count) =>
      '$count calendars found. Pick the ones you want to see in Aporah.';
  @override
  String get nameYourCalendarBody => 'That\'s what the calendar is called in Aporah. You can rename it now.';
  @override
  String get nameEachCalendarBody =>
      'That\'s what the calendars are called in Aporah. You can rename them now.';
  @override
  String get whichCalendars => 'Calendars';
  @override
  String get whichCalendarsHint => 'Only the ones you tick show up in Aporah. You can change this later.';
  @override
  String get readOnlyCalendar => 'Read-only';
  @override
  String get pickAtLeastOneCalendar => 'Pick at least one calendar.';
  @override
  String get selectAll => 'Select all';
  @override
  String get deselectAll => 'Deselect all';
  @override
  String calendarsSelected(int count) => count == 1 ? '1 calendar selected' : '$count calendars selected';
  @override
  String get loadingCalendarsEllipsis => 'Loading calendars …';
  @override
  String get appPasswordHint => 'Not your normal Apple ID password.';
  @override
  String get createAppPassword => 'Create an app-specific password';
  @override
  String get school => 'School';
  @override
  String get schoolAddressHint => 'The address you open IServ at.';
  @override
  String get username => 'Username';
  @override
  String get appleId => 'Apple ID';
  @override
  String get icloudEmailHint => 'name@icloud.com';
  @override
  String get emailAddress => 'Email address';
  @override
  String get oneAndOneAppPasswordHint =>
      'An application password is best — it covers the calendar only and can be '
      'revoked on its own.';
  @override
  String get appPasswordPlaceholder => 'Application password';
  @override
  String get iservPassword => 'IServ password';
  @override
  String get checkingEllipsis => 'Checking …';
  @override
  String get connect => 'Connect';
  @override
  String get bundesland => 'Bundesland';
  @override
  String get holidaysIntro => 'You can pick several Bundesländer.';
  @override
  String get pickABundesland => 'Pick a Bundesland.';
  @override
  String schoolHolidaysOf(String state) => 'School holidays $state';
  @override
  String holidaysSelectedBody(String state) =>
      'You picked $state. The holiday dates will then appear in your calendar — '
      'for everyone in the household.';
  @override
  String get wasteIntro =>
      'General, organic, paper and recycling collection dates go into your '
      'calendar automatically — for everyone in the household.';
  @override
  String get houseNumber => 'House number';
  @override
  String get multipleDistrictsHint =>
      'This street has several collection districts. Without a choice, the plan '
      'for the whole street applies.';
  @override
  String wasteFor(String street) => 'Waste $street';
  @override
  String wasteForTown(String town) => 'Waste $town';
  @override
  String noVendorForTown(String town) =>
      'We don\'t know a waste provider for $town yet. Most of them publish their '
      'dates themselves: look on your provider\'s website for "Abfuhrkalender" or '
      '"Kalender abonnieren" and paste the link here.';
  @override
  String get checkingLinkEllipsis => 'Checking the link …';
  @override
  List<String> get iservLinkSteps => const [
    'Sign in to IServ and open the calendar.',
    'Bottom left, choose "Einstellungen", then "Plugins".',
    'Next to the calendar you want — exams or homework, say — choose "Link erstellen".',
    'Copy the link it creates and paste it here.',
  ];
  @override
  List<String> get webuntisLinkSteps => const [
    'Sign in to WebUntis and tap your own name at the top.',
    'Under "Freigaben", choose "Kalender publizieren" — or, in the timetable, '
        'open the three dots, choose "iCal-Abo verwalten", pick the "Standard" '
        'format and press "Link erstellen".',
    'Copy the iCal link it creates and paste it here.',
  ];
  @override
  String get icalLinkNote =>
      'Any calendar you can subscribe to: a club, a nursery, work. What is wanted '
      'is the subscription address (ICS), not the calendar\'s web page.';
  @override
  String get uploadCalendarFile => 'Upload a calendar file';
  @override
  String get uploadCalendarFileHint => 'For a calendar published as a download rather than as a link.';
  @override
  String get calendarFileNote =>
      'A file is a snapshot: it holds exactly the events it contained when you '
      'uploaded it. When a new one comes out, upload it here again.';
  @override
  String get checkingFileEllipsis => 'Checking the file …';
  @override
  String get calendarFileUnreadable => "That file couldn't be read. Please choose an .ics file.";
  @override
  String calendarFileCoversTo(String date) => 'The events run to $date.';
  @override
  String calendarFileChosen(String name) => '$name selected';
  @override
  String longDate(DateTime at) => '${monthNames[at.month]} ${at.day}, ${at.year}';
  @override
  String get pasteCalendarLink => 'Calendar link';
  @override
  String get pasteCalendarLinkHint => 'We fetch it right away, so you know at once whether it works.';
  @override
  String get whoseCalendar => 'Whose account is this?';
  @override
  String get whoseCalendarHint => 'Shown on the calendar filter later, e.g. "IServ · Alice".';
  @override
  String get whoseCalendarPlaceholder => "Child's name";
  @override
  String get linkedCalendarName => 'Calendar name';
  @override
  String get linkedCalendarNameHint => 'Exams, homework or the class calendar, for instance.';
  @override
  String get nameThisCalendarFirst => 'Give the calendar a name.';
  @override
  String get whoseCalendarFirst => 'Say whose account this is.';
  @override
  String get addAnotherCalendar => 'Add calendar';
  @override
  String get addAnotherCalendarBody =>
      'The school platform makes a separate link for each calendar. Every link '
      'on this account ends up under one filter in Kalender.';
  @override
  String get schoolCalendars => 'Calendars';
  @override
  String get removeCalendar => 'Remove calendar';
  @override
  String get linkStaysAtSchool => ' The link stays in the school platform — we simply stop remembering it.';
  @override
  String get connectWithLogin => 'Sign in with credentials instead';
  @override
  String get connectWithLoginBody =>
      'Only worth it if your school has enabled CalDAV. Homework and exams are '
      'not there — those need the links above.';
  @override
  String get linkedCalendarsNote =>
      'Aporah only reads these calendars. Keep changing events in the school platform.';
  @override
  String eventsFoundAtLink(int count) => count == 1 ? '1 event found' : '$count events found';
  @override
  String get noEventsAtLinkYet =>
      'The link works but has no events right now. That is normal over the holidays.';

  // The four field names stay German: they label what the WebUntis dialog calls
  // them, and somebody copying across two screens needs the words to match.

  @override
  String get calendarLinkIcs => 'Calendar link (ICS)';
  @override
  String get calendarLinkHint => 'Usually ends in .ics — the link behind "Kalender abonnieren".';
  @override
  String get pasteLinkHere => 'Paste the calendar link here.';
  @override
  String get noEventsAtThatLink =>
      'No events were found at that link. Is it the link to the calendar itself?';
  @override
  String get yourAddress => 'Address';
  @override
  String get yourAddressHint => 'We\'ll find your waste provider.';
  @override
  String get pickYourAddressFirst => 'Search for your address and tap it.';
  @override
  String get addressPlaceholder => 'Street house number, town';
  @override
  String get searchingAddresses => 'Searching addresses …';
  @override
  String get noAddressFound => 'No address found.';
  @override
  String get searchingVendor => 'Searching for a waste provider …';
  @override
  String get tapToRetry => 'Tap to try again';
  @override
  String foundVendor(String where) => 'Found: $where';
  @override
  String get noVendorFoundTapForLink => 'No waste provider found — tap for the calendar link';
  @override
  String get askingNearbyVendors => 'Asking the waste providers nearby …';
  @override
  String get connectionStartFailed => 'The connection couldn\'t be started.';
  @override
  String get connectionsLoadFailed => 'The connections couldn\'t be loaded.';
  @override
  String get connectingEllipsis => 'Connecting …';
  @override
  String get calendarConnected => 'Calendar connected';
  @override
  String get calendarNameInAporah =>
      'This is what the calendar is called in Aporah. You can rename it later.';

  // -------------------------------------------------------- provider meta --
  @override
  String get providerIcalLabel => 'Other calendar';
  @override
  String get providerHolidaysLabel => 'Holidays';
  @override
  String get providerWasteLabel => 'Waste';
  @override
  String get providerGoogleDesc => 'Connect Google Calendar.';
  @override
  String get providerOutlookDesc => 'Connect Outlook or Microsoft 365.';
  @override
  String get providerIcloudDesc => 'Connect iCloud with an app-specific password.';
  @override
  String get providerGmxDesc => 'Connect the GMX calendar — events go back too.';
  @override
  String get providerWebdeDesc => 'Connect the WEB.DE calendar — events go back too.';
  @override
  String get providerIservDesc => 'Homework, exams and class calendars from IServ.';
  @override
  String get providerWebuntisDesc => 'Show the timetable from WebUntis, via the iCal link in the profile.';
  @override
  String get providerIcalDesc => 'Add any calendar you can subscribe to — a club, a nursery, work.';
  @override
  String get providerHolidaysDesc => 'Show school holidays for your Bundesland.';
  @override
  String get providerWasteDesc => 'Show waste collection dates for your address.';

  // --------------------------------------------------------------- shares --
  @override
  String get shareTitle => 'Share';
  @override
  String shareIntro(String resource) => 'Share “$resource” with people outside your family. ';
  @override
  String shareIntroSecond(String noun) => 'They\'ll see $noun and nothing else of yours.';
  @override
  String get emailOptional => 'Email (optional)';
  @override
  String get createLink => 'Create link';
  @override
  String get sendInvite => 'Send invitation';
  @override
  String get guests => 'Guests';
  @override
  String get activeLinks => 'Active links';
  @override
  String get notSharedYet => 'Not shared yet.\nCreate a link to let somebody in.';
  @override
  String get newLink => 'New link';
  @override
  String get copied => 'Copied';
  @override
  String get copyLink => 'Copy link';
  @override
  String get linkShownOnce => 'This link is only shown now — we don\'t store it.';
  @override
  String usedTimes(int count) => count == 1 ? 'used 1×' : 'used $count×';
  @override
  String get linkExpired => 'expired';
  @override
  String get linkUsedUp => 'used up';
  @override
  String get shareLink => 'Share link';
  @override
  String get revoke => 'Revoke';
  @override
  String get guest => 'Guest';
  @override
  String get sharesLoadFailed => 'The shares couldn\'t be loaded.';
  @override
  String get shareLinkCreateFailed => 'The share link couldn\'t be created.';
  @override
  String get linkRevokeFailed => 'The link couldn\'t be revoked.';
  @override
  String get guestRemoveFailed => 'The guest couldn\'t be removed.';
  @override
  String shareListMessage(String name) => '“$name” on Aporah — this link lets you in:';
  @override
  String get sharedOutsideTitle => 'Shared with';
  @override
  String openInvitations(int count, String? until) {
    final what = count == 1 ? 'Open invitation' : '$count open invitations';
    return until == null ? what : '$what · valid until $until';
  }

  @override
  String get sharedOutsideLabel => 'Shared with people outside the family';

  // ----------------------------------------------------------- visibility --
  @override
  String get forWhom => 'Who for?';
  @override
  String get everyone => 'Everyone';
  @override
  String get onlyMe => 'Only me';
  @override
  String get selected => 'Selected';
  @override
  String peopleCount(int count) => '$count people';
  @override
  String wholeFamilySees(String noun) => 'For the whole family — everyone can see and edit $noun.';
  @override
  String onlyYouSee(String noun) => 'Visible to you only — nobody else sees $noun.';
  @override
  String youAndOthersSee(String names, String noun) => 'Only you and $names see $noun.';
  @override
  String joinNames(List<String> names) =>
      names.length == 1 ? names.first : '${names.sublist(0, names.length - 1).join(', ')} and ${names.last}';

  // ------------------------------------------------------------ icon pick --
  @override
  String get symbol => 'Symbol';
  @override
  String get change => 'Change';
  @override
  String get photoUploadFailed => 'The photo could not be uploaded.';
  @override
  String get photoRemoveFailed => 'The photo could not be removed.';
  @override
  String get chooseSymbol => 'Choose a symbol';
  @override
  String get uploadImage => 'Upload an image';
  @override
  String get searchSymbolOrShop => 'Search symbols or shops';
  @override
  String get matches => 'Matches';
  @override
  String nothingFoundFor(String query) => 'Nothing found for "$query"';
  @override
  String get suggestionFromName => 'Suggested from the name';
  @override
  String get shops => 'Shops';
  @override
  String get showLess => 'Show less';
  @override
  String allMoreShops(int count) => 'All $count more shops';
  @override
  String noMatchesFor(String query) => 'No matches for “$query”';

  // ------------------------------------------------------------- settings --
  @override
  String get settingsTitle => 'Settings';
  @override
  String get searchSettings => 'Search settings';
  @override
  String get profile => 'Profile';
  @override
  String get familyMembers => 'Family members';
  @override
  String get language => 'Language';
  @override
  String get darkMode => 'Dark mode';
  @override
  String get welcomeTour => 'Welcome tour';
  @override
  String get repeat => 'Repeat';
  @override
  String get signOut => 'Sign out';
  @override
  String noSettingFoundFor(String query) => 'No setting found for “$query”';
  @override
  String get notConnected => 'Not connected';
  @override
  String get displayName => 'Display name';
  @override
  String get avatarColour => 'Avatar colour';
  @override
  String get removePhoto => 'Remove photo';
  @override
  String get avatarUploadFailed => 'The profile picture could not be uploaded.';
  @override
  String get avatarRemoveFailed => 'The profile picture could not be removed.';
  @override
  String get adminsManageFamily => 'Admins manage the family and all connections.';
  @override
  String get familyMembersDesc =>
      'Set each family member\'s role. Admins manage the family; children see a '
      'simplified view.';
  @override
  String get familyMembersDescAdmin =>
      'Who belongs to your household. Only admins can invite people and change roles.';
  @override
  String get nobodyInHouseholdYet =>
      'Nobody in the household yet.\nInvite somebody to share lists, to-dos and events.';
  @override
  String get inviteMember => 'Invite member';
  @override
  String pendingWithRole(String role) => '$role · pending';
  @override
  String get inviteFamilyMember => 'Invite a family member';
  @override
  String get inviteValidity =>
      'The invitation is valid for 14 days. Whoever accepts it leaves their previous household.';
  @override
  String get inviteSending => 'Sending the invitation…';
  @override
  String get inviteSentTitle => 'Invitation sent';
  @override
  String get inviteCreatedTitle => 'Invitation created';
  @override
  String inviteSentTo(String email) => 'We\'ve emailed $email.';
  @override
  String inviteMailNotSent(String email) =>
      'The email to $email couldn\'t be delivered. Share the link below instead.';
  @override
  String invitedAsRole(String role) => 'Invited as $role';
  @override
  String inviteValidUntil(String date) => 'Valid until $date';
  @override
  String invitedPerson(String who) => '$who invited';
  @override
  String get tapSendToInvite => 'Tap send to deliver the invitation.';
  @override
  String get youCaps => 'YOU';
  @override
  String get removeMemberQuestion => 'Remove member?';
  @override
  String removeMemberBody(String name) =>
      '“$name” will lose access to your household. Shared content stays, private '
      'content is deleted.';
  @override
  String get languagePageDesc =>
      'Sets the language of the app. Menus, buttons and dates switch over straight away.';
  @override
  String get setUpProfile => 'Set up profile';
  @override
  String get languageGerman => 'Deutsch';
  @override
  String get languageEnglish => 'English';
  @override
  String get languagePortuguese => 'Português';
  @override
  String get languageSpanish => 'Español';
  @override
  String get languageGermanRegion => 'Germany';
  @override
  String get languageEnglishRegion => 'United Kingdom';
  @override
  String get languagePortugueseRegion => 'Brazil';
  @override
  String get languageSpanishRegion => 'Spain';

  // Both languages' keywords, so search finds a row whichever word comes to mind.
  @override
  String get searchTermsProfile => 'profile account name display name avatar colour role admin profil konto';
  @override
  String get searchTermsFamily =>
      'family members people invite role roles child children admin familie mitglieder';
  @override
  String get searchTermsCalendar =>
      'calendar events connections connect google outlook icloud iserv holidays waste school kalender';
  @override
  String get searchTermsApplePay =>
      'apple pay google wallet samsung pay spending devices iphone android shortcuts automation '
      'notifications notification access detection activate remove geräte';
  @override
  String get searchTermsLanguage => 'language sprache german english deutsch translation';
  @override
  String get searchTermsDarkMode => 'dark mode appearance light dark night theme dunkelmodus darstellung';
  @override
  String get searchTermsTour => 'welcome tour onboarding intro repeat help willkommenstour';
  @override
  String get searchTermsSignOut => 'sign out log out logout account switch abmelden';

  // ----------------------------------------------------------------- roles --
  @override
  String get roleAdmin => 'Admin';
  @override
  String get roleMember => 'Member';
  @override
  String get roleChild => 'Child';

  // ----------------------------------------------------------- onboarding --
  @override
  String get onboardSetUpFamily => 'Let\'s set up your family';
  @override
  String get onboardSetUpFamilyBody =>
      'In a few steps you\'ll invite your family and connect the calendars that '
      'matter for your everyday life.';
  @override
  String get onboardInviteTitle => 'Invite your family';
  @override
  String get onboardInviteBody => 'Everyone in your family can see and add to events, boxes and lists.';
  @override
  String get adult => 'Adult';
  @override
  String get child => 'Child';
  @override
  String get onboardAddressTitle => 'Connect your address';
  @override
  String get onboardAddressBody =>
      'We\'ll suggest calendars that fit — waste collection and school holidays, for instance.';
  @override
  String get address => 'Address';
  @override
  String get wasteCalendar => 'Waste collection calendar';
  @override
  String get holidayCalendar => 'School holiday calendar';
  @override
  String get onboardFindingCalendars => 'Looking for calendars for your address …';
  @override
  String get onboardFoundForYou => 'Found for your address';
  @override
  String get onboardNothingForAddress =>
      'We found no calendar for this address. You can connect more later in Settings.';
  @override
  String get onboardNotFoundHere => 'Not found for this address';
  @override
  String get onboardRenameLater => 'You can rename the calendars later under Settings → Calendar.';
  @override
  String get onboardConnectMoreHint => 'Add Google, Outlook, iCloud or IServ';
  @override
  String get onboardConnectingCalendars => 'Connecting calendars …';
  @override
  String get calendarsConnectFailed => 'The calendars couldn\'t be connected just now.';
  @override
  String get onboardReady => 'Ready!';
  @override
  String get onboardReadyBody => 'Your family is set up — you can change all of it later in Settings.';
  @override
  String get noInvitesSent => 'No invitations sent';
  @override
  String invitedCount(int count) => '$count invited';

  // ----------------------------------------------------------------- auth --
  @override
  String get welcomeToAporah => 'Welcome to Aporah';
  @override
  String get welcomeBack => 'Welcome back';
  @override
  String get signUpBlurb =>
      'Create your account. Your household is created automatically — you can invite '
      'your family afterwards.';
  @override
  String get signInBlurb => 'Sign in with your email address.';
  @override
  String get yourName => 'Your name';
  @override
  String get atLeast8Chars => 'At least 8 characters.';
  @override
  String get createAccount => 'Create account';
  @override
  String get signIn => 'Sign in';
  @override
  String get haveAccountAlready => 'I already have an account';
  @override
  String get newHereCreateAccount => 'New here? Create an account';
  @override
  String get forgotPassword => 'Forgotten your password?';
  @override
  String get almostThere => 'Almost there';
  @override
  String confirmMailSent(String email) =>
      'We\'ve sent an email to $email. Click the link in it, then you can sign in.';
  @override
  String get toSignIn => 'To sign in';
  @override
  String get pleaseEnterName => 'Please enter your name.';
  @override
  String get noConnectionTryAgain => 'No connection. Please try again.';
  @override
  String get pleaseEnterEmailFirst => 'Please enter your email address first.';
  @override
  String get resetMailSent => 'We\'ve sent you an email to reset it.';
  @override
  String get wrongCredentials => 'That email address or password isn\'t right.';
  @override
  String get confirmEmailFirst => 'Please confirm your email address first.';
  @override
  String get accountExists => 'There\'s already an account for this email address.';
  @override
  String get passwordTooShort => 'That password is too short.';
  @override
  String get passwordLeaked => 'This password appears in known data leaks. Please choose another one.';
  @override
  String get tooManyAttempts => 'Too many attempts. Please wait a moment.';
  @override
  String get emailLooksInvalid => 'That email address doesn\'t look valid.';
  @override
  String get signInFailed => 'Signing in failed. Please try again.';

  // --------------------------------------------------------------- family --
  @override
  String get noHouseholdForAccount => 'No household was found for your account.';
  @override
  String get householdLoadFailed => 'The household couldn\'t be loaded.';
  @override
  String get enterValidEmail => 'Please enter a valid email address.';
  @override
  String get inviteSendFailed => 'The invitation couldn\'t be sent.';
  @override
  String get roleChangeFailed => 'The role couldn\'t be changed.';
  @override
  String get memberRemoveFailed => 'The member couldn\'t be removed.';
  @override
  String get inviteRevokeFailed => 'The invitation couldn\'t be revoked.';

  // --------------------------------------------------- calendar ownership --

  @override
  String get assignCalendar => 'Assign';
  @override
  String assignCalendarBody(String calendar) =>
      'Who does “$calendar” belong to? The calendar then appears under that person in Calendar and Board.';
  @override
  String get assignCalendarFamilyHint => 'Belongs to the whole household';
  @override
  String get assignCalendarNewPerson => 'Someone else';
  @override
  String get assignCalendarNotVisibility =>
      'This does not change who can see the calendar — everyone in the household still can.';
  @override
  String get assignCalendarFailed => 'That assignment did not go through.';
  @override
  String get family => 'Family';
  @override
  String get noAccountYet => 'No account';

  @override
  String get familyName => 'Family name';
  @override
  String get familyNameHint => 'What your family is called in Aporah.';
  @override
  String get renameFamily => 'Rename family';
  @override
  String get renameFamilyBody => 'The name appears on the family chip in Calendar and Board.';
  @override
  String get familyRenameFailed => 'The name could not be changed.';

  @override
  String homeOverdue(int count) => '$count overdue';
  @override
  String homeOpenToday(int count) => '$count still open';
  @override
  String homeTrackersLeft(int count) => '$count trackers left';
  @override
  String homeNextUp(String time, String title) => '$time · $title';
  @override
  String get homeAllDone => 'All done';
  @override
  String homeDayOffset(int days) => switch (days) {
    1 => 'Tomorrow',
    -1 => 'Yesterday',
    > 1 => 'In $days days',
    _ => '${-days} days ago',
  };
  @override
  String get homeHintBackToToday => 'Tap to go back to today';
  @override
  String get homeThinking => 'One moment';
  @override
  String get homeHintThinking => 'Putting your day together';
  @override
  String get homeHintSetup => 'Set Aporah up for your family';
  @override
  String get homeHintOverdue => 'To-dos past their date';
  @override
  String get homeHintOpen => 'To-dos for today';
  @override
  String get homeHintTrackers => 'Not ticked off today yet';
  @override
  String get homeHintNext => 'Next up in your calendar';
  @override
  String get homeHintDone => 'Nothing left for today';
  @override
  String get homeTrackerSection => 'Due today';
  @override
  String get homeTrackerEmpty => 'No tracker yet';
  @override
  String get homeTrackerEmptyBody => 'Sport, reading, vitamins — whatever you keep up.';
  @override
  String get homeListsSection => 'Lists';
  @override
  String get homeShowAll => 'Show all';
  @override
  String homeListOpenItems(int count) => '$count open';

  @override
  String get firstStepsTitle => 'First steps';
  @override
  String firstStepsProgress(int done, int total) => '$done of $total';
  @override
  String get firstStepCalendar => 'Connect a calendar';
  @override
  String get firstStepCalendarBody => 'School, work and waste collection in one place.';
  @override
  String get firstStepFamily => 'Invite your family';
  @override
  String get firstStepFamilyBody => 'So everyone sees the same thing.';
  @override
  String get firstStepTodo => 'First to-do';
  @override
  String get firstStepTodoBody => 'Something that has to happen this week.';
  @override
  String get firstStepTracker => 'Add a tracker';
  @override
  String get firstStepTrackerBody => 'A habit you keep together.';
  @override
  String get firstStepList => 'First list';
  @override
  String get firstStepListBody => 'The shopping is a good place to start.';

  // ------------------------------------------------------- Spending

  @override
  String get navMore => 'More';
  @override
  String get decimalSeparator => '.';
  @override
  String get thousandsSeparator => ',';
  @override
  String get thousandsSuffix => 'k';
  @override
  String get millionsSuffix => 'M';
  @override
  String money(String amount, String symbol) => '$symbol$amount';
  @override
  String percent(int value) => '$value%';

  @override
  String get spendTitle => 'Spending';
  @override
  String get spendAdminsOnly => 'Only admins can see spending.';
  @override
  String get spendEmpty => 'Nothing recorded for this month yet.';
  @override
  String get spendEmptyEnrolled =>
      'Nothing this month yet. Your next Apple Pay payment lands here on its own.';

  @override
  String get spendByCategory => 'By category';
  @override
  String get spendTopMerchants => 'By shop';
  @override
  String get spendByMember => 'By person';

  @override
  String get spendOtherCategories => 'Other';
  @override
  String get spendAllPurchases => 'All purchases';
  @override
  String get spendFormerMember => 'Former member';

  @override
  String spendCountShort(int count) => count == 1 ? '1 payment' : '$count payments';

  @override
  String spendPaymentsWord(int count) => count == 1 ? 'payment' : 'payments';

  @override
  String get spendChartTrend => 'Trend';
  @override
  String get spendChartBars => 'Bars';
  @override
  String get spendChartRing => 'Ring';

  @override
  String get spendRangeWeek => '1 W';
  @override
  String get spendRangeMonth => '1 M';
  @override
  String get spendRangeHalfYear => '6 M';
  @override
  String get spendRangeYear => '1 Y';

  @override
  String get spendRangeThisWeek => 'This week';
  @override
  String get spendRangeThisMonth => 'This month';
  @override
  String get spendRangeLastSixMonths => 'Last 6 months';
  @override
  String get spendRangeThisYear => 'This year';

  @override
  String get spendRangePick => 'Pick a range';

  @override
  String spendAveragePerDay(String amount) => 'Avg. $amount per day';
  @override
  String spendAveragePerMonth(String amount) => 'Avg. $amount per month';

  @override
  String get spendMetricAll => 'Spending';
  @override
  String get spendShowAll => 'Show all';

  @override
  String spendShowAllCount(int count) => 'Show all $count';

  @override
  String get spendIslandThinking => 'Working it out';
  @override
  String get spendIslandThinkingHint => 'Loading payments';

  @override
  String get spendIslandReviewHint => 'Merchant or amount missing';

  @override
  String get spendIslandNothing => 'Nothing recorded';

  @override
  String spendIslandUp(int percent) => '$percent% more spent';
  @override
  String spendIslandDown(int percent) => '$percent% less spent';
  @override
  String get spendIslandVsPrevious => 'against the period before';

  @override
  String spendIslandTop(String category) => '$category is the biggest slice';
  @override
  String spendIslandTopHint(int percent) => '$percent% of spending';

  @override
  String get spendAdd => 'Add a spend';
  @override
  String get spendEdit => 'Edit spend';
  @override
  String get spendAmount => 'Amount';
  @override
  String get spendDate => 'Date';
  @override
  String get spendCategory => 'Category';
  @override
  String get spendLabel => 'Spend';
  @override
  String get spendKindLabel => 'Kind';
  @override
  String get spendPaidBy => 'Paid by';
  @override
  String get spendCard => 'Card';
  @override
  String get spendSourceLabel => 'Captured';
  @override
  String get spendSourceWallet => 'Apple Pay';
  @override
  String get spendSourceManual => 'By hand';
  @override
  String get spendNote => 'Note';
  @override
  String get spendCategoryAuto => 'Automatic';
  @override
  String get spendMerchantPlaceholder => 'Where? e.g. REWE';
  @override
  String get spendNotePlaceholder => 'Note (optional)';
  @override
  String get spendKindQuestion => 'What kind of spend?';
  @override
  String get spendKindBudget => 'Regular';
  @override
  String get spendKindExtra => 'Extra';
  @override
  String get spendNeedsMerchantAndAmount => 'Merchant and amount are still missing.';
  @override
  String get spendSaved => 'Spend saved';
  @override
  String get spendUpdated => 'Spend updated';
  @override
  String get spendDeleted => 'Spend deleted';

  @override
  String spendReviewTitle(int count) =>
      count == 1 ? 'One payment needs a moment' : '$count payments need a moment';
  @override
  String get spendReviewBody =>
      'Apple did not pass on the merchant or the amount. Tap the row and fill it in.';
  @override
  String get spendReviewDetail =>
      'Apple did not pass on the merchant or the amount. Tap the pencil above and fill it in.';

  @override
  String get spendLoadFailed => 'Spending could not be loaded.';
  @override
  String get spendSaveFailed => 'The spend could not be saved.';
  @override
  String get spendDeleteFailed => 'The spend could not be deleted.';
  @override
  String get spendEnrolFailed => 'This device could not be activated.';

  @override
  String get spendWalletTitle => 'Capture Apple Pay automatically';
  @override
  String get spendWalletIntro =>
      'Every payment made with this iPhone lands here by itself. No link, no code — you set up one Shortcuts automation, once.';
  @override
  String get spendWalletEnable => 'Activate this iPhone';
  @override
  String get spendWalletUnsupported =>
      'Automatic capture works on iPhone and Android. On other devices you add spending by hand.';
  @override
  String get spendWalletEnabled => 'Device activated';
  @override
  String get spendWalletActive => 'This iPhone is activated';
  @override
  String get spendWalletInactive => 'This iPhone is not activated yet';
  @override
  String get spendWalletStepsTitle => 'One more step, in the Shortcuts app';
  @override
  String get spendWalletStep1 => 'Open Shortcuts, tap Automation at the bottom.';
  @override
  String get spendWalletStep2 => 'Tap +, then choose Wallet.';
  @override
  String get spendWalletStep3 => 'Pick your cards and choose Run Immediately.';
  @override
  String get spendWalletStep4 => 'Choose the action "Log a spend" — it is already in the list.';
  @override
  String get spendWalletStep5 =>
      'In the action, tap Merchant and Amount and insert the matching variable from the automation — otherwise the shortcut stops to ask and logs nothing.';
  @override
  String get spendWalletOpenShortcuts => 'Open Shortcuts';
  @override
  String get settingsWalletCapture => 'Wallet detection';
  @override
  String get walletCapturePageDesc =>
      'Payments made with this phone land in Ausgaben by themselves. Activate this device here — and take any device back the same way.';
  @override
  String get spendWalletAndroidTitle => 'Capture payments automatically';
  @override
  String get spendWalletAndroidIntro =>
      'When you pay with your phone, your wallet tells you the amount. Aporah reads that one notification and files the spend — no bank, no login, nothing to type.';
  @override
  String get spendWalletAndroidEnable => 'Activate this device';
  @override
  String get spendWalletAndroidActive => 'This device is capturing payments';
  @override
  String get spendWalletAndroidInactive => 'This device is not activated yet';
  @override
  String get spendWalletAndroidDeaf =>
      'Activated, but without notification access — no payment can reach us.';
  @override
  String get spendWalletAndroidStepsTitle => 'Two switches, then it runs';
  @override
  String get spendWalletAndroidStep1 => 'Activate this device — that is what lets it file spending.';
  @override
  String get spendWalletAndroidStep2 => 'Turn on notification access for Aporah in your system settings.';
  @override
  String get spendWalletAndroidStep3 => 'Pay with your phone — the spend shows up here by itself.';
  @override
  String get spendWalletAndroidNoDevicesHint => 'Use the button below to activate this device.';
  @override
  String get spendWalletGrantAccess => 'Allow notification access';
  @override
  String get spendWalletAccessGranted => 'Access granted';
  @override
  String get spendWalletDisclosureTitle => 'What Aporah reads';
  @override
  String get spendWalletDisclosureBody =>
      'Android has no per-app notification access: granting it grants everything. Aporah only ever evaluates the payment notifications posted by wallet apps — every other notification is discarded immediately, unread, unstored and uncounted. What leaves the device is the merchant, the amount, the last digits of the card and the time. Never the text of a notification.';
  @override
  String get spendWalletAndroidSources => 'Google Wallet, Google Pay and Samsung Wallet are detected.';
  @override
  String get settingsApplePay => 'Apple Pay';
  @override
  String get applePayPageDesc =>
      'Apple Pay payments land in Ausgaben by themselves. Activate this iPhone here — and take any device back the same way.';
  @override
  String get spendWalletNoDevices => 'No device activated yet';
  @override
  String get spendWalletNoDevicesHint => 'Use the button below to activate this iPhone.';
  @override
  String get spendWalletDevicesLabel => 'Activated devices';
  @override
  String get spendWalletDeviceUnused => 'Nothing filed yet';
  @override
  String spendWalletDeviceLastUsed(String date) => 'Last on $date';
  @override
  String spendWalletDeviceCount(int count) => count == 0
      ? 'None'
      : count == 1
      ? '1 device'
      : '$count devices';
  @override
  String get spendWalletRevoke => 'Remove';
  @override
  String get spendWalletRenameTitle => 'Rename device';
  @override
  String get spendWalletRenameBody =>
      'This is the name the device goes by in the list — so you can tell your phones apart.';
  @override
  String get spendWalletDeviceNameHint => "e.g. Anna's iPhone";
  @override
  String get spendWalletThisDevice => 'This device';

  @override
  String get spendCatGroceries => 'Groceries';
  @override
  String get spendCatDrugstore => 'Drugstore';
  @override
  String get spendCatFuel => 'Fuel';
  @override
  String get spendCatRestaurant => 'Restaurant';
  @override
  String get spendCatCafe => 'Bakery & café';
  @override
  String get spendCatShipping => 'Post & shipping';
  @override
  String get spendCatClothing => 'Clothing';
  @override
  String get spendCatShopping => 'Shopping';
  @override
  String get spendCatElectronics => 'Electronics';
  @override
  String get spendCatTransport => 'Getting around';
  @override
  String get spendCatEntertainment => 'Entertainment';
  @override
  String get spendCatHealth => 'Health';
  @override
  String get spendCatHome => 'Home';
  @override
  String get spendCatOther => 'Other';

  @override
  String get spendSearchPlaceholder => 'Shop, category, person';
  @override
  String get spendSearchAction => 'Search spending';
  @override
  String get spendViewAll => 'All';
  @override
  String get spendViewMembers => 'People';
  @override
  String get spendViewMerchants => 'Shops';
  @override
  String get spendViewCategories => 'Categories';
  @override
  String get spendNoMatches => 'No payments match.';
  @override
  String get spendClearFilter => 'Remove filter';
  @override
  String get spendBudget => 'Budget';
  @override
  String get spendBudgets => 'Budgets';
  @override
  String get spendBudgetAdd => 'New budget';
  @override
  String get spendBudgetEdit => 'Edit budget';
  @override
  String get spendBudgetPerMonth => 'Per month';
  @override
  String get spendBudgetHint =>
      'How much can this category cost in a month? The rings show whether you are on track.';
  @override
  String spendBudgetLastMonth(String amount) => 'Last month: $amount';
  @override
  String get spendBudgetSaved => 'Budget saved';
  @override
  String get spendBudgetDeleted => 'Budget deleted';
  @override
  String get spendBudgetSaveFailed => "Couldn't save the budget";
  @override
  String get spendBudgetNeedsAmount => 'Enter an amount';
  @override
  String spendBudgetOf(String spent, String limit) => '$spent of $limit';
  @override
  String spendBudgetLeft(String amount) => '$amount left';
  @override
  String spendBudgetOver(String amount) => '$amount over';
  @override
  String get spendBudgetOnTrack => 'On track';
  @override
  String get spendBudgetAhead => 'Ahead of pace';
  @override
  String get spendBudgetExceeded => 'Budget exceeded';
  @override
  String spendBudgetLine(String amount) => 'Budget $amount';

  @override
  String get plusName => 'Aporah Plus';
  @override
  String get plusPriceMonthly => '€4.99 / month';
  @override
  String get plusPriceYearly => '€39.99 / year';
  @override
  String get plusYearlySaving => 'Saves 33%';
  @override
  String get plusTrialNote => 'Free for 14 days. Cancel any time.';

  @override
  String plusForOnly(String price) => 'For just $price.';
  @override
  String get plusUpgrade => 'Get Plus';
  @override
  String get plusNotNow => 'Not now';
  @override
  String get plusRestore => 'Restore purchase';
  @override
  String get plusActive => 'Plus is active';
  @override
  String plusActiveUntil(String date) => 'Plus runs until $date';
  @override
  String get plusDebugOverride => 'Test mode: the plan is simulated';

  @override
  String get paywallCalendarsTitle => 'All your calendars';
  @override
  String get paywallCalendarsBody => 'With Plus you connect as many calendars as you need!';
  @override
  String get paywallTrackersTitle => 'More routines';
  @override
  String get paywallTrackersBody =>
      'Three routines are free. With Plus you can keep as many as daily life asks for — '
      'brushing teeth, taking the bins out, vocabulary, each with its own record.';
  @override
  String get paywallBoxesTitle => 'More boxes';
  @override
  String get paywallBoxesBody =>
      'One box is free. With Plus every cellar, every loft and every moving carton gets its own — '
      'with a photograph, so nobody has to guess.';
  @override
  String get paywallMembersTitle => 'More people';
  @override
  String get paywallMembersBody =>
      'Up to four people are free. With Plus the household is as big as it actually is — '
      'grandma, the au pair, the third child.';
  @override
  String get paywallPhotosTitle => 'Photographs and files';
  @override
  String get paywallPhotosBody =>
      'With Plus every box, every thing inside it and every article on a list gets a photograph — '
      'the serial number on the drill, the right cable out of three. A picture says what no symbol '
      'can.';
  @override
  String get paywallSpendTitle => 'Spending';
  @override
  String get paywallSpendBody =>
      'With Plus you can see where the money goes: Apple Pay payments file themselves, and '
      'everything else takes two taps to add.';

  @override
  String get debugPlanTitle => 'Plan (debug)';
  @override
  String debugPlanReal(String plan) => 'Real: $plan';
  @override
  String debugPlanSimulated(String plan) => '$plan (simulated)';
  // --- Planner ----------------------------------------------------------
  @override
  String get plannerTitle => 'Plan';
  @override
  String get plannerPrompt =>
      'Say in one sentence what you are up to. You get the method and, more to the point, the '
      'list you can take to the shop.';
  @override
  String get plannerHint => 'What are you planning?';
  @override
  String get plannerExamplesLabel => 'FOR EXAMPLE';
  @override
  List<List<PlannerExample>> get plannerExampleGroups => const [
    [
      (text: "Kid's birthday for 8", icon: AppIcons.cake),
      (text: "New Year's Eve for 10", icon: AppIcons.confetti),
      (text: 'Barbecue in the garden', icon: AppIcons.flame),
      (text: 'Christmas dinner for the family', icon: AppIcons.treeEvergreen),
      (text: 'A housewarming party', icon: AppIcons.house),
      (text: 'Pack for a week in Italy', icon: AppIcons.suitcaseRolling),
    ],
    [
      (text: 'Weekly shop for 5 days', icon: AppIcons.shoppingCart),
      (text: 'Restock the pantry', icon: AppIcons.package),
      (text: 'Deep clean the bathroom', icon: AppIcons.sprayBottle),
      (text: 'Refill the first-aid kit', icon: AppIcons.bandaids),
      (text: 'Swap the wardrobe for winter', icon: AppIcons.tShirt),
      (text: 'Everything a new baby needs', icon: AppIcons.baby),
    ],
    [
      (text: 'Build a raised garden bed', icon: AppIcons.hammer),
      (text: "Build shelves for the kids' room", icon: AppIcons.ruler),
      (text: 'Repaint the living room', icon: AppIcons.paintRoller),
      (text: 'Plant up the balcony', icon: AppIcons.plant),
      (text: 'Get the bikes ready for spring', icon: AppIcons.bicycle),
      (text: 'A treehouse for the kids', icon: AppIcons.tree),
    ],
    [
      (text: 'Butter chicken for 4', icon: AppIcons.cookingPot),
      (text: 'Sunday roast for 6', icon: AppIcons.forkKnife),
      (text: 'Pizza night from scratch', icon: AppIcons.pizza),
      (text: 'A cake for the school fair', icon: AppIcons.cake),
      (text: 'Brunch for 6 guests', icon: AppIcons.egg),
      (text: 'Homemade ice cream', icon: AppIcons.iceCream),
    ],
  ];
  @override
  String get plannerGo => 'Suggest a list';
  @override
  String get plannerWorking => 'Putting it together …';
  @override
  String get plannerWhatToBuy => 'WHAT YOU NEED';
  @override
  String plannerItemCount(int count) => count == 1 ? '1 item' : '$count items';
  @override
  String get plannerHowTo => 'HOW TO';
  @override
  String get plannerRecipe => 'RECIPE';
  @override
  String get adLabel => 'Ad';
  @override
  String get plannerCreateList => 'Create list';
  @override
  String get plannerAgain => 'Ask again';
  @override
  String get plannerEditGoal => 'Word it differently';
  @override
  String get plannerListCreated => 'List created';
  @override
  String get plannerUnavailable => "That didn't work just now. Try again in a moment.";
  @override
  String get plannerUnusable =>
      "We couldn't make a list out of that. Try something more specific — a dish, a project or "
      'an occasion.';
  @override
  String get plannerNotConfigured => 'The planner is not set up right now.';
  @override
  String get plannerMonthlyLimit => "This month's plans are used up. More on the 1st.";
  @override
  String get plannerDailyLimit => "That's enough plans for today. Try again tomorrow.";
  @override
  String plannerLeft(int left, int limit) => '$left of $limit plans left this month';
  @override
  String plannerNoneLeft(int day, String month) => 'No plans left – more on $month $day';
  @override
  String plannerMonthlyLimitUntil(int day, String month) =>
      "This month's plans are used up. More on $month $day.";
  @override
  String plannerDailyLimitAt(String time, {required bool tomorrow}) => tomorrow
      ? "That's enough plans for today. More tomorrow from $time."
      : "That's enough plans for now. More from $time.";
  @override
  String get plannerLimitsLifted => 'Limits lifted (test)';
  @override
  String get debugPlannerLimitsTitle => 'Plan limits (debug)';
  @override
  String get debugPlannerLimitsEnforced => 'On';
  @override
  String get debugPlannerLimitsLifted => 'Lifted';
  @override
  String get plannerIslandLine => 'Say what you are planning.';
  @override
  String get plannerIslandHint => 'We turn it into the list';

  // -------------------------------------------------------- notifications --
  @override
  String get notificationsTitle => 'Notifications';
  @override
  String get notificationsPageDesc => 'What Aporah sends to your phone, and when.';
  @override
  String get searchTermsNotifications =>
      'notifications reminders push alerts morning brief bins waste mitteilungen';
  @override
  String get notificationsAllowTitle => 'Allow notifications';
  @override
  String get notificationsAllowBody => 'Without permission, no reminder arrives.';
  @override
  String get notificationsDeniedBody => 'Notifications are turned off in system settings.';
  @override
  String get notificationsAllow => 'Allow';
  @override
  String get notificationsOpenSettings => 'Settings';
  @override
  String get notificationsQuietTitle => 'Delivered quietly';
  @override
  String get notificationsQuietBody => 'Notifications arrive silently in Notification Center.';
  @override
  String get notifyBriefTitle => 'Morning brief';
  @override
  String get notifyBriefSubtitle => 'What today holds, each morning';
  @override
  String get notifyAbfallTitle => 'Bin collection';
  @override
  String get notifyAbfallSubtitle => 'The evening before pickup';
  @override
  String get notifyTaskTimesTitle => 'To-dos with a time';
  @override
  String get notifyTaskTimesSubtitle => 'At the time you set';
  @override
  String get notifyTime => 'Time';
  @override
  String get notificationsEventNote =>
      'Set a reminder for an appointment on the appointment itself. It applies to this device only.';
  @override
  String get reminderNone => 'None';
  @override
  String get reminderAtStart => 'At start';
  @override
  String reminderHoursBefore(int hours) => hours == 1 ? '1 hour before' : '$hours hours before';
  @override
  String reminderDaysBefore(int days) => days == 1 ? '1 day before' : '$days days before';
  @override
  String reminderDayBefore(String time) => 'The day before at $time';
  @override
  String reminderMorningOf(String time) => 'On the day at $time';
  @override
  String reminderCalendarAlready(String label) => 'Your calendar already reminds you: $label';
  @override
  String get reminderDenied => 'Notifications are off – allow them in Settings.';
  @override
  String get noticeBriefTitle => 'Your day';
  @override
  String briefEvents(int count) => count == 1 ? '1 appointment' : '$count appointments';
  @override
  String briefFirstAt(String time) => 'from $time';
  @override
  String briefTasks(int count) => count == 1 ? '1 to-do due' : '$count to-dos due';
  @override
  String noticeAbfallTitle(String bins) => 'Put out $bins yet?';
  @override
  String get noticeAbfallBody => 'Pickup is tomorrow morning.';
  @override
  String noticeTaskDue(String time) => 'Due at $time';
  @override
  String joinAnd(List<String> parts) =>
      parts.length < 2 ? parts.join() : '${parts.sublist(0, parts.length - 1).join(', ')} and ${parts.last}';
  @override
  String get rateApp => 'Rate Aporah';
  @override
  String get searchTermsRate => 'rate review stars app store bewerten';
}
