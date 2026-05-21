import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../services/finance_service.dart';
import '../../data/models/orcamento.dart';
import '../../data/models/transaction.dart';
import '../../data/models/conta.dart';
import '../../utils/formatters.dart';
import '../../utils/app_theme.dart';
import '../../utils/app_state.dart';
import '../../widgets/common.dart';
import '../../repositories/planning_repository.dart';
import '../../repositories/account_repository.dart';
import '../../repositories/transaction_repository.dart';

class PlanningScreen extends StatefulWidget {
  const PlanningScreen({super.key});

  @override
  State<PlanningScreen> createState() => _PlanningScreenState();
}

class _PlanningScreenState extends State<PlanningScreen>
    with SingleTickerProviderStateMixin {
  static const _planningRepository = PlanningRepository.instance;
  static const _accountRepository = AccountRepository.instance;
  static const _transactionRepository = TransactionRepository.instance;
  late TabController _tabController;
  DateTime _selectedMonth = DateTime.now();
  MonthlySummary? _summary;
  List<Meta> _metas = [];
  List<OrcamentoComRollover> _orcamentos = [];
  List<Map<String, double>> _yearlyData = [];
  bool _loadingRelatorios = false;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadData();
    AppState.dataChanges.addListener(_loadData);
  }

  @override
  void dispose() {
    AppState.dataChanges.removeListener(_loadData);
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await FinanceService.loadPlanningData(_selectedMonth);
      if (!mounted) return;
      setState(() {
        _summary = data.summary;
        _metas = data.metas;
        _orcamentos = data.orcamentos;
        _yearlyData = data.yearly;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.appBackground,
      appBar: AppBar(
        backgroundColor: context.appSurface,
        title:
            Text('Planejamento', style: TextStyle(color: context.textPrimary)),
        actions: [
          IconButton(
            icon: Icon(Icons.add, color: context.primary),
            onPressed: () {
              if (_tabController.index == 1) {
                _addOrcamento();
              } else {
                _addMeta();
              }
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: context.primary,
          labelColor: context.primary,
          unselectedLabelColor: context.textSecondary,
          labelStyle: const TextStyle(fontWeight: FontWeight.w600),
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: const [
            Tab(text: 'Resumo'),
            Tab(text: 'Orçamentos'),
            Tab(text: 'Metas'),
            Tab(text: 'Relatórios'),
          ],
        ),
      ),
      body: _loading
          ? const LoadingState()
          : _error != null
              ? ErrorState(
                  message: _error,
                  onRetry: _loadData,
                )
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _buildResumoTab(),
                    _buildOrcamentosTab(),
                    _buildMetasTab(),
                    _buildRelatoriosTab(),
                  ],
                ),
    );
  }

  Widget _buildResumoTab() {
    final s = _summary;
    if (s == null) return const LoadingState();

    return RefreshIndicator(
      onRefresh: _loadData,
      color: context.primary,
      backgroundColor: context.appSurface,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Month selector
            Center(
              child: MonthSelectorPill(
                selectedMonth: _selectedMonth,
                onPrev: () {
                  setState(() => _selectedMonth =
                      DateTime(_selectedMonth.year, _selectedMonth.month - 1));
                  _loadData();
                },
                onNext: () {
                  setState(() => _selectedMonth =
                      DateTime(_selectedMonth.year, _selectedMonth.month + 1));
                  _loadData();
                },
              ),
            ),
            const SizedBox(height: 20),

            // Summary card
            _buildSummaryCard(s),
            const SizedBox(height: 20),

            // Spending breakdown
            if (s.despesasPorCategoria.isNotEmpty) ...[
              SectionHeader(title: 'Gastos por categoria'),
              const SizedBox(height: 12),
              _buildCategoryBreakdown(s),
              const SizedBox(height: 20),
            ],

            // Insights
            SectionHeader(title: 'Insights financeiros'),
            const SizedBox(height: 12),
            _buildInsights(s),
            const SizedBox(height: 20),

            // 50/30/20 rule
            SectionHeader(title: 'Regra 50/30/20'),
            const SizedBox(height: 12),
            _buildBudgetRule(s),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCard(MonthlySummary s) {
    return AppCard(
      child: Column(
        children: [
          _SummaryRow(
            icon: Icons.arrow_upward_rounded,
            color: context.primary,
            label: 'Receitas',
            value: fmtBRL(s.receitas),
          ),
          const Divider(height: 24),
          _SummaryRow(
            icon: Icons.arrow_downward_rounded,
            color: AppColors.red,
            label: 'Despesas',
            value: fmtBRL(s.despesas),
          ),
          const Divider(height: 24),
          _SummaryRow(
            icon: Icons.account_balance_wallet_rounded,
            color: s.saldo >= 0 ? context.primary : AppColors.red,
            label: 'Saldo',
            value: fmtBRL(s.saldo),
            bold: true,
          ),
          if (s.receitas > 0) ...[
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: (s.despesas / s.receitas).clamp(0.0, 1.0),
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
            const SizedBox(height: 6),
            Text(
              '${(s.despesas / s.receitas * 100).toStringAsFixed(0)}% da renda comprometida',
              style: TextStyle(color: context.textSecondary, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCategoryBreakdown(MonthlySummary s) {
    final sorted = s.despesasPorCategoria.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final total = s.despesas;

    return AppCard(
      child: Column(
        children: sorted.map((e) {
          final pct = total > 0 ? e.value / total : 0.0;
          final (icon, color) = CategoriaHelper.get(e.key);
          return Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(icon, color: color, size: 16),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(e.key,
                          style: TextStyle(
                              color: context.textPrimary, fontSize: 14)),
                    ),
                    Text(fmtBRL(e.value),
                        style: TextStyle(
                            color: context.textPrimary,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 36,
                      child: Text(
                        '${(pct * 100).toStringAsFixed(0)}%',
                        style: TextStyle(
                            color: context.textSecondary, fontSize: 12),
                        textAlign: TextAlign.right,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: pct,
                    backgroundColor: context.appCardLight,
                    valueColor: AlwaysStoppedAnimation(color),
                    minHeight: 4,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildInsights(MonthlySummary s) {
    final insights = <_InsightData>[];

    if (s.receitas > 0) {
      final taxa = (s.receitas - s.despesas) / s.receitas * 100;
      if (taxa >= 20) {
        insights.add(_InsightData(
          icon: Icons.thumb_up_rounded,
          color: context.primary,
          title: 'Ótima poupança!',
          desc: 'Você poupou ${taxa.toStringAsFixed(0)}% da renda este mês.',
        ));
      } else if (taxa < 0) {
        insights.add(_InsightData(
          icon: Icons.warning_rounded,
          color: AppColors.red,
          title: 'Gastos acima da renda',
          desc:
              'Você gastou ${(-taxa).toStringAsFixed(0)}% a mais do que recebeu.',
        ));
      } else {
        insights.add(_InsightData(
          icon: Icons.info_rounded,
          color: AppColors.amber,
          title: 'Poupança abaixo do ideal',
          desc: 'Tente poupar pelo menos 20% da renda mensalmente.',
        ));
      }
    }

    if (s.despesasPorCategoria.isNotEmpty) {
      final top = s.despesasPorCategoria.entries
          .reduce((a, b) => a.value > b.value ? a : b);
      insights.add(_InsightData(
        icon: CategoriaHelper.getIcon(top.key),
        color: CategoriaHelper.getColor(top.key),
        title: 'Maior gasto: ${top.key}',
        desc:
            '${fmtBRL(top.value)} (${s.despesas > 0 ? (top.value / s.despesas * 100).toStringAsFixed(0) : 0}% das despesas)',
      ));
    }

    if (insights.isEmpty) {
      insights.add(const _InsightData(
        icon: Icons.lightbulb_outline,
        color: AppColors.blue,
        title: 'Adicione transações',
        desc:
            'Registre suas receitas e despesas para ver insights personalizados.',
      ));
    }

    return Column(
      children: insights
          .map((i) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _InsightCard(data: i),
              ))
          .toList(),
    );
  }

  Widget _buildBudgetRule(MonthlySummary s) {
    final receitas = s.receitas > 0 ? s.receitas : 1;
    final necessidades = s.receitas * 0.5;
    final desejos = s.receitas * 0.3;
    final investimentos = s.receitas * 0.2;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Distribua sua renda assim:',
            style: TextStyle(color: context.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 16),
          _BudgetSlice(
            label: '50% — Necessidades',
            desc: 'Moradia, alimentação, saúde',
            ideal: necessidades,
            real: s.despesas,
            color: AppColors.blue,
          ),
          const SizedBox(height: 12),
          _BudgetSlice(
            label: '30% — Desejos',
            desc: 'Lazer, restaurantes, assinaturas',
            ideal: desejos,
            real: s.despesas * 0.3,
            color: AppColors.purple,
          ),
          const SizedBox(height: 12),
          _BudgetSlice(
            label: '20% — Investimentos',
            desc: 'Poupança, renda fixa, ações',
            ideal: investimentos,
            real: s.saldo > 0 ? s.saldo : 0,
            color: context.primary,
          ),
        ],
      ),
    );
  }

  Widget _buildOrcamentosTab() {
    return RefreshIndicator(
      onRefresh: _loadData,
      color: context.primary,
      backgroundColor: context.appSurface,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Center(
                child: MonthSelectorPill(
                  selectedMonth: _selectedMonth,
                  onPrev: () {
                    setState(() => _selectedMonth = DateTime(
                        _selectedMonth.year, _selectedMonth.month - 1));
                    _loadData();
                  },
                  onNext: () {
                    setState(() => _selectedMonth = DateTime(
                        _selectedMonth.year, _selectedMonth.month + 1));
                    _loadData();
                  },
                ),
              ),
            ),
          ),
          if (_orcamentos.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
                child: _OrcamentoResumoCard(orcamentos: _orcamentos),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (_, i) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _OrcamentoCard(
                      data: _orcamentos[i],
                      onEdit: () => _editOrcamento(_orcamentos[i].orcamento),
                      onDelete: () =>
                          _deleteOrcamento(_orcamentos[i].orcamento),
                      onToggleRollover: () =>
                          _toggleRollover(_orcamentos[i].orcamento),
                    ),
                  ),
                  childCount: _orcamentos.length,
                ),
              ),
            ),
          ] else ...[
            SliverFillRemaining(
              child: EmptyState(
                icon: Icons.account_balance_wallet_outlined,
                title: 'Nenhum orçamento',
                subtitle:
                    'Defina limites por categoria para controlar seus gastos mensais',
                actionLabel: 'Criar orçamento',
                accentColor: AppColors.purple,
                onAction: _addOrcamento,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _addOrcamento() => _showOrcamentoForm(null);
  Future<void> _editOrcamento(Orcamento o) => _showOrcamentoForm(o);

  Future<void> _toggleRollover(Orcamento o) async {
    final updated = Orcamento(
      id: o.id,
      categoria: o.categoria,
      limite: o.limite,
      mes: o.mes,
      ano: o.ano,
      rollover: !o.rollover,
    );
    await _planningRepository.saveOrcamento(updated);
    AppState.notify();
  }

  Future<void> _showOrcamentoForm(Orcamento? editando) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: context.appSurface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _OrcamentoFormSheet(
        editando: editando,
        mesPadrao: _selectedMonth.month,
        anoPadrao: _selectedMonth.year,
      ),
    );
    if (result == true) _loadData();
  }

  Future<void> _deleteOrcamento(Orcamento o) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: context.appSurface,
        title: Text('Excluir orçamento',
            style: TextStyle(color: context.textPrimary)),
        content: Text('Excluir orçamento de "${o.categoria}"?',
            style: TextStyle(color: context.textSecondary)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('Cancelar',
                  style: TextStyle(color: context.textSecondary))),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Excluir',
                  style: TextStyle(color: AppColors.red))),
        ],
      ),
    );
    if (ok == true) {
      await _planningRepository.deleteOrcamento(o.id);
      AppState.notify();
    }
  }

  Widget _buildMetasTab() {
    return RefreshIndicator(
      onRefresh: _loadData,
      color: context.primary,
      backgroundColor: context.appSurface,
      child: _metas.isEmpty
          ? EmptyState(
              icon: Icons.flag_outlined,
              title: 'Nenhuma meta',
              subtitle: 'Defina metas financeiras para alcançar seus objetivos',
              actionLabel: 'Criar meta',
              accentColor: AppColors.green,
              onAction: _addMeta,
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
              itemCount: _metas.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (_, i) => _MetaCard(
                meta: _metas[i],
                onEdit: () => _editMeta(_metas[i]),
                onDelete: () => _deleteMeta(_metas[i]),
                onDeposit: () => _depositMeta(_metas[i]),
                summary: _summary,
              ),
            ),
    );
  }

  Widget _buildRelatoriosTab() {
    final s = _summary;
    return RefreshIndicator(
      onRefresh: _loadData,
      color: context.primary,
      backgroundColor: context.appSurface,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Month selector
            Center(
              child: MonthSelectorPill(
                selectedMonth: _selectedMonth,
                onPrev: () {
                  setState(() => _selectedMonth =
                      DateTime(_selectedMonth.year, _selectedMonth.month - 1));
                  _loadData();
                },
                onNext: () {
                  setState(() => _selectedMonth =
                      DateTime(_selectedMonth.year, _selectedMonth.month + 1));
                  _loadData();
                },
              ),
            ),
            const SizedBox(height: 20),

            // Pie chart — Gastos por categoria
            if (s != null && s.despesasPorCategoria.isNotEmpty) ...[
              SectionHeader(title: 'Gastos por categoria'),
              const SizedBox(height: 12),
              _buildPieChart(s),
              const SizedBox(height: 24),
            ],

            // Bar chart — Receita vs Despesa por categoria
            if (s != null &&
                (s.despesasPorCategoria.isNotEmpty ||
                    s.receitasPorCategoria.isNotEmpty)) ...[
              SectionHeader(title: 'Receita vs Despesa por categoria'),
              const SizedBox(height: 12),
              _buildHorizontalBarChart(s),
              const SizedBox(height: 24),
            ],

            // 12-month evolution
            if (_yearlyData.isNotEmpty) ...[
              SectionHeader(title: 'Evolução anual — ${_selectedMonth.year}'),
              const SizedBox(height: 12),
              _buildYearlyChart(),
              const SizedBox(height: 24),
            ],

            // Future balance projection
            if (s != null) ...[
              SectionHeader(title: 'Projeção dos próximos 6 meses'),
              const SizedBox(height: 12),
              _buildProjectionChart(s),
              const SizedBox(height: 24),
            ],

            if (s == null)
              EmptyState(
                icon: Icons.bar_chart_outlined,
                title: 'Sem dados',
                subtitle: 'Adicione transações para ver relatórios',
                accentColor: AppColors.blue,
              ),
          ],
        ),
      ),
    );
  }

  // ── Gráfico de pizza — categorias ─────────────────────────────

  Widget _buildPieChart(MonthlySummary s) {
    final sorted = s.despesasPorCategoria.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top = sorted.take(6).toList();
    final total = s.despesas;

    final sections = top.asMap().entries.map((e) {
      final color = CategoriaHelper.getColor(e.value.key);
      final pct = total > 0 ? (e.value.value / total) : 0.0;
      return PieChartSectionData(
        value: e.value.value,
        color: color,
        radius: 64,
        title: pct > 0.08 ? '${(pct * 100).toStringAsFixed(0)}%' : '',
        titleStyle: const TextStyle(
            fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white),
        badgeWidget: null,
      );
    }).toList();

    return AppCard(
      child: Column(
        children: [
          SizedBox(
            height: 200,
            child: PieChart(
              PieChartData(
                sections: sections,
                centerSpaceRadius: 40,
                sectionsSpace: 2,
                borderData: FlBorderData(show: false),
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Legend
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: top.map((e) {
              final color = CategoriaHelper.getColor(e.key);
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration:
                        BoxDecoration(color: color, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 4),
                  Text(e.key,
                      style: TextStyle(
                          fontSize: 12, color: context.textSecondary)),
                  const SizedBox(width: 4),
                  Text(fmtBRL(e.value),
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: context.textPrimary)),
                ],
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  // ── Barras horizontais — Receita vs Despesa por categoria ─────

  Widget _buildHorizontalBarChart(MonthlySummary s) {
    // Merge all categories
    final allCats = {
      ...s.despesasPorCategoria.keys,
      ...s.receitasPorCategoria.keys
    }.toList();
    allCats.sort();
    if (allCats.isEmpty) return const SizedBox.shrink();

    return AppCard(
      child: Column(
        children: allCats.map((cat) {
          final desp = s.despesasPorCategoria[cat] ?? 0;
          final rec = s.receitasPorCategoria[cat] ?? 0;
          final max = [desp, rec, 1.0].reduce((a, b) => a > b ? a : b);
          final color = CategoriaHelper.getColor(cat);

          return Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(cat,
                    style: TextStyle(
                        color: context.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                if (desp > 0) ...[
                  Row(children: [
                    SizedBox(
                      width: 60,
                      child: Text('Desp.',
                          style: TextStyle(fontSize: 11, color: AppColors.red)),
                    ),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: desp / max,
                          backgroundColor: context.appCardLight,
                          valueColor:
                              const AlwaysStoppedAnimation(AppColors.red),
                          minHeight: 8,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(fmtBRL(desp),
                        style: TextStyle(
                            fontSize: 11, color: context.textSecondary)),
                  ]),
                  const SizedBox(height: 4),
                ],
                if (rec > 0)
                  Row(children: [
                    SizedBox(
                      width: 60,
                      child: Text('Rec.',
                          style:
                              TextStyle(fontSize: 11, color: context.primary)),
                    ),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: rec / max,
                          backgroundColor: context.appCardLight,
                          valueColor: AlwaysStoppedAnimation(context.primary),
                          minHeight: 8,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(fmtBRL(rec),
                        style: TextStyle(
                            fontSize: 11, color: context.textSecondary)),
                  ]),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  // ── Gráfico de linha — evolução anual ─────────────────────────

  Widget _buildYearlyChart() {
    final months = ['J', 'F', 'M', 'A', 'M', 'J', 'J', 'A', 'S', 'O', 'N', 'D'];
    final recData = _yearlyData
        .asMap()
        .entries
        .map((e) => FlSpot(e.key.toDouble(), e.value['receitas']!))
        .toList();
    final despData = _yearlyData
        .asMap()
        .entries
        .map((e) => FlSpot(e.key.toDouble(), e.value['despesas']!))
        .toList();
    final maxY = _yearlyData.fold<double>(
        0,
        (m, d) => [m, d['receitas']!, d['despesas']!]
            .reduce((a, b) => a > b ? a : b));

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            _LegendDot(color: context.primary, label: 'Receitas'),
            const SizedBox(width: 16),
            const _LegendDot(color: AppColors.red, label: 'Despesas'),
          ]),
          const SizedBox(height: 16),
          SizedBox(
            height: 180,
            child: LineChart(
              LineChartData(
                minY: 0,
                maxY: maxY * 1.2 + 1,
                clipData: const FlClipData.all(),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (_) => FlLine(
                    color: context.appCardLight,
                    strokeWidth: 1,
                  ),
                ),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  leftTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (v, _) {
                        final i = v.toInt();
                        if (i < 0 || i >= months.length)
                          return const SizedBox();
                        return Text(months[i],
                            style: TextStyle(
                                fontSize: 11, color: context.textSecondary));
                      },
                      reservedSize: 22,
                    ),
                  ),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: recData,
                    isCurved: true,
                    color: context.primary,
                    barWidth: 2.5,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      color: context.primary.withOpacity(0.08),
                    ),
                  ),
                  LineChartBarData(
                    spots: despData,
                    isCurved: true,
                    color: AppColors.red,
                    barWidth: 2.5,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      color: AppColors.red.withOpacity(0.08),
                    ),
                  ),
                ],
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipColor: (_) => context.appCardLight,
                    getTooltipItems: (spots) => spots
                        .map((s) => LineTooltipItem(
                              fmtBRL(s.y),
                              TextStyle(
                                color: s.barIndex == 0
                                    ? context.primary
                                    : AppColors.red,
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                              ),
                            ))
                        .toList(),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Projeção dos próximos 6 meses ─────────────────────────────

  Widget _buildProjectionChart(MonthlySummary s) {
    // Usa o saldo atual como ponto de partida e projeta com base no saldo médio do mês
    final saldoMedio = s.receitas - s.despesas;
    final now = _selectedMonth;

    final projections = List.generate(6, (i) {
      final m = DateTime(now.year, now.month + i + 1);
      final nomeMes = _monthShort(m.month);
      final saldoProjetado = saldoMedio * (i + 1);
      return (nomeMes, saldoProjetado);
    });

    final allValues = projections.map((p) => p.$2).toList();
    final minV = allValues.reduce((a, b) => a < b ? a : b);
    final maxV = allValues.reduce((a, b) => a > b ? a : b);
    final range = (maxV - minV).abs();

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            saldoMedio >= 0
                ? 'Com a sua taxa atual de poupança de ${fmtBRL(saldoMedio)}/mês:'
                : 'Atenção: você está gastando ${fmtBRL(saldoMedio.abs())} a mais do que recebe/mês.',
            style: TextStyle(
                color: saldoMedio >= 0 ? context.textSecondary : AppColors.red,
                fontSize: 13),
          ),
          const SizedBox(height: 16),
          ...projections.map((p) {
            final (mes, val) = p;
            final pct =
                range > 0 ? ((val - minV) / range).clamp(0.0, 1.0) : 0.5;
            final isPositive = val >= 0;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  SizedBox(
                    width: 34,
                    child: Text(mes,
                        style: TextStyle(
                            fontSize: 12,
                            color: context.textSecondary,
                            fontWeight: FontWeight.w600)),
                  ),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: pct,
                        backgroundColor: context.appCardLight,
                        valueColor: AlwaysStoppedAnimation(
                            isPositive ? context.primary : AppColors.red),
                        minHeight: 10,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 80,
                    child: Text(
                      '${isPositive ? '+' : ''}${fmtBRL(val)}',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: isPositive ? context.primary : AppColors.red),
                      textAlign: TextAlign.right,
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

  String _monthShort(int m) {
    const names = [
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
      'Dez'
    ];
    return names[m - 1];
  }

  Future<void> _addMeta() => _showMetaForm(null);
  Future<void> _editMeta(Meta m) => _showMetaForm(m);

  Future<void> _showMetaForm(Meta? editando) async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: context.appSurface,
      isScrollControlled: true,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _MetaFormSheet(editando: editando),
    );
  }

  Future<void> _depositMeta(Meta m) async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: context.appSurface,
      isScrollControlled: true,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _DepositMetaSheet(meta: m),
    );
  }

  Future<void> _deleteMeta(Meta m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: context.appSurface,
        title:
            Text('Excluir meta', style: TextStyle(color: context.textPrimary)),
        content: Text('Excluir "${m.nome}"?',
            style: TextStyle(color: context.textSecondary)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('Cancelar',
                  style: TextStyle(color: context.textSecondary))),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Excluir',
                  style: TextStyle(color: AppColors.red))),
        ],
      ),
    );
    if (ok == true) {
      await _planningRepository.deleteMeta(m.id);
      AppState.notify();
    }
  }
}

// ─── Supporting widgets ────────────────────────────────────────

// ── Orçamento widgets ─────────────────────────────────────────

class _OrcamentoResumoCard extends StatelessWidget {
  final List<OrcamentoComRollover> orcamentos;
  const _OrcamentoResumoCard({required this.orcamentos});

  @override
  Widget build(BuildContext context) {
    final totalLimite = orcamentos.fold(0.0, (s, o) => s + o.limiteEfetivo);
    final totalGasto = orcamentos.fold(0.0, (s, o) => s + o.gastoReal);
    final totalRollover =
        orcamentos.fold(0.0, (s, o) => s + o.rolloverAcumulado);
    final pct =
        totalLimite > 0 ? (totalGasto / totalLimite).clamp(0.0, 1.0) : 0.0;
    final estourados = orcamentos.where((o) => o.estourado).length;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.blue.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.account_balance_wallet_rounded,
                    color: AppColors.blue, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Visão geral',
                        style: TextStyle(
                            color: context.textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w700)),
                    Text('${orcamentos.length} categorias orçadas',
                        style: TextStyle(
                            color: context.textSecondary, fontSize: 12)),
                  ],
                ),
              ),
              if (estourados > 0)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.redLight,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '$estourados estourado${estourados > 1 ? 's' : ''}',
                    style: const TextStyle(
                        color: AppColors.red,
                        fontSize: 11,
                        fontWeight: FontWeight.w700),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: pct,
              backgroundColor: context.appCardLight,
              valueColor: AlwaysStoppedAnimation(
                  pct >= 1.0 ? AppColors.red : AppColors.blue),
              minHeight: 8,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Gasto',
                        style: TextStyle(
                            color: context.textSecondary, fontSize: 11)),
                    Text(fmtBRL(totalGasto),
                        style: TextStyle(
                            color: context.textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text('Disponível',
                        style: TextStyle(
                            color: context.textSecondary, fontSize: 11)),
                    Text(
                        fmtBRL((totalLimite - totalGasto)
                            .clamp(0, double.infinity)),
                        style: TextStyle(
                            color: totalGasto > totalLimite
                                ? AppColors.red
                                : AppColors.green,
                            fontSize: 15,
                            fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('Limite total',
                        style: TextStyle(
                            color: context.textSecondary, fontSize: 11)),
                    Text(fmtBRL(totalLimite),
                        style: TextStyle(
                            color: context.textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            ],
          ),
          if (totalRollover > 0) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: AppColors.purple.withOpacity(0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.purple.withOpacity(0.2)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.auto_awesome_rounded,
                      color: AppColors.purple, size: 14),
                  const SizedBox(width: 6),
                  Text(
                    '${fmtBRL(totalRollover)} acumulado de meses anteriores',
                    style: const TextStyle(
                        color: AppColors.purple,
                        fontSize: 12,
                        fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _OrcamentoCard extends StatelessWidget {
  final OrcamentoComRollover data;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onToggleRollover;

  const _OrcamentoCard({
    required this.data,
    required this.onEdit,
    required this.onDelete,
    required this.onToggleRollover,
  });

  @override
  Widget build(BuildContext context) {
    final o = data.orcamento;
    final (icon, color) = CategoriaHelper.get(o.categoria);
    final pct = data.percentualUsado;
    final saldo = data.saldoDisponivel;
    final barColor = data.estourado
        ? AppColors.red
        : pct >= 0.8
            ? AppColors.amber
            : color;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(o.categoria,
                        style: TextStyle(
                            color: context.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w600)),
                    if (o.rollover && data.rolloverAcumulado > 0)
                      Text(
                        '+ ${fmtBRL(data.rolloverAcumulado)} de meses anteriores',
                        style: const TextStyle(
                            color: AppColors.purple,
                            fontSize: 11,
                            fontWeight: FontWeight.w500),
                      ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                color: context.appSurface,
                icon: Icon(Icons.more_vert_rounded,
                    color: context.textSecondary, size: 18),
                onSelected: (v) {
                  if (v == 'edit') onEdit();
                  if (v == 'delete') onDelete();
                  if (v == 'rollover') onToggleRollover();
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'rollover',
                    child: Row(
                      children: [
                        Icon(
                          o.rollover
                              ? Icons.toggle_on_rounded
                              : Icons.toggle_off_rounded,
                          color: o.rollover
                              ? AppColors.purple
                              : context.textSecondary,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          o.rollover ? 'Rollover ativo' : 'Ativar rollover',
                          style: TextStyle(color: context.textPrimary),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'edit',
                    child: Row(
                      children: [
                        Icon(Icons.edit_rounded,
                            color: context.textSecondary, size: 18),
                        const SizedBox(width: 8),
                        Text('Editar',
                            style: TextStyle(color: context.textPrimary)),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete_rounded,
                            color: AppColors.red, size: 18),
                        SizedBox(width: 8),
                        Text('Excluir', style: TextStyle(color: AppColors.red)),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Gasto',
                        style: TextStyle(
                            color: context.textSecondary, fontSize: 11)),
                    Text(fmtBRL(data.gastoReal),
                        style: TextStyle(
                            color: context.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('Limite${o.rollover ? ' (c/ rollover)' : ''}',
                      style: TextStyle(
                          color: context.textSecondary, fontSize: 11)),
                  Text(fmtBRL(data.limiteEfetivo),
                      style: TextStyle(
                          color: context.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w700)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: pct,
              backgroundColor: context.appCardLight,
              valueColor: AlwaysStoppedAnimation(barColor),
              minHeight: 6,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              if (o.rollover)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.purple.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.auto_awesome_rounded,
                          color: AppColors.purple, size: 11),
                      SizedBox(width: 3),
                      Text('Rollover',
                          style: TextStyle(
                              color: AppColors.purple,
                              fontSize: 10,
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
                )
              else
                const SizedBox(),
              Text(
                data.estourado
                    ? '${fmtBRL(data.gastoReal - data.limiteEfetivo)} acima do limite'
                    : '${fmtBRL(saldo)} disponível',
                style: TextStyle(
                    color: data.estourado
                        ? AppColors.red
                        : saldo < data.limiteEfetivo * 0.2
                            ? AppColors.amber
                            : context.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w500),
              ),
              Text(
                '${(pct * 100).toStringAsFixed(0)}%',
                style: TextStyle(
                    color: barColor, fontSize: 12, fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _OrcamentoFormSheet extends StatefulWidget {
  final Orcamento? editando;
  final int mesPadrao;
  final int anoPadrao;

  const _OrcamentoFormSheet({
    required this.editando,
    required this.mesPadrao,
    required this.anoPadrao,
  });

  @override
  State<_OrcamentoFormSheet> createState() => _OrcamentoFormSheetState();
}

class _OrcamentoFormSheetState extends State<_OrcamentoFormSheet> {
  static const _planningRepository = PlanningRepository.instance;
  final _limiteCtrl = TextEditingController();
  String _categoria = 'Alimentação';
  bool _rollover = false;
  bool _saving = false;

  static const _categorias = [
    'Alimentação',
    'Moradia',
    'Transporte',
    'Saúde',
    'Lazer',
    'Entretenimento',
    'Educação',
    'Assinatura',
    'Vestuário',
    'Viagem',
    'Outros',
  ];

  @override
  void initState() {
    super.initState();
    if (widget.editando != null) {
      final o = widget.editando!;
      _limiteCtrl.text = o.limite.toStringAsFixed(2).replaceAll('.', ',');
      _categoria = o.categoria;
      _rollover = o.rollover;
    }
  }

  @override
  void dispose() {
    _limiteCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final limite = parseBRL(_limiteCtrl.text);
    if (limite == null || limite <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Informe um valor válido')),
      );
      return;
    }
    setState(() => _saving = true);
    final o = Orcamento(
      id: widget.editando?.id,
      categoria: _categoria,
      limite: limite,
      mes: widget.editando?.mes ?? widget.mesPadrao,
      ano: widget.editando?.ano ?? widget.anoPadrao,
      rollover: _rollover,
    );
    await _planningRepository.saveOrcamento(o);
    AppState.notify();
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 24,
          bottom: MediaQuery.of(context).viewInsets.bottom + 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: context.appCardLight,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            widget.editando == null ? 'Novo orçamento' : 'Editar orçamento',
            style: TextStyle(
                color: context.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 20),

          // Categoria
          Text('Categoria',
              style: TextStyle(color: context.textSecondary, fontSize: 13)),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: _categoria,
            dropdownColor: context.appSurface,
            style: TextStyle(color: context.textPrimary),
            decoration: InputDecoration(
              filled: true,
              fillColor: context.appCardLight,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
            items: _categorias
                .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                .toList(),
            onChanged: (v) => setState(() => _categoria = v!),
          ),
          const SizedBox(height: 16),

          // Limite
          Text('Limite mensal (R\$)',
              style: TextStyle(color: context.textSecondary, fontSize: 13)),
          const SizedBox(height: 8),
          TextField(
            controller: _limiteCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: TextStyle(color: context.textPrimary),
            decoration: InputDecoration(
              hintText: '0,00',
              prefixText: 'R\$ ',
              prefixStyle: TextStyle(color: context.textSecondary),
              filled: true,
              fillColor: context.appCardLight,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Rollover toggle
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _rollover
                  ? AppColors.purple.withOpacity(0.07)
                  : context.appCardLight,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _rollover
                    ? AppColors.purple.withOpacity(0.3)
                    : Colors.transparent,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.purple.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.auto_awesome_rounded,
                      color: AppColors.purple, size: 18),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Rollover',
                          style: TextStyle(
                              color: context.textPrimary,
                              fontSize: 14,
                              fontWeight: FontWeight.w600)),
                      Text(
                        'Saldo não gasto passa para o mês seguinte',
                        style: TextStyle(
                            color: context.textSecondary, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: _rollover,
                  activeColor: AppColors.purple,
                  onChanged: (v) => setState(() => _rollover = v),
                ),
              ],
            ),
          ),
          if (_rollover) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.blueLight,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline_rounded,
                      color: AppColors.blue, size: 14),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'O saldo economizado em meses anteriores é acumulado automaticamente e somado ao limite deste mês.',
                      style:
                          const TextStyle(color: AppColors.blue, fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 24),

          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(
                backgroundColor: context.primary,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : Text(
                      widget.editando == null ? 'Criar orçamento' : 'Salvar',
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String value;
  final bool bold;

  const _SummaryRow({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
    this.bold = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, color: color, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(label,
              style: TextStyle(
                  fontSize: 14,
                  color: bold ? context.textPrimary : context.textSecondary,
                  fontWeight: bold ? FontWeight.w700 : FontWeight.w400)),
        ),
        Text(value,
            style: TextStyle(
                fontSize: bold ? 16 : 15,
                fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
                color: color)),
      ],
    );
  }
}

class _InsightData {
  final IconData icon;
  final Color color;
  final String title;
  final String desc;
  const _InsightData(
      {required this.icon,
      required this.color,
      required this.title,
      required this.desc});
}

class _InsightCard extends StatelessWidget {
  final _InsightData data;
  const _InsightCard({required this.data});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: data.color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: data.color.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
                color: data.color.withOpacity(0.15), shape: BoxShape.circle),
            child: Icon(data.icon, color: data.color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(data.title,
                    style: TextStyle(
                        color: context.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(data.desc,
                    style:
                        TextStyle(color: context.textSecondary, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BudgetSlice extends StatelessWidget {
  final String label;
  final String desc;
  final double ideal;
  final double real;
  final Color color;

  const _BudgetSlice({
    required this.label,
    required this.desc,
    required this.ideal,
    required this.real,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        color: context.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
                Text(desc,
                    style:
                        TextStyle(color: context.textSecondary, fontSize: 11)),
              ],
            ),
            Text(fmtBRL(ideal),
                style: TextStyle(
                    color: color, fontSize: 13, fontWeight: FontWeight.w700)),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: ideal > 0 ? (real / ideal).clamp(0.0, 1.0) : 0,
            backgroundColor: context.appCardLight,
            valueColor: AlwaysStoppedAnimation(color),
            minHeight: 6,
          ),
        ),
      ],
    );
  }
}

class _MetaCard extends StatelessWidget {
  final Meta meta;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onDeposit;
  final MonthlySummary? summary;

  const _MetaCard({
    required this.meta,
    required this.onEdit,
    required this.onDelete,
    required this.onDeposit,
    this.summary,
  });

  @override
  Widget build(BuildContext context) {
    // Cor calculada dentro do build para ter acesso ao contexto
    Color getColor() {
      try {
        return Color(int.parse('FF${meta.cor}', radix: 16));
      } catch (_) {
        return context.primary;
      }
    }

    final color = getColor();
    final pct = meta.progresso;
    final falta = meta.valorAlvo - meta.valorAtual;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                    color: color.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12)),
                child: Icon(Icons.flag_rounded, color: color, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(meta.nome,
                        style: TextStyle(
                            color: context.textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w700)),
                    Text(
                      falta > 0
                          ? 'Faltam ${fmtBRL(falta)}'
                          : 'Meta atingida! 🎉',
                      style: TextStyle(
                          color: falta <= 0
                              ? context.primary
                              : context.textSecondary,
                          fontSize: 12),
                    ),
                  ],
                ),
              ),
              Text(
                '${(pct * 100).toStringAsFixed(0)}%',
                style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w800, color: color),
              ),
              PopupMenuButton<String>(
                color: context.appCardLight,
                icon: Icon(Icons.more_vert,
                    color: context.textSecondary, size: 20),
                onSelected: (v) {
                  if (v == 'edit') onEdit();
                  if (v == 'delete') onDelete();
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                      value: 'edit',
                      child: Text('Editar',
                          style: TextStyle(color: context.textPrimary))),
                  const PopupMenuItem(
                      value: 'delete',
                      child: Text('Excluir',
                          style: TextStyle(color: AppColors.red))),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: pct,
              backgroundColor: context.appCardLight,
              valueColor: AlwaysStoppedAnimation(color),
              minHeight: 10,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(fmtBRL(meta.valorAtual),
                  style: TextStyle(
                      color: context.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600)),
              Text(fmtBRL(meta.valorAlvo),
                  style: TextStyle(color: context.textSecondary, fontSize: 13)),
            ],
          ),
          if (falta > 0) ...[
            const SizedBox(height: 12),

            // Projeção: quantos meses para atingir
            _buildProjectionRow(context, falta, color),
            const SizedBox(height: 12),

            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onDeposit,
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Depositar'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: color,
                  side: BorderSide(color: color.withOpacity(0.4)),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildProjectionRow(BuildContext context, double falta, Color color) {
    final poupancaMensal =
        summary != null ? (summary!.receitas - summary!.despesas) : 0.0;
    final prazo = meta.prazo;
    final now = DateTime.now();

    // Alerta de prazo
    if (prazo != null && !prazo.isBefore(now)) {
      final mesesRestantes =
          (prazo.year - now.year) * 12 + (prazo.month - now.month);
      final mesesNecessarios =
          poupancaMensal > 0 ? (falta / poupancaMensal).ceil() : null;
      final atrasado =
          mesesNecessarios != null && mesesNecessarios > mesesRestantes;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(
              atrasado
                  ? Icons.warning_amber_rounded
                  : Icons.calendar_today_rounded,
              size: 14,
              color: atrasado ? AppColors.amber : context.textSecondary,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                atrasado
                    ? 'Prazo em risco: faltam $mesesRestantes ${mesesRestantes == 1 ? 'mês' : 'meses'}, mas você precisa de $mesesNecessarios'
                    : 'Prazo: ${_fmtDate(prazo)} ($mesesRestantes ${mesesRestantes == 1 ? 'mês' : 'meses'})',
                style: TextStyle(
                  fontSize: 12,
                  color: atrasado ? AppColors.amber : context.textSecondary,
                ),
              ),
            ),
          ]),
          if (poupancaMensal > 0 && mesesNecessarios != null) ...[
            const SizedBox(height: 4),
            Text(
              'Poupando ${fmtBRL(poupancaMensal)}/mês → ${mesesNecessarios} ${mesesNecessarios == 1 ? 'mês' : 'meses'} para concluir',
              style: TextStyle(fontSize: 11, color: context.textSecondary),
            ),
          ],
        ],
      );
    }

    // Sem prazo — só projeção
    if (poupancaMensal > 0) {
      final meses = (falta / poupancaMensal).ceil();
      final conclusao = DateTime(now.year, now.month + meses);
      return Row(children: [
        Icon(Icons.trending_up_rounded, size: 14, color: color),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            'Com ${fmtBRL(poupancaMensal)}/mês de poupança → $meses ${meses == 1 ? 'mês' : 'meses'} (${_fmtDate(conclusao)})',
            style: TextStyle(fontSize: 12, color: context.textSecondary),
          ),
        ),
      ]);
    }

    return Row(children: [
      Icon(Icons.info_outline, size: 14, color: context.textSecondary),
      const SizedBox(width: 6),
      Text(
        'Adicione transações para ver a projeção',
        style: TextStyle(fontSize: 12, color: context.textSecondary),
      ),
    ]);
  }

  String _fmtDate(DateTime d) {
    const months = [
      'jan',
      'fev',
      'mar',
      'abr',
      'mai',
      'jun',
      'jul',
      'ago',
      'set',
      'out',
      'nov',
      'dez'
    ];
    return '${months[d.month - 1]}/${d.year}';
  }
}

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(text,
        style: TextStyle(color: context.textSecondary, fontSize: 13));
  }
}

class _DarkTextField extends StatelessWidget {
  final TextEditingController ctrl;
  final String hint;
  final bool isNumber;

  const _DarkTextField(
      {required this.ctrl, required this.hint, this.isNumber = false});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: ctrl,
      keyboardType: isNumber ? TextInputType.number : TextInputType.text,
      style: TextStyle(color: context.textPrimary),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: context.textSecondary),
        fillColor: context.appCardLight,
        filled: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      ),
    );
  }
}

// ─── Meta Form Sheet ───────────────────────────────────────────

class _MetaFormSheet extends StatefulWidget {
  final Meta? editando;
  const _MetaFormSheet({this.editando});

  @override
  State<_MetaFormSheet> createState() => _MetaFormSheetState();
}

class _MetaFormSheetState extends State<_MetaFormSheet> {
  static const _planningRepository = PlanningRepository.instance;
  late final TextEditingController _nomeCtrl;
  late final TextEditingController _alvoCtrl;
  late final TextEditingController _atualCtrl;

  @override
  void initState() {
    super.initState();
    final e = widget.editando;
    _nomeCtrl = TextEditingController(text: e?.nome ?? '');
    _alvoCtrl = TextEditingController(
        text: e != null
            ? e.valorAlvo.toStringAsFixed(2).replaceAll('.', ',')
            : '');
    _atualCtrl = TextEditingController(
        text: e != null && e.valorAtual > 0
            ? e.valorAtual.toStringAsFixed(2).replaceAll('.', ',')
            : '');
  }

  @override
  void dispose() {
    _nomeCtrl.dispose();
    _alvoCtrl.dispose();
    _atualCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final editando = widget.editando;
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
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: context.textSecondary,
                  borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            editando != null ? 'Editar meta' : 'Nova meta',
            style: TextStyle(
                color: context.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 20),
          const _FieldLabel('Nome da meta'),
          const SizedBox(height: 6),
          _DarkTextField(
              ctrl: _nomeCtrl, hint: 'Ex: Viagem, Reserva de emergência'),
          const SizedBox(height: 12),
          const _FieldLabel('Valor alvo (R\$)'),
          const SizedBox(height: 6),
          _DarkTextField(ctrl: _alvoCtrl, hint: '0,00', isNumber: true),
          const SizedBox(height: 12),
          const _FieldLabel('Valor atual (R\$)'),
          const SizedBox(height: 6),
          _DarkTextField(ctrl: _atualCtrl, hint: '0,00', isNumber: true),
          const SizedBox(height: 24),
          GradientButton(
            label: editando != null ? 'Salvar' : 'Criar meta',
            onPressed: () async {
              if (_nomeCtrl.text.trim().isEmpty) return;
              final alvo =
                  double.tryParse(_alvoCtrl.text.replaceAll(',', '.')) ?? 0;
              final atual =
                  double.tryParse(_atualCtrl.text.replaceAll(',', '.')) ?? 0;
              final meta = Meta(
                id: editando?.id,
                nome: _nomeCtrl.text.trim(),
                valorAlvo: alvo,
                valorAtual: atual,
              );
              await _planningRepository.saveMeta(meta);
              AppState.notify();
              if (mounted) Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }
}

// ─── Deposit Meta Sheet ────────────────────────────────────────

class _DepositMetaSheet extends StatefulWidget {
  final Meta meta;
  const _DepositMetaSheet({required this.meta});

  @override
  State<_DepositMetaSheet> createState() => _DepositMetaSheetState();
}

class _DepositMetaSheetState extends State<_DepositMetaSheet> {
  static const _planningRepository = PlanningRepository.instance;
  static const _accountRepository = AccountRepository.instance;
  static const _transactionRepository = TransactionRepository.instance;
  late final TextEditingController _ctrl;
  List<Conta> _contas = [];
  String? _contaId;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController();
    _loadContas();
  }

  Future<void> _loadContas() async {
    final contas = await _accountRepository.getAll();
    final contasValidas = contas.where((c) => c.tipo != 'credito').toList();
    setState(() {
      _contas = contasValidas;
      _contaId = contasValidas.isNotEmpty ? contasValidas.first.id : null;
      _loading = false;
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.meta;
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
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: context.textSecondary,
                  borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 20),
          Center(
            child: Text(
              'Depositar em "${m.nome}"',
              style: TextStyle(
                  color: context.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 20),
          Text('Valor (R\$)',
              style: TextStyle(color: context.textSecondary, fontSize: 13)),
          const SizedBox(height: 6),
          _DarkTextField(ctrl: _ctrl, hint: '0,00', isNumber: true),
          const SizedBox(height: 12),
          Text('Descontar de',
              style: TextStyle(color: context.textSecondary, fontSize: 13)),
          const SizedBox(height: 6),
          if (_loading)
            Center(child: CircularProgressIndicator(color: context.primary))
          else if (_contas.isEmpty)
            Text(
              'Nenhuma conta disponível. Cadastre uma conta corrente ou poupança.',
              style: TextStyle(color: context.textSecondary, fontSize: 13),
            )
          else
            Container(
              decoration: BoxDecoration(
                color: context.appCardLight,
                borderRadius: BorderRadius.circular(10),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _contaId,
                  dropdownColor: context.appCard,
                  isExpanded: true,
                  style: TextStyle(color: context.textPrimary, fontSize: 15),
                  items: _contas.map((c) {
                    return DropdownMenuItem(
                      value: c.id,
                      child: Text(c.nome),
                    );
                  }).toList(),
                  onChanged: (v) => setState(() => _contaId = v),
                ),
              ),
            ),
          const SizedBox(height: 24),
          GradientButton(
            label: 'Confirmar depósito',
            onPressed: (_loading || _contas.isEmpty)
                ? null
                : () async {
                    final v =
                        double.tryParse(_ctrl.text.replaceAll(',', '.')) ?? 0;
                    if (v <= 0 || _contaId == null) return;

                    final updated = Meta(
                      id: m.id,
                      nome: m.nome,
                      valorAlvo: m.valorAlvo,
                      valorAtual: (m.valorAtual + v).clamp(0, m.valorAlvo),
                      icone: m.icone,
                      cor: m.cor,
                      prazo: m.prazo,
                    );
                    await _planningRepository.saveMeta(updated);

                    final transacao = Transacao(
                      valor: -v,
                      banco: _contaId!,
                      parcelas: 1,
                      primeiraParcela: DateTime.now(),
                      categoria: 'Metas',
                      tipo: TipoTransacao.saida,
                      descricao: 'Depósito: ${m.nome}',
                      recorrencia: Recorrencia.nenhuma,
                    );
                    await _transactionRepository.save(transacao);

                    AppState.notify();
                    if (mounted) Navigator.pop(context);
                  },
          ),
        ],
      ),
    );
  }
}
// ─── Legend dot widget ─────────────────────────────────────────

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 5),
      Text(label, style: TextStyle(fontSize: 12, color: context.textSecondary)),
    ]);
  }
}
