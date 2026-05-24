import 'package:flutter/material.dart';
import '../../data/models/conta.dart';
import '../../data/models/transaction.dart';
import '../../repositories/account_repository.dart';
import '../../repositories/transaction_repository.dart';
import '../../utils/formatters.dart';
import '../../utils/app_theme.dart';
import '../../utils/app_state.dart';
import '../../utils/bottom_sheet_helper.dart';
import '../../widgets/common.dart';
import 'credit_invoice_screen.dart';
import '../transactions/transfer_screen.dart';

class AccountsScreen extends StatefulWidget {
  const AccountsScreen({super.key});

  @override
  State<AccountsScreen> createState() => _AccountsScreenState();
}

class _AccountsScreenState extends State<AccountsScreen> {
  static const _accountRepository = AccountRepository.instance;
  List<Conta> _contas = [];
  bool _loading = true;
  String? _error;
  late bool _balanceVisible;
  bool _hasLocalBalanceOverride = false;

  @override
  void initState() {
    super.initState();
    _balanceVisible = AppState.instance.balanceVisible;
    _load();
    AppState.dataChanges.addListener(_load);
    AppState.instance.addListener(_syncGlobalBalanceVisibility);
  }

  @override
  void dispose() {
    AppState.dataChanges.removeListener(_load);
    AppState.instance.removeListener(_syncGlobalBalanceVisibility);
    super.dispose();
  }

  void _syncGlobalBalanceVisibility() {
    if (_hasLocalBalanceOverride || !mounted) return;
    setState(() => _balanceVisible = AppState.instance.balanceVisible);
  }

  void _toggleBalanceVisibility() {
    setState(() {
      _hasLocalBalanceOverride = true;
      _balanceVisible = !_balanceVisible;
    });
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final c = await _accountRepository.getAll();
      if (!mounted) return;
      setState(() {
        _contas = c;
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

  double get _totalPatrimonio =>
      _contas.fold<double>(0, (s, c) => c.tipo == 'credito' ? s : s + c.saldo);

  double get _totalLimitesCredito => _contas
      .where((c) => c.tipo == 'credito')
      .fold<double>(0, (s, c) => s + c.limite);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.appBackground,
      body: _loading
          ? const LoadingState()
          : _error != null
              ? ErrorState(
                  message: _error,
                  onRetry: _load,
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  color: context.primary,
                  backgroundColor: context.appSurface,
                  child: CustomScrollView(
                    slivers: [
                      SliverAppBar(
                        backgroundColor: context.appBackground,
                        leading: IconButton(
                          icon: Icon(Icons.arrow_back_ios_new,
                              size: 18, color: context.textPrimary),
                          onPressed: () => Navigator.canPop(context)
                              ? Navigator.pop(context)
                              : null,
                        ),
                        title: Text('Minhas contas',
                            style: TextStyle(color: context.textPrimary)),
                        actions: [
                          IconButton(
                            icon: Icon(
                              _balanceVisible
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                              color: context.textSecondary,
                            ),
                            onPressed: _toggleBalanceVisibility,
                          ),
                          IconButton(
                            icon: Icon(Icons.swap_horiz_rounded,
                                color: context.textSecondary),
                            tooltip: 'Transferência',
                            onPressed: () async {
                              await Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) => const TransferScreen()),
                              );
                              AppState.notify();
                            },
                          ),
                          IconButton(
                            icon: Icon(Icons.add, color: context.primary),
                            onPressed: _addConta,
                          ),
                        ],
                        pinned: true,
                      ),
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                        sliver: SliverList(
                          delegate: SliverChildListDelegate([
                            _buildTotalCard(),
                            const SizedBox(height: 20),
                            if (_contas.isEmpty) ...[
                              AppCard(
                                child: EmptyState(
                                  icon: Icons.account_balance_wallet_outlined,
                                  title: 'Nenhuma conta cadastrada',
                                  subtitle:
                                      'Toque em + para adicionar sua primeira conta ou cartão',
                                  accentColor: AppColors.blue,
                                ),
                              ),
                            ] else ...[
                              if (_contas.any((c) => c.tipo == 'credito')) ...[
                                SectionHeader(title: 'Cartões de crédito'),
                                const SizedBox(height: 12),
                                ..._contas
                                    .where((c) => c.tipo == 'credito')
                                    .map((c) => Padding(
                                          padding:
                                              const EdgeInsets.only(bottom: 12),
                                          child: _ContaCard(
                                            conta: c,
                                            visible: _balanceVisible,
                                            canManage: !_accountRepository
                                                .isManagedBalanceAccount(c),
                                            onTap: () => _openDetail(c),
                                            onEdit: () => _editConta(c),
                                            onDelete: () => _deleteConta(c),
                                          ),
                                        )),
                              ],
                              if (_contas.any((c) => c.tipo != 'credito')) ...[
                                const SizedBox(height: 8),
                                SectionHeader(title: 'Contas e carteiras'),
                                const SizedBox(height: 12),
                                ..._contas
                                    .where((c) => c.tipo != 'credito')
                                    .map((c) => Padding(
                                          padding:
                                              const EdgeInsets.only(bottom: 12),
                                          child: _ContaCard(
                                            conta: c,
                                            visible: _balanceVisible,
                                            canManage: !_accountRepository
                                                .isManagedBalanceAccount(c),
                                            onTap: () => _openDetail(c),
                                            onEdit: () => _editConta(c),
                                            onDelete: () => _deleteConta(c),
                                          ),
                                        )),
                              ],
                            ],
                          ]),
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }

  Widget _buildTotalCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.blue, context.primary],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.blue.withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Patrimônio total',
              style: TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(height: 8),
          Text(
            _balanceVisible ? fmtBRL(_totalPatrimonio) : 'R\$ ••••••',
            style: const TextStyle(
                color: Colors.white, fontSize: 30, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _TotalChip(
                  label: 'Limites de crédito',
                  value:
                      _balanceVisible ? fmtBRL(_totalLimitesCredito) : '••••',
                  icon: Icons.credit_card_outlined,
                ),
              ),
              Expanded(
                child: _TotalChip(
                  label: 'Contas',
                  value: '${_contas.length}',
                  icon: Icons.account_balance_wallet_outlined,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _openDetail(Conta c) {
    if (c.tipo == 'credito') {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => CreditInvoiceScreen(conta: c)),
      ).then((_) => AppState.notify());
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => AccountDetailScreen(conta: c)),
      ).then((_) => AppState.notify());
    }
  }

  Future<void> _addConta() async {
    await _showContaForm(null);
    AppState.notify();
  }

  Future<void> _editConta(Conta c) async {
    if (_accountRepository.isManagedBalanceAccount(c)) return;
    await _showContaForm(c);
    AppState.notify();
  }

  Future<void> _deleteConta(Conta c) async {
    if (_accountRepository.isManagedBalanceAccount(c)) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: context.appSurface,
        title:
            Text('Excluir conta', style: TextStyle(color: context.textPrimary)),
        content: Text(
          'Excluir "${c.nome}"? As transações associadas serão mantidas.',
          style: TextStyle(color: context.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancelar',
                style: TextStyle(color: context.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Excluir', style: TextStyle(color: AppColors.red)),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _accountRepository.delete(c.id);
      AppState.notify();
    }
  }

  Future<void> _showContaForm(Conta? editando) async {
    await context.showAppBottomSheet(
      isScrollControlled: true,
      builder: (_) => _ContaFormSheet(editando: editando),
    );
  }

  String _tipoLabel(String t) {
    switch (t) {
      case 'credito':
        return 'Crédito';
      case 'corrente':
        return 'Corrente';
      case 'poupanca':
        return 'Poupança';
      case 'investimento':
        return 'Investimento';
      case 'beneficio':
        return 'Benefício';
      default:
        return t;
    }
  }
}

// ─── Conta form sheet (StatefulWidget) ────────────────────────

class _ContaFormSheet extends StatefulWidget {
  final Conta? editando;
  const _ContaFormSheet({this.editando});

  @override
  State<_ContaFormSheet> createState() => _ContaFormSheetState();
}

class _ContaFormSheetState extends State<_ContaFormSheet> {
  static const _accountRepository = AccountRepository.instance;
  late final TextEditingController nomeCtrl;
  late final TextEditingController limiteCtrl;
  late final TextEditingController saldoCtrl;
  late String tipo;
  BancoInfo? bancoSelecionado;
  int? diaVencimento;
  int? diaFechamento;

  @override
  void initState() {
    super.initState();
    final e = widget.editando;
    nomeCtrl = TextEditingController(text: e?.nome ?? '');
    limiteCtrl = TextEditingController(
        text: e != null && e.limite > 0
            ? e.limite.toStringAsFixed(2).replaceAll('.', ',')
            : '');
    // Use saldoInicial (opening balance) in the form, not saldo (computed).
    // Editing with saldo would let the computed value overwrite the initial balance.
    saldoCtrl = TextEditingController(
        text: e != null && e.saldoInicial > 0
            ? e.saldoInicial.toStringAsFixed(2).replaceAll('.', ',')
            : '');
    tipo = e?.tipo ?? 'corrente';
    diaVencimento = e?.diaVencimento;
    diaFechamento = e?.diaFechamento;
    if (e?.icone != null) {
      try {
        bancoSelecionado =
            bancosConhecidos.firstWhere((b) => b.icone == e!.icone);
      } catch (_) {
        bancoSelecionado = null;
      }
    }
  }

  @override
  void dispose() {
    nomeCtrl.dispose();
    limiteCtrl.dispose();
    saldoCtrl.dispose();
    super.dispose();
  }

  String _tipoLabel(String t) {
    switch (t) {
      case 'credito':
        return 'Crédito';
      case 'corrente':
        return 'Corrente';
      case 'poupanca':
        return 'Poupança';
      case 'investimento':
        return 'Investimento';
      case 'beneficio':
        return 'Benefício';
      default:
        return t;
    }
  }

  void _onBancoTap(BancoInfo b) {
    setState(() {
      bancoSelecionado = b;
      final isOutros = b.icone == 'outros';
      if (isOutros) {
        final isKnownName = bancosConhecidos
            .where((kb) => kb.icone != 'outros')
            .any((kb) => kb.nome == nomeCtrl.text);
        if (isKnownName) nomeCtrl.text = '';
      } else {
        nomeCtrl.text = b.nome;
      }
    });
  }

  Future<void> _salvar() async {
    final nomeTexto = nomeCtrl.text.trim();
    if (nomeTexto.isEmpty) return;

    final limite = double.tryParse(limiteCtrl.text.replaceAll(',', '.')) ?? 0;
    final saldo = double.tryParse(saldoCtrl.text.replaceAll(',', '.')) ?? 0;

    final e = widget.editando;
    // When editing, preserve the original saldoInicial unless the user
    // explicitly changes the saldo field (for non-credit accounts).
    // For new accounts, saldoInicial = saldo entered by user.
    // When editing, always keep the original saldoInicial (opening balance).
    // Using e.saldo as fallback was wrong: it would overwrite saldoInicial with
    // the computed balance, breaking future recalculations.
    final saldoInicial = e != null
        ? (tipo == 'credito' ? 0.0 : e.saldoInicial)
        : (tipo == 'credito' ? 0.0 : saldo);

    final conta = Conta(
      id: e?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
      nome: nomeTexto,
      limite: limite,
      saldo: tipo == 'credito' ? (e?.saldo ?? 0) : saldo,
      saldoInicial: saldoInicial,
      tipo: tipo,
      cor: bancoSelecionado?.cor ?? '3B82F6',
      icone: bancoSelecionado?.icone,
      diaVencimento: tipo == 'credito' ? diaVencimento : null,
      diaFechamento: tipo == 'credito' ? diaFechamento : null,
    );

    if (e != null) {
      await _accountRepository.save(conta, isUpdate: true);
    } else {
      await _accountRepository.save(conta);
    }
    if (mounted) Navigator.pop(context);
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
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: context.textSecondary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              widget.editando != null ? 'Editar conta' : 'Nova conta',
              style: TextStyle(
                color: context.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 20),

            // Banco picker
            Text('Banco / Instituição',
                style: TextStyle(color: context.textSecondary, fontSize: 13)),
            const SizedBox(height: 8),
            SizedBox(
              height: 80,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: bancosConhecidos.length,
                itemBuilder: (_, i) {
                  final b = bancosConhecidos[i];
                  final sel = bancoSelecionado?.icone == b.icone;
                  final cor = Color(int.parse('FF${b.cor}', radix: 16));
                  return GestureDetector(
                    onTap: () => _onBancoTap(b),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color:
                            sel ? cor.withOpacity(0.25) : context.appCardLight,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: sel ? cor : Colors.transparent,
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 30,
                            height: 30,
                            decoration: BoxDecoration(
                              color: cor.withOpacity(0.2),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(Icons.account_balance,
                                size: 16, color: cor),
                          ),
                          const SizedBox(height: 4),
                          Text(b.nome,
                              style: TextStyle(
                                  color: context.textPrimary, fontSize: 9)),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),

            // Nome
            _TextInput(ctrl: nomeCtrl, label: 'Nome da conta'),
            const SizedBox(height: 12),

            // Tipo
            Text('Tipo',
                style: TextStyle(color: context.textSecondary, fontSize: 13)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                'credito',
                'corrente',
                'poupanca',
                'investimento',
                'beneficio'
              ].map((t) {
                final sel = tipo == t;
                return GestureDetector(
                  onTap: () => setState(() => tipo = t),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    margin: const EdgeInsets.only(bottom: 8),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: sel
                          ? AppColors.blue.withOpacity(0.2)
                          : context.appCardLight,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: sel ? AppColors.blue : Colors.transparent,
                      ),
                    ),
                    child: Text(
                      _tipoLabel(t),
                      style: TextStyle(
                        color: sel ? AppColors.blue : context.textSecondary,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 12),

            // Campos extras para crédito
            if (tipo == 'credito') ...[
              _TextInput(
                  ctrl: limiteCtrl, label: 'Limite (R\%)', isNumber: true),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _DayPickerField(
                      label: 'Dia de fechamento',
                      value: diaFechamento,
                      onChanged: (v) => setState(() {
                        diaFechamento = v;
                      }),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _DayPickerField(
                      label: 'Dia de vencimento',
                      value: diaVencimento,
                      onChanged: (v) => setState(() => diaVencimento = v),
                    ),
                  ),
                ],
              ),
            ],

            if (tipo != 'credito')
              _TextInput(
                  ctrl: saldoCtrl, label: 'Saldo atual (R\%)', isNumber: true),
            const SizedBox(height: 24),
            GradientButton(
              label: widget.editando != null ? 'Salvar' : 'Adicionar conta',
              onPressed: _salvar,
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Day picker field (sem validação de minDay) ─────────────────

class _DayPickerField extends StatelessWidget {
  final String label;
  final int? value;
  final ValueChanged<int?> onChanged;

  const _DayPickerField({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(color: context.textSecondary, fontSize: 13)),
        const SizedBox(height: 6),
        GestureDetector(
          onTap: () async {
            await context.showAppBottomSheet(
              radius: 20,
              builder: (sheetCtx) => Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: TextStyle(
                            color: context.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 200,
                      child: GridView.builder(
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 7,
                          mainAxisSpacing: 8,
                          crossAxisSpacing: 8,
                          childAspectRatio: 1,
                        ),
                        itemCount: 31,
                        itemBuilder: (ctx, i) {
                          final day = i + 1;
                          final isSelected = value == day;
                          return GestureDetector(
                            onTap: () {
                              onChanged(day);
                              Navigator.pop(sheetCtx);
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? AppColors.blue
                                    : context.appCardLight,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                '$day',
                                style: TextStyle(
                                  color: isSelected
                                      ? Colors.white
                                      : context.textPrimary,
                                  fontSize: 13,
                                  fontWeight: isSelected
                                      ? FontWeight.w700
                                      : FontWeight.normal,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (value != null)
                      TextButton(
                        onPressed: () {
                          onChanged(null);
                          Navigator.pop(sheetCtx);
                        },
                        child: Text('Limpar',
                            style: TextStyle(color: context.textSecondary)),
                      ),
                  ],
                ),
              ),
            );
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: context.appCardLight,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  value != null ? 'Dia $value' : 'Selecionar',
                  style: TextStyle(
                    color: value != null
                        ? context.textPrimary
                        : context.textSecondary,
                    fontSize: 14,
                  ),
                ),
                Icon(Icons.keyboard_arrow_down,
                    color: context.textSecondary, size: 18),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Account detail ────────────────────────────────────────────

class AccountDetailScreen extends StatefulWidget {
  final Conta conta;
  const AccountDetailScreen({super.key, required this.conta});

  @override
  State<AccountDetailScreen> createState() => _AccountDetailScreenState();
}

class _AccountDetailScreenState extends State<AccountDetailScreen> {
  static const _accountRepository = AccountRepository.instance;
  static const _transactionRepository = TransactionRepository.instance;
  List<Transacao> _transacoes = [];
  bool _loading = true;
  late Conta _conta;

  @override
  void initState() {
    super.initState();
    _conta = widget.conta;
    _load();
    AppState.dataChanges.addListener(_load);
  }

  @override
  void dispose() {
    AppState.dataChanges.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);
    // Recarrega os dados da conta para refletir saldo atualizado
    final contas = await _accountRepository.getAll();
    final contaAtualizada =
        contas.where((c) => c.id == widget.conta.id).firstOrNull;
    final t = await _transactionRepository.getByAccount(widget.conta.id);
    if (!mounted) return;
    setState(() {
      if (contaAtualizada != null) _conta = contaAtualizada;
      _transacoes = t;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = _conta;
    Color color;
    try {
      color = Color(int.parse('FF${c.cor}', radix: 16));
    } catch (_) {
      color = AppColors.blue;
    }
    return Scaffold(
      backgroundColor: context.appBackground,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 220,
            pinned: true,
            backgroundColor: context.appBackground,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new,
                  size: 18, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [color, color.withOpacity(0.6)],
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 80, 20, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(c.nome,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.w800)),
                      Text(_tipoLabel(c.tipo),
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 14)),
                      const SizedBox(height: 16),
                      Text(
                        fmtBRL(c.tipo == 'credito' ? c.disponivel : c.saldo),
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 32,
                            fontWeight: FontWeight.w800),
                      ),
                      Text(c.tipo == 'credito' ? 'disponível' : 'saldo atual',
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 13)),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (c.tipo == 'credito')
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: _CreditInfo(conta: c, color: color),
              ),
            ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: SectionHeader(title: 'Histórico'),
            ),
          ),
          _loading
              ? const SliverToBoxAdapter(child: LoadingState())
              : _transacoes.isEmpty
                  ? SliverToBoxAdapter(
                      child: EmptyState(
                        icon: Icons.receipt_long_outlined,
                        title: 'Nenhuma transação',
                        subtitle: 'As transações desta conta aparecerão aqui',
                        accentColor: AppColors.blue,
                      ),
                    )
                  : SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (_, i) {
                            final t = _transacoes[i];
                            final isDespesa = t.valor < 0;
                            final color =
                                isDespesa ? AppColors.red : context.primary;
                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: context.appSurface,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(t.descricao ?? t.categoria,
                                            style: TextStyle(
                                                color: context.textPrimary,
                                                fontWeight: FontWeight.w600)),
                                        Text(dtFmt.format(t.primeiraParcela),
                                            style: TextStyle(
                                                color: context.textSecondary,
                                                fontSize: 12)),
                                      ],
                                    ),
                                  ),
                                  Text(
                                    '${isDespesa ? '-' : '+'}${fmtBRL(t.valor.abs())}',
                                    style: TextStyle(
                                        color: color,
                                        fontWeight: FontWeight.w700),
                                  ),
                                ],
                              ),
                            );
                          },
                          childCount: _transacoes.length,
                        ),
                      ),
                    ),
        ],
      ),
    );
  }

  String _tipoLabel(String t) {
    switch (t) {
      case 'credito':
        return 'Cartão de crédito';
      case 'corrente':
        return 'Conta corrente';
      case 'poupanca':
        return 'Poupança';
      case 'investimento':
        return 'Investimentos';
      default:
        return t;
    }
  }
}

class _CreditInfo extends StatelessWidget {
  final Conta conta;
  final Color color;
  const _CreditInfo({required this.conta, required this.color});

  @override
  Widget build(BuildContext context) {
    final pct = conta.percentUsed;
    return AppCard(
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _InfoItem(label: 'Limite total', value: fmtBRL(conta.limite)),
              _InfoItem(label: 'Utilizado', value: fmtBRL(conta.saldo)),
              _InfoItem(label: 'Disponível', value: fmtBRL(conta.disponivel)),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: pct,
              backgroundColor: context.appCardLight,
              valueColor: AlwaysStoppedAnimation(
                pct > 0.8
                    ? AppColors.red
                    : pct > 0.5
                        ? AppColors.amber
                        : color,
              ),
              minHeight: 8,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('${(pct * 100).toStringAsFixed(0)}% utilizado',
                  style: TextStyle(color: context.textSecondary, fontSize: 12)),
              Text(
                pct > 0.8
                    ? 'Limite crítico'
                    : pct > 0.5
                        ? 'Atenção'
                        : 'Limite saudável',
                style: TextStyle(
                  fontSize: 12,
                  color: pct > 0.8
                      ? AppColors.red
                      : pct > 0.5
                          ? AppColors.amber
                          : context.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          if (conta.diaFechamento != null || conta.diaVencimento != null) ...[
            const SizedBox(height: 12),
            Divider(height: 1, color: context.appCardLight),
            const SizedBox(height: 12),
            Row(
              children: [
                if (conta.diaFechamento != null)
                  Expanded(
                    child: _InfoItem(
                        label: 'Fechamento',
                        value: 'Dia ${conta.diaFechamento}'),
                  ),
                if (conta.diaVencimento != null)
                  Expanded(
                    child: _InfoItem(
                        label: 'Vencimento',
                        value: 'Dia ${conta.diaVencimento}'),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _InfoItem extends StatelessWidget {
  final String label;
  final String value;
  const _InfoItem({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(color: context.textSecondary, fontSize: 11)),
        const SizedBox(height: 2),
        Text(value,
            style: TextStyle(
                color: context.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w700)),
      ],
    );
  }
}

class _TotalChip extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  const _TotalChip(
      {required this.label, required this.value, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: Colors.white60, size: 14),
            const SizedBox(width: 4),
            Text(label,
                style: const TextStyle(color: Colors.white60, fontSize: 11)),
          ],
        ),
        const SizedBox(height: 2),
        Text(value,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w700)),
      ],
    );
  }
}

class _ContaCard extends StatelessWidget {
  final Conta conta;
  final bool visible;
  final bool canManage;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  const _ContaCard({
    required this.conta,
    required this.visible,
    required this.canManage,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  Color get _color {
    try {
      return Color(int.parse('FF${conta.cor}', radix: 16));
    } catch (_) {
      return AppColors.blue;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isCredit = conta.tipo == 'credito';
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: context.appSurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _color.withOpacity(0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: _color.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    isCredit
                        ? Icons.credit_card_rounded
                        : Icons.account_balance_wallet_rounded,
                    color: _color,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(conta.nome,
                          style: TextStyle(
                              color: context.textPrimary,
                              fontSize: 16,
                              fontWeight: FontWeight.w700)),
                      Text(_tipoLabel(conta.tipo),
                          style: TextStyle(
                              color: context.textSecondary, fontSize: 12)),
                    ],
                  ),
                ),
                if (canManage)
                  PopupMenuButton<String>(
                    color: context.appCardLight,
                    icon: Icon(Icons.more_vert, color: context.textSecondary),
                    onSelected: (v) {
                      if (v == 'edit') onEdit();
                      if (v == 'delete') onDelete();
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: 'edit',
                        child: Row(children: [
                          Icon(Icons.edit_outlined,
                              color: context.textSecondary, size: 18),
                          const SizedBox(width: 8),
                          Text('Editar',
                              style: TextStyle(color: context.textPrimary)),
                        ]),
                      ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Row(children: [
                          Icon(Icons.delete_outline,
                              color: AppColors.red, size: 18),
                          SizedBox(width: 8),
                          Text('Excluir',
                              style: TextStyle(color: AppColors.red)),
                        ]),
                      ),
                    ],
                  )
                else
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: context.appCardLight,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Sistema',
                      style: TextStyle(
                        color: context.textSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              isCredit ? 'Disponível' : 'Saldo',
              style: TextStyle(color: context.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 2),
            Text(
              visible
                  ? fmtBRL(isCredit ? conta.disponivel : conta.saldo)
                  : 'R\$ ••••••',
              style: TextStyle(
                  color: context.textPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.w800),
            ),
            if (isCredit) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: conta.percentUsed,
                  backgroundColor: context.appCardLight,
                  valueColor: AlwaysStoppedAnimation(
                    conta.percentUsed > 0.8
                        ? AppColors.red
                        : conta.percentUsed > 0.5
                            ? AppColors.amber
                            : _color,
                  ),
                  minHeight: 6,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    visible
                        ? 'Utilizado: ${fmtBRL(conta.saldo)}'
                        : 'Utilizado: ••••',
                    style:
                        TextStyle(color: context.textSecondary, fontSize: 12),
                  ),
                  Text(
                    visible ? 'Limite: ${fmtBRL(conta.limite)}' : '••••',
                    style:
                        TextStyle(color: context.textSecondary, fontSize: 12),
                  ),
                ],
              ),
              if (conta.diaFechamento != null ||
                  conta.diaVencimento != null) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    if (conta.diaFechamento != null) ...[
                      Icon(Icons.lock_clock_outlined,
                          size: 12, color: context.textSecondary),
                      const SizedBox(width: 4),
                      Text('Fecha dia ${conta.diaFechamento}',
                          style: TextStyle(
                              color: context.textSecondary, fontSize: 11)),
                      const SizedBox(width: 10),
                    ],
                    if (conta.diaVencimento != null) ...[
                      Icon(Icons.event_outlined,
                          size: 12, color: context.textSecondary),
                      const SizedBox(width: 4),
                      Text('Vence dia ${conta.diaVencimento}',
                          style: TextStyle(
                              color: context.textSecondary, fontSize: 11)),
                    ],
                  ],
                ),
              ],
              const SizedBox(height: 12),
              // Botão de acesso rápido à fatura
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: onTap,
                  icon:
                      Icon(Icons.receipt_long_rounded, size: 16, color: _color),
                  label: Text('Ver fatura',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: _color)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _color,
                    side: BorderSide(color: _color.withOpacity(0.4)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _tipoLabel(String t) {
    switch (t) {
      case 'credito':
        return 'Cartão de crédito';
      case 'corrente':
        return 'Conta corrente';
      case 'poupanca':
        return 'Poupança';
      case 'investimento':
        return 'Investimentos';
      case 'beneficio':
        return 'Benefício';
      default:
        return t;
    }
  }
}

class _TextInput extends StatelessWidget {
  final TextEditingController ctrl;
  final String label;
  final bool isNumber;
  const _TextInput(
      {required this.ctrl, required this.label, this.isNumber = false});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(color: context.textSecondary, fontSize: 13)),
        const SizedBox(height: 6),
        TextField(
          controller: ctrl,
          keyboardType: isNumber ? TextInputType.number : TextInputType.text,
          style: TextStyle(color: context.textPrimary),
          decoration: InputDecoration(
            fillColor: context.appCardLight,
            filled: true,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
        ),
      ],
    );
  }
}
