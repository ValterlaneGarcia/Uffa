import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../data/models/transaction.dart';
import '../../data/models/conta.dart';
import '../../repositories/account_repository.dart';
import '../../repositories/category_repository.dart';
import '../../repositories/transaction_repository.dart';
import '../../utils/formatters.dart';
import '../../utils/app_theme.dart';
import '../../utils/app_state.dart';
import '../../widgets/common.dart';

class AddTransactionScreen extends StatefulWidget {
  final bool initialIsDespesa;
  final Transacao? editando;

  const AddTransactionScreen({
    super.key,
    this.initialIsDespesa = true,
    this.editando,
  });

  @override
  State<AddTransactionScreen> createState() => _AddTransactionScreenState();
}

class _AddTransactionScreenState extends State<AddTransactionScreen> {
  static const _accountRepository = AccountRepository.instance;
  static const _categoryRepository = CategoryRepository.instance;
  static const _transactionRepository = TransactionRepository.instance;
  late bool _isDespesa;
  bool _isTransferencia = false;
  String? _contaDestinoId;
  final _valorCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  DateTime _date = DateTime.now();
  DateTime _recurrenceDate = DateTime.now();
  String _categoria = 'Alimentação';
  String? _contaId;
  Recorrencia _recorrencia = Recorrencia.nenhuma;
  int _parcelas = 1;
  bool _saving = false;
  List<Conta> _contas = [];
  List<Map<String, dynamic>> _categoriaRows = [];

  Conta? get _contaSelecionada =>
      _contas.where((c) => c.id == _contaId).firstOrNull;
  bool get _contaSelecionadaEhCredito => _contaSelecionada?.tipo == 'credito';

  @override
  void initState() {
    super.initState();
    _isDespesa = widget.initialIsDespesa;
    if (widget.editando != null) {
      final t = widget.editando!;
      _isDespesa = t.valor < 0;
      _valorCtrl.text = t.valor.abs().toStringAsFixed(2).replaceAll('.', ',');
      _descCtrl.text = t.descricao ?? '';
      _date = t.primeiraParcela;
      _recurrenceDate = t.recorrenciaDataBase ?? t.primeiraParcela;
      _categoria = t.categoria;
      _contaId = t.banco;
      _recorrencia = t.recorrencia;
      _parcelas = t.parcelas;
    }
    _loadContas();
    _loadCategorias();
  }

  Future<void> _loadCategorias() async {
    final rows = await _categoryRepository.getAll();
    if (mounted) {
      setState(() => _categoriaRows = rows);
      CategoriaHelper.loadFromRows(rows);
    }
  }

  Future<void> _loadContas() async {
    final c = await _accountRepository.getAll();
    setState(() {
      _contas = c;
      // For income (receita), credit accounts are not allowed
      // Set default account: if receita, skip credit accounts
      if (_contaId == null) {
        final contasValidas =
            _isDespesa ? c : c.where((ct) => ct.tipo != 'credito').toList();
        _contaId = contasValidas.isNotEmpty ? contasValidas.first.id : null;
      }
      if (!_contaSelecionadaEhCredito) {
        _parcelas = 1;
      }
    });
  }

  /// Returns only the accounts valid for the current transaction type.
  /// Credit accounts cannot receive income or be origin of transfers.
  List<Conta> get _contasValidas {
    if (_isTransferencia) {
      // Transferência: origem não pode ser cartão de crédito
      return _contas.where((c) => c.tipo != 'credito').toList();
    }
    if (_isDespesa) return _contas;
    return _contas.where((c) => c.tipo != 'credito').toList();
  }

  /// If the currently selected account is a credit account and the user
  /// switches to income mode, clear the selection.
  void _onToggleTipo(bool isDespesa) {
    setState(() {
      _isDespesa = isDespesa;
      _isTransferencia = false;
      // Always reset recorrencia when switching type to avoid unintended recurrence
      _recorrencia = Recorrencia.nenhuma;
      if (!isDespesa) {
        // If selected account is credit, deselect it
        final selectedConta =
            _contas.where((c) => c.id == _contaId).firstOrNull;
        if (selectedConta?.tipo == 'credito') {
          final nonCreditContas =
              _contas.where((c) => c.tipo != 'credito').toList();
          _contaId =
              nonCreditContas.isNotEmpty ? nonCreditContas.first.id : null;
        }
        // Default to first receita category available
        final receitaCats = _categoriaRows
            .where((r) => r['tipo'] == 'receita' || r['tipo'] == 'ambos')
            .toList();
        _categoria = receitaCats.isNotEmpty
            ? receitaCats.first['nome'] as String
            : 'Salário';
      } else {
        // Default to first despesa category available
        final despesaCats = _categoriaRows
            .where((r) => r['tipo'] == 'despesa' || r['tipo'] == 'ambos')
            .toList();
        final nomeDespesas =
            despesaCats.map((r) => r['nome'] as String).toList();
        if (!nomeDespesas.contains(_categoria)) {
          _categoria =
              nomeDespesas.isNotEmpty ? nomeDespesas.first : 'Alimentação';
        }
      }
    });
  }

  @override
  void dispose() {
    _valorCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
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
        title: Text(
          widget.editando != null ? 'Editar transação' : 'Nova transação',
          style: TextStyle(color: context.textPrimary),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildTypeToggle(),
            const SizedBox(height: 24),
            _buildValueField(),
            const SizedBox(height: 16),
            if (!_isTransferencia) ...[
              _buildCategoryField(),
              const SizedBox(height: 16),
            ],
            _buildContaField(),
            const SizedBox(height: 16),
            if (_isTransferencia) ...[
              _buildContaDestinoField(),
              const SizedBox(height: 16),
            ],
            _buildDateField(),
            const SizedBox(height: 16),
            _buildDescField(),
            const SizedBox(height: 16),
            if (!_isTransferencia) _buildRecurrenceSection(),
            if (!_isTransferencia) const SizedBox(height: 16),
            const SizedBox(height: 32),
            GradientButton(
              label: widget.editando != null
                  ? 'Salvar alterações'
                  : 'Adicionar transação',
              onPressed: _saving ? null : _save,
              loading: _saving,
              icon: Icons.check_rounded,
            ),
            SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildTypeToggle() {
    return Container(
      decoration: BoxDecoration(
        color: context.appSurface,
        borderRadius: BorderRadius.circular(14),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          Expanded(
            child: _TypeBtn(
              label: '↓ Despesa',
              active: _isDespesa && !_isTransferencia,
              activeColor: AppColors.red,
              onTap: () {
                setState(() {
                  _isDespesa = true;
                  _isTransferencia = false;
                  _recorrencia = Recorrencia.nenhuma;
                });
              },
            ),
          ),
          Expanded(
            child: _TypeBtn(
              label: '↑ Receita',
              active: !_isDespesa && !_isTransferencia,
              activeColor: context.primary,
              onTap: () => _onToggleTipo(false),
            ),
          ),
          Expanded(
            child: _TypeBtn(
              label: '⇄ Transfer.',
              active: _isTransferencia,
              activeColor: AppColors.blue,
              onTap: () {
                setState(() {
                  _isTransferencia = true;
                  _isDespesa = true;
                  _recorrencia = Recorrencia.nenhuma;
                  _parcelas = 1;
                  // Transferência só pode sair de conta não-crédito
                  final contaAtual =
                      _contas.where((c) => c.id == _contaId).firstOrNull;
                  if (contaAtual?.tipo == 'credito') {
                    final naoCredito =
                        _contas.where((c) => c.tipo != 'credito').toList();
                    _contaId =
                        naoCredito.isNotEmpty ? naoCredito.first.id : null;
                  }
                  // Limpar destino inválido (crédito)
                  if (_contaDestinoId != null) {
                    final destino = _contas
                        .where((c) => c.id == _contaDestinoId)
                        .firstOrNull;
                    if (destino?.tipo == 'credito') _contaDestinoId = null;
                  }
                });
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildValueField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Valor',
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: context.textSecondary)),
        SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
              color: context.appSurface,
              borderRadius: BorderRadius.circular(12)),
          child: TextField(
            controller: _valorCtrl,
            keyboardType: TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9,.]'))
            ],
            style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: context.textPrimary),
            decoration: InputDecoration(
              prefixText: 'R\$ ',
              prefixStyle: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: _isDespesa ? AppColors.red : context.primary),
              border: InputBorder.none,
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 16, vertical: 18),
              hintText: '0,00',
              hintStyle: TextStyle(color: context.textSecondary),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCategoryField() {
    final (icon, color) = CategoriaHelper.get(_categoria);
    return _FormField(
      label: 'Categoria',
      onTap: _pickCategory,
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          SizedBox(width: 10),
          Expanded(
            child: Text(_categoria,
                style: TextStyle(fontSize: 16, color: context.textPrimary)),
          ),
          Icon(Icons.keyboard_arrow_down, color: context.textSecondary),
        ],
      ),
    );
  }

  Widget _buildContaField() {
    final conta = _contas.where((c) => c.id == _contaId).firstOrNull;
    return _FormField(
      label: 'Conta',
      onTap: _pickConta,
      child: Row(
        children: [
          Icon(Icons.account_balance_wallet_outlined,
              color: context.textSecondary, size: 20),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              conta?.nome ?? 'Selecionar conta',
              style: TextStyle(
                  fontSize: 16,
                  color: conta != null
                      ? context.textPrimary
                      : context.textSecondary),
            ),
          ),
          Icon(Icons.keyboard_arrow_down, color: context.textSecondary),
        ],
      ),
    );
  }

  Widget _buildContaDestinoField() {
    final conta = _contas.where((c) => c.id == _contaDestinoId).firstOrNull;
    return _FormField(
      label: 'Conta de destino',
      onTap: () async {
        // Destino de transferência: excluir a própria conta de origem
        // e cartões de crédito (que não recebem transferência)
        final contasDisponiveis = _contas
            .where((c) => c.id != _contaId && c.tipo != 'credito')
            .toList();
        if (contasDisponiveis.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Nenhuma conta disponível como destino')),
          );
          return;
        }
        final picked = await showModalBottomSheet<String>(
          context: context,
          backgroundColor: context.appSurface,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          builder: (_) => ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.symmetric(vertical: 12),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: Text('Conta de destino',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: context.textPrimary)),
              ),
              ...contasDisponiveis.map((c) => ListTile(
                    title: Text(c.nome,
                        style: TextStyle(color: context.textPrimary)),
                    subtitle: Text(c.tipo,
                        style: TextStyle(
                            color: context.textSecondary, fontSize: 12)),
                    leading: Icon(Icons.account_balance_wallet_outlined,
                        color: context.textSecondary),
                    trailing: _contaDestinoId == c.id
                        ? Icon(Icons.check_circle, color: context.primary)
                        : null,
                    onTap: () => Navigator.pop(context, c.id),
                  )),
            ],
          ),
        );
        if (picked != null) setState(() => _contaDestinoId = picked);
      },
      child: Row(
        children: [
          Icon(Icons.swap_horiz_rounded,
              color: context.textSecondary, size: 20),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              conta?.nome ?? 'Selecionar conta de destino',
              style: TextStyle(
                  fontSize: 16,
                  color: conta != null
                      ? context.textPrimary
                      : context.textSecondary),
            ),
          ),
          Icon(Icons.keyboard_arrow_down, color: context.textSecondary),
        ],
      ),
    );
  }

  Widget _buildDateField() {
    return _FormField(
      label:
          _recorrencia == Recorrencia.nenhuma ? 'Data' : 'Data do lançamento',
      onTap: _pickDate,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(dtFmt.format(_date),
              style: TextStyle(fontSize: 16, color: context.textPrimary)),
          Icon(Icons.calendar_today_outlined,
              color: context.textSecondary, size: 20),
        ],
      ),
    );
  }

  Widget _buildDescField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Descrição (opcional)',
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: context.textSecondary)),
        SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
              color: context.appSurface,
              borderRadius: BorderRadius.circular(12)),
          child: TextField(
            controller: _descCtrl,
            style: TextStyle(fontSize: 16, color: context.textPrimary),
            decoration: InputDecoration(
              border: InputBorder.none,
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              hintText: 'Ex: Almoço com cliente',
              hintStyle: TextStyle(color: context.textSecondary),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRecurrenceSection() {
    return Container(
      decoration: BoxDecoration(
          color: context.appSurface, borderRadius: BorderRadius.circular(14)),
      child: Column(
        children: [
          // Installments (expenses only)
          if (_isDespesa && _contaSelecionadaEhCredito) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Parcelado',
                          style: TextStyle(
                              fontSize: 15, color: context.textPrimary)),
                      Text('Dividir em parcelas',
                          style: TextStyle(
                              fontSize: 12, color: context.textSecondary)),
                    ],
                  ),
                  Row(
                    children: [
                      IconButton(
                        onPressed: _parcelas > 1
                            ? () => setState(() => _parcelas--)
                            : null,
                        icon: Icon(Icons.remove_circle_outline,
                            color: _parcelas > 1
                                ? AppColors.blue
                                : context.textSecondary),
                      ),
                      Text(
                        '$_parcelas×',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: context.textPrimary),
                      ),
                      IconButton(
                        onPressed: _parcelas < 48
                            ? () => setState(() => _parcelas++)
                            : null,
                        icon: const Icon(Icons.add_circle_outline,
                            color: AppColors.blue),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
          ],

          // Recurrence
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Recorrência',
                        style: TextStyle(
                            fontSize: 15, color: context.textPrimary)),
                    Text('Repetir automaticamente',
                        style: TextStyle(
                            fontSize: 12, color: context.textSecondary)),
                  ],
                ),
                DropdownButton<Recorrencia>(
                  value: _recorrencia,
                  dropdownColor: context.appCard,
                  underline: SizedBox(),
                  style: TextStyle(
                      fontSize: 14,
                      color: context.primary,
                      fontWeight: FontWeight.w600),
                  items: const [
                    DropdownMenuItem(
                        value: Recorrencia.nenhuma, child: Text('Nenhuma')),
                    DropdownMenuItem(
                        value: Recorrencia.semanal, child: Text('Semanal')),
                    DropdownMenuItem(
                        value: Recorrencia.mensal, child: Text('Mensal')),
                    DropdownMenuItem(
                        value: Recorrencia.anual, child: Text('Anual')),
                  ],
                  onChanged: (v) => setState(() {
                    _recorrencia = v!;
                    if (_recorrencia != Recorrencia.nenhuma) {
                      _recurrenceDate = _date;
                    }
                  }),
                ),
              ],
            ),
          ),
          if (_recorrencia != Recorrencia.nenhuma) ...[
            const Divider(height: 1),
            _buildRecurrenceDetails(),
          ],
        ],
      ),
    );
  }

  Widget _buildRecurrenceDetails() {
    const weekLabels = <int, String>{
      DateTime.monday: 'Seg',
      DateTime.tuesday: 'Ter',
      DateTime.wednesday: 'Qua',
      DateTime.thursday: 'Qui',
      DateTime.friday: 'Sex',
      DateTime.saturday: 'Sab',
      DateTime.sunday: 'Dom',
    };

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Base da recorrência',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: context.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'O lançamento usa a data acima. A recorrência usa a base abaixo.',
            style: TextStyle(fontSize: 12, color: context.textSecondary),
          ),
          const SizedBox(height: 10),
          if (_recorrencia == Recorrencia.semanal)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: weekLabels.entries.map((entry) {
                final selected = _recurrenceDate.weekday == entry.key;
                return ChoiceChip(
                  label: Text(entry.value),
                  selected: selected,
                  onSelected: (_) => _setRecurringWeekday(entry.key),
                );
              }).toList(),
            ),
          if (_recorrencia == Recorrencia.mensal)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading:
                  Icon(Icons.calendar_month_outlined, color: context.primary),
              title: Text('Todo dia ${_recurrenceDate.day}',
                  style: TextStyle(color: context.textPrimary)),
              subtitle: Text(
                'A recorrência mensal seguirá este dia.',
                style: TextStyle(color: context.textSecondary),
              ),
              trailing: Icon(Icons.edit_calendar_outlined,
                  color: context.textSecondary),
              onTap: _pickRecurringDayOfMonth,
            ),
          if (_recorrencia == Recorrencia.anual)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading:
                  Icon(Icons.event_repeat_outlined, color: context.primary),
              title: Text(
                'Todo ${dtFmt.format(_recurrenceDate)}',
                style: TextStyle(color: context.textPrimary),
              ),
              subtitle: Text(
                'A recorrência anual usará este dia e mês.',
                style: TextStyle(color: context.textSecondary),
              ),
              trailing: Icon(Icons.edit_calendar_outlined,
                  color: context.textSecondary),
              onTap: _pickRecurrenceDate,
            ),
          const SizedBox(height: 4),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: context.appCardLight,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.notifications_active_outlined,
                    size: 18, color: context.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Recorrências usam os lembretes globais do app quando as notificações estiverem ativas.',
                    style: TextStyle(
                      color: context.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickCategory() async {
    // Filter categories by transaction type
    final cats = _categoriaRows.where((r) {
      final tipo = r['tipo'] as String? ?? 'ambos';
      if (_isDespesa) return tipo == 'despesa' || tipo == 'ambos';
      return tipo == 'receita' || tipo == 'ambos';
    }).toList();

    // Fallback to static list if DB not loaded yet
    final catNames = cats.isNotEmpty
        ? cats.map((r) => r['nome'] as String).toList()
        : (_isDespesa
            ? CategoriaHelper.todas
                .where((c) =>
                    !['Salário', 'Freelance', 'Investimentos'].contains(c))
                .toList()
            : ['Salário', 'Freelance', 'Investimentos', 'Outros']);

    await showModalBottomSheet(
      context: context,
      backgroundColor: context.appSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => StatefulBuilder(builder: (ctx, setInner) {
        return Padding(
          padding: EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Categoria',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: context.textPrimary)),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: catNames.map((cat) {
                  final (icon, color) = CategoriaHelper.get(cat);
                  final isSelected = _categoria == cat;
                  return GestureDetector(
                    onTap: () {
                      setState(() => _categoria = cat);
                      Navigator.pop(context);
                    },
                    child: AnimatedContainer(
                      duration: Duration(milliseconds: 150),
                      padding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: isSelected ? color : context.appCardLight,
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(
                          color: isSelected ? color : Colors.transparent,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(icon,
                              size: 16,
                              color: isSelected ? Colors.white : color),
                          SizedBox(width: 6),
                          Text(
                            cat,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: isSelected
                                  ? Colors.white
                                  : context.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
              SizedBox(height: 20),
            ],
          ),
        );
      }),
    );
  }

  Future<void> _pickConta() async {
    final contasParaExibir = _contasValidas;

    await showModalBottomSheet(
      context: context,
      backgroundColor: context.appSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Selecionar conta',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: context.textPrimary)),
            const SizedBox(height: 16),
            if (contasParaExibir.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: EmptyState(
                  icon: Icons.account_balance_wallet_outlined,
                  title: _isDespesa
                      ? 'Nenhuma conta cadastrada'
                      : 'Nenhuma conta disponível',
                  subtitle: _isDespesa
                      ? 'Vá em Contas para cadastrar antes de adicionar transações'
                      : 'Cartões de crédito não aceitam receitas. Cadastre uma conta corrente ou poupança.',
                ),
              ),
            if (contasParaExibir.isNotEmpty)
              ...contasParaExibir.map((c) {
                final isSelected = _contaId == c.id;
                return ListTile(
                  onTap: () {
                    setState(() {
                      _contaId = c.id;
                      if (!_contaSelecionadaEhCredito) {
                        _parcelas = 1;
                      }
                    });
                    Navigator.pop(context);
                  },
                  leading: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: context.appCardLight,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.account_balance_wallet_outlined,
                        color: context.textSecondary, size: 20),
                  ),
                  title: Text(c.nome,
                      style: TextStyle(color: context.textPrimary)),
                  subtitle: Text(c.tipo,
                      style: TextStyle(
                          color: context.textSecondary, fontSize: 12)),
                  trailing: isSelected
                      ? Icon(Icons.check_circle, color: context.primary)
                      : null,
                );
              }),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _pickDate() async {
    final d = await _showStyledDatePicker(_date);
    if (d != null) setState(() => _date = d);
  }

  Future<void> _pickRecurrenceDate() async {
    final d = await _showStyledDatePicker(_recurrenceDate);
    if (d != null) setState(() => _recurrenceDate = d);
  }

  Future<DateTime?> _showStyledDatePicker(DateTime initialDate) async {
    final d = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: Theme.of(ctx).colorScheme.copyWith(
                primary: context.primary,
                onPrimary: Colors.white,
                surface: context.appSurface,
                onSurface: context.textPrimary,
              ),
          dialogBackgroundColor: context.appSurface,
          datePickerTheme: DatePickerThemeData(
            backgroundColor: context.appSurface,
            headerBackgroundColor: context.primary,
            headerForegroundColor: Colors.white,
            dayForegroundColor:
                WidgetStatePropertyAll<Color>(context.textPrimary),
            todayForegroundColor:
                WidgetStatePropertyAll<Color>(context.primary),
          ),
        ),
        child: child!,
      ),
    );
    return d;
  }

  Future<void> _pickRecurringDayOfMonth() async {
    final picked = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: context.appSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => GridView.builder(
        shrinkWrap: true,
        padding: const EdgeInsets.all(20),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 7,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 1,
        ),
        itemCount: 31,
        itemBuilder: (_, index) {
          final day = index + 1;
          final selected = _recurrenceDate.day == day;
          return GestureDetector(
            onTap: () => Navigator.pop(context, day),
            child: Container(
              decoration: BoxDecoration(
                color: selected ? context.primary : context.appCardLight,
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: Text(
                '$day',
                style: TextStyle(
                  color: selected ? Colors.white : context.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          );
        },
      ),
    );
    if (picked != null) {
      _setRecurringMonthDay(picked);
    }
  }

  void _setRecurringMonthDay(int day) {
    final lastDay =
        DateTime(_recurrenceDate.year, _recurrenceDate.month + 1, 0).day;
    setState(() {
      _recurrenceDate = DateTime(
        _recurrenceDate.year,
        _recurrenceDate.month,
        day.clamp(1, lastDay),
      );
    });
  }

  void _setRecurringWeekday(int weekday) {
    var cursor = _recurrenceDate;
    while (cursor.weekday != weekday) {
      cursor = cursor.add(const Duration(days: 1));
    }
    setState(() => _recurrenceDate = cursor);
  }

  Future<void> _save() async {
    final valorStr = _valorCtrl.text.trim().replaceAll(',', '.');
    final valor = double.tryParse(valorStr);
    if (valor == null || valor <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Informe um valor válido'),
          backgroundColor: AppColors.red,
        ),
      );
      return;
    }

    // Validate transfer accounts
    if (_isTransferencia) {
      if (_contaId == null || _contaDestinoId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Selecione a conta de origem e destino'),
            backgroundColor: AppColors.red,
          ),
        );
        return;
      }
      if (_contaId == _contaDestinoId) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Conta de origem e destino devem ser diferentes'),
            backgroundColor: AppColors.red,
          ),
        );
        return;
      }
      // Conta de destino não pode ser cartão de crédito
      final destino = _contas.where((c) => c.id == _contaDestinoId).firstOrNull;
      if (destino?.tipo == 'credito') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('Cartão de crédito não pode ser destino de transferência'),
            backgroundColor: AppColors.red,
          ),
        );
        return;
      }
      // Conta de origem não pode ser cartão de crédito
      final origem = _contas.where((c) => c.id == _contaId).firstOrNull;
      if (origem?.tipo == 'credito') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('Cartão de crédito não pode ser origem de transferência'),
            backgroundColor: AppColors.red,
          ),
        );
        return;
      }
    }

    // Validate: credit accounts cannot have income
    if (!_isDespesa && _contaId != null) {
      final selectedConta = _contas.where((c) => c.id == _contaId).firstOrNull;
      if (selectedConta?.tipo == 'credito') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('Cartões de crédito não aceitam lançamentos de entrada'),
            backgroundColor: AppColors.red,
          ),
        );
        return;
      }
    }

    setState(() => _saving = true);

    if (_isTransferencia) {
      // Transfer: create two linked transactions (saída + entrada)
      final grupoId = 'transf_${DateTime.now().millisecondsSinceEpoch}';
      final saida = Transacao(
        valor: -valor,
        banco: _contaId ?? 'geral',
        parcelas: 1,
        primeiraParcela: _date,
        categoria: 'Transferência',
        tipo: TipoTransacao.saldo,
        descricao: _descCtrl.text.trim().isEmpty
            ? 'Transferência'
            : _descCtrl.text.trim(),
        recorrencia: Recorrencia.nenhuma,
        recorrenciaGrupoId: grupoId,
      );
      final entrada = Transacao(
        valor: valor,
        banco: _contaDestinoId ?? 'geral',
        parcelas: 1,
        primeiraParcela: _date,
        categoria: 'Transferência',
        tipo: TipoTransacao.saldo,
        descricao: _descCtrl.text.trim().isEmpty
            ? 'Transferência'
            : _descCtrl.text.trim(),
        recorrencia: Recorrencia.nenhuma,
        recorrenciaGrupoId: grupoId,
      );
      await _transactionRepository.insertTransfer(
        saida: saida,
        entrada: entrada,
      );
    } else {
      final t = Transacao(
        id: widget.editando?.id,
        valor: _isDespesa ? -valor : valor,
        banco: _contaId ?? 'geral',
        parcelas: _recorrencia != Recorrencia.nenhuma ? 1 : _parcelas,
        primeiraParcela: _date,
        recorrenciaDataBase:
            _recorrencia != Recorrencia.nenhuma ? _recurrenceDate : null,
        categoria: _categoria,
        tipo: _isDespesa ? TipoTransacao.saida : TipoTransacao.receita,
        descricao: _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
        recorrencia: _recorrencia,
      );
      if (widget.editando != null) {
        await _transactionRepository.save(t, isUpdate: true);
      } else {
        await _transactionRepository.save(t);
      }
    }

    setState(() => _saving = false);
    AppState.notify();
    if (mounted) Navigator.pop(context, true);
  }
}

// ─── Supporting widgets ────────────────────────────────────────

class _FormField extends StatelessWidget {
  final String label;
  final Widget child;
  final VoidCallback onTap;

  _FormField({
    required this.label,
    required this.child,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: context.textSecondary)),
        SizedBox(height: 8),
        GestureDetector(
          onTap: onTap,
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
                color: context.appSurface,
                borderRadius: BorderRadius.circular(12)),
            child: child,
          ),
        ),
      ],
    );
  }
}

class _TypeBtn extends StatelessWidget {
  final String label;
  final bool active;
  final Color activeColor;
  final VoidCallback onTap;

  const _TypeBtn({
    required this.label,
    required this.active,
    required this.activeColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: active ? activeColor : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          boxShadow: active
              ? [
                  BoxShadow(
                    color: activeColor.withOpacity(0.3),
                    blurRadius: 8,
                    offset: Offset(0, 2),
                  )
                ]
              : null,
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: active ? Colors.white : context.textSecondary,
          ),
        ),
      ),
    );
  }
}
