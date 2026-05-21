import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../data/models/transaction.dart';
import '../../data/models/conta.dart';
import '../../repositories/account_repository.dart';
import '../../repositories/transaction_repository.dart';
import '../../utils/formatters.dart';
import '../../utils/app_theme.dart';
import '../../utils/app_state.dart';
import '../../widgets/common.dart';

class TransferScreen extends StatefulWidget {
  /// Pré-seleciona conta de origem (ex: ao chamar da tela de contas).
  final String? initialOrigemId;
  const TransferScreen({super.key, this.initialOrigemId});

  @override
  State<TransferScreen> createState() => _TransferScreenState();
}

class _TransferScreenState extends State<TransferScreen> {
  static const _accountRepository = AccountRepository.instance;
  static const _transactionRepository = TransactionRepository.instance;
  final _valorCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  DateTime _date = DateTime.now();
  String? _origemId;
  String? _destinoId;
  bool _saving = false;
  List<Conta> _contas = [];
  // Controle anti-spam de mensagens de erro
  DateTime? _lastSnackTime;
  String? _lastSnackMsg;

  // Apenas contas não-crédito podem ser origem ou destino de transferência
  List<Conta> get _contasValidas =>
      _contas.where((c) => c.tipo != 'credito').toList();

  @override
  void initState() {
    super.initState();
    _origemId = widget.initialOrigemId;
    _loadContas();
  }

  @override
  void dispose() {
    _valorCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadContas() async {
    final c = await _accountRepository.getAll();
    setState(() {
      _contas = c;
      // Se não há origem pré-definida, seleciona a primeira válida
      if (_origemId == null && _contasValidas.isNotEmpty) {
        _origemId = _contasValidas.first.id;
      }
    });
  }

  Conta? get _contaOrigem =>
      _contas.where((c) => c.id == _origemId).firstOrNull;
  Conta? get _contaDestino =>
      _contas.where((c) => c.id == _destinoId).firstOrNull;

  Future<void> _pickConta({required bool isOrigem}) async {
    final excludeId = isOrigem ? _destinoId : _origemId;
    final lista = _contasValidas.where((c) => c.id != excludeId).toList();

    if (lista.isEmpty) {
      _snack('Nenhuma conta disponível para selecionar');
      return;
    }

    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: context.appSurface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _ContaPicker(
        contas: lista,
        selectedId: isOrigem ? _origemId : _destinoId,
        titulo: isOrigem ? 'Conta de origem' : 'Conta de destino',
      ),
    );

    if (picked != null) {
      setState(() {
        if (isOrigem) {
          _origemId = picked;
          // Se destino = origem após troca, limpa destino
          if (_destinoId == picked) _destinoId = null;
        } else {
          _destinoId = picked;
          if (_origemId == picked) _origemId = null;
        }
      });
    }
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: ColorScheme.dark(
            primary: context.primary,
            surface: context.appCard,
          ),
        ),
        child: child!,
      ),
    );
    if (d != null) setState(() => _date = d);
  }

  void _snack(String msg, {bool error = false}) {
    final now = DateTime.now();
    // Anti-spam: ignora se a mesma mensagem foi exibida nos últimos 2 segundos
    if (_lastSnackMsg == msg &&
        _lastSnackTime != null &&
        now.difference(_lastSnackTime!) < const Duration(seconds: 2)) {
      return;
    }
    _lastSnackMsg = msg;
    _lastSnackTime = now;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Row(
          children: [
            Icon(
              error ? Icons.error_outline_rounded : Icons.info_outline_rounded,
              color: Colors.white,
              size: 18,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(msg,
                  style: const TextStyle(fontWeight: FontWeight.w500)),
            ),
          ],
        ),
        backgroundColor: error ? AppColors.red : AppColors.blue,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 3),
      ));
  }

  Future<void> _save() async {
    final valorStr = _valorCtrl.text.trim().replaceAll(',', '.');
    final valor = double.tryParse(valorStr);

    if (valor == null || valor <= 0) {
      _snack('Informe um valor válido', error: true);
      return;
    }
    if (_origemId == null) {
      _snack('Selecione a conta de origem', error: true);
      return;
    }
    if (_destinoId == null) {
      _snack('Selecione a conta de destino', error: true);
      return;
    }
    if (_origemId == _destinoId) {
      _snack('Origem e destino devem ser diferentes', error: true);
      return;
    }

    setState(() => _saving = true);

    final grupoId = 'transf_${DateTime.now().millisecondsSinceEpoch}';
    final desc =
        _descCtrl.text.trim().isEmpty ? 'Transferência' : _descCtrl.text.trim();

    final saida = Transacao(
      valor: -valor,
      banco: _origemId!,
      parcelas: 1,
      primeiraParcela: _date,
      categoria: 'Transferência',
      tipo: TipoTransacao.saldo,
      descricao: desc,
      recorrencia: Recorrencia.nenhuma,
      recorrenciaGrupoId: grupoId,
    );
    final entrada = Transacao(
      valor: valor,
      banco: _destinoId!,
      parcelas: 1,
      primeiraParcela: _date,
      categoria: 'Transferência',
      tipo: TipoTransacao.saldo,
      descricao: desc,
      recorrencia: Recorrencia.nenhuma,
      recorrenciaGrupoId: grupoId,
    );

    await _transactionRepository.insertTransfer(saida: saida, entrada: entrada);

    setState(() => _saving = false);
    AppState.notify();
    if (mounted) {
      // Feedback de sucesso antes de fechar
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded,
                    color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Transferência de ${fmtBRL(valor)} realizada!',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            backgroundColor: AppColors.green,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.all(16),
            duration: const Duration(seconds: 2),
          ),
        );
      Navigator.pop(context, true);
    }
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
        title: Text('Transferência',
            style: TextStyle(
                color: context.textPrimary, fontWeight: FontWeight.w700)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Cabeçalho visual ──────────────────────────────────
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppColors.blue, AppColors.blue.withOpacity(0.7)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.swap_horiz_rounded,
                      color: Colors.white, size: 32),
                  const SizedBox(width: 12),
                  Text(
                    'Transferência entre contas',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),

            // ── Valor ─────────────────────────────────────────────
            _Label('Valor'),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                  color: context.appSurface,
                  borderRadius: BorderRadius.circular(14)),
              child: TextField(
                controller: _valorCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9,.]'))
                ],
                style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: AppColors.blue),
                decoration: InputDecoration(
                  prefixText: 'R\$ ',
                  prefixStyle: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: AppColors.blue),
                  border: InputBorder.none,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                  hintText: '0,00',
                  hintStyle: TextStyle(color: context.textSecondary),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // ── Fluxo origem → destino ────────────────────────────
            Container(
              decoration: BoxDecoration(
                color: context.appSurface,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  // Origem
                  _ContaRow(
                    label: 'De',
                    conta: _contaOrigem,
                    placeholder: 'Selecionar conta de origem',
                    onTap: () => _pickConta(isOrigem: true),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Divider(height: 1, color: context.appDivider),
                  ),
                  // Seta indicando direção
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Center(
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: AppColors.blue.withOpacity(0.12),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.arrow_downward_rounded,
                            color: AppColors.blue, size: 18),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Divider(height: 1, color: context.appDivider),
                  ),
                  // Destino
                  _ContaRow(
                    label: 'Para',
                    conta: _contaDestino,
                    placeholder: 'Selecionar conta de destino',
                    onTap: () => _pickConta(isOrigem: false),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ── Data ──────────────────────────────────────────────
            _Label('Data'),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: _pickDate,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: context.appSurface,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(dtFmt.format(_date),
                        style: TextStyle(
                            fontSize: 16, color: context.textPrimary)),
                    Icon(Icons.calendar_today_outlined,
                        color: context.textSecondary, size: 20),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // ── Descrição ─────────────────────────────────────────
            _Label('Descrição (opcional)'),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                  color: context.appSurface,
                  borderRadius: BorderRadius.circular(14)),
              child: TextField(
                controller: _descCtrl,
                style: TextStyle(fontSize: 16, color: context.textPrimary),
                decoration: InputDecoration(
                  border: InputBorder.none,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  hintText: 'Ex: Pagamento de fatura',
                  hintStyle: TextStyle(color: context.textSecondary),
                ),
              ),
            ),
            const SizedBox(height: 32),

            // ── Botão ─────────────────────────────────────────────
            GradientButton(
              label: 'Realizar transferência',
              onPressed: _saving ? null : _save,
              loading: _saving,
              icon: Icons.swap_horiz_rounded,
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}

// ─── Widgets auxiliares ────────────────────────────────────────

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);
  @override
  Widget build(BuildContext context) => Text(
        text,
        style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: context.textSecondary),
      );
}

class _ContaRow extends StatelessWidget {
  final String label;
  final Conta? conta;
  final String placeholder;
  final VoidCallback onTap;

  const _ContaRow({
    required this.label,
    required this.conta,
    required this.placeholder,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    Color? contaColor;
    if (conta != null) {
      try {
        contaColor = Color(int.parse('FF${conta!.cor}', radix: 16));
      } catch (_) {
        contaColor = AppColors.blue;
      }
    }
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: conta != null
                    ? contaColor!.withOpacity(0.15)
                    : context.appCardLight,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                conta != null
                    ? Icons.account_balance_wallet_rounded
                    : Icons.add_circle_outline_rounded,
                color: conta != null ? contaColor : context.textTertiary,
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(
                          color: context.textSecondary, fontSize: 11)),
                  const SizedBox(height: 2),
                  Text(
                    conta?.nome ?? placeholder,
                    style: TextStyle(
                      color: conta != null
                          ? context.textPrimary
                          : context.textTertiary,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (conta != null)
                    Text(
                      'Saldo: ${fmtBRL(conta!.saldo)}',
                      style:
                          TextStyle(color: context.textSecondary, fontSize: 12),
                    ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                color: context.textTertiary, size: 20),
          ],
        ),
      ),
    );
  }
}

class _ContaPicker extends StatelessWidget {
  final List<Conta> contas;
  final String? selectedId;
  final String titulo;

  const _ContaPicker({
    required this.contas,
    required this.selectedId,
    required this.titulo,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: context.appDivider,
                  borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 20),
          Text(titulo,
              style: TextStyle(
                  color: context.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),
          ...contas.map((c) {
            Color cor;
            try {
              cor = Color(int.parse('FF${c.cor}', radix: 16));
            } catch (_) {
              cor = AppColors.blue;
            }
            final isSelected = c.id == selectedId;
            return InkWell(
              onTap: () => Navigator.pop(context, c.id),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color:
                      isSelected ? cor.withOpacity(0.1) : context.appCardLight,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSelected ? cor : Colors.transparent,
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
                                  fontWeight: FontWeight.w600,
                                  fontSize: 15)),
                          Text('Saldo: ${fmtBRL(c.saldo)}',
                              style: TextStyle(
                                  color: context.textSecondary, fontSize: 12)),
                        ],
                      ),
                    ),
                    if (isSelected)
                      Icon(Icons.check_circle_rounded, color: cor, size: 20),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}
