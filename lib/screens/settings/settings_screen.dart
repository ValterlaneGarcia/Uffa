import 'package:flutter/material.dart';
import '../../data/db/app_db.dart';
import '../../utils/app_theme.dart';
import '../../utils/app_state.dart';
import '../../widgets/common.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;

// ── Phase 2 additions ──────────────────────────────────────────
import 'dart:io';
import 'package:csv/csv.dart';
import 'package:share_plus/share_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:local_auth/local_auth.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

/// Thin wrapper around flutter_local_notifications (v17+).
/// Call [NotificationService.init] once from main(), then use the other
/// methods throughout the app.
///
/// Required in pubspec.yaml:
///   flutter_local_notifications: ^17.0.0
///   timezone: ^0.9.0
class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static Future<void> init() async {
    if (_initialized) return;
    tz_data.initializeTimeZones();
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwinSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const settings = InitializationSettings(
      android: androidSettings,
      iOS: darwinSettings,
      macOS: darwinSettings,
    );
    await _plugin.initialize(settings);
    _initialized = true;
  }

  static const _androidDetails = AndroidNotificationDetails(
    'vencimentos',
    'Vencimentos',
    channelDescription: 'Avisos de vencimento de contas e faturas',
    importance: Importance.high,
    priority: Priority.high,
  );
  static const _notifDetails = NotificationDetails(
    android: _androidDetails,
    iOS: DarwinNotificationDetails(),
  );

  /// Cancels all previously scheduled notifications and re-schedules them
  /// based on the current config (dias_aviso_antecipado) and upcoming bills.
  static Future<void> reagendarNotificacoes({
    required bool ativas,
    required int diasAviso,
    required List<Map<String, dynamic>> contas,
  }) async {
    await _plugin.cancelAll();
    if (!ativas) return;

    int notifId = 1;
    final now = DateTime.now();
    final localTz = tz.local;

    for (final conta in contas) {
      final diaVencimento = conta['dia_vencimento'] as int?;
      if (diaVencimento == null || diaVencimento <= 0) continue;

      final nomeContaStr = conta['nome'] as String? ?? 'Conta';

      // Schedule for the current and next month
      for (int delta = 0; delta <= 1; delta++) {
        final mesRaw = now.month + delta;
        final ano = now.year + (mesRaw > 12 ? 1 : 0);
        final mes = mesRaw > 12 ? mesRaw - 12 : mesRaw;

        final lastDay = DateTime(ano, mes + 1, 0).day;
        final diaReal = diaVencimento.clamp(1, lastDay);
        final dataAviso = DateTime(ano, mes, diaReal).subtract(Duration(days: diasAviso));

        if (dataAviso.isAfter(now)) {
          final tzDataAviso = tz.TZDateTime.from(dataAviso, localTz);
          final mesStr = mes < 10 ? '0$mes' : '$mes';
          await _plugin.zonedSchedule(
            notifId++,
            'Vencimento se aproximando',
            '$nomeContaStr vence em $diasAviso dia(s) — $diaReal/$mesStr/$ano',
            tzDataAviso,
            _notifDetails,
            androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
            uiLocalNotificationDateInterpretation:
                UILocalNotificationDateInterpretation.absoluteTime,
          );
        }
      }
    }
  }
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _nome = 'Usuário';
  bool _notificacoes = true;
  int _diasAviso = 3;
  bool _loading = true;
  List<Map<String, dynamic>> _contas = [];
  bool _biometricoAtivo = false;

  @override
  void initState() {
    super.initState();
    NotificationService.init();
    _load();
  }

  Future<void> _load() async {
    final config = await AppDB.getConfig();
    final contas = await AppDB.getContas();
    setState(() {
      _nome = config['nome_usuario'] ?? 'Usuário';
      _notificacoes = config['notificacoes_ativas'] != 'false';
      _diasAviso = int.tryParse(config['dias_aviso_antecipado'] ?? '3') ?? 3;
      _contas = contas.map((c) => c.toMap()).toList();
      _biometricoAtivo = config['biometrico_ativo'] == 'true';
      _loading = false;
    });
  }

  Future<void> _reagendarNotificacoes() async {
    await NotificationService.reagendarNotificacoes(
      ativas: _notificacoes,
      diasAviso: _diasAviso,
      contas: _contas,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.appBackground,
      appBar: AppBar(
        backgroundColor: context.appSurface,
        title: Text('Configurações',
            style: TextStyle(color: context.textPrimary)),
      ),
      body: _loading
          ? const LoadingState()
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 100),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Profile card
                  _buildProfileCard(),
                  const SizedBox(height: 24),

                  _SectionLabel('Notificações'),
                  const SizedBox(height: 10),
                  _buildNotificacoesSection(),
                  const SizedBox(height: 20),

                  _SectionLabel('Preferências'),
                  const SizedBox(height: 10),
                  _buildPreferenciasSection(),
                  const SizedBox(height: 20),

                  _SectionLabel('Segurança'),
                  const SizedBox(height: 10),
                  _buildSegurancaSection(),
                  const SizedBox(height: 20),

                  _SectionLabel('Dados'),
                  const SizedBox(height: 10),
                  _buildDadosSection(),
                  const SizedBox(height: 20),

                  _SectionLabel('Sobre'),
                  const SizedBox(height: 10),
                  _buildSobreSection(),
                ],
              ),
            ),
    );
  }

  Widget _buildProfileCard() {
    return GestureDetector(
      onTap: _editNome,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.blue, AppColors.green],
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.person, color: Colors.white, size: 30),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _nome,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w700),
                  ),
                  const Text('Toque para editar',
                      style: TextStyle(color: Colors.white70, fontSize: 12)),
                ],
              ),
            ),
            const Icon(Icons.edit_outlined, color: Colors.white70, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildNotificacoesSection() {
    return _SettingsCard(
      children: [
        _SwitchTile(
          icon: Icons.notifications_outlined,
          iconColor: AppColors.amber,
          label: 'Notificações',
          subtitle: 'Lembretes de pagamentos e recebimentos',
          value: _notificacoes,
          onChanged: (v) async {
            setState(() => _notificacoes = v);
            await AppDB.setConfig('notificacoes_ativas', v.toString());
            await _reagendarNotificacoes();
          },
        ),
        if (_notificacoes) ...[
          const Divider(height: 1),
          _SliderTile(
            icon: Icons.access_time_rounded,
            iconColor: AppColors.blue,
            label: 'Dias de antecedência',
            subtitle: 'Avisar $_diasAviso dia(s) antes',
            value: _diasAviso.toDouble(),
            min: 1,
            max: 7,
            onChanged: (v) async {
              setState(() => _diasAviso = v.round());
              await AppDB.setConfig('dias_aviso_antecipado', v.round().toString());
              await _reagendarNotificacoes();
            },
          ),
        ],
      ],
    );
  }

  Widget _buildPreferenciasSection() {
    return _SettingsCard(
      children: [
        _NavTile(
          icon: Icons.category_outlined,
          iconColor: AppColors.purple,
          label: 'Categorias',
          subtitle: 'Gerencie categorias personalizadas',
          onTap: _gerenciarCategorias,
        ),
        const Divider(height: 1),
        _NavTile(
          icon: Icons.attach_money_rounded,
          iconColor: AppColors.green,
          label: 'Renda base',
          subtitle: 'Configure sua renda mensal estimada',
          onTap: _editRendaBase,
        ),
        const Divider(height: 1),
        _NavTile(
          icon: Icons.palette_outlined,
          iconColor: AppColors.red,
          label: 'Aparência',
          subtitle: 'Tema e preferências visuais',
          onTap: _abrirAparencia,
        ),
      ],
    );
  }

  Widget _buildSegurancaSection() {
    return _SettingsCard(
      children: [
        _SwitchTile(
          icon: Icons.lock_outline,
          iconColor: AppColors.green,
          label: 'Senha e biometria',
          subtitle: 'Bloquear app com biometria/PIN',
          value: _biometricoAtivo,
          onChanged: _toggleBiometrico,
        ),
        const Divider(height: 1),
        _SwitchTile(
          icon: Icons.visibility_off_outlined,
          iconColor: AppColors.blue,
          label: 'Ocultar saldos',
          subtitle: 'Ocultar valores por padrão ao abrir',
          value: !AppState.instance.balanceVisible,
          onChanged: (_) => AppState.instance.toggleBalanceVisibility(),
        ),
      ],
    );
  }

  Widget _buildDadosSection() {
    return _SettingsCard(
      children: [
        _NavTile(
          icon: Icons.upload_outlined,
          iconColor: AppColors.blue,
          label: 'Exportar dados',
          subtitle: 'Exportar transações em CSV',
          onTap: _exportarCSV,
        ),
        const Divider(height: 1),
        _NavTile(
          icon: Icons.download_outlined,
          iconColor: AppColors.green,
          label: 'Importar dados',
          subtitle: 'Importar transações de planilha CSV',
          onTap: _importarCSV,
        ),
        const Divider(height: 1),
        _NavTile(
          icon: Icons.delete_outline,
          iconColor: AppColors.red,
          label: 'Limpar dados',
          subtitle: 'Remover todas as transações',
          onTap: _confirmarLimpeza,
        ),
      ],
    );
  }

  Widget _buildSobreSection() {
    return _SettingsCard(
      children: [
        _NavTile(
          icon: Icons.info_outline,
          iconColor: context.textSecondary,
          label: 'Versão do app',
          subtitle: 'v2.0.0 — Flutter / SQLite',
          onTap: null,
          showChevron: false,
        ),
        const Divider(height: 1),
        _NavTile(
          icon: Icons.star_outline_rounded,
          iconColor: AppColors.amber,
          label: 'Avaliar o app',
          subtitle: 'Ajude com uma avaliação na loja',
          onTap: () => _showSnack('Obrigado pelo interesse!'),
        ),
      ],
    );
  }

  Future<void> _gerenciarCategorias() async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: context.appSurface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => const _CategoriasSheet(),
    );
  }

  Future<void> _editNome() async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: context.appSurface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _EditNomeSheet(nomeAtual: _nome),
    );
    _load();
  }

  Future<void> _editRendaBase() async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: context.appSurface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => const _RendaBaseSheet(),
    );
    // Reload local state after the sheet closes
    _load();
  }

  Future<void> _confirmarLimpeza() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: context.appSurface,
        title: Text('Limpar dados',
            style: TextStyle(color: context.textPrimary)),
        content: Text(
            'Isso removerá TODAS as transações permanentemente. Esta ação não pode ser desfeita.',
            style: TextStyle(color: context.textSecondary)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('Cancelar',
                  style: TextStyle(color: context.textSecondary))),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Limpar tudo',
                  style: TextStyle(color: AppColors.red))),
        ],
      ),
    );
    if (ok == true) {
      _showSnack('Dados limpos com sucesso');
    }
  }

  // ── FALTA-01: Aparência (modo escuro + cor primária) ──────────
  Future<void> _abrirAparencia() async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: context.appSurface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => const _AparenciaSheet(),
    );
  }

  // ── FALTA-02: Exportar CSV ────────────────────────────────────
  Future<void> _exportarCSV() async {
    try {
      final transacoes = await AppDB.getTransacoes();
      final rows = <List<dynamic>>[
        ['id', 'descricao', 'valor', 'categoria', 'tipo', 'banco', 'parcelas', 'primeira_parcela', 'recorrencia'],
        ...transacoes.map((t) => [
              t.id,
              t.descricao ?? '',
              t.valor.toStringAsFixed(2),
              t.categoria,
              t.tipo.name,
              t.banco,
              t.parcelas,
              t.primeiraParcela.toIso8601String(),
              t.recorrencia.index,
            ]),
      ];
      final csv = const ListToCsvConverter().convert(rows);
      final dir = await getTemporaryDirectory();
      final now = DateTime.now();
      final filename =
          'financeapp_${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}.csv';
      final file = File('${dir.path}/$filename');
      await file.writeAsString(csv);
      await Share.shareXFiles([XFile(file.path)], text: 'Transações FinanceApp');
    } catch (e) {
      _showSnack('Erro ao exportar: $e');
    }
  }

  // ── FALTA-03: Importar CSV ────────────────────────────────────
  Future<void> _importarCSV() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
      );
      if (result == null || result.files.single.path == null) return;

      final content = await File(result.files.single.path!).readAsString();
      final rows = const CsvToListConverter().convert(content, eol: '\n');
      if (rows.isEmpty) {
        _showSnack('Arquivo vazio ou inválido.');
        return;
      }

      // Detect header row
      final startRow = (rows.first.first.toString().toLowerCase() == 'id') ? 1 : 0;
      int imported = 0;
      int skipped = 0;

      for (int i = startRow; i < rows.length; i++) {
        final row = rows[i];
        if (row.length < 8) { skipped++; continue; }
        try {
          final id = row[0].toString();
          final descricao = row[1].toString();
          final valor = double.parse(row[2].toString());
          final categoria = row[3].toString();
          final tipoStr = row[4].toString();
          final banco = row[5].toString();
          final parcelas = int.tryParse(row[6].toString()) ?? 1;
          final primeiraParcela = DateTime.parse(row[7].toString());
          final recorrenciaIdx = int.tryParse(row[8].toString()) ?? 0;

          // Map tipo string → index
          final tipoMap = {
            'entrada': 0, 'saida': 1, 'saldo': 2,
            'receita': 3, 'investimento': 4,
          };
          final tipoIdx = tipoMap[tipoStr] ?? (valor >= 0 ? 0 : 1);

          await (await AppDB.db).insert(
            'transacoes',
            {
              'id': id.isEmpty ? const Uuid().v4() : id,
              'descricao': descricao,
              'valor': valor,
              'categoria': categoria,
              'tipo': tipoIdx,
              'banco': banco.isEmpty ? 'geral' : banco,
              'parcelas': parcelas,
              'primeira_parcela': primeiraParcela.toIso8601String(),
              'recorrencia': recorrenciaIdx,
            },
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
          imported++;
        } catch (_) {
          skipped++;
        }
      }

      AppState.notify();
      _showSnack('$imported transações importadas${skipped > 0 ? ', $skipped ignoradas' : ''}.');
    } catch (e) {
      _showSnack('Erro ao importar: $e');
    }
  }

  // ── FALTA-05: Biometria ───────────────────────────────────────
  Future<void> _toggleBiometrico(bool value) async {
    if (value) {
      final auth = LocalAuthentication();
      final canCheck = await auth.canCheckBiometrics;
      final isAvailable = await auth.isDeviceSupported();
      if (!canCheck || !isAvailable) {
        _showSnack('Biometria não disponível neste dispositivo.');
        return;
      }
      final authenticated = await auth.authenticate(
        localizedReason: 'Confirme sua identidade para ativar o bloqueio',
        options: const AuthenticationOptions(biometricOnly: false),
      );
      if (!authenticated) return;
    }
    setState(() => _biometricoAtivo = value);
    await AppDB.setConfig('biometrico_ativo', value.toString());
    _showSnack(value ? 'Bloqueio biométrico ativado.' : 'Bloqueio biométrico desativado.');
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: context.appSurface,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }
}

// ─── Supporting widgets ────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: context.textSecondary,
            letterSpacing: 1.2),
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  final List<Widget> children;
  const _SettingsCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
          color: context.appSurface, borderRadius: BorderRadius.circular(16)),
      child: Column(children: children),
    );
  }
}

class _NavTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String subtitle;
  final VoidCallback? onTap;
  final bool showChevron;

  const _NavTile({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.subtitle,
    required this.onTap,
    this.showChevron = true,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: context.textPrimary)),
                  Text(subtitle,
                      style: TextStyle(
                          fontSize: 12, color: context.textSecondary)),
                ],
              ),
            ),
            if (showChevron)
              Icon(Icons.chevron_right,
                  size: 20, color: context.textSecondary),
          ],
        ),
      ),
    );
  }
}

class _SwitchTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SwitchTile({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
                color: iconColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: context.textPrimary)),
                Text(subtitle,
                    style: TextStyle(
                        fontSize: 12, color: context.textSecondary)),
              ],
            ),
          ),
          Switch(value: value, onChanged: onChanged, activeColor: AppColors.green),
        ],
      ),
    );
  }
}

class _SliderTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String subtitle;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  const _SliderTile({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.subtitle,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
                color: iconColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: context.textPrimary)),
                Text(subtitle,
                    style: TextStyle(
                        fontSize: 12, color: context.textSecondary)),
                SliderTheme(
                  data: SliderThemeData(
                    activeTrackColor: AppColors.blue,
                    inactiveTrackColor: context.appCardLight,
                    thumbColor: AppColors.blue,
                    overlayColor: AppColors.blue.withOpacity(0.1),
                    trackHeight: 4,
                  ),
                  child: Slider(
                    value: value,
                    min: min,
                    max: max,
                    divisions: (max - min).round(),
                    onChanged: onChanged,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Edit Nome Sheet ──────────────────────────────────────────

class _EditNomeSheet extends StatefulWidget {
  final String nomeAtual;
  const _EditNomeSheet({required this.nomeAtual});

  @override
  State<_EditNomeSheet> createState() => _EditNomeSheetState();
}

class _EditNomeSheetState extends State<_EditNomeSheet> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.nomeAtual);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Seu nome',
              style: TextStyle(
                  color: context.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),
          TextField(
            controller: _ctrl,
            autofocus: true,
            style: TextStyle(color: context.textPrimary),
            decoration: InputDecoration(
              fillColor: context.appCardLight,
              filled: true,
              hintText: 'Como quer ser chamado?',
              hintStyle: TextStyle(color: context.textSecondary),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            ),
          ),
          const SizedBox(height: 20),
          GradientButton(
            label: 'Salvar',
            onPressed: () async {
              final novo = _ctrl.text.trim();
              if (novo.isNotEmpty) {
                await AppDB.setConfig('nome_usuario', novo);
                AppState.notify();
              }
              if (mounted) Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }
}

// ─── Renda Base Sheet ──────────────────────────────────────────
// StatefulWidget próprio para evitar o crash _dependents.isEmpty
// e centralizar toda a lógica de configuração da renda base.

class _RendaBaseSheet extends StatefulWidget {
  const _RendaBaseSheet();

  @override
  State<_RendaBaseSheet> createState() => _RendaBaseSheetState();
}

class _RendaBaseSheetState extends State<_RendaBaseSheet> {
  final _ctrl = TextEditingController();

  // 'fixo' = dia do mês / 'util' = Nth dia útil
  String _modoData = 'fixo';
  int _diaFixo = 5;
  int _nthUtil = 5;

  bool _loading = true;
  bool _temRenda = false;

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _loadConfig() async {
    final config = await AppDB.getConfig();
    final valor    = config['receita_base'] ?? '';
    final diaFixo  = config['receita_base_dia_fixo'] ?? '';
    final diaUtil  = config['receita_base_dia_util'] ?? '';

    setState(() {
      _ctrl.text  = valor.isNotEmpty
          ? double.tryParse(valor)?.toStringAsFixed(2).replaceAll('.', ',') ?? ''
          : '';
      _temRenda   = valor.isNotEmpty && double.tryParse(valor) != null && double.parse(valor) > 0;
      _modoData   = diaUtil.isNotEmpty ? 'util' : 'fixo';
      _diaFixo    = int.tryParse(diaFixo) ?? 5;
      _nthUtil    = int.tryParse(diaUtil) ?? 5;
      _loading    = false;
    });
  }

  Future<void> _salvar() async {
    final raw   = _ctrl.text.trim().replaceAll(',', '.');
    final valor = double.tryParse(raw);
    if (valor == null || valor <= 0) return;

    await AppDB.salvarRendaBase(
      valor:     valor,
      diaFixo:   _modoData == 'fixo' ? _diaFixo : null,
      nthDiaUtil: _modoData == 'util' ? _nthUtil : null,
    );
    AppState.notify();
    if (mounted) Navigator.pop(context);
  }

  Future<void> _remover() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: context.appSurface,
        title: Text('Remover renda base',
            style: TextStyle(color: context.textPrimary)),
        content: Text(
            'Isso removerá a conta Salário e a transação recorrente.',
            style: TextStyle(color: context.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancelar', style: TextStyle(color: context.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remover', style: TextStyle(color: AppColors.red)),
          ),
        ],
      ),
    );
    if (ok == true) {
      await AppDB.removerRendaBase();
      AppState.notify();
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 28,
      ),
      child: _loading
          ? const SizedBox(height: 120, child: Center(child: CircularProgressIndicator()))
          : SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Handle bar
                  Center(
                    child: Container(
                      width: 40, height: 4,
                      decoration: BoxDecoration(
                        color: context.textSecondary,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Title
                  Text('Renda mensal base',
                      style: TextStyle(
                          color: context.textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  Text(
                    'Cria uma conta "Salário" e uma entrada recorrente mensal. '
                    'Você pode adicionar ou remover valores diretamente pela tela de transações.',
                    style: TextStyle(color: context.textSecondary, fontSize: 12),
                  ),
                  const SizedBox(height: 20),

                  // Valor
                  Text('Valor (R\$)',
                      style: TextStyle(color: context.textSecondary, fontSize: 13)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _ctrl,
                    autofocus: true,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    style: TextStyle(color: context.textPrimary, fontSize: 18),
                    decoration: InputDecoration(
                      prefixText: 'R\$ ',
                      prefixStyle: const TextStyle(color: AppColors.green, fontSize: 16),
                      fillColor: context.appCardLight,
                      filled: true,
                      hintText: '0,00',
                      hintStyle: TextStyle(color: context.textSecondary),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none),
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Modo de data
                  Text('Dia de recebimento',
                      style: TextStyle(color: context.textSecondary, fontSize: 13)),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      _ModeChip(
                        label: 'Dia fixo',
                        selected: _modoData == 'fixo',
                        onTap: () => setState(() => _modoData = 'fixo'),
                      ),
                      const SizedBox(width: 10),
                      _ModeChip(
                        label: 'Dia útil',
                        selected: _modoData == 'util',
                        onTap: () => setState(() => _modoData = 'util'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Seletor de dia
                  if (_modoData == 'fixo') ...[
                    Text('Qual dia do mês?',
                        style: TextStyle(color: context.textSecondary, fontSize: 12)),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 180,
                      child: GridView.builder(
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 7,
                          mainAxisSpacing: 6,
                          crossAxisSpacing: 6,
                          childAspectRatio: 1,
                        ),
                        itemCount: 31,
                        itemBuilder: (_, i) {
                          final d = i + 1;
                          final sel = _diaFixo == d;
                          return GestureDetector(
                            onTap: () => setState(() => _diaFixo = d),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 120),
                              decoration: BoxDecoration(
                                color: sel ? AppColors.green : context.appCardLight,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              alignment: Alignment.center,
                              child: Text('$d',
                                  style: TextStyle(
                                    color: sel ? Colors.white : context.textPrimary,
                                    fontSize: 12,
                                    fontWeight: sel ? FontWeight.w700 : FontWeight.normal,
                                  )),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Recebimento no dia $_diaFixo de cada mês.',
                      style: TextStyle(color: context.textSecondary, fontSize: 11),
                    ),
                  ] else ...[
                    Text('Qual dia útil do mês?',
                        style: TextStyle(color: context.textSecondary, fontSize: 12)),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      children: List.generate(10, (i) {
                        final n = i + 1;
                        final sel = _nthUtil == n;
                        return GestureDetector(
                          onTap: () => setState(() => _nthUtil = n),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 120),
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 10),
                            decoration: BoxDecoration(
                              color: sel
                                  ? AppColors.green.withOpacity(0.2)
                                  : context.appCardLight,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                  color: sel
                                      ? AppColors.green
                                      : Colors.transparent),
                            ),
                            child: Text(
                              '${n}º D.U.',
                              style: TextStyle(
                                color: sel ? AppColors.green : context.textSecondary,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        );
                      }),
                    ),
                    Text(
                      'Recebimento no ${_nthUtil}º dia útil (seg–sex) de cada mês.',
                      style: TextStyle(color: context.textSecondary, fontSize: 11),
                    ),
                  ],

                  const SizedBox(height: 24),

                  GradientButton(
                    label: 'Salvar renda',
                    onPressed: _salvar,
                  ),

                  if (_temRenda) ...[
                    const SizedBox(height: 12),
                    Center(
                      child: TextButton.icon(
                        onPressed: _remover,
                        icon: const Icon(Icons.delete_outline,
                            color: AppColors.red, size: 18),
                        label: const Text('Remover renda base',
                            style: TextStyle(color: AppColors.red, fontSize: 13)),
                      ),
                    ),
                  ],
                ],
              ),
            ),
    );
  }
}

class _ModeChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ModeChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppColors.blue.withOpacity(0.2) : context.appCardLight,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: selected ? AppColors.blue : Colors.transparent),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? AppColors.blue : context.textSecondary,
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}

// ─── Categorias Sheet ──────────────────────────────────────────

class _CategoriasSheet extends StatefulWidget {
  const _CategoriasSheet();

  @override
  State<_CategoriasSheet> createState() => _CategoriasSheetState();
}

class _CategoriasSheetState extends State<_CategoriasSheet> {
  List<Map<String, dynamic>> _categorias = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final rows = await AppDB.getCategorias();
    if (mounted) {
      setState(() {
        _categorias = rows;
        _loading = false;
      });
      CategoriaHelper.loadFromRows(rows);
    }
  }

  Future<void> _abrirForm({Map<String, dynamic>? cat}) async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: context.appSurface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _CategoriaFormSheet(categoriaExistente: cat),
    );
    await _load();
    AppState.notify();
  }

  Future<void> _deletar(Map<String, dynamic> cat) async {
    final isPadrao = (cat['padrao'] as int) == 1;
    if (isPadrao) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('Categorias padrão não podem ser removidas'),
          backgroundColor: context.appSurface,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ));
      }
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: context.appSurface,
        title: Text('Remover "${cat['nome']}"',
            style: TextStyle(color: context.textPrimary)),
        content: Text('Esta categoria será removida. Transações existentes não serão afetadas.',
            style: TextStyle(color: context.textSecondary)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('Cancelar', style: TextStyle(color: context.textSecondary))),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Remover', style: TextStyle(color: AppColors.red))),
        ],
      ),
    );
    if (ok == true) {
      await AppDB.deleteCategoria(cat['id'] as String);
      await _load();
      AppState.notify();
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      builder: (_, scrollCtrl) => Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 16, 0),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 4),
                      Text('Categorias',
                          style: TextStyle(
                              color: context.textPrimary,
                              fontSize: 18,
                              fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text('Toque para editar • Segure para reordenar',
                          style: TextStyle(color: context.textSecondary, fontSize: 12)),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => _abrirForm(),
                  icon: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.purple.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.add, color: AppColors.purple, size: 20),
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 20, color: context.appDivider),

          // Body
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _categorias.isEmpty
                    ? Center(
                        child: Text('Nenhuma categoria',
                            style: TextStyle(color: context.textSecondary)))
                    : ReorderableListView.builder(
                        scrollController: scrollCtrl,
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 80),
                        onReorder: (oldIdx, newIdx) async {
                          if (newIdx > oldIdx) newIdx--;
                          final list = [..._categorias];
                          final item = list.removeAt(oldIdx);
                          list.insert(newIdx, item);
                          setState(() => _categorias = list);
                          for (int i = 0; i < list.length; i++) {
                            await AppDB.updateCategoriaOrdem(
                                list[i]['id'] as String, i);
                          }
                        },
                        itemCount: _categorias.length,
                        itemBuilder: (_, i) {
                          final cat = _categorias[i];
                          final isPadrao = (cat['padrao'] as int) == 1;
                          final corHex = cat['cor'] as String? ?? '6B7280';
                          final color = Color(int.parse('FF$corHex', radix: 16));
                          final iconeKey = cat['icone'] as String? ?? 'category';
                          final icon = CategoriaHelper.iconFromName(iconeKey);
                          final tipo = cat['tipo'] as String? ?? 'ambos';

                          return Dismissible(
                            key: ValueKey(cat['id']),
                            direction: isPadrao
                                ? DismissDirection.none
                                : DismissDirection.endToStart,
                            background: Container(
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.only(right: 20),
                              decoration: BoxDecoration(
                                color: AppColors.red.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: const Icon(Icons.delete_outline,
                                  color: AppColors.red),
                            ),
                            confirmDismiss: (_) async {
                              await _deletar(cat);
                              return false; // _load handles state
                            },
                            child: InkWell(
                              onTap: () => _abrirForm(cat: cat),
                              borderRadius: BorderRadius.circular(14),
                              child: Container(
                                margin: const EdgeInsets.symmetric(vertical: 4),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 12),
                                decoration: BoxDecoration(
                                  color: context.appCardLight,
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 40,
                                      height: 40,
                                      decoration: BoxDecoration(
                                        color: color.withOpacity(0.15),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Icon(icon, color: color, size: 20),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(cat['nome'] as String,
                                              style: TextStyle(
                                                  color: context.textPrimary,
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.w600)),
                                          Text(
                                            tipo == 'receita'
                                                ? 'Receita'
                                                : tipo == 'despesa'
                                                    ? 'Despesa'
                                                    : 'Receita & Despesa',
                                            style: TextStyle(
                                                color: context.textSecondary,
                                                fontSize: 12),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (isPadrao)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color:
                                              context.textSecondary.withOpacity(0.1),
                                          borderRadius:
                                              BorderRadius.circular(20),
                                        ),
                                        child: Text('Padrão',
                                            style: TextStyle(
                                                color: context.textSecondary,
                                                fontSize: 10)),
                                      )
                                    else
                                      Icon(Icons.drag_handle,
                                          color: context.textSecondary, size: 20),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

// ─── Categoria Form Sheet ──────────────────────────────────────

class _CategoriaFormSheet extends StatefulWidget {
  final Map<String, dynamic>? categoriaExistente;
  const _CategoriaFormSheet({this.categoriaExistente});

  @override
  State<_CategoriaFormSheet> createState() => _CategoriaFormSheetState();
}

class _CategoriaFormSheetState extends State<_CategoriaFormSheet> {
  late final TextEditingController _nomeCtrl;
  late String _icone;
  late String _cor;
  late String _tipo;
  bool get _isEdit => widget.categoriaExistente != null;
  bool get _isPadrao =>
      _isEdit && (widget.categoriaExistente!['padrao'] as int) == 1;

  static const _cores = [
    'F59E0B', '3B82F6', '8B5CF6', '06B6D4', 'EC4899',
    'EF4444', '6366F1', '22C55E', '10B981', 'F97316',
    'A855F7', '14B8A6', 'E11D48', '6B7280',
  ];

  @override
  void initState() {
    super.initState();
    final cat = widget.categoriaExistente;
    _nomeCtrl = TextEditingController(text: cat?['nome'] as String? ?? '');
    _icone = cat?['icone'] as String? ?? 'category';
    _cor   = cat?['cor']   as String? ?? '6B7280';
    _tipo  = cat?['tipo']  as String? ?? 'ambos';
  }

  @override
  void dispose() {
    _nomeCtrl.dispose();
    super.dispose();
  }

  Future<void> _salvar() async {
    final nome = _nomeCtrl.text.trim();
    if (nome.isEmpty) return;
    final id = _isEdit
        ? widget.categoriaExistente!['id'] as String
        : 'cat_custom_${const Uuid().v4()}';
    final ordem = _isEdit
        ? (widget.categoriaExistente!['ordem'] as int? ?? 99)
        : 99;
    await AppDB.upsertCategoria({
      'id': id,
      'nome': nome,
      'icone': _icone,
      'cor': _cor,
      'tipo': _tipo,
      'ordem': ordem,
      'padrao': _isPadrao ? 1 : 0,
    });
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final selectedColor = Color(int.parse('FF$_cor', radix: 16));
    final selectedIcon = CategoriaHelper.iconFromName(_icone);

    return Padding(
      padding: EdgeInsets.only(
        left: 20, right: 20, top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: context.textSecondary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),

            Text(_isEdit ? 'Editar categoria' : 'Nova categoria',
                style: TextStyle(
                    color: context.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 20),

            // Preview chip
            Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                decoration: BoxDecoration(
                  color: selectedColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: selectedColor.withOpacity(0.5)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(selectedIcon, color: selectedColor, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      _nomeCtrl.text.isEmpty ? 'Prévia' : _nomeCtrl.text,
                      style: TextStyle(
                          color: selectedColor,
                          fontWeight: FontWeight.w600,
                          fontSize: 14),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Nome
            Text('Nome', style: TextStyle(color: context.textSecondary, fontSize: 13)),
            const SizedBox(height: 6),
            TextField(
              controller: _nomeCtrl,
              enabled: !_isPadrao,
              autofocus: !_isEdit,
              onChanged: (_) => setState(() {}),
              style: TextStyle(color: context.textPrimary),
              decoration: InputDecoration(
                fillColor: context.appCardLight,
                filled: true,
                hintText: 'Ex.: Pets, Academia…',
                hintStyle: TextStyle(color: context.textSecondary),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              ),
            ),
            const SizedBox(height: 20),

            // Tipo
            Text('Tipo', style: TextStyle(color: context.textSecondary, fontSize: 13)),
            const SizedBox(height: 8),
            Row(
              children: [
                for (final (label, value) in [
                  ('Ambos', 'ambos'),
                  ('Despesa', 'despesa'),
                  ('Receita', 'receita'),
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: GestureDetector(
                      onTap: _isPadrao ? null : () => setState(() => _tipo = value),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 130),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: _tipo == value
                              ? AppColors.blue.withOpacity(0.2)
                              : context.appCardLight,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color: _tipo == value
                                  ? AppColors.blue
                                  : Colors.transparent),
                        ),
                        child: Text(label,
                            style: TextStyle(
                                color: _tipo == value
                                    ? AppColors.blue
                                    : context.textSecondary,
                                fontSize: 13,
                                fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 20),

            // Cor
            Text('Cor', style: TextStyle(color: context.textSecondary, fontSize: 13)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: _cores.map((hex) {
                final c = Color(int.parse('FF$hex', radix: 16));
                final sel = _cor == hex;
                return GestureDetector(
                  onTap: () => setState(() => _cor = hex),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 130),
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: c,
                      shape: BoxShape.circle,
                      border: sel
                          ? Border.all(color: Colors.white, width: 2.5)
                          : null,
                      boxShadow: sel
                          ? [BoxShadow(color: c.withOpacity(0.5), blurRadius: 6)]
                          : null,
                    ),
                    child: sel
                        ? const Icon(Icons.check, color: Colors.white, size: 16)
                        : null,
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),

            // Ícone
            Text('Ícone', style: TextStyle(color: context.textSecondary, fontSize: 13)),
            const SizedBox(height: 8),
            SizedBox(
              height: 120,
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 7,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 1,
                ),
                itemCount: CategoriaHelper.availableIcons.length,
                itemBuilder: (_, i) {
                  final (name, iconData) = CategoriaHelper.availableIcons[i];
                  final sel = _icone == name;
                  return GestureDetector(
                    onTap: () => setState(() => _icone = name),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 120),
                      decoration: BoxDecoration(
                        color: sel
                            ? selectedColor.withOpacity(0.2)
                            : context.appCardLight,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: sel ? selectedColor : Colors.transparent),
                      ),
                      child: Icon(iconData,
                          color: sel ? selectedColor : context.textSecondary,
                          size: 20),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 24),

            GradientButton(
              label: _isEdit ? 'Salvar alterações' : 'Criar categoria',
              onPressed: _salvar,
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Aparência Sheet (FALTA-01 + FALTA-04) ─────────────────────────────────
// Tela de personalização completa: presets de tema nomeados (cor + modo escuro
// embutido), ajuste manual de modo e opção de reset ao padrão de fábrica.

class _AparenciaSheet extends StatefulWidget {
  const _AparenciaSheet();

  @override
  State<_AparenciaSheet> createState() => _AparenciaSheetState();
}

class _AparenciaSheetState extends State<_AparenciaSheet> {
  late String _selectedHex;
  late ThemeMode _themeMode;

  @override
  void initState() {
    super.initState();
    _selectedHex = AppState.instance.primaryColorHex;
    _themeMode = AppState.instance.themeMode;
    // Ouve mudancas globais para refletir no sheet em tempo real
    AppState.instance.addListener(_onStateChange);
  }

  @override
  void dispose() {
    AppState.instance.removeListener(_onStateChange);
    super.dispose();
  }

  void _onStateChange() {
    if (mounted) {
      setState(() {
        _selectedHex = AppState.instance.primaryColorHex;
        _themeMode = AppState.instance.themeMode;
      });
    }
  }

  bool get _isDark => _themeMode == ThemeMode.dark;
  Color get _primary => Color(int.parse('FF$_selectedHex', radix: 16));

  // Cores adaptadas ao modo atual
  Color get _bg => _isDark ? AppColors.backgroundDark : AppColors.background;
  Color get _surface => _isDark ? AppColors.surfaceDark : AppColors.surface;
  Color get _card => _isDark ? AppColors.cardLightDark : AppColors.cardLight;
  Color get _textPrimary =>
      _isDark ? AppColors.textPrimaryDark : AppColors.textPrimary;
  Color get _textSecondary =>
      _isDark ? AppColors.textSecondaryDark : AppColors.textSecondary;
  Color get _divider =>
      _isDark ? AppColors.dividerDark : AppColors.divider;

  AppThemePreset? get _activePreset {
    for (final p in AppThemePreset.all) {
      if (p.hex == _selectedHex && (p.mode == ThemeMode.dark) == _isDark) {
        return p;
      }
    }
    return null;
  }

  Future<void> _applyPreset(AppThemePreset preset) async {
    setState(() {
      _selectedHex = preset.hex;
      _themeMode = preset.mode;
    });
    await AppState.instance.applyPreset(preset);
  }

  Future<void> _toggleDark(bool v) async {
    final newMode = v ? ThemeMode.dark : ThemeMode.light;
    setState(() => _themeMode = newMode);
    await AppState.instance.setThemeMode(newMode);
  }

  Future<void> _reset() async {
    await AppState.instance.resetToDefault();
    // _onStateChange sera chamado automaticamente via listener
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOut,
      color: _bg,
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 8,
          bottom: MediaQuery.of(context).viewInsets.bottom + 32,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: _textSecondary.withOpacity(0.35),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Titulo + reset
              Row(
                children: [
                  Text(
                    'Aparência',
                    style: TextStyle(
                      color: _textPrimary,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: _reset,
                    icon: Icon(Icons.restart_alt_rounded,
                        size: 16, color: _textSecondary),
                    label: Text(
                      'Padrão',
                      style: TextStyle(
                        fontSize: 13,
                        color: _textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: TextButton.styleFrom(
                      backgroundColor: _card,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Preview em tempo real do tema selecionado
              _ThemePreviewCard(
                primary: _primary,
                isDark: _isDark,
                presetName: _activePreset?.name ?? 'Personalizado',
              ),
              const SizedBox(height: 24),

              // Secao: Presets
              _AparenciaSectionLabel(label: 'TEMAS', color: _textSecondary),
              const SizedBox(height: 12),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 0.78,
                ),
                itemCount: AppThemePreset.all.length,
                itemBuilder: (_, i) {
                  final preset = AppThemePreset.all[i];
                  final isActive = _activePreset == preset;
                  return _PresetTile(
                    preset: preset,
                    isActive: isActive,
                    onTap: () => _applyPreset(preset),
                  );
                },
              ),
              const SizedBox(height: 24),

              // Secao: Ajuste manual do modo
              _AparenciaSectionLabel(label: 'MODO', color: _textSecondary),
              const SizedBox(height: 12),
              _ModeToggleRow(
                isDark: _isDark,
                primary: _primary,
                surface: _surface,
                card: _card,
                textPrimary: _textPrimary,
                textSecondary: _textSecondary,
                divider: _divider,
                onChanged: _toggleDark,
              ),
              const SizedBox(height: 28),

              // Botao fechar
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text(
                    'Concluído',
                    style: TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Preview card ──────────────────────────────────────────────────────────────

class _ThemePreviewCard extends StatelessWidget {
  final Color primary;
  final bool isDark;
  final String presetName;

  const _ThemePreviewCard({
    required this.primary,
    required this.isDark,
    required this.presetName,
  });

  @override
  Widget build(BuildContext context) {
    final bg = isDark ? AppColors.surfaceDark : AppColors.cardLight;
    final surface = isDark ? AppColors.cardLightDark : AppColors.surface;
    final textP = isDark ? AppColors.textPrimaryDark : AppColors.textPrimary;
    final textS = isDark ? AppColors.textSecondaryDark : AppColors.textSecondary;
    final divider = isDark ? AppColors.dividerDark : AppColors.divider;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: primary.withOpacity(0.35), width: 1.5),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: primary,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.account_balance_wallet_rounded,
                    color: Colors.white, size: 18),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('FinanceApp',
                      style: TextStyle(
                          color: textP,
                          fontSize: 13,
                          fontWeight: FontWeight.w700)),
                  Text(presetName,
                      style: TextStyle(color: primary, fontSize: 11, fontWeight: FontWeight.w600)),
                ],
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: primary.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  isDark ? 'Escuro' : 'Claro',
                  style: TextStyle(
                      color: primary, fontSize: 10, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(height: 1, color: divider),
          const SizedBox(height: 14),
          // Mini transacoes simuladas
          _PreviewRow(label: 'Salário', value: 'R\$ 5.000', isPositive: true,
              primary: primary, surface: surface, textP: textP, textS: textS),
          const SizedBox(height: 8),
          _PreviewRow(label: 'Mercado', value: '- R\$ 320', isPositive: false,
              primary: primary, surface: surface, textP: textP, textS: textS),
          const SizedBox(height: 14),
          // Mini barra de orcamento
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Orçamento mensal',
                      style: TextStyle(color: textS, fontSize: 10)),
                  Text('64%',
                      style: TextStyle(
                          color: primary,
                          fontSize: 10,
                          fontWeight: FontWeight.w700)),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: 0.64,
                  minHeight: 6,
                  backgroundColor: primary.withOpacity(0.15),
                  valueColor: AlwaysStoppedAnimation(primary),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PreviewRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isPositive;
  final Color primary;
  final Color surface;
  final Color textP;
  final Color textS;

  const _PreviewRow({
    required this.label,
    required this.value,
    required this.isPositive,
    required this.primary,
    required this.surface,
    required this.textP,
    required this.textS,
  });

  @override
  Widget build(BuildContext context) {
    final valueColor = isPositive ? primary : AppColors.red;
    return Row(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: valueColor.withOpacity(0.12),
            borderRadius: BorderRadius.circular(7),
          ),
          child: Icon(
            isPositive ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
            size: 14,
            color: valueColor,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(label,
              style: TextStyle(color: textP, fontSize: 11, fontWeight: FontWeight.w500)),
        ),
        Text(value,
            style: TextStyle(
                color: valueColor, fontSize: 11, fontWeight: FontWeight.w700)),
      ],
    );
  }
}

// ── Preset tile ───────────────────────────────────────────────────────────────

class _PresetTile extends StatelessWidget {
  final AppThemePreset preset;
  final bool isActive;
  final VoidCallback onTap;

  const _PresetTile({
    required this.preset,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = preset.color;
    final darkMode = preset.mode == ThemeMode.dark;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isActive ? color : Colors.transparent,
            width: 2,
          ),
          boxShadow: isActive
              ? [BoxShadow(color: color.withOpacity(0.35), blurRadius: 10)]
              : null,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Stack(
            children: [
              // Fundo simulado do tema
              Container(
                color: darkMode
                    ? const Color(0xFF1C1F2A)
                    : const Color(0xFFF5F6FA),
              ),
              // Faixa de cor primaria no topo
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: 36,
                child: Container(color: color),
              ),
              // Icone centrado na faixa
              Positioned(
                top: 8,
                left: 0,
                right: 0,
                child: Icon(preset.icon,
                    color: Colors.white.withOpacity(0.92), size: 18),
              ),
              // Nome abaixo da faixa
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(
                    children: [
                      Text(
                        preset.name,
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: isActive
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: darkMode
                              ? AppColors.textPrimaryDark
                              : AppColors.textPrimary,
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (darkMode)
                        Icon(Icons.dark_mode_rounded,
                            size: 9,
                            color: AppColors.textSecondaryDark)
                      else
                        const SizedBox(height: 9),
                    ],
                  ),
                ),
              ),
              // Checkmark se ativo
              if (isActive)
                Positioned(
                  top: 4,
                  right: 4,
                  child: Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                            color: Colors.black.withOpacity(0.15),
                            blurRadius: 4)
                      ],
                    ),
                    child: Icon(Icons.check_rounded, size: 10, color: color),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Modo toggle row ───────────────────────────────────────────────────────────

class _ModeToggleRow extends StatelessWidget {
  final bool isDark;
  final Color primary;
  final Color surface;
  final Color card;
  final Color textPrimary;
  final Color textSecondary;
  final Color divider;
  final ValueChanged<bool> onChanged;

  const _ModeToggleRow({
    required this.isDark,
    required this.primary,
    required this.surface,
    required this.card,
    required this.textPrimary,
    required this.textSecondary,
    required this.divider,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: divider),
      ),
      child: Row(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: isDark
                  ? const Color(0xFF6366F1).withOpacity(0.15)
                  : const Color(0xFFF59E0B).withOpacity(0.12),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(
              isDark ? Icons.nights_stay_rounded : Icons.wb_sunny_rounded,
              color: isDark
                  ? const Color(0xFF6366F1)
                  : const Color(0xFFF59E0B),
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isDark ? 'Modo Escuro' : 'Modo Claro',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: textPrimary,
                  ),
                ),
                Text(
                  isDark
                      ? 'Interface em tons escuros'
                      : 'Interface em tons claros',
                  style: TextStyle(fontSize: 12, color: textSecondary),
                ),
              ],
            ),
          ),
          Switch(
            value: isDark,
            activeColor: const Color(0xFF6366F1),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

// ── Section label (aparencia sheet) ─────────────────────────────────────────────

class _AparenciaSectionLabel extends StatelessWidget {
  final String label;
  final Color color;

  const _AparenciaSectionLabel({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: color,
        letterSpacing: 1.2,
      ),
    );
  }
}