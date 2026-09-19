import '../data/german_holidays.dart';
import '../models/grocery_unit.dart';
import '../theme/app_icons.dart';
import 'app_strings.dart';

/// Brazilian Portuguese (pt-BR).
///
/// **Brazilian, not European, and `appSupportedLocales` still carries a bare
/// `Locale('pt')`.** That is deliberate: a phone set to pt-PT resolves here
/// rather than falling back to German, so a household in Lisbon gets Portuguese
/// that reads as foreign to them instead of a language they do not speak. If
/// Portugal ever becomes a market of its own, this file is the one to fork —
/// `stringsFor` already switches on the code and would take `'pt_PT'` beside it.
///
/// The giveaways are lexical (*senha*, *celular*, *ônibus*, *geladeira*,
/// *compartilhar*, *excluir*) and grammatical: Brazilian says **"Carregando…"**
/// where Portugal says *"A carregar…"*, and that gerund sits on every loading
/// state in the app. Address the reader as **você** throughout, which matches
/// the German side's `du`.
///
/// Where a string names something that only exists in Germany — the Bundesland
/// list, the bin names the waste vendors publish, the IServ and WebUntis menu
/// paths — the German word stays, exactly as it does in [StringsEn]: somebody
/// copying a link across two screens needs the words to match what is actually
/// on the other screen.
///
/// **Month and weekday names are capitalised**, against the orthographic rule
/// that writes them lowercase. They are labels here rather than prose:
/// [monthYear] is a header on its own and [weekdayWithDate] opens a line, so
/// lowercase reads as a bug in every place the app actually draws them.
class StringsPt extends AppStrings {
  const StringsPt();

  @override
  String get localeCode => 'pt';
  @override
  bool get use24HourClock => true;

  // ---------------------------------------------------------------- dates --
  @override
  List<String> get monthNames => const [
    '',
    'Janeiro',
    'Fevereiro',
    'Março',
    'Abril',
    'Maio',
    'Junho',
    'Julho',
    'Agosto',
    'Setembro',
    'Outubro',
    'Novembro',
    'Dezembro',
  ];
  @override
  List<String> get monthShort => const [
    '',
    'Jan',
    'Fev',
    'Mar',
    'Abr',
    'Mai',
    'Jun',
    'Jul',
    'Ago',
    'Set',
    'Out',
    'Nov',
    'Dez',
  ];
  @override
  List<String> get weekdayShort => const ['Dom', 'Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb'];
  @override
  List<String> get weekdayLong => const [
    'Domingo',
    'Segunda-feira',
    'Terça-feira',
    'Quarta-feira',
    'Quinta-feira',
    'Sexta-feira',
    'Sábado',
  ];
  // Monday first. Segunda/Sexta and Terça/Quarta collide on their initial, which
  // is unavoidable — Portuguese numbers its weekdays and the grid has one glyph.
  @override
  List<String> get dayLetters => const ['S', 'T', 'Q', 'Q', 'S', 'S', 'D'];

  // `13 de Agosto` — the preposition is part of the date in Portuguese, so it
  // lives here rather than at the call site.
  @override
  String dayMonth(int day, int month) => '$day de ${monthNames[month]}';
  @override
  String dayMonthShort(int day, int month) => '$day ${monthShort[month]}';
  @override
  String todayWithDate(int day, int month) => 'Hoje, ${dayMonth(day, month)}';
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
  String get delete => 'Excluir';
  @override
  String get edit => 'Editar';
  @override
  String get share => 'Compartilhar';
  @override
  String get close => 'Fechar';
  @override
  String get doneAction => 'Pronto';
  @override
  String get add => 'Adicionar';
  @override
  String get rename => 'Renomear';
  @override
  String get remove => 'Remover';
  @override
  String get disconnect => 'Desconectar';
  @override
  String get undo => 'Desfazer';
  @override
  String get restored => 'Restaurado';
  @override
  String get beingRestored => 'Restaurando …';
  @override
  String get reload => 'Recarregar';

  @override
  String get showFullName => 'Ver o nome completo';

  @override
  String get hideFullName => 'Recolher o nome';

  @override
  String get notes => 'Notas';
  @override
  String get addNotes => 'Adicionar notas';
  @override
  String get name => 'Nome';
  @override
  String get unknown => 'Desconhecido';
  @override
  String get next => 'Avançar';
  @override
  String get skip => 'Pular';
  @override
  String get letsGo => 'Vamos lá';
  @override
  String get today => 'Hoje';
  @override
  String get allDay => 'Dia inteiro';
  @override
  String get place => 'Local';
  @override
  String get searchPlace => 'Buscar um local ou estabelecimento';
  @override
  String get noPlacesFound => 'Nenhum local encontrado';
  @override
  String get quantity => 'Quantidade';
  @override
  String get unit => 'Unidade';
  @override
  // Sistema métrico: o Brasil também compra em g, kg, ml e l.
  String unitName(GroceryUnit unit) => switch (unit) {
    GroceryUnit.piece => 'Unidade',
    GroceryUnit.gram => 'g',
    GroceryUnit.kilogram => 'kg',
    GroceryUnit.milliliter => 'ml',
    GroceryUnit.liter => 'l',
    GroceryUnit.pack => 'Pacote',
    GroceryUnit.can => 'Lata',
    GroceryUnit.bottle => 'Garrafa',
    GroceryUnit.bunch => 'Maço',
    GroceryUnit.glass => 'Pote',
  };
  @override
  String get size => 'Tamanho';
  @override
  String get titleLabel => 'Título';
  @override
  String get role => 'Papel';
  @override
  String get nameOptional => 'Nome (opcional)';
  @override
  String get password => 'Senha';
  @override
  String get calendar => 'Calendário';
  @override
  String get somethingWentWrong => 'Isso não funcionou agora.';
  @override
  String get noServerConnection => 'Sem conexão com o servidor.';
  @override
  String get serverTooSlow => 'O servidor demorou demais. Tente de novo.';
  @override
  String get notSignedIn => 'Ninguém está conectado.';
  @override
  String get householdNotLoaded => 'Sua família ainda não carregou.';

  // ------------------------------------------------------------------ nav --
  @override
  String get navHome => 'Início';
  @override
  String get navCalendar => 'Calendário';
  @override
  String get navLists => 'Listas';
  @override
  String get navBoard => 'Board';
  @override
  String get navBox => 'Caixas';
  @override
  String get navExpand => 'Mostrar a navegação';

  // ---------------------------------------------------------------- board --
  @override
  String get boardTitle => 'Board';
  @override
  String doneCountSeparator(int count) => 'Concluídas · $count';
  @override
  String get newTask => 'Novo To-do';
  @override
  String get editTask => 'Editar To-do';
  @override
  String get taskPlaceholder => 'O que precisa ser feito?';
  @override
  String get dueLabel => 'Prazo';
  @override
  String get dueNone => '—';
  @override
  String get sectionOverdue => 'Atrasadas';
  @override
  String get sectionToday => 'Hoje';
  @override
  String get sectionTomorrow => 'Amanhã';
  @override
  String get sectionThisWeek => 'Esta semana';
  @override
  String get sectionLater => 'Mais tarde';
  @override
  String get sectionUndated => 'Sem data';
  @override
  String get dueThisWeekend => 'Fim de semana';
  @override
  String get dueNextWeek => 'Semana que vem';
  @override
  String get duePickDate => 'Escolher uma data …';
  @override
  String get dueTimeLabel => 'Horário';
  @override
  String get dueNoTime => 'Sem horário';
  @override
  String get dueTimeNeedsDate => 'Escolha uma data primeiro';
  @override
  String get theTask => 'o To-do';
  @override
  String get deleteTask => 'Excluir To-do';
  @override
  String get assigneeLabel => 'Responsável';
  @override
  String get nobody => 'Ninguém';
  @override
  String get me => 'Eu';
  @override
  String get nothingPlanned => 'Nada planejado';
  @override
  String doneOfTotal(int done, int total) => '$done de $total concluídas';
  @override
  String get trackerTitle => 'Rotinas';
  @override
  String trackerDaysDone(int done, int total) => '$done de $total dias cumpridos';

  // ------------------------------------------------------------- Tracker --
  @override
  String get whatToCreate => 'O que você quer criar?';
  @override
  String get newEntry => 'Novo';
  @override
  String get kindTask => 'To-do';
  @override
  String get kindTracker => 'Rotina';
  @override
  String get newTracker => 'Nova rotina';
  @override
  String get editTracker => 'Editar rotina';
  @override
  String get trackerPlaceholder => 'O que vocês querem manter?';
  @override
  String get theTracker => 'a rotina';
  @override
  String get deleteTracker => 'Excluir rotina';
  @override
  String get trackerRhythm => 'Ritmo';
  @override
  String get rhythmDaily => 'Todos os dias';
  @override
  String get rhythmDailyHint => 'Sete dias por semana';
  @override
  String get rhythmWeekdays => 'Em certos dias';
  @override
  String get rhythmWeekdaysHint => 'Toda segunda e quinta, por exemplo';
  @override
  String get rhythmTimesPerWeek => 'Tantas vezes por semana';
  @override
  String get rhythmTimesPerWeekHint => 'Nos dias que der';
  @override
  String get whichDays => 'Quais dias?';
  @override
  String get howOften => 'Com que frequência?';
  @override
  String timesPerWeekValue(int times) => times == 1 ? 'Uma vez por semana' : '$times vezes por semana';
  @override
  String get timesPerWeekExplainer =>
      'O que conta é a semana, não o dia. Nada vence num dia específico — a conta é feita quando a semana fecha, no domingo.';
  @override
  String get trackersTitle => 'Rotinas';
  @override
  String get tasksTitle => 'To-dos';
  @override
  String weekProgressLabel(int done, int target) => '$done de $target esta semana';
  @override
  String streakDays(int days) => days == 1 ? '1 dia seguido' : '$days dias seguidos';
  @override
  String streakWeeks(int weeks) => weeks == 1 ? '1 semana seguida' : '$weeks semanas seguidas';
  @override
  String get trackerGridEmpty => 'Ainda não há nada para manter';
  @override
  String moreTrackers(int count) => count == 1 ? 'mais 1 rotina' : 'mais $count rotinas';
  @override
  String get trackerHistory => 'Histórico';
  @override
  String trackerWeeksDone(int done, int total) => '$done de $total semanas cumpridas';
  @override
  String weekDoneOfTarget(int done, int target) => '$done de $target';
  @override
  String get trackerLegendKept => 'cumprido';
  @override
  String get trackerLegendMissed => 'falhou';
  @override
  String get trackerLegendNotDue => 'não era dia';
  @override
  String get trackerBackfillTitle => 'Preencher';
  @override
  String get trackerBackfillHint => 'Toque num dia para preenchê-lo depois.';
  @override
  String get trackerBackfillOlderHint => 'Os dias mais antigos podem ser tocados na grade.';
  @override
  String trackerDayFilledIn(String day) => '$day preenchido';
  @override
  String trackerDayCleared(String day) => '$day limpo';
  @override
  String get trackerNotDueToday => 'Hoje não é dia';
  @override
  String get trackerStartedOn => 'Começou em';
  @override
  String get trackersLoadFailed => 'Não foi possível carregar as rotinas.';
  @override
  String get trackerSaveFailed => 'Não foi possível salvar a rotina.';
  @override
  String get trackerDeleteFailed => 'Não foi possível excluir a rotina.';
  @override
  String get trackerCheckFailed => 'Não foi possível salvar a marcação.';
  @override
  String get trackerRestoreFailed => 'Não foi possível restaurar a rotina.';
  @override
  String get pickAtLeastOneDay => 'Escolha pelo menos um dia.';
  @override
  String get trackerCreated => 'Rotina adicionada';
  @override
  String get trackerUpdated => 'Rotina atualizada';
  @override
  String get trackerDeleted => 'Rotina excluída';
  @override
  String get noOpenTasks => 'Nenhum To-do pendente';
  @override
  String get addTask => 'Adicionar To-do';
  @override
  String get tasksLoadFailed => 'Não foi possível carregar os To-dos.';
  @override
  String get taskSaveFailed => 'Não foi possível salvar o To-do.';
  @override
  String get changeSaveFailed => 'Não foi possível salvar a alteração.';
  @override
  String get saveFailed => 'Não foi possível salvar.';
  @override
  String get someDoneTasksNotDeleted => 'Não foi possível excluir todos os To-dos concluídos.';
  @override
  String get doneTasksDeleteFailed => 'Não foi possível excluir os To-dos concluídos.';
  @override
  String get taskDeleteFailed => 'Não foi possível excluir o To-do.';
  @override
  String get taskCreated => 'To-do criado';
  @override
  String get taskUpdated => 'To-do atualizado';
  @override
  String get taskDeleted => 'To-do excluído';
  @override
  String get taskRestoreFailed => 'Não foi possível restaurar o To-do.';

  // ------------------------------------------------------------------ box --
  @override
  String get boxTitle => 'Caixas';
  @override
  String get searchBoxesAndItems => 'Buscar caixas e itens';
  @override
  String get searchBoxesAndItemsLong => 'Buscar por caixas e itens';
  @override
  String get boxes => 'Caixas';
  @override
  String get items => 'Itens';
  @override
  String get noBoxesYet => 'Ainda não há caixas.\nCrie uma para achar de novo o que você guardou.';
  @override
  String matchCount(int count) => count == 1 ? '1 resultado' : '$count resultados';
  @override
  String itemCount(int count) => count == 1 ? '1 item' : '$count itens';
  @override
  String get newBox => 'Nova caixa';
  @override
  String get editBox => 'Editar caixa';
  @override
  String get boxName => 'Nome da caixa';
  @override
  String get placeExample => 'ex.: porão, sótão';
  @override
  String get theBox => 'a caixa';
  @override
  String get boxLabel => 'Caixa';
  @override
  String get tapAboveToAddFirst => 'Toque acima para adicionar o primeiro item';
  @override
  String get newItem => 'Novo item';
  @override
  String get editItem => 'Editar item';
  @override
  String get itemName => 'Nome do item';
  @override
  String get sizeExample => 'ex.: 38, GG, 500 ml';
  @override
  String get itemNotePlaceholder => 'Notas, estado, lugar...';
  @override
  String get deleteItem => 'Excluir item';
  @override
  String get addItemPlaceholder => 'Adicionar item...';
  @override
  String get viewAsCards => 'Em cartões';
  @override
  String get viewAsList => 'Em lista';
  @override
  String get empty => 'Vazia';
  @override
  String emptyWithPlace(String place) => 'Vazia · $place';
  @override
  String itemsWithPlace(int count, String place) => '${itemCount(count)} · $place';
  @override
  String get boxesLoadFailed => 'Não foi possível carregar as caixas.';
  @override
  String get boxSaveFailed => 'Não foi possível salvar a caixa.';
  @override
  String get boxDeleteFailed => 'Não foi possível excluir a caixa.';
  @override
  String get itemSaveFailed => 'Não foi possível salvar o item.';
  @override
  String get itemDeleteFailed => 'Não foi possível excluir o item.';
  @override
  String get itemDeleted => 'Item excluído';
  @override
  String get itemRestoreFailed => 'Não foi possível restaurar o item.';
  @override
  String get itemCreated => 'Item criado';
  @override
  String get boxCreated => 'Caixa criada';
  @override
  String get boxUpdated => 'Caixa atualizada';
  @override
  String get boxDeleted => 'Caixa excluída';
  @override
  String get boxRestoreFailed => 'Não foi possível restaurar a caixa.';

  // ----------------------------------------------------------------- list --
  @override
  String get listsTitle => 'Listas';
  @override
  String get searchListsAndItems => 'Buscar listas e itens';
  @override
  String get searchListsAndItemsLong => 'Buscar por listas e itens';
  @override
  String get noListsYet => 'Ainda não há listas.\nToque acima para criar a primeira.';
  @override
  String doneInList(String list) => 'Concluídos · $list';
  @override
  String inList(String list) => 'em $list';
  @override
  String get newList => 'Nova lista';
  @override
  String get editList => 'Editar lista';
  @override
  String get whichKindOfList => 'Que tipo de lista?';
  @override
  String get groceries => 'Mercado';
  @override
  String get otherKind => 'Outra';
  @override
  String get listName => 'Nome da lista';
  @override
  String get theList => 'a lista';
  @override
  String get allDone => 'Tudo pronto';
  @override
  String remaining(int count) => 'faltam $count';
  @override
  String get listLabel => 'Lista';
  @override
  String doneWithCount(int count) => 'Concluídos ($count)';
  @override
  String get deleteDone => 'Excluir os concluídos';
  @override
  String get allItems => 'Todos os itens';
  @override
  String get whichList => 'Em qual lista?';
  @override
  String get itemLabel => 'Item';
  @override
  String attachmentCount(int count) => count == 1 ? '1 anexo' : '$count anexos';
  @override
  String get searchOnAmazon => 'Buscar na Amazon';
  @override
  String get photo => 'Foto';
  @override
  String get camera => 'Câmera';
  @override
  String get itemLink => 'Link';
  @override
  String get removeItemLink => 'Remover o link';
  @override
  String get itemLinkMessage => 'A página onde dá para comprar este item. Tocar no link abre no navegador.';
  @override
  String get itemLinkHint => 'ex.: amazon.com.br/dp/B0C…';
  @override
  String get itemLinkSaved => 'Link salvo';
  @override
  String get itemLinkInvalid => 'Isso não parece um endereço da web.';
  @override
  String get listsLoadFailed => 'Não foi possível carregar as listas.';
  @override
  String get listSaveFailed => 'Não foi possível salvar a lista.';
  @override
  String get listDeleteFailed => 'Não foi possível excluir a lista.';
  @override
  String get listCreated => 'Lista criada';
  @override
  String get listUpdated => 'Lista atualizada';
  @override
  String get listDeleted => 'Lista excluída';
  @override
  String get listRestoreFailed => 'Não foi possível restaurar a lista.';
  @override
  String get someDoneItemsNotDeleted => 'Não foi possível excluir todos os itens concluídos.';
  @override
  String get doneItemsDeleteFailed => 'Não foi possível excluir os itens concluídos.';

  // ------------------------------------------------------------- calendar --
  @override
  String get calendarTitle => 'Calendário';
  @override
  String get yourDay => 'Seu dia';
  @override
  String get all => 'Todos';
  @override
  String get newEvent => 'Novo evento';
  @override
  String get editEvent => 'Editar evento';
  @override
  String get startsAt => 'Começa';
  @override
  String get endsAt => 'Termina';
  @override
  String get eventRepeat => 'Repetição';
  @override
  String get repeatNever => 'Nunca';
  @override
  String get repeatDaily => 'Todo dia';
  // O português contrai a preposição com o artigo e o gênero muda entre
  // "à segunda" e "ao sábado". O ponto médio evita a concordância inteira.
  @override
  String repeatWeekly(String weekday) => 'Semanal · $weekday';
  @override
  String repeatBiweekly(String weekday) => 'Quinzenal · $weekday';
  @override
  String get repeatMonthly => 'Mensal';
  @override
  String get repeatYearly => 'Anual';
  @override
  String get repeatEnds => 'Termina';
  @override
  String get repeatFollowsStart => 'A repetição segue a data de início.';
  @override
  String repeatUntilDate(String date) => 'até $date';
  @override
  String get repeats => 'Se repete';
  @override
  String get repeatNotEditable => 'A regra de repetição não muda aqui — só no próprio calendário.';
  @override
  String get repeatingEvent => 'Evento repetido';
  @override
  String get changeRepeatingEventBody => 'Aplicar esta alteração só a este evento ou a toda a série?';
  @override
  String get deleteRepeatingEventBody => 'Excluir só este evento ou toda a série?';
  @override
  String get thisEventOnly => 'Só este evento';
  @override
  String get seriesCannotMoveCalendar =>
      'Uma série inteira não pode mudar de calendário. Escolha “Só este evento”.';
  @override
  String get wholeSeries => 'Toda a série';
  @override
  String get noEventsThisDay => 'Nenhum evento neste dia';
  @override
  String get todosChip => 'To-dos';
  @override
  String get dueRailLabel => 'Prazo';
  @override
  String get addEvent => 'Adicionar evento';
  @override
  String get eventsPerCalendar => 'Eventos por calendário';
  @override
  String get publicHoliday => 'Feriado';
  @override
  String get schoolHoliday => 'Férias escolares';
  @override
  // Os feriados alemães ficam com o nome consagrado em português onde ele
  // existe; os que só existem na Alemanha são descritos, não traduzidos ao pé
  // da letra.
  String germanHolidayName(GermanHoliday holiday) => switch (holiday) {
    GermanHoliday.neujahr => 'Ano-Novo',
    GermanHoliday.heiligeDreiKoenige => 'Dia de Reis',
    GermanHoliday.frauentag => 'Dia Internacional da Mulher',
    GermanHoliday.karfreitag => 'Sexta-feira Santa',
    GermanHoliday.ostersonntag => 'Domingo de Páscoa',
    GermanHoliday.ostermontag => 'Segunda-feira de Páscoa',
    GermanHoliday.tagDerArbeit => 'Dia do Trabalho',
    GermanHoliday.christiHimmelfahrt => 'Ascensão',
    GermanHoliday.pfingstsonntag => 'Domingo de Pentecostes',
    GermanHoliday.pfingstmontag => 'Segunda-feira de Pentecostes',
    GermanHoliday.fronleichnam => 'Corpus Christi',
    GermanHoliday.mariaeHimmelfahrt => 'Assunção de Nossa Senhora',
    GermanHoliday.weltkindertag => 'Dia Mundial da Criança',
    GermanHoliday.deutscheEinheit => 'Dia da Unidade Alemã',
    GermanHoliday.reformationstag => 'Dia da Reforma',
    GermanHoliday.allerheiligen => 'Dia de Todos os Santos',
    GermanHoliday.bussUndBettag => 'Dia de Penitência',
    GermanHoliday.weihnachtstag1 => 'Natal',
    GermanHoliday.weihnachtstag2 => 'Segundo dia de Natal',
  };
  @override
  String eventCount(int count) => count == 1 ? '1 evento' : '$count eventos';
  @override
  String get eventLabel => 'Evento';
  @override
  String get createListFromEvent => 'Criar uma lista para este evento';
  @override
  String get createTaskFromEvent => 'Criar um To-do para este evento';
  @override
  String get createForEvent => 'Criar';
  @override
  String get alreadyCreated => 'Já criado';
  @override
  String get linkedToEvent => 'Criado para este evento';
  @override
  String get linkedEventLabel => 'Evento';
  @override
  String get doneLabel => 'Concluído';
  @override
  String get openInCalendar => 'Ver no calendário';
  @override
  String linkedListCount(int count) => count == 1 ? '1 lista' : '$count listas';
  @override
  String linkedTaskCount(int count) => count == 1 ? '1 To-do' : '$count To-dos';
  @override
  String get route => 'Rota';
  @override
  String get reminder => 'Lembrete';
  @override
  String get deleteEvent => 'Excluir evento';
  @override
  String get deleteEventQuestion => 'Excluir o evento?';
  @override
  String deleteEventBody(String title) => '“$title” será excluído de vez.';
  @override
  String get untitledEvent => 'Sem título';
  @override
  String reminderMinutesBefore(int minutes) => '$minutes minutos antes';
  @override
  String get calendarLoadFailed => 'Não foi possível carregar o calendário.';
  @override
  String get eventNeedsTitle => 'O evento precisa de um título.';
  @override
  String get eventSaveFailed => 'Não foi possível salvar o evento.';
  @override
  String get calendarNotEditable => 'Este calendário não pode ser editado no Aporah.';
  @override
  String get eventDeleteFailed => 'Não foi possível excluir o evento.';
  @override
  String eventBeingCreatedIn(String calendar) => 'Adicionando o evento em $calendar …';
  @override
  String get eventBeingCreated => 'Adicionando o evento …';
  @override
  String get eventBeingDeleted => 'Excluindo o evento …';
  @override
  String get seriesBeingDeleted => 'Excluindo a série …';
  @override
  String get eventBeingSaved => 'Salvando a alteração …';
  @override
  String eventBeingMovedTo(String calendar) => 'Movendo o evento para $calendar …';
  @override
  String get seriesBeingSaved => 'Salvando a série …';
  @override
  String get eventCreated => 'Evento criado';
  @override
  String get eventUpdated => 'Evento atualizado';
  @override
  String get eventDeleted => 'Evento excluído';
  @override
  String get eventRestoreFailed => 'Não foi possível restaurar o evento.';
  @override
  String get calendarNoLongerAvailable => 'Este calendário não está mais disponível.';
  @override
  String get noWritableCalendar =>
      'Não há calendário onde escrever. Conecte um calendário nas Configurações primeiro.';
  @override
  String get noHouseholdFound => 'Nenhuma família encontrada.';
  @override
  String get eventSaveFailedRemote => 'Não foi possível salvar o evento no calendário conectado.';

  @override
  String get allDayDuration => 'Dia inteiro';
  @override
  String durationDays(int days) => '$days dias';
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
  String get weatherAttribution => 'DWD · OpenStreetMap';
  @override
  String get weatherClear => 'Céu limpo';
  @override
  String get weatherPartlyCloudy => 'Parcialmente nublado';
  @override
  String get weatherCloudy => 'Nublado';
  @override
  String get weatherFog => 'Neblina';
  @override
  String get weatherDrizzle => 'Garoa';
  @override
  String get weatherRain => 'Chuva';
  @override
  String get weatherSnow => 'Neve';
  @override
  String get weatherStorm => 'Tempestade';

  // ------------------------------------------------------- calendar setup --
  @override
  String get connectCalendars => 'Conectar calendários';
  @override
  String get calendarAccountsGroup => 'Contas';
  @override
  String get noAccountGroup => 'Sem conta';
  @override
  String get connectCalendarsIntro =>
      'Veja os compromissos da sua família no app — escola, coleta de lixo e '
      'calendários pessoais num lugar só.';
  @override
  String get connectCalendarsAdminNote => 'Um adulto da família é quem conecta os calendários.';
  @override
  String get noCalendarsConnected => 'Nenhum calendário conectado ainda.';
  @override
  String noProviderCalendarYet(String provider) =>
      'Ainda não há calendário do $provider.\nToque em "Conectar" para adicionar o primeiro.';
  @override
  String get loadingEllipsis => 'Carregando …';
  @override
  String get notSyncedYet => 'Ainda não sincronizado';
  @override
  String get syncedJustNow => 'Sincronizado agora mesmo';
  @override
  String syncedMinutesAgo(int minutes) => 'Sincronizado há $minutes minutos';
  @override
  String syncedHoursAgo(int hours) => 'Sincronizado há $hours horas';
  @override
  String syncedDaysAgo(int days) => 'Sincronizado há $days dias';
  @override
  String get actionNeeded => 'Precisa de atenção';
  @override
  String get connected => 'Conectada';
  @override
  String calendarCount(int count) => count == 1 ? '1 calendário' : '$count calendários';
  @override
  String get calendarSettings => 'Editar calendário';
  @override
  String get calendarColor => 'Cor';
  @override
  String get renameCalendar => 'Renomear calendário';
  @override
  String get renameCalendarBody =>
      'É com este nome que o calendário aparece no Aporah — no calendário, nos filtros e aqui.';
  @override
  String get householdOnly => 'Só para a sua família.';
  @override
  String get savingEllipsis => 'Salvando …';
  @override
  String get nameChanged => 'Nome alterado';
  @override
  String get removeCalendarQuestion => 'Remover o calendário?';
  @override
  String get disconnectQuestion => 'Desconectar?';
  @override
  String removeCalendarBody(String name) => '“$name” vai sumir do seu calendário. ';
  @override
  String get accessRevokedToo => 'O acesso também será revogado no provedor.';
  @override
  String get accountStaysConnected => 'A conta continua conectada — e os outros calendários dela também.';
  @override
  String get householdOnlyOthersKeep => 'Só para a sua família — os outros continuam com o calendário.';
  @override
  String get credentialsDeleted => 'Suas credenciais serão excluídas.';
  @override
  String get connectionNeedsAttention => 'A conexão precisa de atenção.';
  @override
  String get refreshingEllipsis => 'Atualizando …';
  @override
  String providerNotSetUp(String provider) => '$provider ainda não está configurado.';
  @override
  String get browserCouldNotOpen => 'Não foi possível abrir o navegador.';
  @override
  String connectProvider(String provider) => 'Conectar $provider';
  @override
  String redirectNotice(String provider) =>
      'Você entra no $provider. O Aporah só vê seus calendários — nunca sua senha.';
  @override
  String get openingEllipsis => 'Abrindo …';
  @override
  String signInWithProvider(String provider) => 'Entrar com $provider';
  @override
  String get comeBackWhenDone => 'Volte aqui quando terminar no navegador.';
  @override
  String get connectedDot => 'Conectada.';
  @override
  String calendarsFoundPickThem(int count) =>
      'Encontramos $count calendários. Escolha os que você quer ver no Aporah.';
  @override
  String get nameYourCalendarBody =>
      'É assim que o calendário se chama no Aporah. Você pode renomeá-lo agora.';
  @override
  String get nameEachCalendarBody =>
      'É assim que os calendários se chamam no Aporah. Você pode renomeá-los agora.';
  @override
  String get whichCalendars => 'Calendários';
  @override
  String get whichCalendarsHint => 'Só as que você marcar aparecem no Aporah. Dá para mudar isso depois.';
  @override
  String get readOnlyCalendar => 'Somente leitura';
  @override
  String get pickAtLeastOneCalendar => 'Escolha pelo menos um calendário.';
  @override
  String get selectAll => 'Selecionar tudo';
  @override
  String get deselectAll => 'Desmarcar tudo';
  @override
  String calendarsSelected(int count) =>
      count == 1 ? '1 calendário selecionado' : '$count calendários selecionados';
  @override
  String get loadingCalendarsEllipsis => 'Carregando os calendários …';
  @override
  String get appPasswordHint => 'Não é a senha normal do Apple ID.';
  @override
  String get createAppPassword => 'Criar uma senha específica do app';
  @override
  String get school => 'Escola';
  @override
  String get schoolAddressHint => 'O endereço em que você abre o IServ.';
  @override
  String get username => 'Nome de usuário';
  @override
  String get appleId => 'Apple ID';
  @override
  String get icloudEmailHint => 'nome@icloud.com';
  @override
  String get emailAddress => 'E-mail';
  @override
  String get oneAndOneAppPasswordHint =>
      'O melhor é uma senha de aplicativo — ela cobre só o calendário e pode ser '
      'revogada sozinha.';
  @override
  String get appPasswordPlaceholder => 'Senha de aplicativo';
  @override
  String get iservPassword => 'Senha do IServ';
  @override
  String get checkingEllipsis => 'Verificando …';
  @override
  String get connect => 'Conectar';
  // "Bundesland" fica em alemão: é o que está escrito na lista e no site da
  // escola, e traduzir faria o usuário procurar uma palavra que não existe lá.
  @override
  String get bundesland => 'Bundesland';
  @override
  String get holidaysIntro => 'Você pode escolher vários Bundesländer.';
  @override
  String get pickABundesland => 'Escolha um Bundesland.';
  @override
  String schoolHolidaysOf(String state) => 'Férias escolares $state';
  @override
  String holidaysSelectedBody(String state) =>
      'Você escolheu $state. As datas das férias passam a aparecer no seu calendário — '
      'para todo mundo da família.';
  @override
  String get wasteIntro =>
      'As datas de coleta de lixo comum, orgânico, papel e recicláveis entram na '
      'seu calendário automaticamente — para todo mundo da família.';
  @override
  String get houseNumber => 'Número';
  @override
  String get multipleDistrictsHint =>
      'Esta rua tem várias rotas de coleta. Sem escolher, vale o plano da rua inteira.';
  @override
  String wasteFor(String street) => 'Lixo $street';
  @override
  String wasteForTown(String town) => 'Lixo $town';
  @override
  String noVendorForTown(String town) =>
      'Ainda não conhecemos nenhuma empresa de coleta em $town. A maioria publica '
      'as datas: procure no site da sua empresa por "Abfuhrkalender" ou '
      '"Kalender abonnieren" e cole o link aqui.';
  @override
  String wasteUploadOnlyBody(String town) =>
      '$town não libera as datas de coleta para consulta automática por apps — vejam como trazer o calendário de coleta para cá em poucos passos.';
  @override
  String get openTownCalendarPage => 'Abrir o calendário de coleta da cidade';
  @override
  String get wasteUploadOnlyShort => 'Só como arquivo — toque para adicionar';
  @override
  List<String> get binFileStepsInApp => [
    'Abram o calendário de coleta da cidade abaixo.',
    'Escolham a rua de vocês.',
    'Toquem no download em iCal ou ICS.',
    'O Aporah reconhece o arquivo automaticamente e o traz direto para cá.',
  ];
  @override
  List<String> get binFileStepsBrowser => [
    'Abram o calendário de coleta da cidade abaixo.',
    'Escolham a rua de vocês.',
    'Toquem no download em iCal ou ICS.',
    'Depois enviem o arquivo aqui em "Enviar um arquivo de calendário".',
  ];
  @override
  String get calendarPagePrompt => 'Escolham a rua e toquem na exportação iCal';
  @override
  String get calendarPageNotCalendar => 'Isso não é um arquivo de calendário. Procurem por "iCal" ou "ICS" na página.';
  @override
  String get calendarPageFailed => 'Não deu para baixar o arquivo. Tentem de novo.';
  @override
  String get ok => 'OK';
  @override
  String get wasteUploadOnlyLater => 'Só disponível como arquivo — dá para adicionar depois como arquivo de calendário.';
  @override
  String get wasteOnTownPage => 'Datas na página da cidade';
  @override
  String get onboardWasteFileTitle => 'O calendário de coleta de vocês vem como arquivo';
  @override
  String get pdfDistrictLabel => 'Distrito de vocês';
  @override
  String get wasteFileAdded => 'Calendário de coleta adicionado como arquivo';
  @override
  String wasteOwnPageBody(String town) =>
      '$town publica o calendário de coleta na própria página — vejam como trazê-lo para cá em poucos passos.';
  @override
  String get wasteLinkLater =>
      'Ainda não encontramos aqui — dá para adicionar o calendário depois como link ou arquivo.';
  @override
  List<String> get binFileStepsPdfInApp => [
    'Abram o calendário de coleta da cidade abaixo.',
    'Escolham a cidade ou a rua de vocês.',
    'Toquem no calendário em iCal, ICS ou PDF.',
    'O Aporah reconhece o arquivo automaticamente e o traz direto para cá.',
  ];
  @override
  List<String> get binFileStepsPdfBrowser => [
    'Abram o calendário de coleta da cidade abaixo.',
    'Escolham a cidade ou a rua de vocês.',
    'Toquem no calendário em iCal, ICS ou PDF.',
    'Depois enviem o arquivo aqui em "Enviar um arquivo de calendário ou PDF".',
  ];
  @override
  String get townPagePdfOnly =>
      'Lá o calendário só existe como PDF para imprimir, e o app não consegue ler. Vocês encontram as datas na página da cidade — e, se houver um arquivo iCal, dá para trazê-lo para cá.';
  @override
  String get townPageDatesOnly =>
      'As datas talvez apareçam só na própria página. Procurem uma exportação em iCal ou ICS.';
  @override
  String get townPageAppOnly =>
      'As datas talvez estejam só no app da cidade. Procurem na página uma exportação em iCal ou ICS.';
  @override
  String get calendarPagePromptPdf =>
      'Escolham a rua e baixem o calendário em iCal ou PDF';
  @override
  String get calendarPageNotCalendarPdf =>
      'Isso não é um arquivo de calendário. Procurem por "iCal", "ICS" ou "PDF" na página.';
  @override
  String get pdfNotReadableYet =>
      'Isso é um PDF, e o app não consegue ler. Escolham um arquivo de calendário (iCal ou ICS).';
  @override
  String get fileTooLarge =>
      'Este arquivo é grande demais.';
  @override
  String get pickDistrictFirst =>
      'Escolham o distrito de vocês.';
  @override
  String get pdfDistrictIntro =>
      'O plano vale para vários distritos. Qual é o de vocês? As próximas datas ajudam a reconhecer.';
  @override
  String nextPickups(String dates) =>
      'Próximas: $dates';
  @override
  String get wasteNeedsHouseNumber => 'Digite o endereço com o número — aqui a coleta é planejada por casa.';
  @override
  String get houseNumberAsk =>
      'E o número?';
  @override
  String get houseNumberAskHint =>
      'Pra gente achar a coleta certinha da sua casa.';
  @override
  String get houseNumberPlaceholder =>
      'ex.: 12a';
  @override
  String get houseNumberInvalid =>
      'Digite um número como 12 ou 12a.';
  @override
  String get houseNumberUnknown =>
      'A coleta não reconhece esse número — confira, por favor.';
  @override
  String get addressPrivacyNote =>
      'O endereço só é usado pra achar a coleta de lixo, as férias escolares e o clima.';
  @override
  String get onboardRhythmTitle => 'Mais uma pergunta sobre a coleta';
  @override
  String get pickHouseNumberHint => 'Aqui a coleta é planejada por casa — escolha o número da sua casa.';
  @override
  String rhythmQuestion(String bin) => '$bin — com que frequência é esvaziado?';
  @override
  String get rhythmHint => 'Está no adesivo da sua lixeira — é a mesma pergunta do calendário da cidade. Só esse ritmo aparece.';
  @override
  String get pickRhythmFirst => 'Escolha antes com que frequência sua lixeira é esvaziada.';
  @override
  String get rhythmWeekly => 'semanal';
  @override
  String rhythmEveryWeeks(int n) => 'a cada $n semanas';
  @override
  String get checkingRhythm => 'Verificando o ritmo da coleta …';
  @override
  String get checkingLinkEllipsis => 'Verificando o link …';
  // Os passos citam itens de menu reais de uma plataforma escolar alemã. A frase
  // é traduzida; o caminho do menu fica como está na tela do usuário.
  @override
  List<String> get iservLinkSteps => const [
    'Entre no IServ e abra o calendário.',
    'Embaixo à esquerda, escolha "Einstellungen" e depois "Plugins".',
    'Ao lado do calendário que você quer — provas ou tarefas, por exemplo — escolha "Link erstellen".',
    'Copie o link criado e cole aqui.',
  ];
  @override
  List<String> get webuntisLinkSteps => const [
    'Entre no WebUntis e toque no seu nome, lá em cima.',
    'Em "Freigaben", escolha "Kalender publizieren" — ou, no horário, abra os '
        'três pontinhos, escolha "iCal-Abo verwalten", selecione o formato '
        '"Standard" e aperte "Link erstellen".',
    'Copie o link iCal criado e cole aqui.',
  ];
  @override
  String get icalLinkNote =>
      'Qualquer calendário que você possa assinar: um clube, uma creche, o trabalho. '
      'O que precisa é o endereço de assinatura (ICS), não a página do calendário.';
  @override
  String get uploadCalendarFileOrPdf => 'Enviar um arquivo de calendário ou PDF';
  @override
  String get uploadCalendarFile => 'Enviar um arquivo de calendário';
  @override
  String get uploadCalendarFileHint => 'Para um calendário publicado como download em vez de link.';
  @override
  String get calendarFileNote =>
      'Um arquivo é uma foto do momento: ele tem exatamente os eventos que tinha '
      'quando você enviou. Quando sair um novo, envie aqui de novo.';
  @override
  String get checkingFileEllipsis => 'Verificando o arquivo …';
  @override
  String get calendarFileUnreadable => 'Não foi possível ler esse arquivo. Escolha um arquivo .ics.';
  @override
  String calendarFileCoversTo(String date) => 'Os eventos vão até $date.';
  @override
  String calendarFileChosen(String name) => '$name selecionado';
  @override
  String longDate(DateTime at) => '${at.day} de ${monthNames[at.month]} de ${at.year}';
  @override
  String get pasteCalendarLink => 'Link do calendário';
  @override
  String get pasteCalendarLinkHint => 'A gente busca na hora, para você saber logo se funciona.';
  @override
  String get whoseCalendar => 'De quem é esta conta?';
  @override
  String get whoseCalendarHint => 'Aparece depois no filtro do calendário, ex.: "IServ · Ana".';
  @override
  String get whoseCalendarPlaceholder => 'Nome da criança';
  @override
  String get linkedCalendarName => 'Nome do calendário';
  @override
  String get linkedCalendarNameHint => 'Provas, tarefas ou o calendário da turma, por exemplo.';
  @override
  String get nameThisCalendarFirst => 'Dê um nome ao calendário.';
  @override
  String get whoseCalendarFirst => 'Diga de quem é esta conta.';
  @override
  String get schoolCalendars => 'Calendários';
  @override
  String get removeCalendar => 'Remover calendário';
  @override
  String get linkStaysAtSchool => ' O link continua na plataforma da escola — a gente só para de guardá-lo.';
  @override
  String get linkedCalendarsNote =>
      'O Aporah só lê estes calendários. Continue alterando os eventos na plataforma '
      'da escola.';
  @override
  String eventsFoundAtLink(int count) => count == 1 ? '1 evento encontrado' : '$count eventos encontrados';
  @override
  String get noEventsAtLinkYet => 'O link funciona mas não tem eventos agora. Isso é normal nas férias.';

  @override
  String get calendarLinkIcs => 'Link do calendário (ICS)';
  @override
  String get calendarLinkHint => 'Costuma terminar em .ics — o link por trás de "Assinar calendário".';
  @override
  String get pasteLinkHere => 'Cole o link do calendário aqui.';
  @override
  String get noEventsAtThatLink => 'Nenhum evento encontrado nesse link. É mesmo o link do calendário?';
  @override
  String get yourAddress => 'Endereço';
  @override
  String get yourAddressHint => 'A gente acha a sua empresa de coleta.';
  @override
  String get pickYourAddressFirst => 'Busque seu endereço e toque nele.';
  @override
  String get addressPlaceholder => 'Rua e número, cidade';
  @override
  String get searchingAddresses => 'Buscando endereços …';
  @override
  String get noAddressFound => 'Nenhum endereço encontrado.';
  @override
  String get searchingVendor => 'Buscando uma empresa de coleta …';
  @override
  String get tapToRetry => 'Toque para tentar de novo';
  @override
  String foundVendor(String where) => 'Encontrada: $where';
  @override
  String get noVendorFoundTapForLink =>
      'Nenhuma empresa encontrada — toque para informar o link do calendário';
  @override
  String get askingNearbyVendors => 'Consultando as empresas da região …';
  @override
  String get connectionStartFailed => 'Não foi possível iniciar a conexão.';
  @override
  String get connectionsLoadFailed => 'Não foi possível carregar as conexões.';
  @override
  String get connectingEllipsis => 'Conectando …';
  @override
  String get calendarConnected => 'Calendário conectado';
  @override
  String get calendarNameInAporah =>
      'É assim que o calendário se chama no Aporah. Você pode renomeá-lo depois.';

  // -------------------------------------------------------- provider meta --
  @override
  String get providerIcalLabel => 'Outro calendário';
  @override
  String get providerHolidaysLabel => 'Férias';
  @override
  String get providerWasteLabel => 'Lixo';
  @override
  String get providerGoogleDesc => 'Conectar o Google Agenda.';
  @override
  String get providerOutlookDesc => 'Conectar o Outlook ou o Microsoft 365.';
  @override
  String get providerIcloudDesc => 'Conectar o iCloud com uma senha específica do app.';
  @override
  String get providerGmxDesc => 'Conectar o calendário do GMX — os eventos voltam também.';
  @override
  String get providerWebdeDesc => 'Conectar o calendário do WEB.DE — os eventos voltam também.';
  @override
  String get providerIservDesc => 'Tarefas, provas e calendários de turma do IServ.';
  @override
  String get providerWebuntisDesc => 'Mostrar o horário do WebUntis, pelo link iCal do perfil.';
  @override
  String get providerIcalDesc =>
      'Adicionar qualquer calendário que você possa assinar — um clube, uma creche, o trabalho.';
  @override
  String get providerHolidaysDesc => 'Mostrar as férias escolares do seu Bundesland.';
  @override
  String get providerWasteDesc => 'Mostrar as datas de coleta de lixo do seu endereço.';

  // --------------------------------------------------------------- shares --
  @override
  String get shareTitle => 'Compartilhar';
  @override
  String shareIntro(String resource) => 'Compartilhe “$resource” com gente de fora da família. ';
  @override
  String shareIntroSecond(String noun) => 'Elas veem $noun e mais nada do que é seu.';
  @override
  String get emailOptional => 'E-mail (opcional)';
  @override
  String get createLink => 'Criar link';
  @override
  String get sendInvite => 'Enviar convite';
  @override
  String get guests => 'Convidados';
  @override
  String get activeLinks => 'Links ativos';
  @override
  String get notSharedYet => 'Ainda não está compartilhado.\nCrie um link para deixar alguém entrar.';
  @override
  String get newLink => 'Novo link';
  @override
  String get copied => 'Copiado';
  @override
  String get copyLink => 'Copiar link';
  @override
  String get linkShownOnce => 'Este link só aparece agora — a gente não guarda ele.';
  @override
  String usedTimes(int count) => count == 1 ? 'usado 1×' : 'usado $count×';
  @override
  String get linkExpired => 'expirado';
  @override
  String get linkUsedUp => 'esgotado';
  @override
  String get shareLink => 'Link de compartilhamento';
  @override
  String get revoke => 'Revogar';
  @override
  String get guest => 'Convidado';
  @override
  String get sharesLoadFailed => 'Não foi possível carregar os compartilhamentos.';
  @override
  String get shareLinkCreateFailed => 'Não foi possível criar o link.';
  @override
  String get linkRevokeFailed => 'Não foi possível revogar o link.';
  @override
  String get guestRemoveFailed => 'Não foi possível remover o convidado.';
  @override
  String shareListMessage(String name) => '“$name” no Aporah — é só entrar por este link:';
  @override
  String get sharedOutsideTitle => 'Compartilhada com';
  @override
  String openInvitations(int count, String? until) {
    if (count == 1) return until == null ? 'Convite em aberto' : 'Convite em aberto · vale até $until';
    return until == null ? '$count convites em aberto' : '$count convites em aberto · valem até $until';
  }

  @override
  String get sharedOutsideLabel => 'Compartilhada com gente de fora da família';

  // ----------------------------------------------------------- visibility --
  @override
  String get forWhom => 'Para quem?';
  @override
  String get everyone => 'Todo mundo';
  @override
  String get onlyMe => 'Só eu';
  @override
  String get selected => 'Selecionados';
  @override
  String peopleCount(int count) => '$count pessoas';
  @override
  String wholeFamilySees(String noun) => 'Para a família toda — todo mundo pode ver e editar $noun.';
  @override
  String onlyYouSee(String noun) => 'Só você vê — mais ninguém vê $noun.';
  @override
  String youAndOthersSee(String names, String noun) => 'Só você e $names veem $noun.';
  @override
  String joinNames(List<String> names) =>
      names.length == 1 ? names.first : '${names.sublist(0, names.length - 1).join(', ')} e ${names.last}';

  // ------------------------------------------------------------ icon pick --
  @override
  String get symbol => 'Símbolo';
  @override
  String get change => 'Alterar';
  @override
  String get photoUploadFailed => 'Não foi possível enviar a foto.';
  @override
  String get photoRemoveFailed => 'Não foi possível remover a foto.';
  @override
  String get chooseSymbol => 'Escolher um símbolo';
  @override
  String get uploadImage => 'Enviar uma imagem';
  @override
  String get searchSymbolOrShop => 'Buscar símbolos ou lojas';
  @override
  String get matches => 'Resultados';
  @override
  String nothingFoundFor(String query) => 'Nada encontrado para "$query"';
  @override
  String get suggestionFromName => 'Sugerido a partir do nome';
  @override
  String get shops => 'Lojas';
  @override
  String get showLess => 'Ver menos';
  @override
  String allMoreShops(int count) => 'Mais $count lojas';
  @override
  String noMatchesFor(String query) => 'Sem resultados para “$query”';

  // ------------------------------------------------------------- settings --
  @override
  String get settingsTitle => 'Configurações';
  @override
  String get searchSettings => 'Buscar nas configurações';
  @override
  String get profile => 'Perfil';
  @override
  String get familyMembers => 'Membros da família';
  @override
  String get language => 'Idioma';
  @override
  String get darkMode => 'Modo escuro';
  @override
  String get welcomeTour => 'Tour de boas-vindas';
  @override
  String get repeat => 'Repetir';
  @override
  String get signOut => 'Sair';
  @override
  String noSettingFoundFor(String query) => 'Nenhuma configuração para “$query”';
  @override
  String get notConnected => 'Não conectado';
  @override
  String get displayName => 'Nome de exibição';
  @override
  String get avatarColour => 'Cor do avatar';
  @override
  String get removePhoto => 'Remover foto';
  @override
  String get removeSymbol => 'Remover símbolo';
  @override
  String get avatarUploadFailed => 'Não foi possível enviar a foto de perfil.';
  @override
  String get avatarRemoveFailed => 'Não foi possível remover a foto de perfil.';
  @override
  String get adminsManageFamily => 'Os administradores cuidam da família e de todas as conexões.';
  @override
  String get familyMembersDesc =>
      'Defina o papel de cada membro da família. Os administradores cuidam da '
      'família; as crianças veem uma versão simplificada.';
  @override
  String get familyMembersDescAdmin =>
      'Quem faz parte da sua família. Só os administradores podem convidar gente '
      'e mudar papéis.';
  @override
  String get nobodyInHouseholdYet =>
      'Ainda não tem ninguém na família.\nConvide alguém para dividir listas, '
      'To-dos e eventos.';
  @override
  String get inviteMember => 'Convidar alguém';
  @override
  String pendingWithRole(String role) => '$role · pendente';
  @override
  String get inviteFamilyMember => 'Convidar um membro da família';
  @override
  String get inviteValidity => 'O convite vale 14 dias. Quem aceitar sai da família anterior.';
  @override
  String get inviteSending => 'Enviando o convite…';
  @override
  String get inviteSentTitle => 'Convite enviado';
  @override
  String get inviteCreatedTitle => 'Convite criado';
  @override
  String inviteSentTo(String email) => 'Mandamos um e-mail para $email.';
  @override
  String inviteMailNotSent(String email) =>
      'Não foi possível entregar o e-mail para $email. Compartilhe o link abaixo.';
  @override
  String invitedAsRole(String role) => 'Convidado como $role';
  @override
  String inviteValidUntil(String date) => 'Vale até $date';
  @override
  String invitedPerson(String who) => '$who convidado';
  @override
  String get tapSendToInvite => 'Toque em enviar para entregar o convite.';
  @override
  String get youCaps => 'VOCÊ';
  @override
  String get removeMemberQuestion => 'Remover o membro?';
  @override
  String removeMemberBody(String name) =>
      '“$name” perde o acesso à sua família. O conteúdo compartilhado fica, o '
      'conteúdo privado é excluído.';
  @override
  String get languagePageDesc => 'Define o idioma do app. Menus, botões e datas mudam na hora.';
  @override
  String get setUpProfile => 'Configurar o perfil';
  @override
  String get languageGerman => 'Deutsch';
  @override
  String get languageEnglish => 'English';
  @override
  String get languagePortuguese => 'Português';
  @override
  String get languageSpanish => 'Español';
  @override
  String get languageGermanRegion => 'Alemanha';
  @override
  String get languageEnglishRegion => 'Reino Unido';
  @override
  String get languagePortugueseRegion => 'Brasil';
  @override
  String get languageSpanishRegion => 'Espanha';

  // Palavras-chave nos quatro idiomas, para a linha aparecer seja qual for a
  // palavra que vier primeiro à cabeça do usuário.
  @override
  String get searchTermsProfile =>
      'perfil conta nome avatar cor papel administrador profile account profil konto';
  @override
  String get searchTermsFamily =>
      'família membros pessoas convidar papel papéis criança crianças administrador '
      'family members familie mitglieder';
  @override
  String get searchTermsCalendar =>
      'agenda calendário eventos conexões conectar google outlook icloud iserv férias '
      'lixo escola calendar kalender';
  @override
  String get searchTermsApplePay =>
      'apple pay google wallet samsung pay gastos despesas dispositivos iphone android '
      'atalhos automação notificações acesso às notificações detecção ativar remover geräte';
  @override
  String get searchTermsLanguage =>
      'idioma língua português inglês alemão espanhol tradução language sprache';
  @override
  String get searchTermsDarkMode => 'modo escuro aparência claro escuro noite tema dunkelmodus dark mode';
  @override
  String get searchTermsTour => 'tour boas-vindas introdução repetir ajuda onboarding willkommenstour';
  @override
  String get searchTermsSignOut => 'sair logout conta trocar desconectar abmelden sign out';

  // ----------------------------------------------------------------- roles --
  @override
  String get roleAdmin => 'Administrador';
  @override
  String get roleMember => 'Membro';
  @override
  String get roleChild => 'Criança';

  // ----------------------------------------------------------- onboarding --
  @override
  String get onboardSetUpFamily => 'Vamos configurar a sua família';
  @override
  String get onboardSetUpFamilyBody =>
      'Dê um nome e uma foto para a sua família. Você pode mudar os dois depois, quando '
      'quiser.';
  @override
  String get onboardJoinExistingFamily => 'A sua família já usa o Aporah?';
  @override
  String get onboardJoinExistingFamilyBody =>
      'Então não crie uma nova aqui — peça a alguém da família para convidar você.';
  @override
  String get onboardInviteTitle => 'Convide a sua família';
  @override
  String get onboardInviteBody => 'Todo mundo da família pode ver e acrescentar eventos, caixas e listas.';
  @override
  String get adult => 'Adulto';
  @override
  String get child => 'Criança';
  @override
  String get onboardAddressTitle => 'Conecte o seu endereço';
  @override
  String get onboardAddressBody =>
      'A gente sugere calendários que combinam — a coleta de lixo e as férias '
      'escolares, por exemplo.';
  @override
  String get address => 'Endereço';
  @override
  String get wasteCalendar => 'Calendário da coleta de lixo';
  @override
  String get holidayCalendar => 'Calendário das férias escolares';
  @override
  String get onboardFindingCalendars => 'Buscando calendários para o seu endereço …';
  @override
  String get onboardFoundForYou => 'Encontradas para o seu endereço';
  @override
  String get onboardNothingForAddress =>
      'Não achamos nenhum calendário para este endereço. Você pode conectar mais '
      'depois nas Configurações.';
  @override
  String get onboardNotFoundHere => 'Não encontrado para este endereço';
  @override
  String get onboardRenameLater => 'Dá para renomear os calendários depois em Configurações → Calendário.';
  @override
  String get onboardConnectMoreHint => 'Adicionar Google, Outlook, iCloud ou IServ';
  @override
  String get onboardConnectingCalendars => 'Conectando os calendários …';
  @override
  String get calendarsConnectFailed => 'Não foi possível conectar os calendários agora.';
  @override
  String get onboardReady => 'Pronto!';
  @override
  String get onboardReadyBody =>
      'Sua família está configurada — dá para mudar tudo isso depois nas Configurações.';
  @override
  String get noInvitesSent => 'Nenhum convite enviado';
  @override
  String invitedCount(int count) => '$count convidados';

  // ----------------------------------------------------------------- auth --
  @override
  String get welcomeToAporah => 'Boas-vindas ao Aporah';
  @override
  String get welcomeBack => 'Que bom te ver de novo';
  @override
  String get signUpBlurb =>
      'Crie a sua conta. A família é criada automaticamente — você pode convidar '
      'todo mundo depois.';
  @override
  String get signInBlurb => 'Entre com o seu e-mail.';
  @override
  String get yourName => 'Seu nome';
  @override
  String get atLeast8Chars => 'Pelo menos 8 caracteres.';
  @override
  String get createAccount => 'Criar conta';
  @override
  String get signIn => 'Entrar';
  @override
  String get haveAccountAlready => 'Já tenho conta';
  @override
  String get newHereCreateAccount => 'É novo por aqui? Crie uma conta';
  @override
  String get forgotPassword => 'Esqueceu a senha?';
  @override
  String get almostThere => 'Falta pouco';
  @override
  String confirmMailSent(String email) =>
      'Mandamos um e-mail para $email. Clique no link e depois é só entrar.';
  @override
  String get toSignIn => 'Ir para o login';
  @override
  String get pleaseEnterName => 'Digite o seu nome.';
  @override
  String get noConnectionTryAgain => 'Sem conexão. Tente de novo.';
  @override
  String get pleaseEnterEmailFirst => 'Digite o seu e-mail primeiro.';
  @override
  String get resetMailSent => 'Mandamos um e-mail para você redefinir.';
  @override
  String get wrongCredentials => 'Esse e-mail ou essa senha não estão certos.';
  @override
  String get confirmEmailFirst => 'Confirme o seu e-mail primeiro.';
  @override
  String get accountExists => 'Já existe uma conta com este e-mail.';
  @override
  String get passwordTooShort => 'Essa senha é curta demais.';
  @override
  String get passwordLeaked => 'Esta senha aparece em vazamentos conhecidos. Escolha outra.';
  @override
  String get tooManyAttempts => 'Tentativas demais. Espere um pouco.';
  @override
  String get emailLooksInvalid => 'Esse e-mail não parece válido.';
  @override
  String get signInFailed => 'Não foi possível entrar. Tente de novo.';

  // --------------------------------------------------------------- family --
  @override
  String get noHouseholdForAccount => 'Não achamos nenhuma família para a sua conta.';
  @override
  String get householdLoadFailed => 'Não foi possível carregar a família.';
  @override
  String get enterValidEmail => 'Digite um e-mail válido.';
  @override
  String get inviteSendFailed => 'Não foi possível enviar o convite.';
  @override
  String get roleChangeFailed => 'Não foi possível mudar o papel.';
  @override
  String get memberRemoveFailed => 'Não foi possível remover o membro.';
  @override
  String get inviteRevokeFailed => 'Não foi possível revogar o convite.';

  // --------------------------------------------------- calendar ownership --
  @override
  String get assignCalendar => 'Atribuir';
  @override
  String assignCalendarBody(String calendar) =>
      'De quem é “$calendar”? O calendário passa a aparecer embaixo dessa pessoa no '
      'Calendário e no Board.';
  @override
  String get assignCalendarFamilyHint => 'É da família toda';
  @override
  String get assignCalendarNewPerson => 'Outra pessoa';
  @override
  String get assignCalendarNotVisibility =>
      'Isso não muda quem pode ver o calendário — a família toda continua vendo.';
  @override
  String get assignCalendarFailed => 'Essa atribuição não foi aceita.';
  @override
  String get family => 'Família';
  @override
  String get noAccountYet => 'Sem conta';

  @override
  String get familyName => 'Nome da família';
  @override
  String get familyNameHint => 'Como a sua família se chama no Aporah.';
  @override
  String get renameFamily => 'Renomear a família';
  @override
  String get renameFamilyBody => 'O nome aparece na aba da família no Calendário e no Board.';
  @override
  String get renamePerson => 'Renomear pessoa';
  @override
  String get renamePersonBody =>
      'O nome aparece na aba dela no Calendário e no Board, e em cada calendário atribuído a ela.';
  @override
  String get removePersonQuestion => 'Remover pessoa?';
  @override
  String removePersonBody(String name) =>
      '“$name” não tem conta e só aparece nos calendários atribuídos a ela. '
      'Esses calendários voltam a ser da família toda – nada é desconectado.';
  @override
  String get familyRenameFailed => 'Não foi possível mudar o nome.';

  // ------------------------------------------------------------------- Home
  @override
  String homeOverdue(int count) => '$count atrasadas';
  @override
  String homeOpenToday(int count) => 'faltam $count';
  @override
  String homeTrackersLeft(int count) => 'faltam $count rotinas';
  @override
  String homeNextUp(String time, String title) => '$time · $title';
  @override
  String get homeAllDone => 'Tudo pronto';
  @override
  String homeDayOffset(int days) => switch (days) {
    1 => 'Amanhã',
    -1 => 'Ontem',
    > 1 => 'Em $days dias',
    _ => 'Há ${-days} dias',
  };
  @override
  String get homeHintBackToToday => 'Toque para voltar a hoje';
  @override
  String get homeThinking => 'Um instante';
  @override
  String get homeHintThinking => 'Montando o seu dia';
  @override
  String get homeHintSetup => 'Configure o Aporah para a sua família';
  @override
  String get homeHintOverdue => 'To-dos fora do prazo';
  @override
  String get homeHintOpen => 'To-dos para hoje';
  @override
  String get homeHintTrackers => 'Ainda não marcadas hoje';
  @override
  String get homeHintNext => 'O próximo do seu calendário';
  @override
  String get homeHintDone => 'Não falta mais nada hoje';
  @override
  String get homeTrackerSection => 'Para hoje';
  @override
  String get homeTrackerEmpty => 'Nenhuma rotina ainda';
  @override
  String get homeTrackerEmptyBody => 'Esporte, leitura, vitaminas — o que vocês fazem sempre.';
  @override
  String get homeListsSection => 'Listas';
  @override
  String get homeShowAll => 'Ver tudo';
  @override
  String homeListOpenItems(int count) => '$count para comprar';

  // ------------------------------------------------------------ First steps
  @override
  String get firstStepsTitle => 'Primeiros passos';
  @override
  String firstStepsProgress(int done, int total) => '$done de $total';
  @override
  String get firstStepCalendar => 'Conectar um calendário';
  @override
  String get firstStepCalendarBody => 'Escola, trabalho e coleta de lixo num lugar só.';
  @override
  String get firstStepFamily => 'Convidar a família';
  @override
  String get firstStepFamilyBody => 'Para todo mundo ver a mesma coisa.';
  @override
  String get firstStepTodo => 'Primeiro To-do';
  @override
  String get firstStepTodoBody => 'Alguma coisa que precisa acontecer esta semana.';
  @override
  String get firstStepTracker => 'Criar uma rotina';
  @override
  String get firstStepTrackerBody => 'Um hábito que vocês mantêm juntos.';
  @override
  String get firstStepList => 'Primeira lista';
  @override
  String get firstStepListBody => 'O mercado é um bom lugar para começar.';

  // --------------------------------------------------------------- Ausgaben
  @override
  String get navMore => 'Mais';

  // O Brasil escreve `R$ 1.234,56`: vírgula decimal e ponto nos milhares, como
  // a Alemanha, mas **o símbolo vem antes do número** — ao contrário do euro.
  // Por isso [money] inverte a ordem em vez de herdar a alemã.
  @override
  String get decimalSeparator => ',';
  @override
  String get thousandsSeparator => '.';
  @override
  String get thousandsSuffix => 'mil';
  @override
  String get millionsSuffix => 'mi';
  @override
  String money(String amount, String symbol) => '$symbol $amount';
  @override
  String percent(int value) => '$value%';

  @override
  String get spendTitle => 'Gastos';
  @override
  String get spendAdminsOnly => 'Só os administradores podem ver os gastos.';
  @override
  String get spendEmpty => 'Nada registrado neste mês ainda.';
  @override
  String get spendEmptyEnrolled =>
      'Nada neste mês ainda. Seu próximo pagamento por Apple Pay cai aqui sozinho.';

  @override
  String get spendByCategory => 'Por categoria';
  @override
  String get spendTopMerchants => 'Por loja';
  @override
  String get spendByMember => 'Por pessoa';

  @override
  String get spendOtherCategories => 'Outras';
  @override
  String get spendAllPurchases => 'Todas as compras';
  @override
  String get spendFormerMember => 'Ex-membro';

  @override
  String spendCountShort(int count) => count == 1 ? '1 pagamento' : '$count pagamentos';

  @override
  String spendPaymentsWord(int count) => count == 1 ? 'pagamento' : 'pagamentos';

  @override
  String get spendChartTrend => 'Tendência';
  @override
  String get spendChartBars => 'Barras';
  @override
  String get spendChartRing => 'Anel';

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
  String get spendRangeThisMonth => 'Este mês';
  @override
  String get spendRangeLastSixMonths => 'Últimos 6 meses';
  @override
  String get spendRangeThisYear => 'Este ano';

  @override
  String get spendRangePick => 'Escolher um período';

  @override
  String spendAveragePerDay(String amount) => 'Média de $amount por dia';
  @override
  String spendAveragePerMonth(String amount) => 'Média de $amount por mês';

  @override
  String get spendMetricAll => 'Gastos';
  @override
  String get spendShowAll => 'Ver tudo';

  @override
  String spendShowAllCount(int count) => 'Ver os $count';

  @override
  String get spendTotal => 'Total';

  @override
  String get spendIslandThinking => 'Fazendo as contas';
  @override
  String get spendIslandThinkingHint => 'Carregando os pagamentos';

  @override
  String get spendIslandReviewHint => 'Falta a loja ou o valor';

  @override
  String get spendIslandNothing => 'Nada registrado';

  @override
  String spendIslandUp(int percent) => '$percent% a mais de gasto';
  @override
  String spendIslandDown(int percent) => '$percent% a menos de gasto';
  @override
  String get spendIslandVsPrevious => 'em relação ao período anterior';

  @override
  String spendIslandTop(String category) => '$category é a maior fatia';
  @override
  String spendIslandTopHint(int percent) => '$percent% dos gastos';

  @override
  String get spendAdd => 'Adicionar um gasto';
  @override
  String get spendEdit => 'Editar gasto';
  @override
  String get spendAmount => 'Valor';
  @override
  String get spendDate => 'Data';
  @override
  String get spendCategory => 'Categoria';
  @override
  String get spendLabel => 'Gasto';
  @override
  String get spendKindLabel => 'Tipo';
  @override
  String get spendPaidBy => 'Pago por';
  @override
  String get spendCard => 'Cartão';
  @override
  String get spendSourceLabel => 'Registro';
  @override
  String get spendSourceWallet => 'Apple Pay';
  @override
  String get spendSourceManual => 'Na mão';
  @override
  String get spendNote => 'Nota';
  @override
  String get spendCategoryAuto => 'Automática';
  @override
  String get spendMerchantPlaceholder => 'Onde? ex.: Pão de Açúcar';
  @override
  String get spendNotePlaceholder => 'Nota (opcional)';
  @override
  String get spendKindQuestion => 'Que tipo de gasto?';
  @override
  String get spendKindBudget => 'Do mês';
  @override
  String get spendKindExtra => 'Extra';
  @override
  String get spendNeedsMerchantAndAmount => 'Ainda faltam a loja e o valor.';
  @override
  String get spendSaved => 'Gasto salvo';
  @override
  String get spendUpdated => 'Gasto atualizado';
  @override
  String get spendDeleted => 'Gasto excluído';

  @override
  String spendReviewTitle(int count) => count == 1
      ? 'Um pagamento precisa de você um instante'
      : '$count pagamentos precisam de você um instante';
  @override
  String get spendReviewBody => 'A Apple não passou a loja ou o valor. Toque na linha e preencha.';
  @override
  String get spendReviewDetail => 'A Apple não passou a loja ou o valor. Toque no lápis acima e preencha.';

  @override
  String get spendLoadFailed => 'Não foi possível carregar os gastos.';
  @override
  String get spendSaveFailed => 'Não foi possível salvar o gasto.';
  @override
  String get spendDeleteFailed => 'Não foi possível excluir o gasto.';
  @override
  String get spendEnrolFailed => 'Não foi possível ativar este aparelho.';

  @override
  String get spendWalletTitle => 'Registrar o Apple Pay automaticamente';
  @override
  String get spendWalletIntro =>
      'Todo pagamento feito com este iPhone cai aqui sozinho. Sem link, sem código '
      '— você configura uma automação nos Atalhos, uma vez só.';
  @override
  String get spendWalletEnable => 'Ativar este iPhone';
  @override
  String get spendWalletUnsupported =>
      'O registro automático funciona em iPhone e Android. Em outros aparelhos, '
      'os gastos são adicionados na mão.';
  @override
  String get spendWalletEnabled => 'Aparelho ativado';
  @override
  String get spendWalletActive => 'Este iPhone está ativado';
  @override
  String get spendWalletInactive => 'Este iPhone ainda não está ativado';
  @override
  String get spendWalletStepsTitle => 'Falta um passo, no app Atalhos';
  @override
  String get spendWalletStep1 => 'Abra os Atalhos e toque em Automação, embaixo.';
  @override
  String get spendWalletStep2 => 'Toque em + e escolha Carteira.';
  @override
  String get spendWalletStep3 => 'Escolha seus cartões e marque Executar imediatamente.';
  @override
  String get spendWalletStep4 => 'Escolha a ação "Registrar gasto" — ela já está na lista.';
  @override
  String get spendWalletStep5 =>
      'Na ação, toque em Loja e Valor e insira a variável correspondente da automação — senão o atalho para e pergunta, e nada é registrado.';
  @override
  String get spendWalletOpenShortcuts => 'Abrir os Atalhos';
  @override
  String get settingsWalletCapture => 'Detecção da carteira';
  @override
  String get walletCapturePageDesc =>
      'Os pagamentos feitos com este celular entram em Gastos sozinhos. Ative este '
      'aparelho aqui — e tire qualquer aparelho do mesmo jeito.';
  @override
  String get spendWalletAndroidTitle => 'Registrar os pagamentos automaticamente';
  @override
  String get spendWalletAndroidIntro =>
      'Quando você paga com o celular, a carteira mostra o valor. O Aporah lê só '
      'essa notificação e arquiva o gasto — sem banco, sem senha, sem nada para digitar.';
  @override
  String get spendWalletAndroidEnable => 'Ativar este aparelho';
  @override
  String get spendWalletAndroidActive => 'Este aparelho está registrando pagamentos';
  @override
  String get spendWalletAndroidInactive => 'Este aparelho ainda não está ativado';
  @override
  String get spendWalletAndroidDeaf =>
      'Ativado, mas sem acesso às notificações — nenhum pagamento chega até nós.';
  @override
  String get spendWalletAndroidStepsTitle => 'Duas chavinhas e está funcionando';
  @override
  String get spendWalletAndroidStep1 => 'Ative este aparelho — é isso que deixa ele arquivar gastos.';
  @override
  String get spendWalletAndroidStep2 =>
      'Ligue o acesso às notificações para o Aporah nas configurações do sistema.';
  @override
  String get spendWalletAndroidStep3 => 'Pague com o celular — o gasto aparece aqui sozinho.';
  @override
  String get spendWalletAndroidNoDevicesHint => 'Use o botão abaixo para ativar este aparelho.';
  @override
  String get spendWalletGrantAccess => 'Permitir o acesso às notificações';
  @override
  String get spendWalletAccessGranted => 'Acesso liberado';
  @override
  String get spendWalletDisclosureTitle => 'O que o Aporah lê';
  @override
  String get spendWalletDisclosureBody =>
      'O Android não tem acesso às notificações app por app: liberar é liberar '
      'tudo. O Aporah só avalia as notificações de pagamento publicadas por apps '
      'de carteira — todas as outras são descartadas na hora, sem ler, sem guardar '
      'e sem contar. O que sai do aparelho é a loja, o valor, os últimos dígitos '
      'do cartão e o horário. Nunca o texto de uma notificação.';
  @override
  String get spendWalletAndroidSources => 'A Google Wallet, o Google Pay e a Samsung Wallet são detectados.';
  @override
  String get settingsApplePay => 'Apple Pay';
  @override
  String get applePayPageDesc =>
      'Os pagamentos por Apple Pay entram em Gastos sozinhos. Ative este iPhone '
      'aqui — e tire qualquer aparelho do mesmo jeito.';
  @override
  String get spendWalletNoDevices => 'Nenhum aparelho ativado ainda';
  @override
  String get spendWalletNoDevicesHint => 'Use o botão abaixo para ativar este iPhone.';
  @override
  String get spendWalletDevicesLabel => 'Aparelhos ativados';
  @override
  String get spendWalletDeviceUnused => 'Ainda não arquivou nada';
  @override
  String spendWalletDeviceLastUsed(String date) => 'Último em $date';
  @override
  String spendWalletDeviceCount(int count) => count == 0
      ? 'Nenhum'
      : count == 1
      ? '1 aparelho'
      : '$count aparelhos';
  @override
  String get spendWalletRevoke => 'Remover';
  @override
  String get spendWalletRenameTitle => 'Renomear aparelho';
  @override
  String get spendWalletRenameBody =>
      'É com este nome que o aparelho aparece na lista — para vocês distinguirem os celulares.';
  @override
  String get spendWalletDeviceNameHint => 'ex.: iPhone da Ana';
  @override
  String get spendWalletThisDevice => 'Este aparelho';

  @override
  String get spendCatGroceries => 'Mercado';
  @override
  String get spendCatDrugstore => 'Farmácia e higiene';
  @override
  String get spendCatFuel => 'Combustível';
  @override
  String get spendCatRestaurant => 'Restaurante';
  @override
  String get spendCatCafe => 'Padaria e café';
  @override
  String get spendCatShipping => 'Correios e entregas';
  @override
  String get spendCatClothing => 'Roupas';
  @override
  String get spendCatShopping => 'Compras';
  @override
  String get spendCatElectronics => 'Eletrônicos';
  @override
  String get spendCatTransport => 'Transporte';
  @override
  String get spendCatEntertainment => 'Lazer';
  @override
  String get spendCatHealth => 'Saúde';
  @override
  String get spendCatHome => 'Casa';
  @override
  String get spendCatOther => 'Outros';

  @override
  String get spendSearchPlaceholder => 'Loja, categoria, pessoa';
  @override
  String get spendSearchAction => 'Pesquisar gastos';
  @override
  String get spendViewCategories => 'Categorias';
  @override
  String get spendNoMatches => 'Nenhum gasto encontrado.';
  @override
  String get spendClearFilter => 'Remover filtro';
  @override
  String get spendBudget => 'Orçamento';
  @override
  String get spendBudgets => 'Orçamentos';
  @override
  String get spendBudgetAdd => 'Novo orçamento';
  @override
  String get spendBudgetEdit => 'Editar orçamento';
  @override
  String get spendBudgetPerMonth => 'Por mês';
  @override
  String get spendBudgetHint =>
      'Quanto esta categoria pode custar por mês? Os anéis mostram se vocês estão dentro do plano.';
  @override
  String spendBudgetLastMonth(String amount) => 'Mês passado: $amount';
  @override
  String get spendBudgetSaved => 'Orçamento salvo';
  @override
  String get spendBudgetDeleted => 'Orçamento excluído';
  @override
  String get spendBudgetSaveFailed => 'Não foi possível salvar o orçamento';
  @override
  String get spendBudgetNeedsAmount => 'Digite um valor';
  @override
  String spendBudgetOf(String spent, String limit) => '$spent de $limit';
  @override
  String spendBudgetLeft(String amount) => 'Restam $amount';
  @override
  String spendBudgetOver(String amount) => '$amount acima';
  @override
  String get spendBudgetOnTrack => 'Dentro do plano';
  @override
  String get spendBudgetAhead => 'Acima do ritmo';
  @override
  String get spendBudgetExceeded => 'Orçamento ultrapassado';
  @override
  String spendBudgetLine(String amount) => 'Orçamento $amount';

  // ------------------------------------------------------ Plus (paywall) --
  //
  // **Os preços em reais são provisórios.** Eles seguem a mesma faixa do euro
  // (R$ 24,90 ≈ € 4,99) e a mesma economia de 33% no anual, para o texto fazer
  // sentido. O preço de verdade vem da App Store e da Play Store quando o
  // faturamento entrar — veja a Fase 4 do docs/production-plan.md.
  @override
  String get plusName => 'Aporah Plus';
  @override
  String get plusPriceMonthly => 'R\$ 24,90 / mês';
  @override
  String get plusPriceYearly => 'R\$ 199,90 / ano';
  @override
  String get plusYearlySaving => 'Economize 33%';
  @override
  String get plusTrialNote => 'Grátis por 14 dias. Cancele quando quiser.';

  @override
  String plusForOnly(String price) => 'Por apenas $price.';
  @override
  String get plusUpgrade => 'Assinar o Plus';
  @override
  String get plusNotNow => 'Agora não';
  @override
  String get plusRestore => 'Restaurar a compra';
  @override
  String get plusActive => 'O Plus está ativo';
  @override
  String plusActiveUntil(String date) => 'O Plus vai até $date';
  @override
  String get plusDebugOverride => 'Modo de teste: o plano é simulado';

  @override
  String get paywallCalendarsTitle => 'Todos os seus calendários';
  @override
  String get paywallCalendarsBody => 'Com o Plus você conecta quantos calendários precisar!';
  @override
  String get paywallTrackersTitle => 'Mais rotinas';
  @override
  String get paywallTrackersBody =>
      'Três rotinas são de graça. Com o Plus dá para manter quantas o dia a dia '
      'pedir — escovar os dentes, pôr o lixo na rua, as palavras novas, cada uma '
      'com o seu histórico.';
  @override
  String get paywallBoxesTitle => 'Mais caixas';
  @override
  String get paywallBoxesBody =>
      'Uma caixa é de graça. Com o Plus cada porão, cada sótão e cada caixa de '
      'mudança tem a sua — com foto, para ninguém ter que adivinhar.';
  @override
  String get paywallMembersTitle => 'Mais gente';
  @override
  String get paywallMembersBody =>
      'Até quatro pessoas é de graça. Com o Plus a família é do tamanho que ela é '
      'de verdade — a avó, a babá, o terceiro filho.';
  @override
  String get paywallPhotosTitle => 'Fotos e arquivos';
  @override
  String get paywallPhotosBody =>
      'Com o Plus cada caixa, cada coisa dentro dela e cada item de uma lista ganha '
      'uma foto — o número de série da furadeira, o cabo certo entre três. Uma '
      'imagem diz o que nenhum símbolo diz.';
  @override
  String get paywallSpendTitle => 'Gastos';
  @override
  String get paywallSpendBody =>
      'Com o Plus, todo pagamento feito pelo celular aparece aqui sozinho — já separado por '
      'categoria, loja e pessoa. E um orçamento por categoria que mostra quanto ainda sobra.';

  @override
  String get debugPlanTitle => 'Plano (debug)';
  @override
  String debugPlanReal(String plan) => 'Real: $plan';
  @override
  String debugPlanSimulated(String plan) => '$plan (simulado)';

  // ------------------------------------------------------------- Vorhaben
  //
  // Só a moldura. A *resposta* é conteúdo no idioma em que o modelo foi
  // perguntado — veja `systemPrompt` em supabase/functions/list-plan/index.ts.
  @override
  String get plannerTitle => 'Plano';
  @override
  String get plannerPrompt =>
      'Diga numa frase o que você quer fazer. Você recebe o passo a passo e, '
      'principalmente, a lista para ir ao mercado.';
  @override
  String get plannerHint => 'O que você está planejando?';
  @override
  String get plannerExamplesLabel => 'POR EXEMPLO';
  // Não são traduções dos outros idiomas, de propósito: cada língua escolhe o
  // que uma família de lá realmente digitaria. Quatro grupos, nesta ordem, e o
  // ícone anda junto com as palavras.
  @override
  List<List<PlannerExample>> get plannerExampleGroups => const [
    [
      (text: 'Aniversário para 8 crianças', icon: AppIcons.cake),
      (text: 'Ceia de Ano-Novo para 10', icon: AppIcons.confetti),
      (text: 'Churrasco no quintal', icon: AppIcons.flame),
      (text: 'Ceia de Natal em família', icon: AppIcons.treeEvergreen),
      (text: 'Festa de casa nova', icon: AppIcons.house),
      (text: 'Mala para uma semana na praia', icon: AppIcons.suitcaseRolling),
    ],
    [
      (text: 'Compra do mês para 5 pessoas', icon: AppIcons.shoppingCart),
      (text: 'Encher a despensa', icon: AppIcons.package),
      (text: 'Faxina pesada no banheiro', icon: AppIcons.sprayBottle),
      (text: 'Renovar a caixa de remédios', icon: AppIcons.bandaids),
      (text: 'Troca de armário para o inverno', icon: AppIcons.tShirt),
      (text: 'Enxoval do bebê', icon: AppIcons.baby),
    ],
    [
      (text: 'Montar uma horta suspensa', icon: AppIcons.hammer),
      (text: 'Prateleiras para o quarto', icon: AppIcons.ruler),
      (text: 'Pintar a sala de novo', icon: AppIcons.paintRoller),
      (text: 'Plantar na varanda', icon: AppIcons.plant),
      (text: 'Deixar as bicicletas em ordem', icon: AppIcons.bicycle),
      (text: 'Uma casa na árvore', icon: AppIcons.tree),
    ],
    [
      (text: 'Feijoada para 8', icon: AppIcons.cookingPot),
      (text: 'Almoço de domingo para 6', icon: AppIcons.forkKnife),
      (text: 'Noite de pizza caseira', icon: AppIcons.pizza),
      (text: 'Bolo para a festa da escola', icon: AppIcons.cake),
      (text: 'Café da manhã para 6 convidados', icon: AppIcons.egg),
      (text: 'Sorvete caseiro', icon: AppIcons.iceCream),
    ],
  ];
  @override
  String get plannerGo => 'Sugerir uma lista';
  @override
  String get plannerWorking => 'Preparando …';
  @override
  String get plannerWhatToBuy => 'O QUE VOCÊ PRECISA';
  @override
  String plannerItemCount(int count) => count == 1 ? '1 item' : '$count itens';
  @override
  String get plannerHowTo => 'COMO FAZER';
  @override
  String get plannerShowMethod => 'Mostrar tudo';
  @override
  String get plannerRecipe => 'RECEITA';
  @override
  String get adLabel => 'Publicidade';
  @override
  String get plannerCreateList => 'Criar lista';
  @override
  String get plannerAgain => 'Perguntar de novo';
  @override
  String get plannerEditGoal => 'Dizer de outro jeito';
  @override
  String get plannerListCreated => 'Lista criada';
  @override
  String get plannerUnavailable => 'Agora não deu. Tente de novo daqui a pouco.';
  @override
  String get plannerUnusable =>
      'Não conseguimos montar uma lista com isso. Tente algo mais concreto: um '
      'prato, um projeto ou uma ocasião.';
  @override
  String get plannerNotConfigured => 'O plano não está configurado no momento.';
  @override
  String get plannerMonthlyLimit => 'Os planos deste mês acabaram. No dia 1º tem mais.';
  @override
  String get plannerDailyLimit => 'Por hoje já deu. Tente de novo amanhã.';
  @override
  String plannerLeft(int left, int limit) =>
      left == 1 ? 'Resta 1 de $limit planos este mês' : 'Restam $left de $limit planos este mês';
  @override
  String plannerNoneLeft(int day, String month) =>
      'Sem planos restantes: mais no dia $day de ${month.toLowerCase()}';
  @override
  String plannerMonthlyLimitUntil(int day, String month) =>
      'Os planos deste mês acabaram. No dia $day de ${month.toLowerCase()} tem mais.';
  @override
  String plannerDailyLimitAt(String time, {required bool tomorrow}) => tomorrow
      ? 'Por hoje já deu. Amanhã, a partir das $time, tem mais.'
      : 'Por enquanto já deu. A partir das $time tem mais.';
  @override
  String get plannerLimitsLifted => 'Limites desativados (teste)';
  @override
  String get debugPlannerLimitsTitle => 'Limites de planos (debug)';
  @override
  String get debugPlannerLimitsEnforced => 'Ativos';
  @override
  String get debugPlannerLimitsLifted => 'Desativados';
  @override
  String get plannerIslandLine => 'Diga o que você está planejando.';
  @override
  String get plannerIslandHint => 'A lista é por nossa conta';

  // -------------------------------------------------------- notifications --
  @override
  String get notificationsTitle => 'Notificações';
  @override
  String get notificationsPageDesc => 'O que o Aporah envia para o seu celular, e quando.';
  @override
  String get searchTermsNotifications =>
      'notificações lembretes alertas push resumo do dia lixo coleta orçamento gastos mitteilungen';
  @override
  String get notificationsAllowTitle => 'Permitir notificações';
  @override
  String get notificationsAllowBody => 'Sem permissão, nenhum lembrete chega.';
  @override
  String get notificationsDeniedBody => 'As notificações estão desativadas nos ajustes do sistema.';
  @override
  String get notificationsAllow => 'Permitir';
  @override
  String get notificationsOpenSettings => 'Ajustes';
  @override
  String get notificationsQuietTitle => 'Entregues em silêncio';
  @override
  String get notificationsQuietBody => 'As notificações chegam sem som na Central de Notificações.';
  @override
  String get notifyBriefTitle => 'Resumo do dia';
  @override
  String get notifyBriefSubtitle => 'O que tem para o dia';
  @override
  String get notifyAbfallTitle => 'Coleta de lixo';
  @override
  String get notifyAbfallSubtitle => 'Para a lixeira estar na rua a tempo';
  @override
  String get notifyAbfallWhen => 'Quando';
  @override
  String get abfallDayBefore => 'Na véspera';
  @override
  String get abfallSameDay => 'No dia da coleta';
  @override
  String get notifyTaskTimesTitle => 'To-dos com horário';
  @override
  String get notifyTaskTimesSubtitle => 'No horário que você definiu';
  @override
  String get notifyBudgetsTitle => 'Orçamentos';
  @override
  String get notifyBudgetsSubtitle => 'Quando um orçamento adianta o mês ou passa do limite';
  @override
  String get notifyTime => 'Horário';
  @override
  String get notificationsEventNote =>
      'O lembrete de um evento é definido no próprio evento. Vale só neste aparelho.';
  @override
  String get reminderNone => 'Nenhum';
  @override
  String get reminderAtStart => 'No início';
  @override
  String reminderHoursBefore(int hours) => hours == 1 ? '1 hora antes' : '$hours horas antes';
  @override
  String reminderDaysBefore(int days) => days == 1 ? '1 dia antes' : '$days dias antes';
  @override
  String reminderDayBefore(String time) => 'Na véspera às $time';
  @override
  String reminderMorningOf(String time) => 'No dia às $time';
  @override
  String get firstStepBinReminder => 'Ativar lembrete da coleta';
  @override
  String get firstStepBinReminderBody => 'Na véspera, antes de pôr o lixo para fora.';
  @override
  String get reminderAbfallShared => 'Vale para todas as coletas, como nas Configurações';
  @override
  String get reminderAbfallCustom => 'Outro horário…';
  @override
  String reminderCalendarAlready(String label) => 'Seu calendário já lembra: $label';
  @override
  String get reminderDenied => 'As notificações estão desativadas – permita nos ajustes.';
  @override
  String get noticeBriefTitle => 'Seu dia';
  @override
  String briefEvents(int count) => count == 1 ? '1 evento' : '$count eventos';
  @override
  String briefFirstAt(String time) => 'a partir das $time';
  @override
  String briefTasks(int count) => count == 1 ? '1 To-do pendente' : '$count To-dos pendentes';
  @override
  String noticeAbfallTitle(String bins) => 'Já colocou $bins para fora?';
  @override
  String get noticeAbfallBody => 'A coleta é amanhã cedo.';
  @override
  String get noticeAbfallBodyToday => 'A coleta é hoje.';
  @override
  String noticeTaskDue(String time) => 'Para as $time';
  @override
  String noticeBudgetAheadOne(String category) => '$category está adiantando o mês';
  @override
  String noticeBudgetAheadMany(int count) => '$count orçamentos estão adiantando o mês';
  @override
  String noticeBudgetOverOne(String category) => '$category passou do limite';
  @override
  String noticeBudgetOverMany(int count) => '$count orçamentos passaram do limite';
  @override
  String noticeBudgetAmount(String spent, String limit) => '$spent de $limit';
  @override
  String joinAnd(List<String> parts) =>
      parts.length < 2 ? parts.join() : '${parts.sublist(0, parts.length - 1).join(', ')} e ${parts.last}';
  @override
  String get rateApp => 'Avaliar o Aporah';
  @override
  String get searchTermsRate => 'avaliar avaliação estrelas app store bewerten rate';

  // -------------------------------------------------------------- app lock --
  @override
  String get appLockSubtitle => 'Pedido ao abrir o app';
  @override
  String get appLockLockedTitle => 'O Aporah está bloqueado';
  @override
  String get appLockUnlockReason => 'Desbloquear o Aporah';
  @override
  String get appLockEnableReason => 'Ativar o bloqueio do app';
  @override
  String get appLockDisableReason => 'Desativar o bloqueio do app';
  @override
  String unlockWith(String method) => 'Desbloquear com $method';
  @override
  String get biometricFingerprint => 'impressão digital';
  @override
  String get biometricFace => 'reconhecimento facial';
  @override
  String get biometricGeneric => 'biometria';
  @override
  String get biometricPasscode => 'código do aparelho';
  @override
  String get searchTermsAppLock => 'face id touch id optic id impressão digital digital rosto bloqueio bloquear desbloquear biometria segurança código privacidade';
  @override
  String get biometricFaceId => 'Face ID';
  @override
  String get biometricTouchId => 'Touch ID';
  @override
  String get biometricOpticId => 'Optic ID';
}
