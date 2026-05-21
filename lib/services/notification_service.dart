import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../data/db/app_db.dart';
import '../data/models/conta.dart';
import '../data/models/orcamento.dart';
import '../data/models/transaction.dart';
import 'finance_service.dart';

class NotificationService {
  NotificationService._();

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static bool _initialized = false;

  static const String budgetAlertPercentConfigKey =
      'orcamento_alerta_percentual';
  static const String goalAlert80Prefix = 'meta_alerta_80';
  static const String goalAlert100Prefix = 'meta_alerta_100';
  static const String expenseSalaryAlertPrefix = 'despesa_salario_alerta';

  static const int _billingNotificationBaseId = 10000;
  static const int _billingDueNotificationBaseId = 15000;
  static const int _salaryNotificationBaseId = 20000;
  static const int _budgetNotificationBaseId = 30000;
  static const int _goalNotificationBaseId = 40000;
  static const int _insightNotificationBaseId = 50000;
  static const int _recurringNotificationBaseId = 60000;
  static const String _budgetAlertConfigPrefix = 'orcamento_alertado';

  static const AndroidNotificationDetails _androidDetails =
      AndroidNotificationDetails(
    'Uffa_lembretes',
    'Lembretes financeiros',
    channelDescription: 'Avisos de vencimentos, renda base e orcamentos',
    importance: Importance.high,
    priority: Priority.high,
  );

  static const NotificationDetails _notificationDetails = NotificationDetails(
    android: _androidDetails,
    iOS: DarwinNotificationDetails(),
    macOS: DarwinNotificationDetails(),
  );

  static Future<void> init() async {
    if (_initialized) return;

    tz_data.initializeTimeZones();
    await _configureLocalTimezone();

    const initializationSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      ),
      macOS: DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      ),
    );

    await _plugin.initialize(initializationSettings);
    await _requestPermissions();
    _initialized = true;
  }

  static Future<void> syncFromDatabase() async {
    await init();

    final config = await AppDB.getConfig();
    final notificationsEnabled = config['notificacoes_ativas'] != 'false';

    await _cancelScheduledNotifications();
    if (!notificationsEnabled) return;

    final diasAviso = int.tryParse(config['dias_aviso_antecipado'] ?? '3') ?? 3;
    final thresholdPercent =
        int.tryParse(config[budgetAlertPercentConfigKey] ?? '80') ?? 80;
    final contas = await AppDB.getContas();

    await _scheduleBillingNotifications(contas, diasAviso);
    await _scheduleSalaryReminder(config);
    await _scheduleRecurringTransactionNotifications();
    await notifyBudgetThresholdsIfNeeded(
      thresholdPercent: thresholdPercent,
      config: config,
    );
    await notifyGoalMilestonesIfNeeded(config: config);
    await notifyExpenseVsSalaryIfNeeded(config: config);
  }

  static Future<void> notifyBudgetThresholdsIfNeeded({
    int? thresholdPercent,
    Map<String, String>? config,
  }) async {
    await init();

    final effectiveConfig = config ?? await AppDB.getConfig();
    if (effectiveConfig['notificacoes_ativas'] == 'false') {
      return;
    }

    final threshold = thresholdPercent ??
        int.tryParse(effectiveConfig[budgetAlertPercentConfigKey] ?? '80') ??
        80;

    final now = DateTime.now();
    final prefixAtual = '${_budgetAlertConfigPrefix}_${now.year}_${now.month}_';

    for (final key in effectiveConfig.keys) {
      if (key.startsWith(_budgetAlertConfigPrefix) &&
          !key.startsWith(prefixAtual)) {
        await AppDB.deleteConfig(key);
      }
    }

    final orcamentos = await FinanceServiceOrcamento.getOrcamentosComRollover(
      now.year,
      now.month,
    );

    for (final item in orcamentos) {
      if (item.limiteEfetivo <= 0) continue;
      if (item.percentualUsado < threshold / 100) continue;

      final categoriaId = Uri.encodeComponent(item.orcamento.categoria);
      final statusKey = item.estourado
          ? 'estourado'
          : item.percentualUsado >= 1
              ? 'concluido'
              : 'alerta';
      final dedupeKey =
          '${_budgetAlertConfigPrefix}_${now.year}_${now.month}_${categoriaId}_${statusKey}_$threshold';
      if (effectiveConfig[dedupeKey] == 'true') continue;

      final percentRounded = (item.percentualUsado * 100).round();
      final saldoDisponivel =
          (item.limiteEfetivo - item.gastoReal).clamp(0.0, double.infinity);
      final title = item.estourado
          ? 'Orçamento ultrapassado'
          : item.percentualUsado >= 1
              ? 'Orçamento concluído'
              : 'Orçamento em alerta';
      final body = item.estourado
          ? '${item.orcamento.categoria} passou do limite mensal em ${percentRounded - 100}%.'
          : item.percentualUsado >= 1
              ? '${item.orcamento.categoria} consumiu todo o limite deste mês.'
              : '${item.orcamento.categoria} ja consumiu $percentRounded% do limite mensal. Restam R\$ ${saldoDisponivel.toStringAsFixed(2)}.';

      await _plugin.show(
        _budgetNotificationBaseId + _stableId(dedupeKey),
        title,
        body,
        _notificationDetails,
      );

      await AppDB.setConfig(dedupeKey, 'true');
    }
  }

  static Future<void> _scheduleBillingNotifications(
    List<Conta> contas,
    int diasAviso,
  ) async {
    final now = DateTime.now();
    int avisoAntecipadoOffset = 0;
    int diaDoVencimentoOffset = 0;

    for (final conta in contas) {
      final diaVencimento = conta.diaVencimento;
      if (diaVencimento == null || diaVencimento <= 0) continue;

      for (int monthDelta = 0; monthDelta < 3; monthDelta++) {
        final competencia = DateTime(now.year, now.month + monthDelta, 1);
        final lastDay =
            DateTime(competencia.year, competencia.month + 1, 0).day;
        final diaReal = diaVencimento.clamp(1, lastDay);
        final disparo = DateTime(
          competencia.year,
          competencia.month,
          diaReal,
          9,
        ).subtract(Duration(days: diasAviso));

        if (!disparo.isAfter(now)) continue;

        final dueDate = DateTime(
          competencia.year,
          competencia.month,
          diaReal,
        );
        final descricao = _billingDescription(conta, dueDate, diasAviso);

        await _plugin.zonedSchedule(
          _billingNotificationBaseId + avisoAntecipadoOffset++,
          conta.tipo == 'credito'
              ? 'Fatura se aproximando'
              : 'Vencimento proximo',
          descricao,
          tz.TZDateTime.from(disparo, tz.local),
          _notificationDetails,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
        );

        final lembreteNoDia = DateTime(
          dueDate.year,
          dueDate.month,
          dueDate.day,
          8,
        );
        if (!lembreteNoDia.isAfter(now)) continue;

        await _plugin.zonedSchedule(
          _billingDueNotificationBaseId + diaDoVencimentoOffset++,
          conta.tipo == 'credito' ? 'Dia da fatura' : 'Dia do vencimento',
          _billingDueDescription(conta, dueDate),
          tz.TZDateTime.from(lembreteNoDia, tz.local),
          _notificationDetails,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
        );
      }
    }
  }

  static String _billingDescription(
      Conta conta, DateTime dueDate, int diasAviso) {
    final dataFmt =
        '${dueDate.day.toString().padLeft(2, '0')}/${dueDate.month.toString().padLeft(2, '0')}';
    if (conta.tipo == 'credito') {
      return 'A fatura de ${conta.nome} vence em $diasAviso dia(s), no dia $dataFmt.';
    }
    return '${conta.nome} vence em $diasAviso dia(s), no dia $dataFmt.';
  }

  static String _billingDueDescription(Conta conta, DateTime dueDate) {
    final dataFmt =
        '${dueDate.day.toString().padLeft(2, '0')}/${dueDate.month.toString().padLeft(2, '0')}';
    if (conta.tipo == 'credito') {
      return 'Hoje e o dia de vencimento da fatura ${conta.nome} ($dataFmt).';
    }
    return 'Hoje e o dia de vencimento de ${conta.nome} ($dataFmt).';
  }

  static Future<void> _scheduleSalaryReminder(
    Map<String, String> config,
  ) async {
    final receitaBase = double.tryParse(config['receita_base'] ?? '') ?? 0;
    if (receitaBase <= 0) return;

    final diaFixo = int.tryParse(config['receita_base_dia_fixo'] ?? '');
    final nthDiaUtil = int.tryParse(config['receita_base_dia_util'] ?? '') ?? 5;
    final now = DateTime.now();

    for (int monthDelta = 0; monthDelta < 3; monthDelta++) {
      final competencia = DateTime(now.year, now.month + monthDelta, 1);
      final baseDate = diaFixo != null
          ? _fixedDayOfMonth(competencia.year, competencia.month, diaFixo)
          : _nthWeekdayOfMonth(competencia.year, competencia.month, nthDiaUtil);
      final disparo = DateTime(
        baseDate.year,
        baseDate.month,
        baseDate.day,
        8,
      );

      if (!disparo.isAfter(now)) continue;

      await _plugin.zonedSchedule(
        _salaryNotificationBaseId + monthDelta,
        'Lembrete de renda',
        'Hoje e dia de conferir o lancamento da sua renda base.',
        tz.TZDateTime.from(disparo, tz.local),
        _notificationDetails,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    }
  }

  static Future<void> _scheduleRecurringTransactionNotifications() async {
    final now = DateTime.now();
    final transacoes = await AppDB.getTransacoes();
    final recorrentes = transacoes
        .where(
            (t) => t.recorrencia != Recorrencia.nenhuma && !t.isTransferencia)
        .toList();

    for (final t in recorrentes) {
      for (int i = 0; i < 3; i++) {
        final ocorrencia = _occurrenceDate(t, i, now);
        if (ocorrencia == null || !ocorrencia.isAfter(now)) continue;

        final titulo =
            t.valor < 0 ? 'Despesa recorrente' : 'Receita recorrente';
        final descricaoBase = t.descricao?.trim().isNotEmpty == true
            ? t.descricao!.trim()
            : t.categoria;

        await _plugin.zonedSchedule(
          _recurringNotificationBaseId +
              _stableId('${t.id}_${ocorrencia.toIso8601String()}'),
          titulo,
          '$descricaoBase em ${dt(ocorrencia)} no valor de R\$ ${t.valor.abs().toStringAsFixed(2)}.',
          tz.TZDateTime.from(
            DateTime(ocorrencia.year, ocorrencia.month, ocorrencia.day, 8),
            tz.local,
          ),
          _notificationDetails,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
        );
      }
    }
  }

  static DateTime _fixedDayOfMonth(int year, int month, int day) {
    final lastDay = DateTime(year, month + 1, 0).day;
    return DateTime(year, month, day.clamp(1, lastDay));
  }

  static DateTime _nthWeekdayOfMonth(int year, int month, int nth) {
    var count = 0;
    var cursor = DateTime(year, month, 1);
    while (true) {
      if (cursor.weekday >= DateTime.monday &&
          cursor.weekday <= DateTime.friday) {
        count++;
        if (count == nth) return cursor;
      }
      cursor = cursor.add(const Duration(days: 1));
    }
  }

  static Future<void> _cancelScheduledNotifications() async {
    final pendentes = await _plugin.pendingNotificationRequests();
    for (final pending in pendentes) {
      if (pending.id >= _billingNotificationBaseId &&
          pending.id < (_recurringNotificationBaseId + 9999)) {
        await _plugin.cancel(pending.id);
      }
    }
  }

  static DateTime? _occurrenceDate(
    Transacao t,
    int offset,
    DateTime now,
  ) {
    switch (t.recorrencia) {
      case Recorrencia.semanal:
        final baseDate = t.dataBaseRecorrencia;
        var base = DateTime(
          now.year,
          now.month,
          now.day,
          baseDate.hour,
          baseDate.minute,
        );
        while (base.weekday != baseDate.weekday) {
          base = base.add(const Duration(days: 1));
        }
        return base.add(Duration(days: 7 * offset));
      case Recorrencia.mensal:
        return _fixedDayOfMonth(
          now.year,
          now.month + offset,
          t.dataBaseRecorrencia.day,
        );
      case Recorrencia.anual:
        final baseDate = t.dataBaseRecorrencia;
        return DateTime(
          now.year + offset,
          baseDate.month,
          baseDate.day,
        );
      case Recorrencia.nenhuma:
        return null;
    }
  }

  static String dt(DateTime value) =>
      '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}';

  static Future<void> notifyGoalMilestonesIfNeeded({
    Map<String, String>? config,
  }) async {
    await init();

    final effectiveConfig = config ?? await AppDB.getConfig();
    if (effectiveConfig['notificacoes_ativas'] == 'false') return;

    final metas = await AppDB.getMetas();
    final metaIds = metas.map((meta) => meta.id).toSet();

    for (final key in effectiveConfig.keys) {
      if ((key.startsWith('${goalAlert80Prefix}_') ||
              key.startsWith('${goalAlert100Prefix}_')) &&
          !_matchesAnyMeta(key, metaIds)) {
        await AppDB.deleteConfig(key);
      }
    }

    for (final meta in metas) {
      await _notifyGoalThreshold(meta, 0.8, goalAlert80Prefix, 'Meta em 80%');
      await _notifyGoalThreshold(
          meta, 1.0, goalAlert100Prefix, 'Meta concluida');
    }
  }

  static Future<void> _notifyGoalThreshold(
    Meta meta,
    double threshold,
    String configPrefix,
    String title,
  ) async {
    if (meta.valorAlvo <= 0) return;

    final progresso = (meta.valorAtual / meta.valorAlvo).clamp(0.0, 1.0);
    final configKey = '${configPrefix}_${meta.id}';

    if (progresso < threshold) {
      await AppDB.deleteConfig(configKey);
      return;
    }

    final jaAlertado = await AppDB.getConfigValue(configKey) == 'true';
    if (jaAlertado) return;

    final percentual = (progresso * 100).round();
    final falta =
        (meta.valorAlvo - meta.valorAtual).clamp(0.0, double.infinity);

    await _plugin.show(
      _goalNotificationBaseId + _stableId(configKey),
      title,
      threshold >= 1.0
          ? 'Parabens! A meta ${meta.nome} chegou a 100% e foi atingida.'
          : 'A meta ${meta.nome} chegou a $percentual%. Faltam R\$ ${falta.toStringAsFixed(2)} para concluir.',
      _notificationDetails,
    );

    await AppDB.setConfig(configKey, 'true');
  }

  static Future<void> notifyExpenseVsSalaryIfNeeded({
    Map<String, String>? config,
  }) async {
    await init();

    final effectiveConfig = config ?? await AppDB.getConfig();
    if (effectiveConfig['notificacoes_ativas'] == 'false') return;

    final receitaBase =
        double.tryParse(effectiveConfig['receita_base'] ?? '') ?? 0;
    if (receitaBase <= 0) return;

    final now = DateTime.now();
    final summary = await FinanceService.getMonthlySummary(now.year, now.month);
    final configKey = '${expenseSalaryAlertPrefix}_${now.year}_${now.month}';

    for (final key in effectiveConfig.keys) {
      if (key.startsWith('${expenseSalaryAlertPrefix}_') && key != configKey) {
        await AppDB.deleteConfig(key);
      }
    }

    if (summary.despesas <= receitaBase) {
      await AppDB.deleteConfig(configKey);
      return;
    }

    if (effectiveConfig[configKey] == 'true') return;

    final excedente = summary.despesas - receitaBase;
    await _plugin.show(
      _insightNotificationBaseId + _stableId(configKey),
      'Despesa mensal acima da renda',
      'Suas despesas do mes ja passaram da renda base em R\$ ${excedente.toStringAsFixed(2)}. Vale revisar seus gastos.',
      _notificationDetails,
    );

    await AppDB.setConfig(configKey, 'true');
  }

  static bool _matchesAnyMeta(String key, Set<String> metaIds) {
    for (final metaId in metaIds) {
      if (key.endsWith('_$metaId')) return true;
    }
    return false;
  }

  static Future<void> _configureLocalTimezone() async {
    try {
      final timezoneInfo = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(timezoneInfo.identifier));
    } catch (_) {
      tz.setLocalLocation(tz.getLocation('UTC'));
    }
  }

  static Future<void> _requestPermissions() async {
    if (Platform.isAndroid) {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await android?.requestNotificationsPermission();
    }

    if (Platform.isIOS) {
      final ios = _plugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      await ios?.requestPermissions(alert: true, badge: true, sound: true);
    }

    if (Platform.isMacOS) {
      final macos = _plugin.resolvePlatformSpecificImplementation<
          MacOSFlutterLocalNotificationsPlugin>();
      await macos?.requestPermissions(alert: true, badge: true, sound: true);
    }
  }

  static int _stableId(String input) {
    var hash = 0;
    for (final codeUnit in input.codeUnits) {
      hash = ((hash * 31) + codeUnit) & 0x7fffffff;
    }
    return hash % 9999;
  }
}
