import 'package:flutter/material.dart';
import '../../data/models/conta.dart';
import '../../data/models/transaction.dart';
import '../../repositories/account_repository.dart';
import '../../repositories/transaction_repository.dart';
import '../../utils/formatters.dart';
import '../../utils/app_theme.dart';
import '../../utils/app_state.dart';
import '../../widgets/common.dart';

/// Tela de fatura do cartão de crédito.
/// Agrupa transações por mês de fatura, respeitando [diaFechamento].
class CreditInvoiceScreen extends StatefulWidget {
  final Conta conta;
  const CreditInvoiceScreen({super.key, required this.conta});

  @override
  State<CreditInvoiceScreen> createState() => _CreditInvoiceScreenState();
}

class _CreditInvoiceScreenState extends State<CreditInvoiceScreen> {
  static const _transactionRepository = TransactionRepository.instance;
  List<Transacao> _transacoes = [];
  bool _loading = true;

  // Fatura selecionada = mês de referência da fatura (data de vencimento)
  late DateTime _mesAtual;

  @override
  void initState() {
    super.initState();
    _mesAtual = _faturaAtual();
    _load();
    AppState.dataChanges.addListener(_load);
  }

  @override
  void dispose() {
    AppState.dataChanges.removeListener(_load);
    super.dispose();
  }

  /// Retorna o mês da fatura atual levando em conta o diaFechamento.
  DateTime _faturaAtual() {
    final now = DateTime.now();
    final fechamento = widget.conta.diaFechamento;
    if (fechamento != null && fechamento > 0 && now.day > fechamento) {
      return DateTime(now.year, now.month + 1);
    }
    return DateTime(now.year, now.month);
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);
    final txs = await _transactionRepository.getByAccount(widget.conta.id);
    if (!mounted) return;
    setState(() {
      _transacoes = txs;
      _loading = false;
    });
  }

  List<Transacao> get _txDaFatura {
    return _transacoes.where((t) {
      if (t.valor < 0) {
        return t.valorNoMes(_mesAtual.year, _mesAtual.month) < 0;
      } else {
        // Pagamentos: filtrar pelo mês/ano da fatura
        return t.primeiraParcela.year == _mesAtual.year &&
            t.primeiraParcela.month == _mesAtual.month;
      }
    }).toList();
  }

  List<Transacao> get _despesas =>
      _txDaFatura.where((t) => t.valor < 0).toList();
  List<Transacao> get _pagamentos =>
      _txDaFatura.where((t) => t.valor > 0).toList();

  double _valorNaFatura(Transacao t) {
    if (t.valor > 0) return t.valor;
    return t.valorNoMes(_mesAtual.year, _mesAtual.month).abs();
  }

  int? _parcelaAtual(Transacao t) {
    if (t.parcelas <= 1) return null;
    final diff = (_mesAtual.year - t.primeiraParcela.year) * 12 +
        (_mesAtual.month - t.primeiraParcela.month);
    if (diff < 0 || diff >= t.parcelas) return null;
    return diff + 1;
  }

  double get _totalDespesas =>
      _despesas.fold(0.0, (s, t) => s + _valorNaFatura(t));
  double get _totalPagamentos => _pagamentos.fold(0.0, (s, t) => s + t.valor);

  /// Saldo restante da fatura = despesas - pagamentos já efetuados (nunca negativo)
  double get _saldoFatura =>
      (_totalDespesas - _totalPagamentos).clamp(0.0, double.infinity);

  /// A fatura está fechada se a data de fechamento já passou para este mês.
  bool get _faturaFechada {
    final now = DateTime.now();
    final fechamento = widget.conta.diaFechamento;
    if (fechamento == null) return false;
    final dataFechamento =
        DateTime(_mesAtual.year, _mesAtual.month, fechamento);
    return now.isAfter(dataFechamento);
  }

  /// Pode pagar se há saldo a pagar (> 0).
  ///
  /// Regra corrigida:
  /// - Fatura ABERTA: permite pagar múltiplas vezes (novas compras podem
  ///   chegar após um pagamento parcial), desde que _saldoFatura > 0.
  /// - Fatura FECHADA: permite pagar apenas UMA vez (as compras não mudam
  ///   mais), ou seja, bloqueia se já existe pagamento registrado.
  bool get _podeRealizarPagamento {
    if (_saldoFatura <= 0) return false;
    if (_faturaFechada && _pagamentos.isNotEmpty) return false;
    return true;
  }

  /// Fatura considerada "paga" quando saldo restante é zero.
  bool get _faturaPaga => _saldoFatura <= 0 && _totalDespesas > 0;

  Color get _contaColor {
    try {
      return Color(int.parse('FF${widget.conta.cor}', radix: 16));
    } catch (_) {
      return AppColors.blue;
    }
  }

  String get _labelMes {
    const meses = [
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
      'Dezembro'
    ];
    return 'Fatura de ${meses[_mesAtual.month - 1]} ${_mesAtual.year}';
  }

  String get _labelPeriodo {
    if (widget.conta.diaFechamento == null) {
      const meses = [
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
      return '${meses[_mesAtual.month - 1]}/${_mesAtual.year}';
    }
    final fechamento = widget.conta.diaFechamento!;
    final inicioOriginal =
        DateTime(_mesAtual.year, _mesAtual.month - 1, fechamento + 1);
    final fimOriginal = DateTime(_mesAtual.year, _mesAtual.month, fechamento);
    final dInicio =
        '${inicioOriginal.day.toString().padLeft(2, '0')}/${inicioOriginal.month.toString().padLeft(2, '0')}';
    final dFim =
        '${fimOriginal.day.toString().padLeft(2, '0')}/${fimOriginal.month.toString().padLeft(2, '0')}';
    return '$dInicio a $dFim · vence dia ${widget.conta.diaVencimento ?? fechamento}';
  }

  /// Retorna um label de status descritivo para a fatura
  String get _statusLabel {
    if (_totalDespesas <= 0) return 'Sem gastos';
    if (_faturaPaga) return 'Paga';
    if (_faturaFechada) return 'Fechada – aguardando pagamento';
    return 'Em aberto';
  }

  Future<void> _pagarFatura() async {
    final pago = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => _PagarFaturaSheet(
          conta: widget.conta,
          valorFatura: _saldoFatura,
          mesVencimento: _mesAtual,
        ),
      ),
    );
    if (pago == true && mounted) {
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded,
                    color: Colors.white, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Pagamento registrado com sucesso!',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            backgroundColor: AppColors.green,
            duration: const Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.all(16),
          ),
        );
      }
    }
    AppState.notify();
  }

  @override
  Widget build(BuildContext context) {
    final cor = _contaColor;

    return Scaffold(
      backgroundColor: context.appBackground,
      body: RefreshIndicator(
        onRefresh: _load,
        color: cor,
        backgroundColor: context.appSurface,
        child: CustomScrollView(
          slivers: [
            // ── SliverAppBar com cabeçalho da fatura ──────────────
            SliverAppBar(
              expandedHeight: 380,
              pinned: true,
              backgroundColor: cor,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_ios_new,
                    size: 18, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.chevron_left, color: Colors.white),
                  tooltip: 'Mês anterior',
                  onPressed: () => setState(() {
                    _mesAtual = DateTime(_mesAtual.year, _mesAtual.month - 1);
                    _load();
                  }),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right, color: Colors.white),
                  tooltip: 'Próximo mês',
                  onPressed: () => setState(() {
                    _mesAtual = DateTime(_mesAtual.year, _mesAtual.month + 1);
                    _load();
                  }),
                ),
              ],
              flexibleSpace: FlexibleSpaceBar(
                background: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [cor, cor.withOpacity(0.7)],
                    ),
                  ),
                  child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 80, 20, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(widget.conta.nome,
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 14)),
                          const SizedBox(height: 4),
                          Text(_labelMes,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800)),
                          const SizedBox(height: 2),
                          Text(
                            _labelPeriodo,
                            style: const TextStyle(
                                color: Colors.white60, fontSize: 11),
                          ),
                          const SizedBox(height: 16),
                          // Badge de status
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _faturaPaga
                                      ? Icons.check_circle_rounded
                                      : _faturaFechada
                                          ? Icons.lock_rounded
                                          : Icons.schedule_rounded,
                                  color: Colors.white,
                                  size: 13,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  _statusLabel,
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            fmtBRL(_saldoFatura),
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 36,
                                fontWeight: FontWeight.w800),
                          ),
                          Text(
                            _saldoFatura > 0
                                ? 'valor a pagar'
                                : 'fatura quitada',
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 13),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              _HeaderChip(
                                label: 'Gastos',
                                value: fmtBRL(_totalDespesas),
                                icon: Icons.arrow_downward_rounded,
                                color: Colors.redAccent.shade100,
                              ),
                              const SizedBox(width: 12),
                              _HeaderChip(
                                label: 'Pagamentos',
                                value: fmtBRL(_totalPagamentos),
                                icon: Icons.arrow_upward_rounded,
                                color: Colors.greenAccent.shade100,
                              ),
                            ],
                          ),
                        ],
                      ),
                  ),
                ),
              ),
            ),

            // ── Status card da fatura ──────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: _FaturaStatusCard(
                  conta: widget.conta,
                  mesVencimento: _mesAtual,
                  totalFatura: _saldoFatura,
                  totalDespesas: _totalDespesas,
                  totalPagamentos: _totalPagamentos,
                  faturaPaga: _faturaPaga,
                  faturaFechada: _faturaFechada,
                  onPagar: _podeRealizarPagamento ? _pagarFatura : null,
                  cor: cor,
                ),
              ),
            ),

            // ── Seção de despesas ──────────────────────────────────
            if (!_loading) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
                  child: SectionHeader(
                    title: 'Gastos (${_despesas.length})',
                  ),
                ),
              ),
              _despesas.isEmpty
                  ? const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16),
                        child: EmptyState(
                          icon: Icons.credit_card_off_outlined,
                          title: 'Sem gastos nesta fatura',
                          subtitle:
                              'As compras realizadas neste período aparecerão aqui',
                        ),
                      ),
                    )
                  : SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (_, i) => _TxCard(
                            tx: _despesas[i],
                            valorExibido: _valorNaFatura(_despesas[i]),
                            parcelaAtual: _parcelaAtual(_despesas[i]),
                          ),
                          childCount: _despesas.length,
                        ),
                      ),
                    ),

              // ── Seção de pagamentos ────────────────────────────
              if (_pagamentos.isNotEmpty) ...[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
                    child: SectionHeader(
                      title: 'Pagamentos (${_pagamentos.length})',
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (_, i) => _TxCard(
                        tx: _pagamentos[i],
                        valorExibido: _pagamentos[i].valor.abs(),
                      ),
                      childCount: _pagamentos.length,
                    ),
                  ),
                ),
              ] else
                const SliverToBoxAdapter(child: SizedBox(height: 100)),
            ],

            if (_loading) const SliverToBoxAdapter(child: LoadingState()),
          ],
        ),
      ),
    );
  }
}

// ─── Status card da fatura ────────────────────────────────────

class _FaturaStatusCard extends StatelessWidget {
  final Conta conta;
  final DateTime mesVencimento;
  final double totalFatura;
  final double totalDespesas;
  final double totalPagamentos;
  final bool faturaPaga;
  final bool faturaFechada;
  final VoidCallback? onPagar;
  final Color cor;

  const _FaturaStatusCard({
    required this.conta,
    required this.mesVencimento,
    required this.totalFatura,
    required this.totalDespesas,
    required this.totalPagamentos,
    required this.faturaPaga,
    required this.faturaFechada,
    required this.onPagar,
    required this.cor,
  });

  @override
  Widget build(BuildContext context) {
    // Determina cor e ícone do status
    Color statusColor;
    IconData statusIcon;
    String statusText;

    if (faturaPaga) {
      statusColor = AppColors.green;
      statusIcon = Icons.check_circle_rounded;
      statusText = 'Paga';
    } else if (faturaFechada) {
      statusColor = AppColors.red;
      statusIcon = Icons.lock_rounded;
      statusText = 'Fechada';
    } else {
      statusColor = AppColors.amber;
      statusIcon = Icons.schedule_rounded;
      statusText = 'Em aberto';
    }

    return AppCard(
      child: Column(
        children: [
          // Status row
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(statusIcon, size: 14, color: statusColor),
                    const SizedBox(width: 4),
                    Text(
                      statusText,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: statusColor,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              if (conta.diaVencimento != null)
                Text(
                  'Vence dia ${conta.diaVencimento}',
                  style: TextStyle(color: context.textSecondary, fontSize: 12),
                ),
            ],
          ),

          // Mostra detalhes e botão de pagar se há valor a pagar
          if (totalFatura > 0) ...[
            const SizedBox(height: 16),
            Divider(height: 1, color: context.appDivider),
            const SizedBox(height: 16),
            // Resumo financeiro da fatura
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Limite total',
                        style: TextStyle(
                            color: context.textSecondary, fontSize: 11)),
                    Text(fmtBRL(conta.limite),
                        style: TextStyle(
                            color: context.textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w700)),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text('Já pago',
                        style: TextStyle(
                            color: context.textSecondary, fontSize: 11)),
                    Text(
                      fmtBRL(totalPagamentos),
                      style: TextStyle(
                          color: AppColors.green,
                          fontSize: 15,
                          fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('Disponível',
                        style: TextStyle(
                            color: context.textSecondary, fontSize: 11)),
                    Text(
                      fmtBRL((conta.limite - totalFatura)
                          .clamp(0, double.infinity)),
                      style: TextStyle(
                          color: context.primary,
                          fontSize: 15,
                          fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: conta.limite > 0
                    ? (totalFatura / conta.limite).clamp(0.0, 1.0)
                    : 0,
                backgroundColor: context.appCardLight,
                valueColor: AlwaysStoppedAnimation(
                  totalFatura / (conta.limite > 0 ? conta.limite : 1) > 0.8
                      ? AppColors.red
                      : cor,
                ),
                minHeight: 8,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: onPagar,
                icon: Icon(
                  onPagar != null ? Icons.payment_rounded : Icons.block_rounded,
                  size: 18,
                ),
                label: Text(
                  onPagar != null
                      ? 'Pagar fatura'
                      : (faturaFechada
                          ? 'Fatura já paga'
                          : 'Nenhum valor pendente'),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: onPagar != null ? cor : context.appCardLight,
                  foregroundColor:
                      onPagar != null ? Colors.white : context.textSecondary,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            // Nota informativa sobre fatura em aberto
            if (!faturaFechada && onPagar != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.info_outline,
                      size: 12, color: context.textSecondary),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      'Fatura em aberto: novas compras ainda podem ser adicionadas.',
                      style:
                          TextStyle(color: context.textSecondary, fontSize: 11),
                    ),
                  ),
                ],
              ),
            ],
          ],

          // Fatura quitada: mensagem positiva
          if (faturaPaga) ...[
            const SizedBox(height: 12),
            Divider(height: 1, color: context.appDivider),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.celebration_rounded,
                    size: 16, color: AppColors.green),
                const SizedBox(width: 8),
                Text(
                  'Fatura quitada! Total pago: ${fmtBRL(totalPagamentos)}',
                  style: TextStyle(
                      color: AppColors.green,
                      fontSize: 13,
                      fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Card de transação ─────────────────────────────────────────

class _TxCard extends StatelessWidget {
  final Transacao tx;
  final double valorExibido;
  final int? parcelaAtual;

  const _TxCard({
    required this.tx,
    required this.valorExibido,
    this.parcelaAtual,
  });

  @override
  Widget build(BuildContext context) {
    final isDespesa = tx.valor < 0;
    final (icon, catColor) = CategoriaHelper.get(tx.categoria);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.appSurface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: catColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: catColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tx.descricao ?? tx.categoria,
                  style: TextStyle(
                      color: context.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 14),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${tx.categoria} · ${dtFmt.format(tx.primeiraParcela)}${parcelaAtual != null ? ' · $parcelaAtual/${tx.parcelas}' : tx.parcelas > 1 ? ' · ${tx.parcelas}x' : ''}',
                  style: TextStyle(color: context.textSecondary, fontSize: 11),
                ),
              ],
            ),
          ),
          Text(
            '${isDespesa ? '-' : '+'}${fmtBRL(valorExibido)}',
            style: TextStyle(
              color: isDespesa ? AppColors.red : AppColors.green,
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Header chip ──────────────────────────────────────────────

class _HeaderChip extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _HeaderChip({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.15),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(color: Colors.white70, fontSize: 10)),
                  Text(value,
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 13),
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Sheet para pagar fatura ───────────────────────────────────

class _PagarFaturaSheet extends StatefulWidget {
  final Conta conta;
  final double valorFatura;
  final DateTime mesVencimento;
  const _PagarFaturaSheet(
      {required this.conta,
      required this.valorFatura,
      required this.mesVencimento});

  @override
  State<_PagarFaturaSheet> createState() => _PagarFaturaSheetState();
}

class _PagarFaturaSheetState extends State<_PagarFaturaSheet> {
  static const _accountRepository = AccountRepository.instance;
  static const _transactionRepository = TransactionRepository.instance;
  List<Conta> _contas = [];
  String? _origemId;
  bool _saving = false;
  late TextEditingController _valorCtrl;

  @override
  void initState() {
    super.initState();
    _valorCtrl = TextEditingController(
        text: widget.valorFatura.toStringAsFixed(2).replaceAll('.', ','));
    _loadContas();
  }

  @override
  void dispose() {
    _valorCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadContas() async {
    final c = await _accountRepository.getAll();
    setState(() {
      _contas = c.where((ct) => ct.tipo != 'credito').toList();
      if (_contas.isNotEmpty) _origemId = _contas.first.id;
    });
  }

  Future<void> _pagar() async {
    if (_origemId == null) return;
    final valorPagar = double.tryParse(_valorCtrl.text.replaceAll(',', '.')) ??
        widget.valorFatura;
    if (valorPagar <= 0) return;

    setState(() => _saving = true);

    const meses = [
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
      'Dezembro'
    ];
    final mesTxt =
        '${meses[widget.mesVencimento.month - 1]}/${widget.mesVencimento.year}';
    final grupoId = 'pgto_fatura_${DateTime.now().millisecondsSinceEpoch}';

    final diaVenc =
        widget.conta.diaVencimento ?? widget.conta.diaFechamento ?? 1;
    final dataPagamento = DateTime(
      widget.mesVencimento.year,
      widget.mesVencimento.month,
      diaVenc,
    );

    // Saída da conta corrente
    final saida = Transacao(
      valor: -valorPagar,
      banco: _origemId!,
      parcelas: 1,
      primeiraParcela: dataPagamento,
      categoria: 'Transferência',
      tipo: TipoTransacao.saldo,
      descricao: 'Pgto fatura ${widget.conta.nome} $mesTxt',
      recorrencia: Recorrencia.nenhuma,
      recorrenciaGrupoId: grupoId,
    );
    // Entrada no cartão (reduz a fatura)
    final entrada = Transacao(
      valor: valorPagar,
      banco: widget.conta.id,
      parcelas: 1,
      primeiraParcela: dataPagamento,
      categoria: 'Transferência',
      tipo: TipoTransacao.saldo,
      descricao: 'Pgto fatura ${widget.conta.nome} $mesTxt',
      recorrencia: Recorrencia.nenhuma,
      recorrenciaGrupoId: grupoId,
    );

    await _transactionRepository.insertTransfer(saida: saida, entrada: entrada);

    setState(() => _saving = false);
    AppState.notify();
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.appBackground,
      appBar: AppBar(
        backgroundColor: context.appSurface,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new,
              size: 18, color: context.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Pagar fatura',
            style: TextStyle(
                color: context.textPrimary, fontWeight: FontWeight.w700)),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Resumo do valor ──────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: context.appSurface,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  Text('Valor a pagar',
                      style: TextStyle(
                          color: context.textSecondary, fontSize: 13)),
                  const SizedBox(height: 8),
                  // Campo editável para permitir pagamento parcial
                  TextField(
                    controller: _valorCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: context.textPrimary,
                        fontSize: 34,
                        fontWeight: FontWeight.w800),
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      prefixText: 'R\$ ',
                      prefixStyle: TextStyle(
                          color: context.textSecondary,
                          fontSize: 18,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(widget.conta.nome,
                      style: TextStyle(
                          color: context.textSecondary, fontSize: 13)),
                  const SizedBox(height: 4),
                  Text(
                    'Total da fatura: ${fmtBRL(widget.valorFatura)}',
                    style:
                        TextStyle(color: context.textSecondary, fontSize: 11),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // ── Seleção de conta de origem ────────────────────────
            Text('Pagar com',
                style: TextStyle(
                    color: context.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            if (_contas.isEmpty)
              AppCard(
                child: EmptyState(
                  icon: Icons.account_balance_wallet_outlined,
                  title: 'Nenhuma conta disponível',
                  subtitle:
                      'Cadastre uma conta corrente ou poupança para pagar a fatura',
                ),
              )
            else
              ..._contas.map((c) {
                Color cor;
                try {
                  cor = Color(int.parse('FF${c.cor}', radix: 16));
                } catch (_) {
                  cor = AppColors.blue;
                }
                final selected = _origemId == c.id;
                return GestureDetector(
                  onTap: () => setState(() => _origemId = c.id),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color:
                          selected ? cor.withOpacity(0.1) : context.appSurface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: selected ? cor : context.appDivider,
                        width: 1.5,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                              color: cor.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(10)),
                          child: Icon(Icons.account_balance_wallet_rounded,
                              color: cor, size: 20),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(c.nome,
                                  style: TextStyle(
                                      color: context.textPrimary,
                                      fontWeight: FontWeight.w600)),
                              Text('Saldo: ${fmtBRL(c.saldo)}',
                                  style: TextStyle(
                                      color: context.textSecondary,
                                      fontSize: 12)),
                            ],
                          ),
                        ),
                        if (selected)
                          Icon(Icons.check_circle_rounded,
                              color: cor, size: 20),
                      ],
                    ),
                  ),
                );
              }),
            const Spacer(),
            GradientButton(
              label: 'Confirmar pagamento',
              onPressed: (_saving || _origemId == null) ? null : _pagar,
              loading: _saving,
              icon: Icons.check_rounded,
            ),
          ],
        ),
      ),
    );
  }
}