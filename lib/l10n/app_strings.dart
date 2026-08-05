library;

import '../data/german_holidays.dart';

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
  String get size;
  String get titleLabel;
  String get role;
  String get emailAddress;
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

  // ------------------------------------------------------------ start tab --
  String get startNotDesigned;

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
  /// opens the calendar behind them.
  String get dueThisWeekend;
  String get dueNextWeek;
  String get duePickDate;

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
  String get files;
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
  String get all;
  String get newEvent;
  String get editEvent;
  String get startsAt;
  String get endsAt;
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
  String get route;
  String get reminder;
  String get deleteEventQuestion;
  String deleteEventBody(String title);
  String get untitledEvent;
  String reminderMinutesBefore(int minutes);
  String get calendarLoadFailed;
  String get eventNeedsTitle;
  String get eventSaveFailed;
  String get calendarNotEditable;
  String get eventDeleteFailed;
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
  String get providerHolidaysLabel;
  String get providerWasteLabel;
  String get providerGoogleDesc;
  String get providerOutlookDesc;
  String get providerIcloudDesc;
  String get providerIservDesc;
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
}
