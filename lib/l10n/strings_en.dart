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
        '', 'January', 'February', 'March', 'April', 'May', 'June',
        'July', 'August', 'September', 'October', 'November', 'December',
      ];
  @override
  List<String> get monthShort => const [
        '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
      ];
  @override
  List<String> get weekdayShort => const ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
  @override
  List<String> get weekdayLong => const [
        'Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday',
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
  String dayRangeSameMonth(int fromDay, int toDay, int month) =>
      '$fromDay – $toDay ${monthNames[month]}';
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
  String get reload => 'Reload';
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
  String get quantity => 'Quantity';
  @override
  String get size => 'Size';
  @override
  String get titleLabel => 'Title';
  @override
  String get role => 'Role';
  @override
  String get emailAddress => 'Email address';
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
  String get startNotDesigned => 'Not designed yet';

  // ---------------------------------------------------------------- board --
  @override
  String get boardTitle => 'Board';
  @override
  String doneCountSeparator(int count) => 'Done · $count';
  @override
  String get newTask => 'New task';
  @override
  String get editTask => 'Edit task';
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
  String get theTask => 'the task';
  @override
  String get deleteTask => 'Delete task';
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
  @override
  String get noOpenTasks => 'No open tasks';
  @override
  String get addTask => 'Add task';
  @override
  String get tasksLoadFailed => 'Tasks couldn\'t be loaded.';
  @override
  String get taskSaveFailed => 'The task couldn\'t be saved.';
  @override
  String get changeSaveFailed => 'The change couldn\'t be saved.';
  @override
  String get saveFailed => 'Couldn\'t be saved.';
  @override
  String get someDoneTasksNotDeleted => 'Not all completed tasks could be deleted.';
  @override
  String get doneTasksDeleteFailed => 'The completed tasks couldn\'t be deleted.';
  @override
  String get taskDeleteFailed => 'The task couldn\'t be deleted.';
  @override
  String get taskCreated => 'Task created';
  @override
  String get taskUpdated => 'Task updated';
  @override
  String get taskDeleted => 'Task deleted';
  @override
  String get taskRestoreFailed => 'The task couldn\'t be restored.';

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
  String get files => 'Files';
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
  String get noEventsThisDay => 'No events on this day';
  @override
  String get addEvent => 'Add event';
  @override
  String get eventsPerCalendar => 'Events per calendar';
  @override
  String get holiday => 'School holidays';
  @override
  String eventCount(int count) => count == 1 ? '1 event' : '$count events';
  @override
  String get eventLabel => 'Event';
  @override
  String get route => 'Route';
  @override
  String get reminder => 'Reminder';
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
  String get connectCalendarsIntro =>
      'See your family\'s events in the app — school, waste collection and '
      'private calendars in one place.';
  @override
  String get connectCalendarsAdminNote =>
      'An adult in the household connects the calendars. You\'ll see the '
      'connected events in the calendar as usual afterwards.';
  @override
  String get connectedCaps => 'CONNECTED';
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
  String get householdOnlyOthersKeep =>
      'For your household only — others keep the calendar.';
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
  String get oauthGrantedBody =>
      'Aporah may now read this account\'s calendars. Give the calendar a name '
      'you\'ll recognise it by in Aporah.';
  @override
  String redirectNotice(String provider) =>
      'You\'ll be taken to $provider and sign in there. '
      'Aporah only ever sees your calendars — never your password.';
  @override
  String get openingEllipsis => 'Opening …';
  @override
  String signInWithProvider(String provider) => 'Sign in with $provider';
  @override
  String get comeBackWhenDone =>
      'Once you\'re done in the browser, come back to Aporah — the connection '
      'will show up here.';
  @override
  String get connectedDot => 'Connected.';
  @override
  String get signInWorkedNameIt =>
      'Signing in worked. Give the calendar a name you\'ll recognise it by in Aporah.';
  @override
  String calendarsFoundNameThem(int count) =>
      '$count calendars found. Give them a name you\'ll recognise them by in Aporah.';
  @override
  String get iservIntro =>
      'Enter your school\'s address (e.g. schule.de) and sign in with your '
      'IServ account. School calendars are read-only.';
  @override
  String get icloudIntro =>
      'iCloud requires an app-specific password. Your normal Apple ID password '
      'won\'t work here.';
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
  String get iservPassword => 'IServ password';
  @override
  String get checkingEllipsis => 'Checking …';
  @override
  String get connect => 'Connect';
  @override
  String get chooseStateCaps => 'CHOOSE A BUNDESLAND';
  @override
  String get holidaysIntro =>
      'School holidays come from OpenHolidays — free and without an account. '
      'You can connect several Bundesländer.';
  @override
  String get connectHolidays => 'Connect holidays';
  @override
  String schoolHolidaysOf(String state) => 'School holidays $state';
  @override
  String holidaysSelectedBody(String state) =>
      'You picked $state. The holiday dates will then appear in your calendar — '
      'for everyone in the household.';
  @override
  String get connectWaste => 'Connect waste collection';
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
  String get calendarLinkIcs => 'Calendar link (ICS)';
  @override
  String get calendarLinkHint =>
      'Usually ends in .ics — the link behind "Kalender abonnieren".';
  @override
  String get pasteLinkHere => 'Paste the calendar link here.';
  @override
  String get noEventsAtThatLink =>
      'No events were found at that link. Is it the link to the calendar itself?';
  @override
  String get addressCaps => 'ADDRESS';
  @override
  String get addressIntro =>
      'Type your address and pick it — Aporah finds the responsible waste '
      'provider and then only asks what the calendar should be called.';
  @override
  String get yourAddress => 'Your address';
  @override
  String get yourAddressHint => 'Street and house number, then the town.';
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
  String get noVendorFoundTapForLink =>
      'No waste provider found — tap for the calendar link';
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
  String get providerIservDesc => 'Connect the school calendar from IServ.';
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
  String shareIntroSecond(String noun) =>
      'They\'ll see $noun and nothing else of yours.';
  @override
  String get emailOptional => 'Email (optional)';
  @override
  String get editingAllowed => 'Editing allowed';
  @override
  String get canCheckAndAdd => 'Can tick off and add';
  @override
  String get canOnlyView => 'Can only view';
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
  String get mayEdit => 'May edit';
  @override
  String get viewOnly => 'View only';
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
  String wholeFamilySees(String noun) =>
      'For the whole family — everyone can see and edit $noun.';
  @override
  String onlyYouSee(String noun) => 'Visible to you only — nobody else sees $noun.';
  @override
  String youAndOthersSee(String names, String noun) => 'Only you and $names see $noun.';
  @override
  String joinNames(List<String> names) => names.length == 1
      ? names.first
      : '${names.sublist(0, names.length - 1).join(', ')} and ${names.last}';

  // ------------------------------------------------------------ icon pick --
  @override
  String get symbol => 'Symbol';
  @override
  String get change => 'Change';
  @override
  String get chooseSymbol => 'Choose a symbol';
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
      'Nobody in the household yet.\nInvite somebody to share lists, tasks and events.';
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
  String get languageGermanRegion => 'Germany';
  @override
  String get languageEnglishRegion => 'United Kingdom';

  // Both languages' keywords, so search finds a row whichever word comes to mind.
  @override
  String get searchTermsProfile =>
      'profile account name display name avatar colour role admin profil konto';
  @override
  String get searchTermsFamily =>
      'family members people invite role roles child children admin familie mitglieder';
  @override
  String get searchTermsCalendar =>
      'calendar events connections connect google outlook icloud iserv holidays waste school kalender';
  @override
  String get searchTermsLanguage => 'language sprache german english deutsch translation';
  @override
  String get searchTermsDarkMode =>
      'dark mode appearance light dark night theme dunkelmodus darstellung';
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
  String get onboardInviteBody =>
      'Everyone in your family can see and add to events, boxes and lists.';
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
  String get onboardReady => 'Ready!';
  @override
  String get onboardReadyBody =>
      'Your family is set up — you can change all of it later in Settings.';
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
  String get passwordLeaked =>
      'This password appears in known data leaks. Please choose another one.';
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
}
