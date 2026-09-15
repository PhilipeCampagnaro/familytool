import '../data/german_holidays.dart';
import '../models/grocery_unit.dart';
import '../theme/app_icons.dart';
import 'app_strings.dart';

/// Spanish (es-ES).
///
/// Written for a family in Spain rather than as a translation of the German app
/// with the nouns swapped. Where a string names something that only exists in
/// Germany — the Bundesland list, the bin names the waste vendors publish, the
/// IServ and WebUntis menu paths — the German word stays, exactly as it does in
/// [StringsEn]: somebody copying a link across two screens needs the words to
/// match what is actually on the other screen.
///
/// **Tuteo throughout**, matching the German side's `du`. A family organiser
/// that addresses a parent as `usted` reads like a bank.
///
/// **Month and weekday names are capitalised**, against the orthographic rule
/// that writes them lowercase. They are labels here rather than prose:
/// [monthYear] is a header on its own and [weekdayWithDate] opens a line, so
/// lowercase reads as a bug in every place the app actually draws them.
class StringsEs extends AppStrings {
  const StringsEs();

  @override
  String get localeCode => 'es';
  @override
  bool get use24HourClock => true;

  // ---------------------------------------------------------------- dates --
  @override
  List<String> get monthNames => const [
    '',
    'Enero',
    'Febrero',
    'Marzo',
    'Abril',
    'Mayo',
    'Junio',
    'Julio',
    'Agosto',
    'Septiembre',
    'Octubre',
    'Noviembre',
    'Diciembre',
  ];
  @override
  List<String> get monthShort => const [
    '',
    'Ene',
    'Feb',
    'Mar',
    'Abr',
    'May',
    'Jun',
    'Jul',
    'Ago',
    'Sep',
    'Oct',
    'Nov',
    'Dic',
  ];
  @override
  List<String> get weekdayShort => const ['Dom', 'Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb'];
  @override
  List<String> get weekdayLong => const [
    'Domingo',
    'Lunes',
    'Martes',
    'Miércoles',
    'Jueves',
    'Viernes',
    'Sábado',
  ];
  // Monday first. `X` for miércoles is the Spanish convention — `M` is already
  // martes, and two `M` in a row is the one collision a day grid cannot afford.
  @override
  List<String> get dayLetters => const ['L', 'M', 'X', 'J', 'V', 'S', 'D'];

  // `13 de Agosto` — the preposition is part of the date in Spanish, so it lives
  // here rather than at the call site.
  @override
  String dayMonth(int day, int month) => '$day de ${monthNames[month]}';
  @override
  String dayMonthShort(int day, int month) => '$day ${monthShort[month]}';
  @override
  String todayWithDate(int day, int month) => 'Hoy, ${dayMonth(day, month)}';
  @override
  String weekdayWithDate(int weekday, int day, int month) =>
      '${weekdayLong[weekday]}, ${dayMonth(day, month)}';
  @override
  String monthYear(int month, int year) => '${monthNames[month]} $year';
  @override
  String dateRange(String from, String to) => '$from – $to';
  @override
  String dayRangeSameMonth(int fromDay, int toDay, int month) => '$fromDay – $toDay de ${monthNames[month]}';
  @override
  String dayRangeCrossMonth(int fromDay, int fromMonth, int toDay, int toMonth) =>
      '$fromDay de ${monthNames[fromMonth]} – $toDay de ${monthNames[toMonth]}';
  @override
  String weekdayWithDateShort(int weekday, int day, int month) =>
      '${weekdayLong[weekday]}, $day ${monthShort[month]}';

  // --------------------------------------------------------------- common --
  @override
  String get cancel => 'Cancelar';
  @override
  String get delete => 'Eliminar';
  @override
  String get edit => 'Editar';
  @override
  String get share => 'Compartir';
  @override
  String get close => 'Cerrar';
  @override
  String get doneAction => 'Hecho';
  @override
  String get add => 'Añadir';
  @override
  String get rename => 'Cambiar el nombre';
  @override
  String get remove => 'Quitar';
  @override
  String get disconnect => 'Desconectar';
  @override
  String get undo => 'Deshacer';
  @override
  String get restored => 'Restaurado';
  @override
  String get beingRestored => 'Restaurando …';
  @override
  String get reload => 'Recargar';

  @override
  String get showFullName => 'Ver el nombre completo';

  @override
  String get hideFullName => 'Contraer el nombre';

  @override
  String get notes => 'Notas';
  @override
  String get addNotes => 'Añadir notas';
  @override
  String get name => 'Nombre';
  @override
  String get unknown => 'Desconocido';
  @override
  String get next => 'Siguiente';
  @override
  String get skip => 'Omitir';
  @override
  String get letsGo => 'Vamos allá';
  @override
  String get today => 'Hoy';
  @override
  String get allDay => 'Todo el día';
  @override
  String get place => 'Lugar';
  @override
  String get searchPlace => 'Buscar un lugar o un negocio';
  @override
  String get noPlacesFound => 'No se ha encontrado ningún lugar';
  @override
  String get quantity => 'Cantidad';
  @override
  String get unit => 'Unidad';
  @override
  // Sistema métrico, como en toda Europa.
  String unitName(GroceryUnit unit) => switch (unit) {
    GroceryUnit.piece => 'Unidad',
    GroceryUnit.gram => 'g',
    GroceryUnit.kilogram => 'kg',
    GroceryUnit.milliliter => 'ml',
    GroceryUnit.liter => 'l',
    GroceryUnit.pack => 'Paquete',
    GroceryUnit.can => 'Lata',
    GroceryUnit.bottle => 'Botella',
    GroceryUnit.bunch => 'Manojo',
    GroceryUnit.glass => 'Bote',
  };
  @override
  String get size => 'Talla';
  @override
  String get titleLabel => 'Título';
  @override
  String get role => 'Rol';
  @override
  String get nameOptional => 'Nombre (opcional)';
  @override
  String get password => 'Contraseña';
  @override
  String get calendar => 'Calendario';
  @override
  String get somethingWentWrong => 'Eso no ha funcionado.';
  @override
  String get noServerConnection => 'Sin conexión con el servidor.';
  @override
  String get serverTooSlow => 'El servidor ha tardado demasiado. Inténtalo de nuevo.';
  @override
  String get notSignedIn => 'No hay nadie con la sesión iniciada.';
  @override
  String get householdNotLoaded => 'Tu hogar aún no se ha cargado.';

  // ------------------------------------------------------------------ nav --
  @override
  String get navHome => 'Inicio';
  @override
  String get navCalendar => 'Calendario';
  @override
  String get navLists => 'Listas';
  @override
  String get navBoard => 'Tablero';
  @override
  String get navBox => 'Cajas';
  @override
  String get navExpand => 'Mostrar la navegación';

  // ---------------------------------------------------------------- board --
  @override
  String get boardTitle => 'Tablero';
  @override
  String doneCountSeparator(int count) => 'Hechas · $count';
  @override
  String get newTask => 'Nueva tarea';
  @override
  String get editTask => 'Editar tarea';
  @override
  String get taskPlaceholder => '¿Qué hay que hacer?';
  @override
  String get dueLabel => 'Fecha';
  @override
  String get dueNone => '—';
  @override
  String get sectionOverdue => 'Atrasadas';
  @override
  String get sectionToday => 'Hoy';
  @override
  String get sectionTomorrow => 'Mañana';
  @override
  String get sectionThisWeek => 'Esta semana';
  @override
  String get sectionLater => 'Más adelante';
  @override
  String get sectionUndated => 'Sin fecha';
  @override
  String get dueThisWeekend => 'Fin de semana';
  @override
  String get dueNextWeek => 'La semana que viene';
  @override
  String get duePickDate => 'Elegir una fecha …';
  @override
  String get dueTimeLabel => 'Hora';
  @override
  String get dueNoTime => 'Sin hora';
  @override
  String get dueTimeNeedsDate => 'Elige antes una fecha';
  @override
  String get theTask => 'la tarea';
  @override
  String get deleteTask => 'Eliminar tarea';
  @override
  String get assigneeLabel => 'Asignada a';
  @override
  String get nobody => 'Nadie';
  @override
  String get me => 'Yo';
  @override
  String get nothingPlanned => 'Nada planeado';
  @override
  String doneOfTotal(int done, int total) => '$done de $total hechas';
  @override
  String get trackerTitle => 'Rutinas';
  @override
  String trackerDaysDone(int done, int total) => '$done de $total días cumplidos';

  // ------------------------------------------------------------- Tracker --
  @override
  String get whatToCreate => '¿Qué quieres crear?';
  @override
  String get newEntry => 'Nuevo';
  @override
  String get kindTask => 'Tarea';
  @override
  String get kindTracker => 'Rutina';
  @override
  String get newTracker => 'Nueva rutina';
  @override
  String get editTracker => 'Editar rutina';
  @override
  String get trackerPlaceholder => '¿Qué queréis mantener?';
  @override
  String get theTracker => 'la rutina';
  @override
  String get deleteTracker => 'Eliminar rutina';
  @override
  String get trackerRhythm => 'Ritmo';
  @override
  String get rhythmDaily => 'Todos los días';
  @override
  String get rhythmDailyHint => 'Siete días a la semana';
  @override
  String get rhythmWeekdays => 'Ciertos días';
  @override
  String get rhythmWeekdaysHint => 'Todos los lunes y jueves, por ejemplo';
  @override
  String get rhythmTimesPerWeek => 'Tantas veces por semana';
  @override
  String get rhythmTimesPerWeekHint => 'Los días que vengan bien';
  @override
  String get whichDays => '¿Qué días?';
  @override
  String get howOften => '¿Con qué frecuencia?';
  @override
  String timesPerWeekValue(int times) => times == 1 ? 'Una vez por semana' : '$times veces por semana';
  @override
  String get timesPerWeekExplainer =>
      'Lo que cuenta es la semana, no el día. Nada vence un día concreto — se cuenta cuando la semana cierra, el domingo.';
  @override
  String get trackersTitle => 'Rutinas';
  @override
  String get tasksTitle => 'Tareas';
  @override
  String weekProgressLabel(int done, int target) => '$done de $target esta semana';
  @override
  String streakDays(int days) => days == 1 ? '1 día seguido' : '$days días seguidos';
  @override
  String streakWeeks(int weeks) => weeks == 1 ? '1 semana seguida' : '$weeks semanas seguidas';
  @override
  String get trackerGridEmpty => 'Todavía no hay nada que mantener';
  @override
  String moreTrackers(int count) => count == 1 ? '1 rutina más' : '$count rutinas más';
  @override
  String get trackerHistory => 'Historial';
  @override
  String trackerWeeksDone(int done, int total) => '$done de $total semanas cumplidas';
  @override
  String weekDoneOfTarget(int done, int target) => '$done de $target';
  @override
  String get trackerLegendKept => 'cumplido';
  @override
  String get trackerLegendMissed => 'fallado';
  @override
  String get trackerLegendNotDue => 'no tocaba';
  @override
  String get trackerBackfillTitle => 'Rellenar';
  @override
  String get trackerBackfillHint => 'Toca un día para rellenarlo a posteriori.';
  @override
  String get trackerBackfillOlderHint => 'Los días más antiguos se tocan en la cuadrícula.';
  @override
  String trackerDayFilledIn(String day) => '$day rellenado';
  @override
  String trackerDayCleared(String day) => '$day borrado';
  @override
  String get trackerNotDueToday => 'Hoy no toca';
  @override
  String get trackerStartedOn => 'Empezó el';
  @override
  String get trackersLoadFailed => 'No se han podido cargar las rutinas.';
  @override
  String get trackerSaveFailed => 'No se ha podido guardar la rutina.';
  @override
  String get trackerDeleteFailed => 'No se ha podido eliminar la rutina.';
  @override
  String get trackerCheckFailed => 'No se ha podido guardar la marca.';
  @override
  String get trackerRestoreFailed => 'No se ha podido restaurar la rutina.';
  @override
  String get pickAtLeastOneDay => 'Elige al menos un día.';
  @override
  String get trackerCreated => 'Rutina añadida';
  @override
  String get trackerUpdated => 'Rutina actualizada';
  @override
  String get trackerDeleted => 'Rutina eliminada';
  @override
  String get noOpenTasks => 'No hay tareas pendientes';
  @override
  String get addTask => 'Añadir tarea';
  @override
  String get tasksLoadFailed => 'No se han podido cargar las tareas.';
  @override
  String get taskSaveFailed => 'No se ha podido guardar la tarea.';
  @override
  String get changeSaveFailed => 'No se ha podido guardar el cambio.';
  @override
  String get saveFailed => 'No se ha podido guardar.';
  @override
  String get someDoneTasksNotDeleted => 'No se han podido eliminar todas las tareas hechas.';
  @override
  String get doneTasksDeleteFailed => 'No se han podido eliminar las tareas hechas.';
  @override
  String get taskDeleteFailed => 'No se ha podido eliminar la tarea.';
  @override
  String get taskCreated => 'Tarea creada';
  @override
  String get taskUpdated => 'Tarea actualizada';
  @override
  String get taskDeleted => 'Tarea eliminada';
  @override
  String get taskRestoreFailed => 'No se ha podido restaurar la tarea.';

  // ------------------------------------------------------------------ box --
  @override
  String get boxTitle => 'Cajas';
  @override
  String get searchBoxesAndItems => 'Buscar cajas y objetos';
  @override
  String get searchBoxesAndItemsLong => 'Buscar cajas y objetos';
  @override
  String get boxes => 'Cajas';
  @override
  String get items => 'Objetos';
  @override
  String get noBoxesYet => 'Todavía no hay cajas.\nCrea una para volver a encontrar lo que has guardado.';
  @override
  String matchCount(int count) => count == 1 ? '1 resultado' : '$count resultados';
  @override
  String itemCount(int count) => count == 1 ? '1 objeto' : '$count objetos';
  @override
  String get newBox => 'Nueva caja';
  @override
  String get editBox => 'Editar caja';
  @override
  String get boxName => 'Nombre de la caja';
  @override
  String get placeExample => 'p. ej. sótano, trastero';
  @override
  String get theBox => 'la caja';
  @override
  String get boxLabel => 'Caja';
  @override
  String get tapAboveToAddFirst => 'Toca arriba para añadir el primer objeto';
  @override
  String get newItem => 'Nuevo objeto';
  @override
  String get editItem => 'Editar objeto';
  @override
  String get itemName => 'Nombre del objeto';
  @override
  String get sizeExample => 'p. ej. 38, XL, 500 ml';
  @override
  String get itemNotePlaceholder => 'Notas, estado, sitio...';
  @override
  String get deleteItem => 'Eliminar objeto';
  @override
  String get addItemPlaceholder => 'Añadir objeto...';
  @override
  String get empty => 'Vacía';
  @override
  String emptyWithPlace(String place) => 'Vacía · $place';
  @override
  String itemsWithPlace(int count, String place) => '${itemCount(count)} · $place';
  @override
  String get boxesLoadFailed => 'No se han podido cargar las cajas.';
  @override
  String get boxSaveFailed => 'No se ha podido guardar la caja.';
  @override
  String get boxDeleteFailed => 'No se ha podido eliminar la caja.';
  @override
  String get itemSaveFailed => 'No se ha podido guardar el objeto.';
  @override
  String get itemDeleteFailed => 'No se ha podido eliminar el objeto.';
  @override
  String get itemDeleted => 'Objeto eliminado';
  @override
  String get itemRestoreFailed => 'No se ha podido restaurar el objeto.';
  @override
  String get itemCreated => 'Objeto creado';
  @override
  String get boxCreated => 'Caja creada';
  @override
  String get boxUpdated => 'Caja actualizada';
  @override
  String get boxDeleted => 'Caja eliminada';
  @override
  String get boxRestoreFailed => 'No se ha podido restaurar la caja.';

  // ----------------------------------------------------------------- list --
  @override
  String get listsTitle => 'Listas';
  @override
  String get searchListsAndItems => 'Buscar listas y artículos';
  @override
  String get searchListsAndItemsLong => 'Buscar listas y artículos';
  @override
  String get noListsYet => 'Todavía no hay listas.\nToca arriba para crear la primera.';
  @override
  String doneInList(String list) => 'Hechos · $list';
  @override
  String inList(String list) => 'en $list';
  @override
  String get newList => 'Nueva lista';
  @override
  String get editList => 'Editar lista';
  @override
  String get whichKindOfList => '¿Qué tipo de lista?';
  @override
  String get groceries => 'Compra';
  @override
  String get otherKind => 'Otra';
  @override
  String get listName => 'Nombre de la lista';
  @override
  String get theList => 'la lista';
  @override
  String get allDone => 'Todo hecho';
  @override
  String remaining(int count) => 'quedan $count';
  @override
  String get listLabel => 'Lista';
  @override
  String doneWithCount(int count) => 'Hechos ($count)';
  @override
  String get deleteDone => 'Eliminar los hechos';
  @override
  String get allItems => 'Todos los artículos';
  @override
  String get itemLabel => 'Artículo';
  @override
  String attachmentCount(int count) => count == 1 ? '1 adjunto' : '$count adjuntos';
  @override
  String get searchOnAmazon => 'Buscar en Amazon';
  @override
  String get photo => 'Foto';
  @override
  String get camera => 'Cámara';
  @override
  String get itemLink => 'Enlace';
  @override
  String get removeItemLink => 'Quitar el enlace';
  @override
  String get itemLinkMessage =>
      'La página donde se compra este artículo. Al tocar el enlace se abre en el navegador.';
  @override
  String get itemLinkHint => 'p. ej. amazon.es/dp/B0C…';
  @override
  String get itemLinkSaved => 'Enlace guardado';
  @override
  String get itemLinkInvalid => 'Eso no parece una dirección web.';
  @override
  String get listsLoadFailed => 'No se han podido cargar las listas.';
  @override
  String get listSaveFailed => 'No se ha podido guardar la lista.';
  @override
  String get listDeleteFailed => 'No se ha podido eliminar la lista.';
  @override
  String get listCreated => 'Lista creada';
  @override
  String get listUpdated => 'Lista actualizada';
  @override
  String get listDeleted => 'Lista eliminada';
  @override
  String get listRestoreFailed => 'No se ha podido restaurar la lista.';
  @override
  String get someDoneItemsNotDeleted => 'No se han podido eliminar todos los artículos hechos.';
  @override
  String get doneItemsDeleteFailed => 'No se han podido eliminar los artículos hechos.';

  // ------------------------------------------------------------- calendar --
  @override
  String get calendarTitle => 'Calendario';
  @override
  String get yourDay => 'Tu día';
  @override
  String get all => 'Todos';
  @override
  String get newEvent => 'Nuevo evento';
  @override
  String get editEvent => 'Editar evento';
  @override
  String get startsAt => 'Empieza';
  @override
  String get endsAt => 'Acaba';
  @override
  String get eventRepeat => 'Repetición';
  @override
  String get repeatNever => 'Nunca';
  @override
  String get repeatDaily => 'Cada día';
  // Todos los días de la semana son masculinos en español, así que el artículo
  // no cambia — a diferencia del portugués.
  @override
  String repeatWeekly(String weekday) => 'Todos los $weekday';
  @override
  String repeatBiweekly(String weekday) => 'Cada dos $weekday';
  @override
  String get repeatMonthly => 'Cada mes';
  @override
  String get repeatYearly => 'Cada año';
  @override
  String get repeatEnds => 'Acaba';
  @override
  String get repeatFollowsStart => 'La repetición sigue a la fecha de inicio.';
  @override
  String repeatUntilDate(String date) => 'hasta el $date';
  @override
  String get repeats => 'Se repite';
  @override
  String get repeatNotEditable => 'La regla de repetición no se cambia aquí — solo en el propio calendario.';
  @override
  String get repeatingEvent => 'Evento repetido';
  @override
  String get changeRepeatingEventBody => '¿Aplicar este cambio solo a este evento o a toda la serie?';
  @override
  String get deleteRepeatingEventBody => '¿Eliminar solo este evento o toda la serie?';
  @override
  String get thisEventOnly => 'Solo este evento';
  @override
  String get seriesCannotMoveCalendar =>
      'Una serie entera no puede cambiar de calendario. Elige “Solo este evento”.';
  @override
  String get wholeSeries => 'Toda la serie';
  @override
  String get noEventsThisDay => 'Ningún evento este día';
  @override
  String get todosChip => 'Tareas';
  @override
  String get dueRailLabel => 'Fecha';
  @override
  String get addEvent => 'Añadir evento';
  @override
  String get eventsPerCalendar => 'Eventos por calendario';
  @override
  String get publicHoliday => 'Festivo';
  @override
  String get schoolHoliday => 'Vacaciones escolares';
  @override
  // Los festivos alemanes conservan el nombre español consagrado donde existe;
  // los que solo existen en Alemania se describen, no se traducen literalmente.
  String germanHolidayName(GermanHoliday holiday) => switch (holiday) {
    GermanHoliday.neujahr => 'Año Nuevo',
    GermanHoliday.heiligeDreiKoenige => 'Reyes',
    GermanHoliday.frauentag => 'Día Internacional de la Mujer',
    GermanHoliday.karfreitag => 'Viernes Santo',
    GermanHoliday.ostersonntag => 'Domingo de Resurrección',
    GermanHoliday.ostermontag => 'Lunes de Pascua',
    GermanHoliday.tagDerArbeit => 'Día del Trabajo',
    GermanHoliday.christiHimmelfahrt => 'Ascensión',
    GermanHoliday.pfingstsonntag => 'Domingo de Pentecostés',
    GermanHoliday.pfingstmontag => 'Lunes de Pentecostés',
    GermanHoliday.fronleichnam => 'Corpus Christi',
    GermanHoliday.mariaeHimmelfahrt => 'Asunción de la Virgen',
    GermanHoliday.weltkindertag => 'Día Mundial de la Infancia',
    GermanHoliday.deutscheEinheit => 'Día de la Unidad Alemana',
    GermanHoliday.reformationstag => 'Día de la Reforma',
    GermanHoliday.allerheiligen => 'Todos los Santos',
    GermanHoliday.bussUndBettag => 'Día de Penitencia',
    GermanHoliday.weihnachtstag1 => 'Navidad',
    GermanHoliday.weihnachtstag2 => 'San Esteban',
  };
  @override
  String eventCount(int count) => count == 1 ? '1 evento' : '$count eventos';
  @override
  String get eventLabel => 'Evento';
  @override
  String get createListFromEvent => 'Crear una lista para este evento';
  @override
  String get createTaskFromEvent => 'Crear una tarea para este evento';
  @override
  String get createForEvent => 'Crear';
  @override
  String get alreadyCreated => 'Ya creado';
  @override
  String get linkedToEvent => 'Creado para este evento';
  @override
  String get linkedEventLabel => 'Evento';
  @override
  String get doneLabel => 'Hecho';
  @override
  String get openInCalendar => 'Ver en el calendario';
  @override
  String linkedListCount(int count) => count == 1 ? '1 lista' : '$count listas';
  @override
  String linkedTaskCount(int count) => count == 1 ? '1 tarea' : '$count tareas';
  @override
  String get route => 'Ruta';
  @override
  String get reminder => 'Recordatorio';
  @override
  String get deleteEvent => 'Eliminar evento';
  @override
  String get deleteEventQuestion => '¿Eliminar el evento?';
  @override
  String deleteEventBody(String title) => '“$title” se eliminará definitivamente.';
  @override
  String get untitledEvent => 'Sin título';
  @override
  String reminderMinutesBefore(int minutes) => '$minutes minutos antes';
  @override
  String get calendarLoadFailed => 'No se ha podido cargar el calendario.';
  @override
  String get eventNeedsTitle => 'El evento necesita un título.';
  @override
  String get eventSaveFailed => 'No se ha podido guardar el evento.';
  @override
  String get calendarNotEditable => 'Este calendario no se edita en Aporah.';
  @override
  String get eventDeleteFailed => 'No se ha podido eliminar el evento.';
  @override
  String eventBeingCreatedIn(String calendar) => 'Añadiendo el evento a $calendar …';
  @override
  String get eventBeingCreated => 'Añadiendo el evento …';
  @override
  String get eventBeingDeleted => 'Eliminando el evento …';
  @override
  String get seriesBeingDeleted => 'Eliminando la serie …';
  @override
  String get eventBeingSaved => 'Guardando el cambio …';
  @override
  String eventBeingMovedTo(String calendar) => 'Moviendo el evento a $calendar …';
  @override
  String get seriesBeingSaved => 'Guardando la serie …';
  @override
  String get eventCreated => 'Evento creado';
  @override
  String get eventUpdated => 'Evento actualizado';
  @override
  String get eventDeleted => 'Evento eliminado';
  @override
  String get eventRestoreFailed => 'No se ha podido restaurar el evento.';
  @override
  String get calendarNoLongerAvailable => 'Este calendario ya no está disponible.';
  @override
  String get noWritableCalendar =>
      'No hay ningún calendario donde escribir. Conecta antes uno en los Ajustes.';
  @override
  String get noHouseholdFound => 'No se ha encontrado ningún hogar.';
  @override
  String get eventSaveFailedRemote => 'No se ha podido guardar el evento en el calendario conectado.';

  @override
  String get allDayDuration => 'Todo el día';
  @override
  String durationDays(int days) => '$days días';
  @override
  String durationHours(int hours) => '$hours h';
  @override
  String durationHoursMinutes(int hours, int minutes) => '$hours h $minutes';
  @override
  String durationMinutes(int minutes) => '$minutes min';
  @override
  String timeRange(String from, String to) => '$from – $to';

  // -------------------------------------------------------------- weather --
  @override
  String temperature(int degrees) => '$degrees°';
  @override
  String get weatherClear => 'Despejado';
  @override
  String get weatherPartlyCloudy => 'Parcialmente nublado';
  @override
  String get weatherCloudy => 'Nublado';
  @override
  String get weatherFog => 'Niebla';
  @override
  String get weatherDrizzle => 'Llovizna';
  @override
  String get weatherRain => 'Lluvia';
  @override
  String get weatherSnow => 'Nieve';
  @override
  String get weatherStorm => 'Tormenta';

  // ------------------------------------------------------- calendar setup --
  @override
  String get connectCalendars => 'Conectar calendarios';
  @override
  String get calendarAccountsGroup => 'Cuentas';
  @override
  String get noAccountGroup => 'Sin cuenta';
  @override
  String get connectCalendarsIntro =>
      'Ve los planes de tu familia en la app — colegio, recogida de basura y '
      'calendarios personales en un solo sitio.';
  @override
  String get connectCalendarsAdminNote => 'Un adulto del hogar es quien conecta los calendarios.';
  @override
  String get noCalendarsConnected => 'Todavía no hay ningún calendario conectado.';
  @override
  String noProviderCalendarYet(String provider) =>
      'Todavía no hay calendario de $provider.\nToca "Conectar" para añadir el primero.';
  @override
  String get loadingEllipsis => 'Cargando …';
  @override
  String get notSyncedYet => 'Aún sin sincronizar';
  @override
  String get syncedJustNow => 'Sincronizado ahora mismo';
  @override
  String syncedMinutesAgo(int minutes) => 'Sincronizado hace $minutes minutos';
  @override
  String syncedHoursAgo(int hours) => 'Sincronizado hace $hours horas';
  @override
  String syncedDaysAgo(int days) => 'Sincronizado hace $days días';
  @override
  String get actionNeeded => 'Requiere atención';
  @override
  String get connected => 'Conectado';
  @override
  String calendarCount(int count) => count == 1 ? '1 calendario' : '$count calendarios';
  @override
  String get calendarSettings => 'Editar calendario';
  @override
  String get calendarColor => 'Color';
  @override
  String get renameCalendar => 'Cambiar el nombre del calendario';
  @override
  String get renameCalendarBody =>
      'Este es el nombre con el que el calendario aparece en Aporah — en el '
      'calendario, en los filtros y aquí.';
  @override
  String get householdOnly => 'Solo para tu hogar.';
  @override
  String get savingEllipsis => 'Guardando …';
  @override
  String get nameChanged => 'Nombre cambiado';
  @override
  String get removeCalendarQuestion => '¿Quitar el calendario?';
  @override
  String get disconnectQuestion => '¿Desconectar?';
  @override
  String removeCalendarBody(String name) => '“$name” desaparecerá de tu calendario. ';
  @override
  String get accessRevokedToo => 'El acceso también se revocará en el proveedor.';
  @override
  String get accountStaysConnected =>
      'La cuenta sigue conectada — y los demás calendarios que tiene, también.';
  @override
  String get householdOnlyOthersKeep => 'Solo para tu hogar — los demás conservan el calendario.';
  @override
  String get credentialsDeleted => 'Tus credenciales se eliminarán.';
  @override
  String get connectionNeedsAttention => 'La conexión requiere atención.';
  @override
  String get refreshingEllipsis => 'Actualizando …';
  @override
  String providerNotSetUp(String provider) => '$provider aún no está configurado.';
  @override
  String get browserCouldNotOpen => 'No se ha podido abrir el navegador.';
  @override
  String connectProvider(String provider) => 'Conectar $provider';
  @override
  String redirectNotice(String provider) =>
      'La sesión se inicia en $provider. Aporah solo ve tus calendarios — nunca tu '
      'contraseña.';
  @override
  String get openingEllipsis => 'Abriendo …';
  @override
  String signInWithProvider(String provider) => 'Iniciar sesión con $provider';
  @override
  String get comeBackWhenDone => 'Vuelve aquí cuando termines en el navegador.';
  @override
  String get connectedDot => 'Conectado.';
  @override
  String calendarsFoundPickThem(int count) =>
      'Hemos encontrado $count calendarios. Elige los que quieras ver en Aporah.';
  @override
  String get nameYourCalendarBody =>
      'Así se llama el calendario en Aporah. Puedes cambiarle el nombre ahora.';
  @override
  String get nameEachCalendarBody =>
      'Así se llaman los calendarios en Aporah. Puedes cambiarles el nombre ahora.';
  @override
  String get whichCalendars => 'Calendarios';
  @override
  String get whichCalendarsHint => 'Solo los que marques aparecen en Aporah. Puedes cambiarlo más adelante.';
  @override
  String get readOnlyCalendar => 'Solo lectura';
  @override
  String get pickAtLeastOneCalendar => 'Elige al menos un calendario.';
  @override
  String get selectAll => 'Seleccionar todo';
  @override
  String get deselectAll => 'Deseleccionar todo';
  @override
  String calendarsSelected(int count) =>
      count == 1 ? '1 calendario seleccionado' : '$count calendarios seleccionados';
  @override
  String get loadingCalendarsEllipsis => 'Cargando los calendarios …';
  @override
  String get appPasswordHint => 'No es la contraseña normal del Apple ID.';
  @override
  String get createAppPassword => 'Crear una contraseña específica para la app';
  @override
  String get school => 'Colegio';
  @override
  String get schoolAddressHint => 'La dirección con la que abres IServ.';
  @override
  String get username => 'Nombre de usuario';
  @override
  String get appleId => 'Apple ID';
  @override
  String get icloudEmailHint => 'nombre@icloud.com';
  @override
  String get emailAddress => 'Correo electrónico';
  @override
  String get oneAndOneAppPasswordHint =>
      'Lo mejor es una contraseña de aplicación — cubre solo el calendario y se '
      'puede revocar por separado.';
  @override
  String get appPasswordPlaceholder => 'Contraseña de aplicación';
  @override
  String get iservPassword => 'Contraseña de IServ';
  @override
  String get checkingEllipsis => 'Comprobando …';
  @override
  String get connect => 'Conectar';
  // "Bundesland" se queda en alemán: es lo que pone en la lista y en la web del
  // colegio, y traducirlo haría buscar una palabra que allí no existe.
  @override
  String get bundesland => 'Bundesland';
  @override
  String get holidaysIntro => 'Puedes elegir varios Bundesländer.';
  @override
  String get pickABundesland => 'Elige un Bundesland.';
  @override
  String schoolHolidaysOf(String state) => 'Vacaciones escolares $state';
  @override
  String holidaysSelectedBody(String state) =>
      'Has elegido $state. Las fechas de las vacaciones aparecerán en tu '
      'calendario — para todo el hogar.';
  @override
  String get wasteIntro =>
      'Las fechas de recogida de resto, orgánico, papel y envases entran en tu '
      'calendario automáticamente — para todo el hogar.';
  @override
  String get houseNumber => 'Número';
  @override
  String get multipleDistrictsHint =>
      'Esta calle tiene varias zonas de recogida. Sin elegir ninguna, se aplica el '
      'plan de toda la calle.';
  @override
  String wasteFor(String street) => 'Basura $street';
  @override
  String wasteForTown(String town) => 'Basura $town';
  @override
  String noVendorForTown(String town) =>
      'Todavía no conocemos ninguna empresa de recogida en $town. La mayoría '
      'publica sus fechas: busca en la web de tu empresa "Abfuhrkalender" o '
      '"Kalender abonnieren" y pega aquí el enlace.';
  @override
  String get checkingLinkEllipsis => 'Comprobando el enlace …';
  // Los pasos nombran opciones de menú reales de una plataforma escolar alemana.
  // La frase se traduce; la ruta del menú se queda como está en su pantalla.
  @override
  List<String> get iservLinkSteps => const [
    'Inicia sesión en IServ y abre el calendario.',
    'Abajo a la izquierda, elige "Einstellungen" y luego "Plugins".',
    'Junto al calendario que quieras — exámenes o deberes, por ejemplo — elige "Link erstellen".',
    'Copia el enlace que crea y pégalo aquí.',
  ];
  @override
  List<String> get webuntisLinkSteps => const [
    'Inicia sesión en WebUntis y toca tu nombre, arriba.',
    'En "Freigaben", elige "Kalender publizieren" — o, en el horario, abre los '
        'tres puntos, elige "iCal-Abo verwalten", selecciona el formato '
        '"Standard" y pulsa "Link erstellen".',
    'Copia el enlace iCal que crea y pégalo aquí.',
  ];
  @override
  String get icalLinkNote =>
      'Cualquier calendario al que puedas suscribirte: un club, una guardería, el '
      'trabajo. Lo que hace falta es la dirección de suscripción (ICS), no la '
      'página web del calendario.';
  @override
  String get uploadCalendarFile => 'Subir un archivo de calendario';
  @override
  String get uploadCalendarFileHint => 'Para un calendario publicado como descarga en vez de como enlace.';
  @override
  String get calendarFileNote =>
      'Un archivo es una foto fija: contiene exactamente los eventos que tenía '
      'cuando lo subiste. Cuando salga uno nuevo, vuelve a subirlo aquí.';
  @override
  String get checkingFileEllipsis => 'Comprobando el archivo …';
  @override
  String get calendarFileUnreadable => 'No se ha podido leer ese archivo. Elige un archivo .ics.';
  @override
  String calendarFileCoversTo(String date) => 'Los eventos llegan hasta el $date.';
  @override
  String calendarFileChosen(String name) => '$name seleccionado';
  @override
  String longDate(DateTime at) => '${at.day} de ${monthNames[at.month]} de ${at.year}';
  @override
  String get pasteCalendarLink => 'Enlace del calendario';
  @override
  String get pasteCalendarLinkHint => 'Lo consultamos enseguida, para que sepas al momento si funciona.';
  @override
  String get whoseCalendar => '¿De quién es esta cuenta?';
  @override
  String get whoseCalendarHint => 'Aparece luego en el filtro del calendario, p. ej. "IServ · Ana".';
  @override
  String get whoseCalendarPlaceholder => 'Nombre del niño';
  @override
  String get linkedCalendarName => 'Nombre del calendario';
  @override
  String get linkedCalendarNameHint => 'Exámenes, deberes o el calendario de la clase, por ejemplo.';
  @override
  String get nameThisCalendarFirst => 'Ponle un nombre al calendario.';
  @override
  String get whoseCalendarFirst => 'Di de quién es esta cuenta.';
  @override
  String get addAnotherCalendar => 'Añadir calendario';
  @override
  String get addAnotherCalendarBody =>
      'La plataforma del colegio crea un enlace distinto para cada calendario. '
      'Todos los enlaces de esta cuenta quedan bajo un único filtro en Calendario.';
  @override
  String get schoolCalendars => 'Calendarios';
  @override
  String get removeCalendar => 'Quitar calendario';
  @override
  String get linkStaysAtSchool =>
      ' El enlace sigue en la plataforma del colegio — nosotros simplemente dejamos de recordarlo.';
  @override
  String get connectWithLogin => 'Conectar con credenciales';
  @override
  String get connectWithLoginBody =>
      'Solo merece la pena si tu colegio tiene CalDAV activado. Los deberes y los '
      'exámenes no están ahí — para eso hacen falta los enlaces de arriba.';
  @override
  String get linkedCalendarsNote =>
      'Aporah solo lee estos calendarios. Sigue cambiando los eventos en la '
      'plataforma del colegio.';
  @override
  String eventsFoundAtLink(int count) => count == 1 ? '1 evento encontrado' : '$count eventos encontrados';
  @override
  String get noEventsAtLinkYet =>
      'El enlace funciona pero ahora mismo no tiene eventos. Es normal en vacaciones.';

  @override
  String get calendarLinkIcs => 'Enlace del calendario (ICS)';
  @override
  String get calendarLinkHint =>
      'Suele acabar en .ics — el enlace que hay detrás de "Suscribirse al calendario".';
  @override
  String get pasteLinkHere => 'Pega aquí el enlace del calendario.';
  @override
  String get noEventsAtThatLink =>
      'No se ha encontrado ningún evento en ese enlace. ¿Es el enlace del calendario en sí?';
  @override
  String get yourAddress => 'Dirección';
  @override
  String get yourAddressHint => 'Buscaremos tu empresa de recogida.';
  @override
  String get pickYourAddressFirst => 'Busca tu dirección y tócala.';
  @override
  String get addressPlaceholder => 'Calle y número, localidad';
  @override
  String get searchingAddresses => 'Buscando direcciones …';
  @override
  String get noAddressFound => 'No se ha encontrado ninguna dirección.';
  @override
  String get searchingVendor => 'Buscando una empresa de recogida …';
  @override
  String get tapToRetry => 'Toca para volver a intentarlo';
  @override
  String foundVendor(String where) => 'Encontrada: $where';
  @override
  String get noVendorFoundTapForLink =>
      'No se ha encontrado ninguna empresa — toca para indicar el enlace del calendario';
  @override
  String get askingNearbyVendors => 'Consultando a las empresas de la zona …';
  @override
  String get connectionStartFailed => 'No se ha podido iniciar la conexión.';
  @override
  String get connectionsLoadFailed => 'No se han podido cargar las conexiones.';
  @override
  String get connectingEllipsis => 'Conectando …';
  @override
  String get calendarConnected => 'Calendario conectado';
  @override
  String get calendarNameInAporah =>
      'Así se llama el calendario en Aporah. Puedes cambiarle el nombre más adelante.';

  // -------------------------------------------------------- provider meta --
  @override
  String get providerIcalLabel => 'Otro calendario';
  @override
  String get providerHolidaysLabel => 'Vacaciones';
  @override
  String get providerWasteLabel => 'Basura';
  @override
  String get providerGoogleDesc => 'Conectar Google Calendar.';
  @override
  String get providerOutlookDesc => 'Conectar Outlook o Microsoft 365.';
  @override
  String get providerIcloudDesc => 'Conectar iCloud con una contraseña específica para la app.';
  @override
  String get providerGmxDesc => 'Conectar el calendario de GMX — los eventos también vuelven.';
  @override
  String get providerWebdeDesc => 'Conectar el calendario de WEB.DE — los eventos también vuelven.';
  @override
  String get providerIservDesc => 'Deberes, exámenes y calendarios de clase de IServ.';
  @override
  String get providerWebuntisDesc => 'Mostrar el horario de WebUntis, con el enlace iCal del perfil.';
  @override
  String get providerIcalDesc =>
      'Añadir cualquier calendario al que puedas suscribirte — un club, una guardería, el trabajo.';
  @override
  String get providerHolidaysDesc => 'Mostrar las vacaciones escolares de tu Bundesland.';
  @override
  String get providerWasteDesc => 'Mostrar las fechas de recogida de basura de tu dirección.';

  // --------------------------------------------------------------- shares --
  @override
  String get shareTitle => 'Compartir';
  @override
  String shareIntro(String resource) => 'Comparte “$resource” con personas de fuera de la familia. ';
  @override
  String shareIntroSecond(String noun) => 'Verán $noun y nada más de lo vuestro.';
  @override
  String get emailOptional => 'Correo (opcional)';
  @override
  String get createLink => 'Crear enlace';
  @override
  String get sendInvite => 'Enviar invitación';
  @override
  String get guests => 'Invitados';
  @override
  String get activeLinks => 'Enlaces activos';
  @override
  String get notSharedYet => 'Todavía no está compartido.\nCrea un enlace para dejar entrar a alguien.';
  @override
  String get newLink => 'Nuevo enlace';
  @override
  String get copied => 'Copiado';
  @override
  String get copyLink => 'Copiar enlace';
  @override
  String get linkShownOnce => 'Este enlace solo se muestra ahora — no lo guardamos.';
  @override
  String usedTimes(int count) => count == 1 ? 'usado 1×' : 'usado $count×';
  @override
  String get linkExpired => 'caducado';
  @override
  String get linkUsedUp => 'agotado';
  @override
  String get shareLink => 'Enlace para compartir';
  @override
  String get revoke => 'Revocar';
  @override
  String get guest => 'Invitado';
  @override
  String get sharesLoadFailed => 'No se han podido cargar los elementos compartidos.';
  @override
  String get shareLinkCreateFailed => 'No se ha podido crear el enlace.';
  @override
  String get linkRevokeFailed => 'No se ha podido revocar el enlace.';
  @override
  String get guestRemoveFailed => 'No se ha podido quitar al invitado.';

  // ----------------------------------------------------------- visibility --
  @override
  String get forWhom => '¿Para quién?';
  @override
  String get everyone => 'Todos';
  @override
  String get onlyMe => 'Solo yo';
  @override
  String get selected => 'Seleccionados';
  @override
  String peopleCount(int count) => '$count personas';
  @override
  String wholeFamilySees(String noun) => 'Para toda la familia — todos pueden ver y editar $noun.';
  @override
  String onlyYouSee(String noun) => 'Solo visible para ti — nadie más ve $noun.';
  @override
  String youAndOthersSee(String names, String noun) => 'Solo tú y $names veis $noun.';
  @override
  String joinNames(List<String> names) =>
      names.length == 1 ? names.first : '${names.sublist(0, names.length - 1).join(', ')} y ${names.last}';

  // ------------------------------------------------------------ icon pick --
  @override
  String get symbol => 'Símbolo';
  @override
  String get change => 'Cambiar';
  @override
  String get photoUploadFailed => 'No se ha podido subir la foto.';
  @override
  String get photoRemoveFailed => 'No se ha podido quitar la foto.';
  @override
  String get chooseSymbol => 'Elegir un símbolo';
  @override
  String get uploadImage => 'Subir una imagen';
  @override
  String get searchSymbolOrShop => 'Buscar símbolos o tiendas';
  @override
  String get matches => 'Resultados';
  @override
  String nothingFoundFor(String query) => 'No se ha encontrado nada para "$query"';
  @override
  String get suggestionFromName => 'Sugerido a partir del nombre';
  @override
  String get shops => 'Tiendas';
  @override
  String get showLess => 'Ver menos';
  @override
  String allMoreShops(int count) => '$count tiendas más';
  @override
  String noMatchesFor(String query) => 'Sin resultados para “$query”';

  // ------------------------------------------------------------- settings --
  @override
  String get settingsTitle => 'Ajustes';
  @override
  String get searchSettings => 'Buscar en los ajustes';
  @override
  String get profile => 'Perfil';
  @override
  String get familyMembers => 'Miembros de la familia';
  @override
  String get language => 'Idioma';
  @override
  String get darkMode => 'Modo oscuro';
  @override
  String get welcomeTour => 'Visita guiada';
  @override
  String get repeat => 'Repetir';
  @override
  String get signOut => 'Cerrar sesión';
  @override
  String noSettingFoundFor(String query) => 'Ningún ajuste encontrado para “$query”';
  @override
  String get notConnected => 'Sin conectar';
  @override
  String get displayName => 'Nombre visible';
  @override
  String get avatarColour => 'Color del avatar';
  @override
  String get removePhoto => 'Quitar la foto';
  @override
  String get avatarUploadFailed => 'No se ha podido subir la foto de perfil.';
  @override
  String get avatarRemoveFailed => 'No se ha podido quitar la foto de perfil.';
  @override
  String get adminsManageFamily => 'Los administradores gestionan la familia y todas las conexiones.';
  @override
  String get familyMembersDesc =>
      'Define el rol de cada miembro de la familia. Los administradores gestionan '
      'la familia; los niños ven una versión simplificada.';
  @override
  String get familyMembersDescAdmin =>
      'Quién pertenece a tu hogar. Solo los administradores pueden invitar a gente '
      'y cambiar roles.';
  @override
  String get nobodyInHouseholdYet =>
      'Todavía no hay nadie en el hogar.\nInvita a alguien para compartir listas, '
      'tareas y eventos.';
  @override
  String get inviteMember => 'Invitar a alguien';
  @override
  String pendingWithRole(String role) => '$role · pendiente';
  @override
  String get inviteFamilyMember => 'Invitar a un miembro de la familia';
  @override
  String get inviteValidity => 'La invitación vale 14 días. Quien la acepte sale de su hogar anterior.';
  @override
  String get inviteSending => 'Enviando la invitación…';
  @override
  String get inviteSentTitle => 'Invitación enviada';
  @override
  String get inviteCreatedTitle => 'Invitación creada';
  @override
  String inviteSentTo(String email) => 'Hemos enviado un correo a $email.';
  @override
  String inviteMailNotSent(String email) =>
      'No se ha podido entregar el correo a $email. Comparte mejor el enlace de abajo.';
  @override
  String invitedAsRole(String role) => 'Invitado como $role';
  @override
  String inviteValidUntil(String date) => 'Válida hasta el $date';
  @override
  String invitedPerson(String who) => '$who invitado';
  @override
  String get tapSendToInvite => 'Toca enviar para entregar la invitación.';
  @override
  String get youCaps => 'TÚ';
  @override
  String get removeMemberQuestion => '¿Quitar al miembro?';
  @override
  String removeMemberBody(String name) =>
      '“$name” perderá el acceso a tu hogar. El contenido compartido se queda, el '
      'contenido privado se elimina.';
  @override
  String get languagePageDesc => 'Define el idioma de la app. Menús, botones y fechas cambian al momento.';
  @override
  String get setUpProfile => 'Configurar el perfil';
  @override
  String get languageGerman => 'Deutsch';
  @override
  String get languageEnglish => 'English';
  @override
  String get languagePortuguese => 'Português';
  @override
  String get languageSpanish => 'Español';
  @override
  String get languageGermanRegion => 'Alemania';
  @override
  String get languageEnglishRegion => 'Reino Unido';
  @override
  String get languagePortugueseRegion => 'Brasil';
  @override
  String get languageSpanishRegion => 'España';

  // Palabras clave en los cuatro idiomas, para que la fila aparezca sea cual sea
  // la palabra que al usuario le venga antes a la cabeza.
  @override
  String get searchTermsProfile =>
      'perfil cuenta nombre avatar color rol administrador profile account profil konto';
  @override
  String get searchTermsFamily =>
      'familia miembros personas invitar rol roles niño niños administrador '
      'family members familie mitglieder';
  @override
  String get searchTermsCalendar =>
      'calendario eventos conexiones conectar google outlook icloud iserv vacaciones basura '
      'colegio calendar kalender';
  @override
  String get searchTermsApplePay =>
      'apple pay google wallet samsung pay gastos dispositivos iphone android atajos '
      'automatización notificaciones acceso a las notificaciones detección activar quitar geräte';
  @override
  String get searchTermsLanguage =>
      'idioma lengua español inglés alemán portugués traducción language sprache';
  @override
  String get searchTermsDarkMode => 'modo oscuro apariencia claro oscuro noche tema dunkelmodus dark mode';
  @override
  String get searchTermsTour => 'visita guiada introducción repetir ayuda onboarding willkommenstour';
  @override
  String get searchTermsSignOut => 'cerrar sesión salir logout cuenta cambiar abmelden sign out';

  // ----------------------------------------------------------------- roles --
  @override
  String get roleAdmin => 'Administrador';
  @override
  String get roleMember => 'Miembro';
  @override
  String get roleChild => 'Niño';

  // ----------------------------------------------------------- onboarding --
  @override
  String get onboardSetUpFamily => 'Vamos a configurar tu familia';
  @override
  String get onboardSetUpFamilyBody =>
      'En unos pocos pasos invitarás a tu familia y conectarás los calendarios que '
      'cuentan en vuestro día a día.';
  @override
  String get onboardInviteTitle => 'Invita a tu familia';
  @override
  String get onboardInviteBody => 'Todos en la familia pueden ver y añadir eventos, cajas y listas.';
  @override
  String get adult => 'Adulto';
  @override
  String get child => 'Niño';
  @override
  String get onboardAddressTitle => 'Conecta tu dirección';
  @override
  String get onboardAddressBody =>
      'Te sugeriremos calendarios que encajen — la recogida de basura y las '
      'vacaciones escolares, por ejemplo.';
  @override
  String get address => 'Dirección';
  @override
  String get wasteCalendar => 'Calendario de recogida de basura';
  @override
  String get holidayCalendar => 'Calendario de vacaciones escolares';
  @override
  String get onboardFindingCalendars => 'Buscando calendarios para tu dirección …';
  @override
  String get onboardFoundForYou => 'Encontrados para tu dirección';
  @override
  String get onboardNothingForAddress =>
      'No hemos encontrado ningún calendario para esta dirección. Puedes conectar '
      'más adelante en los Ajustes.';
  @override
  String get onboardNotFoundHere => 'No encontrado para esta dirección';
  @override
  String get onboardRenameLater =>
      'Puedes cambiar el nombre de los calendarios más adelante en Ajustes → Calendario.';
  @override
  String get onboardConnectMoreHint => 'Añadir Google, Outlook, iCloud o IServ';
  @override
  String get onboardConnectingCalendars => 'Conectando los calendarios …';
  @override
  String get calendarsConnectFailed => 'No se han podido conectar los calendarios ahora.';
  @override
  String get onboardReady => '¡Listo!';
  @override
  String get onboardReadyBody =>
      'Tu familia está configurada — puedes cambiarlo todo más adelante en los Ajustes.';
  @override
  String get noInvitesSent => 'Ninguna invitación enviada';
  @override
  String invitedCount(int count) => '$count invitados';

  // ----------------------------------------------------------------- auth --
  @override
  String get welcomeToAporah => 'Te damos la bienvenida a Aporah';
  @override
  String get welcomeBack => 'Hola de nuevo';
  @override
  String get signUpBlurb =>
      'Crea tu cuenta. El hogar se crea automáticamente — puedes invitar a tu '
      'familia después.';
  @override
  String get signInBlurb => 'Inicia sesión con tu correo electrónico.';
  @override
  String get yourName => 'Tu nombre';
  @override
  String get atLeast8Chars => 'Al menos 8 caracteres.';
  @override
  String get createAccount => 'Crear cuenta';
  @override
  String get signIn => 'Iniciar sesión';
  @override
  String get haveAccountAlready => 'Ya tengo cuenta';
  @override
  String get newHereCreateAccount => '¿Eres nuevo? Crea una cuenta';
  @override
  String get forgotPassword => '¿Has olvidado la contraseña?';
  @override
  String get almostThere => 'Ya casi está';
  @override
  String confirmMailSent(String email) =>
      'Hemos enviado un correo a $email. Pulsa el enlace y ya podrás iniciar sesión.';
  @override
  String get toSignIn => 'Ir a iniciar sesión';
  @override
  String get pleaseEnterName => 'Introduce tu nombre.';
  @override
  String get noConnectionTryAgain => 'Sin conexión. Inténtalo de nuevo.';
  @override
  String get pleaseEnterEmailFirst => 'Introduce antes tu correo electrónico.';
  @override
  String get resetMailSent => 'Te hemos enviado un correo para restablecerla.';
  @override
  String get wrongCredentials => 'Ese correo o esa contraseña no son correctos.';
  @override
  String get confirmEmailFirst => 'Confirma antes tu correo electrónico.';
  @override
  String get accountExists => 'Ya existe una cuenta con este correo electrónico.';
  @override
  String get passwordTooShort => 'Esa contraseña es demasiado corta.';
  @override
  String get passwordLeaked => 'Esta contraseña aparece en filtraciones conocidas. Elige otra.';
  @override
  String get tooManyAttempts => 'Demasiados intentos. Espera un momento.';
  @override
  String get emailLooksInvalid => 'Ese correo electrónico no parece válido.';
  @override
  String get signInFailed => 'No se ha podido iniciar sesión. Inténtalo de nuevo.';

  // --------------------------------------------------------------- family --
  @override
  String get noHouseholdForAccount => 'No se ha encontrado ningún hogar para tu cuenta.';
  @override
  String get householdLoadFailed => 'No se ha podido cargar el hogar.';
  @override
  String get enterValidEmail => 'Introduce un correo electrónico válido.';
  @override
  String get inviteSendFailed => 'No se ha podido enviar la invitación.';
  @override
  String get roleChangeFailed => 'No se ha podido cambiar el rol.';
  @override
  String get memberRemoveFailed => 'No se ha podido quitar al miembro.';
  @override
  String get inviteRevokeFailed => 'No se ha podido revocar la invitación.';

  // --------------------------------------------------- calendar ownership --
  @override
  String get assignCalendar => 'Asignar';
  @override
  String assignCalendarBody(String calendar) =>
      '¿De quién es “$calendar”? El calendario pasará a aparecer bajo esa persona '
      'en Calendario y en el Tablero.';
  @override
  String get assignCalendarFamilyHint => 'Es de todo el hogar';
  @override
  String get assignCalendarNewPerson => 'Otra persona';
  @override
  String get assignCalendarNotVisibility =>
      'Esto no cambia quién puede ver el calendario — todo el hogar lo sigue viendo.';
  @override
  String get assignCalendarFailed => 'Esa asignación no se ha aplicado.';
  @override
  String get family => 'Familia';
  @override
  String get noAccountYet => 'Sin cuenta';

  @override
  String get familyName => 'Nombre de la familia';
  @override
  String get familyNameHint => 'Cómo se llama tu familia en Aporah.';
  @override
  String get renameFamily => 'Cambiar el nombre de la familia';
  @override
  String get renameFamilyBody =>
      'El nombre aparece en la pestaña de la familia en Calendario y en el Tablero.';
  @override
  String get familyRenameFailed => 'No se ha podido cambiar el nombre.';

  // ------------------------------------------------------------------- Home
  @override
  String homeOverdue(int count) => '$count atrasadas';
  @override
  String homeOpenToday(int count) => 'quedan $count';
  @override
  String homeTrackersLeft(int count) => 'quedan $count rutinas';
  @override
  String homeNextUp(String time, String title) => '$time · $title';
  @override
  String get homeAllDone => 'Todo hecho';
  @override
  String homeDayOffset(int days) => switch (days) {
    1 => 'Mañana',
    -1 => 'Ayer',
    > 1 => 'Dentro de $days días',
    _ => 'Hace ${-days} días',
  };
  @override
  String get homeHintBackToToday => 'Toca para volver a hoy';
  @override
  String get homeThinking => 'Un momento';
  @override
  String get homeHintThinking => 'Montando tu día';
  @override
  String get homeHintSetup => 'Configura Aporah para tu familia';
  @override
  String get homeHintOverdue => 'Tareas fuera de plazo';
  @override
  String get homeHintOpen => 'Tareas para hoy';
  @override
  String get homeHintTrackers => 'Aún sin marcar hoy';
  @override
  String get homeHintNext => 'Lo siguiente en tu calendario';
  @override
  String get homeHintDone => 'Ya no queda nada para hoy';
  @override
  @override
  String get homeTrackerSection => 'Hoy toca';
  @override
  String get homeListsSection => 'Listas';
  @override
  String get homeShowAll => 'Ver todo';
  @override
  String homeListOpenItems(int count) => '$count sin comprar';

  // ------------------------------------------------------------ First steps
  @override
  String get firstStepsTitle => 'Primeros pasos';
  @override
  String firstStepsProgress(int done, int total) => '$done de $total';
  @override
  String get firstStepCalendar => 'Conectar un calendario';
  @override
  String get firstStepCalendarBody => 'Colegio, trabajo y basura en un solo sitio.';
  @override
  String get firstStepFamily => 'Invitar a la familia';
  @override
  String get firstStepFamilyBody => 'Para que todos vean lo mismo.';
  @override
  String get firstStepTodo => 'Primera tarea';
  @override
  String get firstStepTodoBody => 'Algo que tenga que pasar esta semana.';
  @override
  String get firstStepTracker => 'Crear una rutina';
  @override
  String get firstStepTrackerBody => 'Un hábito que mantenéis juntos.';
  @override
  String get firstStepList => 'Primera lista';
  @override
  String get firstStepListBody => 'La compra es un buen sitio para empezar.';

  // --------------------------------------------------------------- Ausgaben
  @override
  String get navMore => 'Más';

  // España escribe `1.234,56 €`, como Alemania: coma decimal, punto en los
  // millares y el símbolo detrás del número.
  @override
  String get decimalSeparator => ',';
  @override
  String get thousandsSeparator => '.';
  @override
  String get thousandsSuffix => 'mil';
  @override
  String get millionsSuffix => 'M';
  @override
  String money(String amount, String symbol) => '$amount $symbol';
  @override
  String percent(int value) => '$value %';

  @override
  String get spendTitle => 'Gastos';
  @override
  String get spendAdminsOnly => 'Solo los administradores pueden ver los gastos.';
  @override
  String get spendEmpty => 'Todavía no hay nada registrado este mes.';
  @override
  String get spendEmptyEnrolled =>
      'Todavía nada este mes. Tu próximo pago con Apple Pay aparecerá aquí solo.';

  @override
  String get spendByCategory => 'Por categoría';
  @override
  String get spendTopMerchants => 'Por tienda';
  @override
  String get spendByMember => 'Por persona';

  @override
  String get spendOtherCategories => 'Otras';
  @override
  String get spendAllPurchases => 'Todas las compras';
  @override
  String get spendFormerMember => 'Antiguo miembro';

  @override
  String spendCountShort(int count) => count == 1 ? '1 pago' : '$count pagos';

  @override
  String spendPaymentsWord(int count) => count == 1 ? 'pago' : 'pagos';

  @override
  String get spendChartTrend => 'Tendencia';
  @override
  String get spendChartBars => 'Barras';
  @override
  String get spendChartRing => 'Anillo';

  @override
  String get spendRangeWeek => '1 S';
  @override
  String get spendRangeMonth => '1 M';
  @override
  String get spendRangeHalfYear => '6 M';
  @override
  String get spendRangeYear => '1 A';

  @override
  String get spendRangeThisWeek => 'Esta semana';
  @override
  String get spendRangeThisMonth => 'Este mes';
  @override
  String get spendRangeLastSixMonths => 'Últimos 6 meses';
  @override
  String get spendRangeThisYear => 'Este año';

  @override
  String get spendRangePick => 'Elegir un periodo';

  @override
  String spendAveragePerDay(String amount) => 'Media de $amount al día';
  @override
  String spendAveragePerMonth(String amount) => 'Media de $amount al mes';

  @override
  String get spendMetricAll => 'Gastos';
  @override
  String get spendShowAll => 'Ver todo';

  @override
  String spendShowAllCount(int count) => 'Ver los $count';

  @override
  String get spendIslandThinking => 'Haciendo cuentas';
  @override
  String get spendIslandThinkingHint => 'Cargando los pagos';

  @override
  String get spendIslandReviewHint => 'Falta la tienda o el importe';

  @override
  String get spendIslandNothing => 'Nada registrado';

  @override
  String spendIslandUp(int percent) => '$percent% más de gasto';
  @override
  String spendIslandDown(int percent) => '$percent% menos de gasto';
  @override
  String get spendIslandVsPrevious => 'frente al periodo anterior';

  @override
  String spendIslandTop(String category) => '$category es la mayor porción';
  @override
  String spendIslandTopHint(int percent) => '$percent% del gasto';

  @override
  String get spendAdd => 'Añadir un gasto';
  @override
  String get spendEdit => 'Editar gasto';
  @override
  String get spendAmount => 'Importe';
  @override
  String get spendDate => 'Fecha';
  @override
  String get spendCategory => 'Categoría';
  @override
  String get spendLabel => 'Gasto';
  @override
  String get spendKindLabel => 'Tipo';
  @override
  String get spendPaidBy => 'Pagado por';
  @override
  String get spendCard => 'Tarjeta';
  @override
  String get spendSourceLabel => 'Registro';
  @override
  String get spendSourceWallet => 'Apple Pay';
  @override
  String get spendSourceManual => 'A mano';
  @override
  String get spendNote => 'Nota';
  @override
  String get spendCategoryAuto => 'Automática';
  @override
  String get spendMerchantPlaceholder => '¿Dónde? p. ej. Mercadona';
  @override
  String get spendNotePlaceholder => 'Nota (opcional)';
  @override
  String get spendKindQuestion => '¿Qué tipo de gasto?';
  @override
  String get spendKindBudget => 'Corriente';
  @override
  String get spendKindExtra => 'Extra';
  @override
  String get spendNeedsMerchantAndAmount => 'Todavía faltan la tienda y el importe.';
  @override
  String get spendSaved => 'Gasto guardado';
  @override
  String get spendUpdated => 'Gasto actualizado';
  @override
  String get spendDeleted => 'Gasto eliminado';

  @override
  String spendReviewTitle(int count) =>
      count == 1 ? 'Un pago necesita un momento tuyo' : '$count pagos necesitan un momento tuyo';
  @override
  String get spendReviewBody => 'Apple no ha pasado la tienda o el importe. Toca la fila y complétalo.';
  @override
  String get spendReviewDetail =>
      'Apple no ha pasado la tienda o el importe. Toca el lápiz de arriba y complétalo.';

  @override
  String get spendLoadFailed => 'No se han podido cargar los gastos.';
  @override
  String get spendSaveFailed => 'No se ha podido guardar el gasto.';
  @override
  String get spendDeleteFailed => 'No se ha podido eliminar el gasto.';
  @override
  String get spendEnrolFailed => 'No se ha podido activar este dispositivo.';

  @override
  String get spendWalletTitle => 'Registrar Apple Pay automáticamente';
  @override
  String get spendWalletIntro =>
      'Todos los pagos hechos con este iPhone aparecen aquí solos. Sin enlaces ni '
      'códigos — se configura una automatización en Atajos, una sola vez.';
  @override
  String get spendWalletEnable => 'Activar este iPhone';
  @override
  String get spendWalletUnsupported =>
      'El registro automático funciona en iPhone y Android. En otros dispositivos, '
      'los gastos se añaden a mano.';
  @override
  String get spendWalletEnabled => 'Dispositivo activado';
  @override
  String get spendWalletActive => 'Este iPhone está activado';
  @override
  String get spendWalletInactive => 'Este iPhone todavía no está activado';
  @override
  String get spendWalletStepsTitle => 'Falta un paso, en la app Atajos';
  @override
  String get spendWalletStep1 => 'Abre Atajos y toca Automatización, abajo.';
  @override
  String get spendWalletStep2 => 'Toca + y elige Cartera.';
  @override
  String get spendWalletStep3 => 'Elige tus tarjetas y selecciona Ejecutar inmediatamente.';
  @override
  String get spendWalletStep4 => 'Elige la acción "Registrar gasto" — ya está en la lista.';
  @override
  String get spendWalletStep5 =>
      'En la acción, toca Comercio e Importe e inserta la variable correspondiente de la automatización — si no, el atajo se detiene a preguntar y no registra nada.';
  @override
  String get spendWalletOpenShortcuts => 'Abrir Atajos';
  @override
  String get settingsWalletCapture => 'Detección de la cartera';
  @override
  String get walletCapturePageDesc =>
      'Los pagos hechos con este móvil entran en Gastos solos. Activa aquí este '
      'dispositivo — y retira cualquier dispositivo de la misma manera.';
  @override
  String get spendWalletAndroidTitle => 'Registrar los pagos automáticamente';
  @override
  String get spendWalletAndroidIntro =>
      'Cuando pagas con el móvil, tu cartera te muestra el importe. Aporah lee solo '
      'esa notificación y archiva el gasto — sin banco, sin contraseña, sin nada '
      'que escribir.';
  @override
  String get spendWalletAndroidEnable => 'Activar este dispositivo';
  @override
  String get spendWalletAndroidActive => 'Este dispositivo está registrando pagos';
  @override
  String get spendWalletAndroidInactive => 'Este dispositivo todavía no está activado';
  @override
  String get spendWalletAndroidDeaf =>
      'Activado, pero sin acceso a las notificaciones — no nos puede llegar ningún pago.';
  @override
  String get spendWalletAndroidStepsTitle => 'Dos interruptores y funciona';
  @override
  String get spendWalletAndroidStep1 => 'Activa este dispositivo — es lo que le permite archivar gastos.';
  @override
  String get spendWalletAndroidStep2 =>
      'Activa el acceso a las notificaciones para Aporah en los ajustes del sistema.';
  @override
  String get spendWalletAndroidStep3 => 'Paga con el móvil — el gasto aparece aquí solo.';
  @override
  String get spendWalletAndroidNoDevicesHint => 'Usa el botón de abajo para activar este dispositivo.';
  @override
  String get spendWalletGrantAccess => 'Permitir el acceso a las notificaciones';
  @override
  String get spendWalletAccessGranted => 'Acceso concedido';
  @override
  String get spendWalletDisclosureTitle => 'Qué lee Aporah';
  @override
  String get spendWalletDisclosureBody =>
      'Android no tiene acceso a las notificaciones app por app: concederlo lo '
      'concede todo. Aporah solo evalúa las notificaciones de pago que publican las '
      'apps de cartera — todas las demás se descartan de inmediato, sin leerlas, sin '
      'guardarlas y sin contarlas. Lo que sale del dispositivo es la tienda, el '
      'importe, los últimos dígitos de la tarjeta y la hora. Nunca el texto de una '
      'notificación.';
  @override
  String get spendWalletAndroidSources => 'Se detectan Google Wallet, Google Pay y Samsung Wallet.';
  @override
  String get settingsApplePay => 'Apple Pay';
  @override
  String get applePayPageDesc =>
      'Los pagos con Apple Pay entran en Gastos solos. Activa aquí este iPhone — y '
      'retira cualquier dispositivo de la misma manera.';
  @override
  String get spendWalletNoDevices => 'Todavía no hay ningún dispositivo activado';
  @override
  String get spendWalletNoDevicesHint => 'Usa el botón de abajo para activar este iPhone.';
  @override
  String get spendWalletDevicesLabel => 'Dispositivos activados';
  @override
  String get spendWalletDeviceUnused => 'Todavía no ha archivado nada';
  @override
  String spendWalletDeviceLastUsed(String date) => 'Último el $date';
  @override
  String spendWalletDeviceCount(int count) => count == 0
      ? 'Ninguno'
      : count == 1
      ? '1 dispositivo'
      : '$count dispositivos';
  @override
  String get spendWalletRevoke => 'Quitar';
  @override
  String get spendWalletRenameTitle => 'Cambiar el nombre del dispositivo';
  @override
  String get spendWalletRenameBody =>
      'Este es el nombre con el que el dispositivo aparece en la lista — para distinguir vuestros móviles.';
  @override
  String get spendWalletDeviceNameHint => 'p. ej. iPhone de Ana';
  @override
  String get spendWalletThisDevice => 'Este dispositivo';

  @override
  String get spendCatGroceries => 'Supermercado';
  @override
  String get spendCatDrugstore => 'Droguería';
  @override
  String get spendCatFuel => 'Combustible';
  @override
  String get spendCatRestaurant => 'Restaurante';
  @override
  String get spendCatCafe => 'Panadería y cafetería';
  @override
  String get spendCatShipping => 'Correos y envíos';
  @override
  String get spendCatClothing => 'Ropa';
  @override
  String get spendCatShopping => 'Compras';
  @override
  String get spendCatElectronics => 'Electrónica';
  @override
  String get spendCatTransport => 'Desplazamientos';
  @override
  String get spendCatEntertainment => 'Ocio';
  @override
  String get spendCatHealth => 'Salud';
  @override
  String get spendCatHome => 'Hogar';
  @override
  String get spendCatOther => 'Otros';

  // ------------------------------------------------------ Plus (paywall) --
  @override
  String get plusName => 'Aporah Plus';
  @override
  String get plusPriceMonthly => '4,99 € / mes';
  @override
  String get plusPriceYearly => '39,99 € / año';
  @override
  String get plusYearlySaving => 'Ahorras un 33%';
  @override
  String get plusTrialNote => 'Gratis 14 días. Cancela cuando quieras.';
  @override
  String get plusUpgrade => 'Conseguir Plus';
  @override
  String get plusNotNow => 'Ahora no';
  @override
  String get plusRestore => 'Restaurar la compra';
  @override
  String get plusActive => 'Plus está activo';
  @override
  String plusActiveUntil(String date) => 'Plus dura hasta el $date';
  @override
  String get plusDebugOverride => 'Modo de prueba: el plan está simulado';

  @override
  String get paywallCalendarsTitle => 'Más de un calendario';
  @override
  String get paywallCalendarsBody =>
      'Con Plus puedes conectar tantos calendarios como necesites — la segunda '
      'cuenta de Google, el Outlook del trabajo, el colegio a través de IServ o '
      'WebUntis y cualquier enlace iCal. La semana de toda la familia en un sitio.';
  @override
  String get paywallTrackersTitle => 'Más rutinas';
  @override
  String get paywallTrackersBody =>
      'Tres rutinas son gratis. Con Plus puedes mantener tantas como pida el día a '
      'día — lavarse los dientes, sacar la basura, el vocabulario, cada una con su '
      'propio historial.';
  @override
  String get paywallBoxesTitle => 'Más cajas';
  @override
  String get paywallBoxesBody =>
      'Una caja es gratis. Con Plus cada trastero, cada altillo y cada caja de '
      'mudanza tiene la suya — con foto, para que nadie tenga que adivinar.';
  @override
  String get paywallMembersTitle => 'Más personas';
  @override
  String get paywallMembersBody =>
      'Hasta cuatro personas es gratis. Con Plus el hogar es tan grande como lo es '
      'de verdad — la abuela, la au pair, el tercer hijo.';
  @override
  String get paywallSharingTitle => 'Más elementos compartidos a la vez';
  @override
  String get paywallSharingBody =>
      'Puede haber dos enlaces compartidos activos a la vez. Con Plus no hay '
      'límite — la lista de la compra para el trabajo, la del campamento y la caja '
      'para el vecino, todas a la vez.';
  @override
  String get paywallPhotosTitle => 'Fotos y archivos';
  @override
  String get paywallPhotosBody =>
      'Con Plus cada caja, cada cosa que hay dentro y cada artículo de una lista '
      'lleva una foto — el número de serie del taladro, el cable correcto entre '
      'tres. Una imagen dice lo que ningún símbolo puede decir.';
  @override
  String get paywallSpendTitle => 'Gastos';
  @override
  String get paywallSpendBody =>
      'Con Plus ves adónde va el dinero: los pagos con Apple Pay se archivan solos '
      'y todo lo demás se añade en dos toques.';

  @override
  String get debugPlanTitle => 'Plan (debug)';
  @override
  String debugPlanReal(String plan) => 'Real: $plan';
  @override
  String debugPlanSimulated(String plan) => '$plan (simulado)';

  // --- Planificador -----------------------------------------------------
  @override
  String get plannerTitle => 'Plan';
  @override
  String get plannerPrompt =>
      'Di en una frase qué quieres hacer. Recibirás las instrucciones y, sobre todo, la lista '
      'con la que ir a comprar.';
  @override
  String get plannerHint => '¿Qué tienes pensado?';
  @override
  String get plannerExamplesLabel => 'POR EJEMPLO';
  @override
  List<List<PlannerExample>> get plannerExampleGroups => const [
    [
      (text: 'Cumpleaños para 8 niños', icon: AppIcons.cake),
      (text: 'Nochevieja para 10 personas', icon: AppIcons.confetti),
      (text: 'Barbacoa en el jardín', icon: AppIcons.flame),
      (text: 'Cena de Navidad en familia', icon: AppIcons.treeEvergreen),
      (text: 'Fiesta de inauguración del piso', icon: AppIcons.house),
      (text: 'Maleta para una semana en Italia', icon: AppIcons.suitcaseRolling),
    ],
    [
      (text: 'Compra semanal para 5 días', icon: AppIcons.shoppingCart),
      (text: 'Llenar la despensa', icon: AppIcons.package),
      (text: 'Limpieza a fondo del baño', icon: AppIcons.sprayBottle),
      (text: 'Renovar el botiquín', icon: AppIcons.bandaids),
      (text: 'Cambio de armario para el invierno', icon: AppIcons.tShirt),
      (text: 'Canastilla para el bebé', icon: AppIcons.baby),
    ],
    [
      (text: 'Construir una jardinera de madera', icon: AppIcons.hammer),
      (text: 'Montar estanterías para el cuarto', icon: AppIcons.ruler),
      (text: 'Pintar el salón de nuevo', icon: AppIcons.paintRoller),
      (text: 'Plantar el balcón', icon: AppIcons.plant),
      (text: 'Poner las bicis a punto', icon: AppIcons.bicycle),
      (text: 'Una casa en el árbol', icon: AppIcons.tree),
    ],
    [
      (text: 'Paella para 4', icon: AppIcons.cookingPot),
      (text: 'Asado de domingo para 6', icon: AppIcons.forkKnife),
      (text: 'Noche de pizza casera', icon: AppIcons.pizza),
      (text: 'Tarta para la fiesta del cole', icon: AppIcons.cake),
      (text: 'Brunch para 6 invitados', icon: AppIcons.egg),
      (text: 'Helado casero', icon: AppIcons.iceCream),
    ],
  ];
  @override
  String get plannerGo => 'Proponer una lista';
  @override
  String get plannerWorking => 'Preparándolo …';
  @override
  String get plannerWhatToBuy => 'LO QUE NECESITAS';
  @override
  String plannerItemCount(int count) => count == 1 ? '1 artículo' : '$count artículos';
  @override
  String get plannerHowTo => 'CÓMO SE HACE';
  @override
  String get plannerCreateList => 'Crear lista';
  @override
  String get plannerAgain => 'Preguntar otra vez';
  @override
  String get plannerEditGoal => 'Formularlo de otra manera';
  @override
  String get plannerListCreated => 'Lista creada';
  @override
  String get plannerUnavailable => 'Ahora mismo no ha funcionado. Inténtalo de nuevo en un momento.';
  @override
  String get plannerUnusable =>
      'No hemos podido hacer una lista con eso. Prueba con algo más concreto: un plato, un '
      'proyecto o una ocasión.';
  @override
  String get plannerNotConfigured => 'El planificador no está configurado ahora mismo.';
  @override
  String get plannerMonthlyLimit => 'Se han agotado los planes de este mes. El día 1 hay más.';
  @override
  String get plannerDailyLimit => 'Por hoy ya está. Vuelve a intentarlo mañana.';
  @override
  String plannerLeft(int left, int limit) =>
      left == 1 ? 'Queda 1 de $limit planes este mes' : 'Quedan $left de $limit planes este mes';
  @override
  String plannerNoneLeft(int day, String month) => 'No quedan planes: más el $day de ${month.toLowerCase()}';
  @override
  String plannerMonthlyLimitUntil(int day, String month) =>
      'Se han agotado los planes de este mes. El $day de ${month.toLowerCase()} hay más.';
  @override
  String plannerDailyLimitAt(String time, {required bool tomorrow}) => tomorrow
      ? 'Por hoy ya está. Mañana a partir de las $time hay más.'
      : 'Por ahora ya está. A partir de las $time hay más.';
  @override
  String get plannerLimitsLifted => 'Límites desactivados (prueba)';
  @override
  String get debugPlannerLimitsTitle => 'Límites de planes (debug)';
  @override
  String get debugPlannerLimitsEnforced => 'Activos';
  @override
  String get debugPlannerLimitsLifted => 'Desactivados';
  @override
  String get plannerIslandLine => 'Di qué tienes pensado.';
  @override
  String get plannerIslandHint => 'Nosotros hacemos la lista';

  // -------------------------------------------------------- notifications --
  @override
  String get notificationsTitle => 'Notificaciones';
  @override
  String get notificationsPageDesc => 'Lo que Aporah envía a tu móvil, y cuándo.';
  @override
  String get searchTermsNotifications =>
      'notificaciones recordatorios avisos push resumen del día basura recogida mitteilungen';
  @override
  String get notificationsAllowTitle => 'Permitir notificaciones';
  @override
  String get notificationsAllowBody => 'Sin permiso no llega ningún recordatorio.';
  @override
  String get notificationsDeniedBody => 'Las notificaciones están desactivadas en los ajustes del sistema.';
  @override
  String get notificationsAllow => 'Permitir';
  @override
  String get notificationsOpenSettings => 'Ajustes';
  @override
  String get notificationsQuietTitle => 'Se entregan en silencio';
  @override
  String get notificationsQuietBody => 'Las notificaciones llegan sin sonido al centro de notificaciones.';
  @override
  String get notifyBriefTitle => 'Resumen del día';
  @override
  String get notifyBriefSubtitle => 'Cada mañana, lo que hay hoy';
  @override
  String get notifyAbfallTitle => 'Recogida de basura';
  @override
  String get notifyAbfallSubtitle => 'La noche antes de la recogida';
  @override
  String get notifyTaskTimesTitle => 'Tareas con hora';
  @override
  String get notifyTaskTimesSubtitle => 'A la hora que pusiste';
  @override
  String get notifyTime => 'Hora';
  @override
  String get notificationsEventNote =>
      'El recordatorio de un evento se pone en el propio evento. Solo vale en este dispositivo.';
  @override
  String get reminderNone => 'Ninguno';
  @override
  String get reminderAtStart => 'Al empezar';
  @override
  String reminderHoursBefore(int hours) => hours == 1 ? '1 hora antes' : '$hours horas antes';
  @override
  String reminderDaysBefore(int days) => days == 1 ? '1 día antes' : '$days días antes';
  @override
  String reminderDayBefore(String time) => 'El día antes a las $time';
  @override
  String reminderMorningOf(String time) => 'El mismo día a las $time';
  @override
  String reminderCalendarAlready(String label) => 'Tu calendario ya te avisa: $label';
  @override
  String get reminderDenied => 'Las notificaciones están desactivadas; permítelas en Ajustes.';
  @override
  String get noticeBriefTitle => 'Tu día';
  @override
  String briefEvents(int count) => count == 1 ? '1 evento' : '$count eventos';
  @override
  String briefFirstAt(String time) => 'desde las $time';
  @override
  String briefTasks(int count) => count == 1 ? '1 tarea pendiente' : '$count tareas pendientes';
  @override
  String noticeAbfallTitle(String bins) => '¿Ya has sacado $bins?';
  @override
  String get noticeAbfallBody => 'La recogida es mañana temprano.';
  @override
  String noticeTaskDue(String time) => 'Para las $time';
  @override
  String joinAnd(List<String> parts) =>
      parts.length < 2 ? parts.join() : '${parts.sublist(0, parts.length - 1).join(', ')} y ${parts.last}';
  @override
  String get rateApp => 'Valorar Aporah';
  @override
  String get searchTermsRate => 'valorar valoración estrellas app store bewerten rate';
}
