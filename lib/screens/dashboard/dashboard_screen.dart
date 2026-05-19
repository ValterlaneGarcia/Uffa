import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../services/finance_service.dart';
import '../../data/db/app_db.dart';
import '../../data/models/conta.dart';
import '../../data/models/transaction.dart';
import '../../utils/formatters.dart';
import '../../utils/app_theme.dart';
import '../../utils/app_state.dart';
import '../../widgets/common.dart';
import '../transactions/add_transaction_screen.dart';
import '../transactions/transactions_screen.dart';
import '../accounts/accounts_screen.dart';

// Lista de meses abreviados para gráficos (constante global)
const _mesesAbreviados = [
  'J', 'F', 'M', 'A', 'M', 'J',
  'J', 'A', 'S', 'O', 'N', 'D'
];

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  DateTime _selectedMonth = DateTime.now();
  MonthlySummary? _summary;
  List<Map<String, double>> _yearly = [];
  List<Conta> _contas = [];
  List<Transacao> _recentes = [];
  bool _loading = true;
  String _nomeUsuario = 'Usuário';

  @override
  void initState() {
    super.initState();
    _loadData();
    AppState.instance.addListener(_loadData);
  }

  @override
  void dispose() {
    AppState.instance.removeListener(_loadData);
    super.dispose();
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() => _loading = true);
    final summary = await FinanceService.getMonthlySummary(
        _selectedMonth.year, _selectedMonth.month);
    final yearly =
        await FinanceService.getYearlyComparison(_selectedMonth.year);
    // Recarrega contas para refletir saldos atualizados
    final contas = await AppDB.getContas();
    // Transações recentes: filtra pelo mês selecionado para manter consistência
    final recentes = await AppDB.getTransacoesQueImpactamMes(
        _selectedMonth.year, _selectedMonth.month);
    final nome = await AppDB.getConfigValue('nome_usuario') ?? 'Usuário';

    if (!mounted) return;
    setState(() {
      _summary = summary;
      _yearly = yearly;
      _contas = contas;
      // Ordena por data decrescente e pega as 5 mais recentes
      recentes.sort((a, b) => b.primeiraParcela.compareTo(a.primeiraParcela));
      _recentes = recentes.take(5).toList();
      _nomeUsuario = nome;
      _loading = false;
    });
  }

  void _prevMonth() {
    setState(() => _selectedMonth =
        DateTime(_selectedMonth.year, _selectedMonth.month - 1));
    _loadData();
  }

  void _nextMonth() {
    final now = DateTime.now();
    final next =
        DateTime(_selectedMonth.year, _selectedMonth.month + 1);
    if (!next.isAfter(DateTime(now.year, now.month + 2))) {
      setState(() => _selectedMonth = next);
      _loadData();
    }
  }

  String get _greeting {
    final h = DateTime.now().hour;
    if (h < 12) return 'Bom dia';
    if (h < 18) return 'Boa tarde';
    return 'Boa noite';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.appBackground,
      body: _loading
          ? const LoadingState()
          : RefreshIndicator(
              onRefresh: _loadData,
              color: context.primary,
              backgroundColor: context.appSurface,
              child: CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(child: _buildHeader()),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                    sliver: SliverList(
                      delegate: SliverChildListDelegate([
                        const SizedBox(height: 20),
                        _buildSummaryCards(),
                        const SizedBox(height: 20),
                        _buildMonthlyChart(),
                        const SizedBox(height: 20),
                        _buildAccountsSection(),
                        if (_recentes.isNotEmpty) ...[
                          const SizedBox(height: 20),
                          _buildRecentTransactions(),
                        ],
                        const SizedBox(height: 20),
                        _buildQuickActions(),
                      ]),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildHeader() {
    final summary = _summary;
    // Patrimônio líquido: soma saldos das contas normais, subtrai dívidas dos cartões
    final saldo = _contas.fold<double>(
      0,
      (s, c) => c.tipo == 'credito' ? s - c.saldo : s + c.saldo,
    );
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [context.primary, context.primary.withOpacity(0.8)]),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top bar
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$_greeting, 👋',
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 13),
                      ),
                      Text(
                        _nomeUsuario,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      _HeaderIconButton(
                        icon: Icons.notifications_outlined,
                        onTap: _showNotifications,
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () => _loadData(),
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.person,
                              color: Colors.white, size: 20),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Wallet card – white frosted
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                      color: Colors.white.withOpacity(0.25), width: 1),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Carteira total',
                          style: TextStyle(
                              color: Colors.white70, fontSize: 13),
                        ),
                        GestureDetector(
                          onTap: () => AppState.instance.toggleBalanceVisibility(),
                          child: Row(
                            children: [
                              Icon(
                                AppState.instance.balanceVisible
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                                color: Colors.white70,
                                size: 18,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      AppState.instance.balanceVisible ? fmtBRL(saldo) : 'R\$ ••••••',
                      style: TextStyle(
                        fontSize: 34,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Saldo disponível',
                      style: TextStyle(
                          color: Colors.white60, fontSize: 12),
                    ),
                    const SizedBox(height: 16),

                    // Month selector
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _WhiteMonthPill(
                          selectedMonth: _selectedMonth,
                          onPrev: _prevMonth,
                          onNext: _nextMonth,
                        ),
                        if (summary != null)
                          _TrendBadge(
                              value: summary.variacaoReceitas,
                              positive: summary.saldo >= 0),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryCards() {
    final summary = _summary;
    return Row(
      children: [
        Expanded(
          child: _SummaryCard(
            label: 'Receitas',
            value: summary?.receitas ?? 0,
            percent: summary?.variacaoReceitas ?? 0,
            color: context.primary,
            bgColor: context.primaryLight,
            icon: Icons.arrow_upward_rounded,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) =>
                      const TransactionsScreen(initialTab: 2)),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _SummaryCard(
            label: 'Despesas',
            value: summary?.despesas ?? 0,
            percent: summary?.variacaoDespesas ?? 0,
            color: AppColors.red,
            bgColor: AppColors.redLight,
            icon: Icons.arrow_downward_rounded,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) =>
                      const TransactionsScreen(initialTab: 1)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMonthlyChart() {
    final hasData = _yearly.any(
        (e) => (e['receitas'] ?? 0) > 0 || (e['despesas'] ?? 0) > 0);
    final maxVal = _yearly.fold<double>(
        0,
        (m, e) => [m, e['receitas'] ?? 0, e['despesas'] ?? 0]
            .reduce((a, b) => a > b ? a : b));

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(title: 'Resumo mensal'),
          if (!hasData)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: EmptyState(
                icon: Icons.bar_chart_outlined,
                title: 'Nenhum dado ainda',
                subtitle:
                    'Adicione transações para ver o resumo',
                accentColor: AppColors.blue,
              ),
            )
          else ...[
            SizedBox(height: 6),
            Row(
              children: [
                _LegendDot(
                    color: context.primary, label: 'Receitas'),
                const SizedBox(width: 16),
                _LegendDot(
                    color: AppColors.red, label: 'Despesas'),
              ],
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 140,
              child: BarChart(
                BarChartData(
                  maxY: maxVal > 0 ? maxVal * 1.2 : 1000,
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    getDrawingHorizontalLine: (_) => FlLine(
                      color: context.appDivider,
                      strokeWidth: 1,
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    leftTitles: const AxisTitles(
                        sideTitles:
                            SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(
                        sideTitles:
                            SideTitles(showTitles: false)),
                    topTitles: const AxisTitles(
                        sideTitles:
                            SideTitles(showTitles: false)),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: _bottomTitle,
                        reservedSize: 24,
                      ),
                    ),
                  ),
                  barGroups:
                      List.generate(_yearly.length, (i) {
                    final isCurrent =
                        i == _selectedMonth.month - 1;
                    return BarChartGroupData(
                        x: i,
                        barRods: [
                          BarChartRodData(
                            toY:
                                _yearly[i]['receitas'] ?? 0,
                            color: isCurrent
                                ? context.primary
                                : context.primary
                                    .withOpacity(0.3),
                            width: 6,
                            borderRadius:
                                const BorderRadius.vertical(
                                    top: Radius.circular(4)),
                          ),
                          BarChartRodData(
                            toY:
                                _yearly[i]['despesas'] ?? 0,
                            color: isCurrent
                                ? AppColors.red
                                : AppColors.red
                                    .withOpacity(0.3),
                            width: 6,
                            borderRadius:
                                const BorderRadius.vertical(
                                    top: Radius.circular(4)),
                          ),
                        ]);
                  }),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // Método auxiliar para o título inferior do gráfico (não estático)
  Widget _bottomTitle(double value, TitleMeta meta) {
    final i = value.toInt();
    if (i < 0 || i >= _mesesAbreviados.length) return const SizedBox();
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        _mesesAbreviados[i],
        style: TextStyle(fontSize: 10, color: context.textSecondary),
      ),
    );
  }

  Widget _buildAccountsSection() {
    if (_contas.isEmpty) {
      return Column(
        children: [
          SectionHeader(
            title: 'Minhas contas',
            action: 'Adicionar',
            onAction: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => const AccountsScreen()),
            ),
          ),
          const SizedBox(height: 12),
          AppCard(
            child: EmptyState(
              icon: Icons.account_balance_wallet_outlined,
              title: 'Nenhuma conta cadastrada',
              subtitle:
                  'Adicione uma conta para começar a controlar suas finanças',
              accentColor: AppColors.blue,
            ),
          ),
        ],
      );
    }

    return Column(
      children: [
        SectionHeader(
          title: 'Minhas contas',
          action: 'Ver todas',
          onAction: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => const AccountsScreen()),
          ),
        ),
        const SizedBox(height: 12),
        ..._contas.take(3).map((c) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _AccountTile(
                conta: c,
                visible: AppState.instance.balanceVisible,
                onTap: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const AccountsScreen()),
                  );
                  _loadData();
                },
              ),
            )),
      ],
    );
  }

  Widget _buildRecentTransactions() {
    const meses = [
      'Jan', 'Fev', 'Mar', 'Abr', 'Mai', 'Jun',
      'Jul', 'Ago', 'Set', 'Out', 'Nov', 'Dez'
    ];
    final mesLabel = '${meses[_selectedMonth.month - 1]}/${_selectedMonth.year}';
    return Column(
      children: [
        SectionHeader(
          title: 'Transações de $mesLabel',
          action: 'Ver todas',
          onAction: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => const TransactionsScreen()),
          ),
        ),
        const SizedBox(height: 12),
        AppCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: _recentes.asMap().entries.map((e) {
              final t = e.value;
              final isLast = e.key == _recentes.length - 1;
              return Column(
                children: [
                  _TransactionTile(transacao: t),
                  if (!isLast)
                    Divider(
                        height: 1,
                        indent: 72,
                        endIndent: 16,
                        color: context.appDivider),
                ],
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildQuickActions() {
    return Column(
      children: [
        SectionHeader(title: 'Ações rápidas'),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _QuickAction(
                icon: Icons.remove_rounded,
                label: 'Nova despesa',
                color: AppColors.red,
                bgColor: AppColors.redLight,
                onTap: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const AddTransactionScreen(
                          initialIsDespesa: true),
                    ),
                  );
                  AppState.notify();
                  _loadData();
                },
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: _QuickAction(
                icon: Icons.add_rounded,
                label: 'Nova receita',
                color: context.primary,
                bgColor: context.primaryLight,
                onTap: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const AddTransactionScreen(
                          initialIsDespesa: false),
                    ),
                  );
                  AppState.notify();
                  _loadData();
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _QuickAction(
                icon: Icons.bar_chart_rounded,
                label: 'Relatório',
                color: AppColors.blue,
                bgColor: AppColors.blueLight,
                onTap: () => _showRelatorio(),
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _showNotifications() {
    showModalBottomSheet(
      context: context,
      backgroundColor: context.appSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: context.appDivider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            SizedBox(height: 16),
            Text('Lembretes',
                style: TextStyle(
                    color: context.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 24),
            EmptyState(
              icon: Icons.notifications_outlined,
              title: 'Nenhum lembrete',
              subtitle: 'Configure lembretes nas transações',
              accentColor: AppColors.amber,
            ),
          ],
        ),
      ),
    );
  }

  void _showRelatorio() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _RelatorioScreen(
          selectedMonth: _selectedMonth,
          summary: _summary,
          yearly: _yearly,
          contas: _contas,
        ),
      ),
    );
  }
}

// ─── Header helpers ──────────────────────────────────────────────

class _HeaderIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _HeaderIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.15),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: 22),
      ),
    );
  }
}

class _WhiteMonthPill extends StatelessWidget {
  final DateTime selectedMonth;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  const _WhiteMonthPill(
      {required this.selectedMonth,
      required this.onPrev,
      required this.onNext});

  @override
  Widget build(BuildContext context) {
    const meses = [
      'Jan', 'Fev', 'Mar', 'Abr', 'Mai', 'Jun',
      'Jul', 'Ago', 'Set', 'Out', 'Nov', 'Dez'
    ];
    final label =
        '${meses[selectedMonth.month - 1]} ${selectedMonth.year}';
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.2),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left,
                color: Colors.white70, size: 18),
            onPressed: onPrev,
            constraints:
                const BoxConstraints(minWidth: 32, minHeight: 32),
            padding: EdgeInsets.zero,
          ),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right,
                color: Colors.white70, size: 18),
            onPressed: onNext,
            constraints:
                const BoxConstraints(minWidth: 32, minHeight: 32),
            padding: EdgeInsets.zero,
          ),
        ],
      ),
    );
  }
}

class _TrendBadge extends StatelessWidget {
  final double value;
  final bool positive;
  const _TrendBadge({required this.value, required this.positive});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.2),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Icon(
            positive
                ? Icons.trending_up_rounded
                : Icons.trending_down_rounded,
            color: Colors.white,
            size: 14,
          ),
          const SizedBox(width: 4),
          Text(
            '${value.abs().toStringAsFixed(0)}%',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Supporting widgets ─────────────────────────────────────────

class _SummaryCard extends StatelessWidget {
  final String label;
  final double value;
  final double percent;
  final Color color;
  final Color bgColor;
  final IconData icon;
  final VoidCallback? onTap;

  const _SummaryCard({
    required this.label,
    required this.value,
    required this.percent,
    required this.color,
    required this.bgColor,
    required this.icon,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isPos = percent >= 0;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: context.appSurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: context.appDivider, width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: bgColor,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: color, size: 18),
                ),
                Spacer(),
                Container(
                  padding: EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: (isPos ? context.primary : AppColors.red)
                        .withOpacity(0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isPos
                            ? Icons.arrow_upward_rounded
                            : Icons.arrow_downward_rounded,
                        size: 10,
                        color: isPos ? context.primary : AppColors.red,
                      ),
                      Text(
                        '${percent.abs().toStringAsFixed(0)}%',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color:
                              isPos ? context.primary : AppColors.red,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            SizedBox(height: 12),
            Text(label,
                style: TextStyle(
                    color: context.textSecondary, fontSize: 12)),
            SizedBox(height: 4),
            Text(
              fmtBRL(value),
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: context.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
            width: 8,
            height: 8,
            decoration:
                BoxDecoration(color: color, shape: BoxShape.circle)),
        SizedBox(width: 4),
        Text(label,
            style: TextStyle(
                fontSize: 11, color: context.textSecondary)),
      ],
    );
  }
}

class _AccountTile extends StatelessWidget {
  final Conta conta;
  final bool visible;
  final VoidCallback onTap;
  const _AccountTile(
      {required this.conta,
      required this.visible,
      required this.onTap});

  Color get _color {
    try {
      return Color(int.parse('FF${conta.cor}', radix: 16));
    } catch (_) {
      return AppColors.blue;
    }
  }

  IconData get _icon {
    switch (conta.tipo) {
      case 'credito':
        return Icons.credit_card_rounded;
      case 'corrente':
        return Icons.account_balance_wallet_rounded;
      case 'investimento':
        return Icons.trending_up_rounded;
      case 'beneficio':
        return Icons.card_giftcard_rounded;
      default:
        return Icons.account_balance_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isCredit = conta.tipo == 'credito';

    // Credit cards get purple gradient (Nubank-style per prototype)
    if (isCredit) {
      return GestureDetector(
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [context.primary.withOpacity(0.85), context.primary]),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.credit_card_rounded,
                    color: Colors.white, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(conta.nome,
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Colors.white)),
                    Text('Cartão de crédito',
                        style: const TextStyle(
                            fontSize: 11,
                            color: Colors.white70)),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    visible ? fmtBRL(conta.disponivel) : 'R\$ ••••',
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Colors.white),
                  ),
                  Text('disponível',
                      style: const TextStyle(
                          fontSize: 11, color: Colors.white70)),
                ],
              ),
              SizedBox(width: 4),
              Icon(Icons.chevron_right,
                  size: 18, color: Colors.white70),
            ],
          ),
        ),
      );
    }

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding:
            EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: context.appSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: context.appDivider, width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: _color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(_icon, color: _color, size: 22),
            ),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(conta.nome,
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: context.textPrimary)),
                  Text(
                    'Conta ${conta.tipo}',
                    style: TextStyle(
                        fontSize: 11,
                        color: context.textSecondary),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  visible ? fmtBRL(conta.saldo) : 'R\$ ••••',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: context.textPrimary),
                ),
                Text('saldo',
                    style: TextStyle(
                        fontSize: 11,
                        color: context.textSecondary)),
              ],
            ),
            SizedBox(width: 4),
            Icon(Icons.chevron_right,
                size: 18, color: context.textTertiary),
          ],
        ),
      ),
    );
  }
}

class _TransactionTile extends StatelessWidget {
  final Transacao transacao;
  _TransactionTile({required this.transacao});

  @override
  Widget build(BuildContext context) {
    final isDespesa = transacao.valor < 0;
    final color = isDespesa ? AppColors.red : context.primary;
    final (icon, catColor) = CategoriaHelper.get(transacao.categoria);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: catColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: catColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  transacao.descricao ?? transacao.categoria,
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: context.textPrimary),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(transacao.categoria,
                    style: TextStyle(
                        fontSize: 11,
                        color: context.textSecondary)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${isDespesa ? '-' : '+'}${fmtBRL(transacao.valor.abs())}',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: color),
              ),
              Text(dtFmt.format(transacao.primeiraParcela),
                  style: TextStyle(
                      fontSize: 11,
                      color: context.textSecondary)),
            ],
          ),
        ],
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final Color bgColor;
  final VoidCallback onTap;

  const _QuickAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.bgColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Column(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: Colors.white, size: 20),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Relatório screen ────────────────────────────────────────────

class _RelatorioScreen extends StatefulWidget {
  final DateTime selectedMonth;
  final MonthlySummary? summary;
  final List<Map<String, double>> yearly;
  final List<Conta> contas;

  const _RelatorioScreen({
    required this.selectedMonth,
    required this.summary,
    required this.yearly,
    required this.contas,
  });

  @override
  State<_RelatorioScreen> createState() => _RelatorioScreenState();
}

class _RelatorioScreenState extends State<_RelatorioScreen> {
  late DateTime _month;
  MonthlySummary? _summary;
  List<Map<String, double>> _yearly = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _month = widget.selectedMonth;
    _summary = widget.summary;
    _yearly = widget.yearly;
  }

  Future<void> _loadMonth() async {
    setState(() => _loading = true);
    final summary = await FinanceService.getMonthlySummary(
        _month.year, _month.month);
    final yearly =
        await FinanceService.getYearlyComparison(_month.year);
    if (!mounted) return;
    setState(() {
      _summary = summary;
      _yearly = yearly;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = _summary;
    return Scaffold(
      backgroundColor: context.appBackground,
      appBar: AppBar(
        backgroundColor: context.appSurface,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new,
              size: 18, color: context.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Relatório',
            style: TextStyle(color: context.textPrimary)),
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(
              height: 1, thickness: 1, color: context.appDivider),
        ),
      ),
      body: _loading
          ? const LoadingState()
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: MonthSelectorPill(
                      selectedMonth: _month,
                      onPrev: () {
                        setState(() => _month =
                            DateTime(_month.year, _month.month - 1));
                        _loadMonth();
                      },
                      onNext: () {
                        setState(() => _month =
                            DateTime(_month.year, _month.month + 1));
                        _loadMonth();
                      },
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (s != null) ...[
                    _buildResumoCards(s),
                    const SizedBox(height: 20),
                    _buildSaldoCard(s),
                    const SizedBox(height: 20),
                    _buildGraficoAnual(),
                    const SizedBox(height: 20),
                    if (s.despesasPorCategoria.isNotEmpty) ...[
                      _buildCategoriasCard(s),
                      SizedBox(height: 20),
                    ],
                    _buildContasCard(),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _buildResumoCards(MonthlySummary s) {
    return Row(
      children: [
        Expanded(
            child: _RelatorioCard(
          label: 'Receitas',
          value: s.receitas,
          color: context.primary,
          bgColor: context.primaryLight,
          icon: Icons.arrow_upward_rounded,
        )),
        const SizedBox(width: 12),
        Expanded(
            child: _RelatorioCard(
          label: 'Despesas',
          value: s.despesas,
          color: AppColors.red,
          bgColor: AppColors.redLight,
          icon: Icons.arrow_downward_rounded,
        )),
      ],
    );
  }

  Widget _buildSaldoCard(MonthlySummary s) {
    final saldo = s.receitas - s.despesas;
    final positivo = saldo >= 0;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(title: 'Saldo do período'),
          SizedBox(height: 16),
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: (positivo ? context.primary : AppColors.red)
                      .withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  positivo
                      ? Icons.trending_up_rounded
                      : Icons.trending_down_rounded,
                  color: positivo ? context.primary : AppColors.red,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      fmtBRL(saldo.abs()),
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color:
                            positivo ? context.primary : AppColors.red,
                      ),
                    ),
                    Text(
                      positivo
                          ? 'Sobrou este mês'
                          : 'Déficit este mês',
                      style: TextStyle(
                          color: context.textSecondary,
                          fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (s.receitas > 0) ...[
            SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value:
                    (s.despesas / s.receitas).clamp(0.0, 1.0),
                backgroundColor: context.appCardLight,
                valueColor: AlwaysStoppedAnimation(
                  s.despesas > s.receitas
                      ? AppColors.red
                      : s.despesas > s.receitas * 0.8
                          ? AppColors.amber
                          : context.primary,
                ),
                minHeight: 8,
              ),
            ),
            SizedBox(height: 6),
            Text(
              '${(s.despesas / s.receitas * 100).toStringAsFixed(0)}% da renda comprometida',
              style: TextStyle(
                  color: context.textSecondary, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildGraficoAnual() {
    final hasData = _yearly.any((e) =>
        (e['receitas'] ?? 0) > 0 || (e['despesas'] ?? 0) > 0);
    final maxVal = _yearly.fold<double>(
        0,
        (m, e) => [m, e['receitas'] ?? 0, e['despesas'] ?? 0]
            .reduce((a, b) => a > b ? a : b));

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(title: 'Evolução anual'),
          if (!hasData)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: EmptyState(
                icon: Icons.bar_chart_outlined,
                title: 'Nenhum dado ainda',
                subtitle:
                    'Adicione transações para ver a evolução anual',
                accentColor: AppColors.blue,
              ),
            )
          else ...[
            SizedBox(height: 6),
            Row(
              children: [
                _LegendDot(
                    color: context.primary, label: 'Receitas'),
                const SizedBox(width: 16),
                _LegendDot(
                    color: AppColors.red, label: 'Despesas'),
              ],
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 160,
              child: BarChart(
                BarChartData(
                  maxY: maxVal > 0 ? maxVal * 1.2 : 1000,
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    getDrawingHorizontalLine: (_) => FlLine(
                      color: context.appDivider,
                      strokeWidth: 1,
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    leftTitles: const AxisTitles(
                        sideTitles:
                            SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(
                        sideTitles:
                            SideTitles(showTitles: false)),
                    topTitles: const AxisTitles(
                        sideTitles:
                            SideTitles(showTitles: false)),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: _bottomTitle,
                        reservedSize: 24,
                      ),
                    ),
                  ),
                  barGroups:
                      List.generate(_yearly.length, (i) {
                    final isCurrent =
                        i == _month.month - 1;
                    return BarChartGroupData(
                        x: i,
                        barRods: [
                          BarChartRodData(
                            toY:
                                _yearly[i]['receitas'] ?? 0,
                            color: isCurrent
                                ? context.primary
                                : context.primary
                                    .withOpacity(0.3),
                            width: 6,
                            borderRadius:
                                const BorderRadius.vertical(
                                    top: Radius.circular(4)),
                          ),
                          BarChartRodData(
                            toY:
                                _yearly[i]['despesas'] ?? 0,
                            color: isCurrent
                                ? AppColors.red
                                : AppColors.red
                                    .withOpacity(0.3),
                            width: 6,
                            borderRadius:
                                const BorderRadius.vertical(
                                    top: Radius.circular(4)),
                          ),
                        ]);
                  }),
                ),
              ),
            ),
            const SizedBox(height: 16),
            _buildTabelaAnual(),
          ],
        ],
      ),
    );
  }

  Widget _buildTabelaAnual() {
    const meses = [
      'Jan', 'Fev', 'Mar', 'Abr', 'Mai', 'Jun',
      'Jul', 'Ago', 'Set', 'Out', 'Nov', 'Dez'
    ];
    final rows = <Widget>[];
    for (int i = 0; i < _yearly.length; i++) {
      final rec = _yearly[i]['receitas'] ?? 0;
      final desp = _yearly[i]['despesas'] ?? 0;
      final saldo = rec - desp;
      if (rec == 0 && desp == 0) continue;
      final isCurrent = i == _month.month - 1;
      rows.add(Container(
        padding:
            EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        decoration: BoxDecoration(
          color: isCurrent
              ? context.primary.withOpacity(0.06)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 32,
              child: Text(
                meses[i],
                style: TextStyle(
                  fontSize: 12,
                  color: isCurrent
                      ? context.primary
                      : context.textSecondary,
                  fontWeight: isCurrent
                      ? FontWeight.w700
                      : FontWeight.w400,
                ),
              ),
            ),
            Expanded(
              child: Text(fmtBRL(rec),
                  textAlign: TextAlign.right,
                  style: TextStyle(
                      fontSize: 12, color: context.primary)),
            ),
            Expanded(
              child: Text(fmtBRL(desp),
                  textAlign: TextAlign.right,
                  style: TextStyle(
                      fontSize: 12, color: AppColors.red)),
            ),
            Expanded(
              child: Text(
                fmtBRL(saldo),
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: saldo >= 0
                      ? context.primary
                      : AppColors.red,
                ),
              ),
            ),
          ],
        ),
      ));
    }

    if (rows.isEmpty) return const SizedBox();

    return Column(
      children: [
        Divider(height: 24, color: context.appDivider),
        Row(
          children: [
            const SizedBox(width: 32),
            Expanded(
                child: Text('Receita',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                        fontSize: 11,
                        color: context.textTertiary))),
            Expanded(
                child: Text('Despesa',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                        fontSize: 11,
                        color: context.textTertiary))),
            Expanded(
                child: Text('Saldo',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                        fontSize: 11,
                        color: context.textTertiary))),
          ],
        ),
        const SizedBox(height: 8),
        ...rows,
      ],
    );
  }

  Widget _buildCategoriasCard(MonthlySummary s) {
    final sorted = s.despesasPorCategoria.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final total = s.despesas;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(title: 'Gastos por categoria'),
          const SizedBox(height: 16),
          ...sorted.map((e) {
            final pct = total > 0 ? e.value / total : 0.0;
            final (icon, color) = CategoriaHelper.get(e.key);
            return Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.12),
                          borderRadius:
                              BorderRadius.circular(8),
                        ),
                        child: Icon(icon,
                            color: color, size: 16),
                      ),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(e.key,
                            style: TextStyle(
                                color: context.textPrimary,
                                fontSize: 13)),
                      ),
                      Text(fmtBRL(e.value),
                          style: TextStyle(
                              color: context.textPrimary,
                              fontWeight: FontWeight.w600,
                              fontSize: 13)),
                      SizedBox(width: 8),
                      SizedBox(
                        width: 36,
                        child: Text(
                          '${(pct * 100).toStringAsFixed(0)}%',
                          style: TextStyle(
                              color: context.textSecondary,
                              fontSize: 11),
                          textAlign: TextAlign.right,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: pct,
                      backgroundColor: context.appCardLight,
                      valueColor:
                          AlwaysStoppedAnimation(color),
                      minHeight: 4,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildContasCard() {
    if (widget.contas.isEmpty) return const SizedBox();
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(title: 'Posição das contas'),
          const SizedBox(height: 16),
          ...widget.contas.map((c) {
            final isCredito = c.tipo == 'credito';
            Color cor;
            try {
              cor = Color(int.parse('FF${c.cor}', radix: 16));
            } catch (_) {
              cor = AppColors.blue;
            }
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: cor.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      isCredito
                          ? Icons.credit_card_rounded
                          : Icons.account_balance_wallet_rounded,
                      color: cor,
                      size: 18,
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        Text(c.nome,
                            style: TextStyle(
                                color: context.textPrimary,
                                fontSize: 13,
                                fontWeight:
                                    FontWeight.w600)),
                        Text(c.tipo,
                            style: TextStyle(
                                color:
                                    context.textSecondary,
                                fontSize: 11)),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.end,
                    children: [
                      Text(
                        fmtBRL(isCredito
                            ? c.disponivel
                            : c.saldo),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: isCredito
                              ? (c.disponivel < c.limite * 0.2
                                  ? AppColors.red
                                  : context.textPrimary)
                              : (c.saldo >= 0
                                  ? context.textPrimary
                                  : AppColors.red),
                        ),
                      ),
                      Text(
                        isCredito ? 'disponível' : 'saldo',
                        style: TextStyle(
                            color: context.textSecondary,
                            fontSize: 11),
                      ),
                    ],
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  // Método auxiliar para o título inferior do gráfico (não estático)
  Widget _bottomTitle(double value, TitleMeta meta) {
    final i = value.toInt();
    if (i < 0 || i >= _mesesAbreviados.length) return const SizedBox();
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        _mesesAbreviados[i],
        style: TextStyle(fontSize: 10, color: context.textSecondary),
      ),
    );
  }
}

class _RelatorioCard extends StatelessWidget {
  final String label;
  final double value;
  final Color color;
  final Color bgColor;
  final IconData icon;

  const _RelatorioCard({
    required this.label,
    required this.value,
    required this.color,
    required this.bgColor,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.appSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.appDivider),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          SizedBox(height: 12),
          Text(label,
              style: TextStyle(
                  color: context.textSecondary, fontSize: 12)),
          SizedBox(height: 4),
          Text(
            fmtBRL(value),
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: context.textPrimary),
          ),
        ],
      ),
    );
  }
}