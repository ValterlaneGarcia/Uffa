import 'package:flutter/material.dart';
import '../../data/models/transaction.dart';
import '../../data/models/conta.dart';
import '../../repositories/account_repository.dart';
import '../../repositories/transaction_repository.dart';
import '../../utils/formatters.dart';
import '../../utils/app_theme.dart';
import '../../utils/app_state.dart';
import '../../widgets/common.dart';
import 'add_transaction_screen.dart';
import 'transfer_screen.dart';

class TransactionsScreen extends StatefulWidget {
  final int initialTab;
  const TransactionsScreen({super.key, this.initialTab = 0});

  @override
  State<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends State<TransactionsScreen>
    with SingleTickerProviderStateMixin {
  static const _accountRepository = AccountRepository.instance;
  static const _transactionRepository = TransactionRepository.instance;
  late TabController _tabController;
  DateTime _selectedMonth = DateTime.now();
  List<Transacao> _transacoes = [];
  List<Conta> _contas = [];
  bool _loading = true;
  String _searchQuery = '';
  bool _showSearch = false;

  // ── Filtros avançados ─────────────────────────────
  String? _filtroContaId; // null = todas
  String? _filtroCategoriaId; // null = todas
  _OrdemTransacao _ordem = _OrdemTransacao.data;
  bool _showFilters = false;

  @override
  void initState() {
    super.initState();
    _tabController =
        TabController(length: 3, vsync: this, initialIndex: widget.initialTab);
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
    setState(() => _loading = true);
    final all = await _transactionRepository.getForMonth(
        _selectedMonth.year, _selectedMonth.month);
    final contas = await _accountRepository.getAll();
    if (!mounted) return;
    setState(() {
      _transacoes = all;
      _contas = contas;
      _loading = false;
    });
  }

  void _prevMonth() {
    setState(() => _selectedMonth =
        DateTime(_selectedMonth.year, _selectedMonth.month - 1));
    _loadData();
  }

  void _nextMonth() {
    setState(() => _selectedMonth =
        DateTime(_selectedMonth.year, _selectedMonth.month + 1));
    _loadData();
  }

  // Transferências (tipo=saldo): pagamentos de fatura e transferências entre contas.
  // Aparecem na aba "Todas" mas não distorcem os totais de Despesas/Receitas.
  bool _isTransferencia(Transacao t) => t.isTransferencia;

  List<Transacao> get _despesas =>
      _transacoes.where((t) => t.valor < 0 && !_isTransferencia(t)).toList();
  List<Transacao> get _receitas =>
      _transacoes.where((t) => t.valor > 0 && !_isTransferencia(t)).toList();

  double get _totalDespesas => _despesas.fold(
      0,
      (s, t) =>
          s + t.valorNoMes(_selectedMonth.year, _selectedMonth.month).abs());
  double get _totalReceitas => _receitas.fold(
      0, (s, t) => s + t.valorNoMes(_selectedMonth.year, _selectedMonth.month));

  List<Transacao> _applySearch(List<Transacao> list) {
    var result = list;

    // Texto
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      result = result
          .where((t) =>
              (t.descricao ?? '').toLowerCase().contains(q) ||
              t.categoria.toLowerCase().contains(q) ||
              t.banco.toLowerCase().contains(q))
          .toList();
    }

    // Conta
    if (_filtroContaId != null) {
      result = result.where((t) => t.banco == _filtroContaId).toList();
    }

    // Categoria
    if (_filtroCategoriaId != null) {
      result = result.where((t) => t.categoria == _filtroCategoriaId).toList();
    }

    // Ordenação
    switch (_ordem) {
      case _OrdemTransacao.data:
        result.sort((a, b) => b.primeiraParcela.compareTo(a.primeiraParcela));
        break;
      case _OrdemTransacao.maiorValor:
        result.sort((a, b) => b
            .valorNoMes(_selectedMonth.year, _selectedMonth.month)
            .abs()
            .compareTo(
                a.valorNoMes(_selectedMonth.year, _selectedMonth.month).abs()));
        break;
      case _OrdemTransacao.menorValor:
        result.sort((a, b) => a
            .valorNoMes(_selectedMonth.year, _selectedMonth.month)
            .abs()
            .compareTo(
                b.valorNoMes(_selectedMonth.year, _selectedMonth.month).abs()));
        break;
      case _OrdemTransacao.categoria:
        result.sort((a, b) => a.categoria.compareTo(b.categoria));
        break;
    }

    return result;
  }

  bool get _hasActiveFilters =>
      _filtroContaId != null ||
      _filtroCategoriaId != null ||
      _ordem != _OrdemTransacao.data;

  void _clearFilters() {
    setState(() {
      _filtroContaId = null;
      _filtroCategoriaId = null;
      _ordem = _OrdemTransacao.data;
    });
  }

  Future<void> _showFilterSheet() async {
    // Categorias únicas do mês
    final cats = _transacoes.map((t) => t.categoria).toSet().toList()..sort();

    await showModalBottomSheet(
      context: context,
      backgroundColor: context.appSurface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      isScrollControlled: true,
      builder: (_) => StatefulBuilder(builder: (ctx, setModal) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: context.appCardLight,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Filtros e ordenação',
                      style: TextStyle(
                          color: context.textPrimary,
                          fontSize: 17,
                          fontWeight: FontWeight.w700)),
                  TextButton(
                    onPressed: () {
                      _clearFilters();
                      Navigator.pop(context);
                    },
                    child: const Text('Limpar',
                        style: TextStyle(color: AppColors.amber)),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Conta
              Text('Conta',
                  style: TextStyle(color: context.textSecondary, fontSize: 13)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _FilterChip(
                    label: 'Todas',
                    selected: _filtroContaId == null,
                    onTap: () =>
                        setModal(() => setState(() => _filtroContaId = null)),
                    color: context.primary,
                  ),
                  ..._contas.map((c) => _FilterChip(
                        label: c.nome,
                        selected: _filtroContaId == c.id,
                        onTap: () => setModal(
                            () => setState(() => _filtroContaId = c.id)),
                        color: context.primary,
                      )),
                ],
              ),
              const SizedBox(height: 20),

              // Categoria
              Text('Categoria',
                  style: TextStyle(color: context.textSecondary, fontSize: 13)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _FilterChip(
                    label: 'Todas',
                    selected: _filtroCategoriaId == null,
                    onTap: () => setModal(
                        () => setState(() => _filtroCategoriaId = null)),
                    color: context.primary,
                  ),
                  ...cats.map((cat) {
                    final color = CategoriaHelper.getColor(cat);
                    return _FilterChip(
                      label: cat,
                      selected: _filtroCategoriaId == cat,
                      onTap: () => setModal(
                          () => setState(() => _filtroCategoriaId = cat)),
                      color: color,
                    );
                  }),
                ],
              ),
              const SizedBox(height: 20),

              // Ordenação
              Text('Ordenar por',
                  style: TextStyle(color: context.textSecondary, fontSize: 13)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _OrdemTransacao.values
                    .map((o) => _FilterChip(
                          label: o.label,
                          selected: _ordem == o,
                          onTap: () =>
                              setModal(() => setState(() => _ordem = o)),
                          color: AppColors.blue,
                        ))
                    .toList(),
              ),
              const SizedBox(height: 20),

              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(context),
                  style: FilledButton.styleFrom(
                    backgroundColor: context.primary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Aplicar',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.appBackground,
      appBar: _buildAppBar(),
      body: _loading
          ? const LoadingState()
          : TabBarView(
              controller: _tabController,
              children: [
                _buildListTab(_applySearch(_transacoes)),
                _buildDespesasTab(),
                _buildReceitasTab(),
              ],
            ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FloatingActionButton.small(
            heroTag: 'fab_transfer',
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const TransferScreen()),
              );
              AppState.notify();
            },
            backgroundColor: AppColors.blue,
            child: const Icon(Icons.swap_horiz_rounded, color: Colors.white),
          ),
          const SizedBox(height: 8),
          FloatingActionButton(
            heroTag: 'fab_add',
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => AddTransactionScreen()),
              );
              AppState.notify();
            },
            backgroundColor: context.primary,
            child: const Icon(Icons.add, color: Colors.white),
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: context.appSurface,
      titleSpacing: 0,
      title: _showSearch
          ? Padding(
              padding: const EdgeInsets.only(left: 8),
              child: TextField(
                autofocus: true,
                style: TextStyle(color: context.textPrimary),
                decoration: InputDecoration(
                  hintText: 'Buscar transações...',
                  hintStyle: TextStyle(color: context.textSecondary),
                  border: InputBorder.none,
                  filled: false,
                ),
                onChanged: (v) => setState(() => _searchQuery = v),
              ),
            )
          : Padding(
              padding: const EdgeInsets.only(left: 16),
              child: Text('Transações',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: context.textPrimary)),
            ),
      actions: [
        if (!_showSearch)
          MonthSelectorPill(
            selectedMonth: _selectedMonth,
            onPrev: _prevMonth,
            onNext: _nextMonth,
          ),
        if (!_showSearch) const SizedBox(width: 4),
        if (_hasActiveFilters)
          IconButton(
            icon: const Icon(Icons.filter_alt_off, color: AppColors.amber),
            tooltip: 'Limpar filtros',
            onPressed: _clearFilters,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            padding: EdgeInsets.zero,
          ),
        IconButton(
          icon: Icon(
            Icons.tune_rounded,
            color: _hasActiveFilters ? AppColors.amber : context.textSecondary,
          ),
          tooltip: 'Filtros',
          onPressed: () => _showFilterSheet(),
          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          padding: EdgeInsets.zero,
        ),
        IconButton(
          icon: Icon(
            _showSearch ? Icons.close : Icons.search,
            color: context.textSecondary,
          ),
          onPressed: () => setState(() {
            _showSearch = !_showSearch;
            if (!_showSearch) _searchQuery = '';
          }),
          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          padding: EdgeInsets.zero,
        ),
        const SizedBox(width: 4),
      ],
      bottom: TabBar(
        controller: _tabController,
        indicatorColor: context.primary,
        indicatorWeight: 2,
        labelColor: context.primary,
        unselectedLabelColor: context.textSecondary,
        labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        tabs: const [
          Tab(text: 'Todas'),
          Tab(text: 'Despesas'),
          Tab(text: 'Receitas'),
        ],
      ),
    );
  }

  Widget _buildDespesasTab() {
    return Column(
      children: [
        _TotalBanner(
          label: 'Total de despesas',
          value: _totalDespesas,
          color: AppColors.red,
        ),
        Expanded(child: _buildListTab(_applySearch(_despesas))),
      ],
    );
  }

  Widget _buildReceitasTab() {
    return Column(
      children: [
        _TotalBanner(
          label: 'Total de receitas',
          value: _totalReceitas,
          color: context.primary,
        ),
        Expanded(child: _buildListTab(_applySearch(_receitas))),
      ],
    );
  }

  Widget _buildListTab(List<Transacao> items) {
    if (items.isEmpty) {
      return EmptyState(
        icon: Icons.receipt_long_outlined,
        title: 'Nenhuma transação',
        subtitle: _searchQuery.isNotEmpty
            ? 'Nenhum resultado para "$_searchQuery"'
            : 'Adicione sua primeira transação',
        actionLabel: _searchQuery.isEmpty ? 'Adicionar' : null,
        accentColor: AppColors.green,
        onAction: _searchQuery.isEmpty
            ? () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const AddTransactionScreen()),
                );
                AppState.notify();
              }
            : null,
      );
    }

    // Group by date
    final grouped = <String, List<Transacao>>{};
    for (final t in items) {
      final key = dtFmt.format(t.primeiraParcela);
      grouped.putIfAbsent(key, () => []).add(t);
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      color: context.primary,
      backgroundColor: context.appSurface,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
        itemCount: grouped.length,
        itemBuilder: (_, i) {
          final date = grouped.keys.elementAt(i);
          final txList = grouped[date]!;
          return _DateGroup(
              date: date,
              transactions: txList,
              onDelete: _deleteTransaction,
              ano: _selectedMonth.year,
              mes: _selectedMonth.month);
        },
      ),
    );
  }

  Future<void> _deleteTransaction(Transacao t) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: context.appSurface,
        title: Text('Excluir transação',
            style: TextStyle(color: context.textPrimary)),
        content: t.isRecorrente
            ? Text(
                'Esta é uma transação recorrente. Deseja excluir apenas este mês ou todos os futuros?',
                style: TextStyle(color: context.textSecondary))
            : Text('Tem certeza que deseja excluir esta transação?',
                style: TextStyle(color: context.textSecondary)),
        actions: t.isRecorrente
            ? [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text('Cancelar',
                      style: TextStyle(color: context.textSecondary)),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Só este mês',
                      style: TextStyle(color: AppColors.amber)),
                ),
                TextButton(
                  onPressed: () async {
                    await _transactionRepository.delete(t.id);
                    Navigator.pop(context, false);
                    AppState.notify();
                  },
                  child: Text('Todos', style: TextStyle(color: AppColors.red)),
                ),
              ]
            : [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text('Cancelar',
                      style: TextStyle(color: context.textSecondary)),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Excluir',
                      style: TextStyle(color: AppColors.red)),
                ),
              ],
      ),
    );

    if (confirm == true) {
      if (t.isRecorrente) {
        await _transactionRepository.deleteMonthOccurrence(
            t.id, _selectedMonth.year, _selectedMonth.month);
      } else {
        await _transactionRepository.delete(t.id);
      }
      AppState.notify();
    }
  }
}

// ─── Supporting widgets ────────────────────────────────────────

class _TotalBanner extends StatelessWidget {
  final String label;
  final double value;
  final Color color;

  _TotalBanner({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: context.appSurface,
      padding: EdgeInsets.fromLTRB(20, 16, 20, 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: TextStyle(fontSize: 13, color: context.textSecondary)),
              SizedBox(height: 4),
              Text(
                fmtBRL(value),
                style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: context.textPrimary),
              ),
            ],
          ),
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(
              color == context.primary
                  ? Icons.arrow_upward_rounded
                  : Icons.arrow_downward_rounded,
              color: color,
              size: 24,
            ),
          ),
        ],
      ),
    );
  }
}

class _DateGroup extends StatelessWidget {
  final String date;
  final List<Transacao> transactions;
  final Future<void> Function(Transacao) onDelete;
  final int ano;
  final int mes;

  const _DateGroup(
      {required this.date,
      required this.transactions,
      required this.onDelete,
      required this.ano,
      required this.mes});

  @override
  Widget build(BuildContext context) {
    // Use valorNoMes so installments and weekly recurrences show the correct month amount.
    final dayTotal =
        transactions.fold<double>(0, (s, t) => s + t.valorNoMes(ano, mes));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(0, 12, 0, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(date,
                  style: TextStyle(
                      fontSize: 12,
                      color: context.textSecondary,
                      fontWeight: FontWeight.w600)),
              Text(
                '${dayTotal >= 0 ? '+' : ''}${fmtBRL(dayTotal)}',
                style: TextStyle(
                  fontSize: 12,
                  color: dayTotal >= 0 ? context.primary : AppColors.red,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: context.appSurface,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            children: transactions.asMap().entries.map((e) {
              final t = e.value;
              final isLast = e.key == transactions.length - 1;
              return Column(
                children: [
                  _TransactionCard(
                      transacao: t,
                      onDelete: () => onDelete(t),
                      ano: ano,
                      mes: mes),
                  if (!isLast)
                    const Divider(height: 1, indent: 72, endIndent: 16),
                ],
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}

class _TransactionCard extends StatelessWidget {
  final Transacao transacao;
  final VoidCallback onDelete;
  final int ano;
  final int mes;
  _TransactionCard(
      {required this.transacao,
      required this.onDelete,
      required this.ano,
      required this.mes});

  @override
  Widget build(BuildContext context) {
    final isTransferencia = transacao.tipo == TipoTransacao.saldo;
    final isDespesa = transacao.valor < 0;
    final valColor = isTransferencia
        ? AppColors.blue
        : isDespesa
            ? AppColors.red
            : context.primary;
    final (icon, catColor) = isTransferencia
        ? (Icons.swap_horiz_rounded, AppColors.blue)
        : CategoriaHelper.get(transacao.categoria);

    return Dismissible(
      key: Key(transacao.id),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) async {
        onDelete();
        return false; // We handle deletion ourselves
      },
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: AppColors.red.withOpacity(0.15),
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Icon(Icons.delete_outline, color: AppColors.red),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: catColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Stack(
                children: [
                  Center(child: Icon(icon, color: catColor, size: 22)),
                  if (transacao.isRecorrente)
                    Positioned(
                      right: 0,
                      top: 0,
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: const BoxDecoration(
                          color: AppColors.blue,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.refresh,
                            color: Colors.white, size: 8),
                      ),
                    ),
                ],
              ),
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
                  Row(
                    children: [
                      Text(transacao.categoria,
                          style: TextStyle(
                              fontSize: 11, color: context.textSecondary)),
                      if (isTransferencia) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: AppColors.blue.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'Transferência',
                            style: TextStyle(
                                fontSize: 9,
                                color: AppColors.blue,
                                fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                      if (transacao.isRecorrente) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: AppColors.blue.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            _recLabel(transacao.recorrencia),
                            style: const TextStyle(
                                fontSize: 9,
                                color: AppColors.blue,
                                fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                      if (transacao.parcelas > 1) ...[
                        const SizedBox(width: 6),
                        Text(
                          '${transacao.parcelas}x',
                          style: const TextStyle(
                              fontSize: 10, color: AppColors.amber),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            Text(
              '${isDespesa ? '-' : '+'}${fmtBRL(transacao.valorNoMes(ano, mes).abs())}',
              style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w700, color: valColor),
            ),
          ],
        ),
      ),
    );
  }

  String _recLabel(Recorrencia r) {
    switch (r) {
      case Recorrencia.mensal:
        return 'Mensal';
      case Recorrencia.semanal:
        return 'Semanal';
      case Recorrencia.anual:
        return 'Anual';
      default:
        return '';
    }
  }
}

// ─── Enum de ordenação ─────────────────────────────────────────

enum _OrdemTransacao {
  data('Data'),
  maiorValor('Maior valor'),
  menorValor('Menor valor'),
  categoria('Categoria');

  final String label;
  const _OrdemTransacao(this.label);
}

// ─── FilterChip customizado ────────────────────────────────────

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color color;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? color.withOpacity(0.18) : context.appCardLight,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? color : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? color : context.textSecondary,
          ),
        ),
      ),
    );
  }
}