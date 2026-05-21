import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../data/models/conta.dart';
import '../../repositories/account_repository.dart';
import '../../repositories/settings_repository.dart';
import '../../utils/app_theme.dart';
import '../../utils/app_state.dart';
import '../../utils/formatters.dart';
import 'package:uuid/uuid.dart';

class OnboardingScreen extends StatefulWidget {
  final VoidCallback onComplete;
  const OnboardingScreen({super.key, required this.onComplete});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with SingleTickerProviderStateMixin {
  static const _accountRepository = AccountRepository.instance;
  static const _settingsRepository = SettingsRepository.instance;
  final _pageController = PageController();
  int _page = 0;
  bool _saving = false;

  // Step 1 — Nome
  final _nomeCtrl = TextEditingController();

  // Step 2 — Renda
  final _rendaCtrl = TextEditingController();

  // Step 3 — Conta
  final _contaNomeCtrl = TextEditingController(text: 'Conta principal');
  final _contaSaldoCtrl = TextEditingController(text: '0,00');
  final _contaLimiteCtrl = TextEditingController(text: '0,00');
  String _contaTipo = 'corrente';
  String _contaCor = '16A34A';
  int? _contaDiaVencimento = 10;
  int? _contaDiaFechamento = 5;

  static const _cores = [
    ('16A34A', 'Verde'),
    ('2563EB', 'Azul'),
    ('7C3AED', 'Roxo'),
    ('EC4899', 'Rosa'),
    ('D97706', 'Âmbar'),
    ('DC2626', 'Vermelho'),
    ('0891B2', 'Ciano'),
    ('374151', 'Cinza'),
  ];

  @override
  void dispose() {
    _pageController.dispose();
    _nomeCtrl.dispose();
    _rendaCtrl.dispose();
    _contaNomeCtrl.dispose();
    _contaSaldoCtrl.dispose();
    _contaLimiteCtrl.dispose();
    super.dispose();
  }

  void _next() {
    if (_page == 0 && _nomeCtrl.text.trim().isEmpty) {
      _shake();
      return;
    }
    if (_page < 2) {
      setState(() => _page++);
      _pageController.nextPage(
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeInOutCubic,
      );
    } else {
      _finish();
    }
  }

  void _skip() {
    if (_page < 2) {
      setState(() => _page++);
      _pageController.nextPage(
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeInOutCubic,
      );
    } else {
      _finish();
    }
  }

  Future<void> _finish() async {
    setState(() => _saving = true);

    // Salva nome do usuário
    final nome = _nomeCtrl.text.trim();
    if (nome.isNotEmpty) {
      await _settingsRepository.setConfig('nome_usuario', nome);
    }

    // Salva renda base
    final renda = parseBRL(_rendaCtrl.text) ?? 0;
    if (renda > 0) {
      await _settingsRepository.setConfig('receita_base', renda.toString());
      await _settingsRepository.setConfig('receita_base_dia_fixo', '5');
      await _settingsRepository.setConfig('receita_base_dia_util', '');
    }

    // Cria primeira conta
    final saldo = parseBRL(_contaSaldoCtrl.text) ?? 0;
    final limite = parseBRL(_contaLimiteCtrl.text) ?? 0;
    final conta = Conta(
      id: const Uuid().v4(),
      nome: _contaNomeCtrl.text.trim().isEmpty
          ? 'Conta principal'
          : _contaNomeCtrl.text.trim(),
      limite: _contaTipo == 'credito' ? limite : 0,
      saldo: saldo,
      saldoInicial: _contaTipo == 'credito' ? 0 : saldo,
      tipo: _contaTipo,
      cor: _contaCor,
      diaVencimento: _contaTipo == 'credito' ? _contaDiaVencimento : null,
      diaFechamento: _contaTipo == 'credito' ? _contaDiaFechamento : null,
    );
    await _accountRepository.save(conta);

    // Marca onboarding como concluído
    await _settingsRepository.setConfig('onboarding_done', 'true');
    await AppState.loadPreferences();
    AppState.notifyDataChanged();

    if (mounted) widget.onComplete();
  }

  void _shake() {
    HapticFeedback.mediumImpact();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.appBackground,
      body: SafeArea(
        child: Column(
          children: [
            // Progress bar
            _OnboardingProgress(current: _page, total: 3),

            // Pages
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _StepNome(ctrl: _nomeCtrl),
                  _StepRenda(ctrl: _rendaCtrl),
                  _StepConta(
                    nomeCtrl: _contaNomeCtrl,
                    saldoCtrl: _contaSaldoCtrl,
                    limiteCtrl: _contaLimiteCtrl,
                    tipo: _contaTipo,
                    cor: _contaCor,
                    diaVencimento: _contaDiaVencimento,
                    diaFechamento: _contaDiaFechamento,
                    cores: _cores,
                    onTipoChanged: (v) => setState(() => _contaTipo = v),
                    onCorChanged: (v) => setState(() => _contaCor = v),
                    onDiaVencimentoChanged: (v) =>
                        setState(() => _contaDiaVencimento = v),
                    onDiaFechamentoChanged: (v) =>
                        setState(() => _contaDiaFechamento = v),
                  ),
                ],
              ),
            ),

            // Bottom actions
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _saving ? null : _next,
                      style: FilledButton.styleFrom(
                        backgroundColor: context.primary,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      child: _saving
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2.5, color: Colors.white),
                            )
                          : Text(
                              _page == 2 ? 'Começar' : 'Continuar',
                              style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white),
                            ),
                    ),
                  ),
                  if (_page > 0) ...[
                    const SizedBox(height: 10),
                    TextButton(
                      onPressed: _saving ? null : _skip,
                      child: Text(
                        'Pular esta etapa',
                        style: TextStyle(
                            color: context.textSecondary, fontSize: 14),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Progress indicator ────────────────────────────────────────

class _OnboardingProgress extends StatelessWidget {
  final int current;
  final int total;

  const _OnboardingProgress({required this.current, required this.total});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      child: Row(
        children: List.generate(total, (i) {
          final active = i <= current;
          return Expanded(
            child: Container(
              margin: EdgeInsets.only(right: i < total - 1 ? 6 : 0),
              height: 4,
              decoration: BoxDecoration(
                color: active ? context.primary : context.appCardLight,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          );
        }),
      ),
    );
  }
}

// ─── Step 1: Nome ─────────────────────────────────────────────

class _StepNome extends StatelessWidget {
  final TextEditingController ctrl;
  const _StepNome({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 40, 28, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _OnboardingIllustration(
            icon: Icons.waving_hand_rounded,
            color: AppColors.amber,
            bgColor: AppColors.amberLight,
          ),
          const SizedBox(height: 32),
          Text(
            'Bem-vindo ao\nseu novo jeito de\ncuidar do dinheiro',
            style: TextStyle(
              color: context.textPrimary,
              fontSize: 30,
              fontWeight: FontWeight.w800,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Vamos personalizar sua experiência no Uffa.',
            style: TextStyle(color: context.textSecondary, fontSize: 15),
          ),
          const SizedBox(height: 36),
          TextField(
            controller: ctrl,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            style: TextStyle(
                color: context.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w600),
            decoration: InputDecoration(
              hintText: 'Seu nome aqui',
              hintStyle: TextStyle(
                  color: context.textTertiary, fontWeight: FontWeight.w400),
              filled: true,
              fillColor: context.appCardLight,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: context.primary, width: 2),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Step 2: Renda ────────────────────────────────────────────

class _StepRenda extends StatelessWidget {
  final TextEditingController ctrl;
  const _StepRenda({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 40, 28, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _OnboardingIllustration(
            icon: Icons.payments_rounded,
            color: AppColors.green,
            bgColor: AppColors.greenLight,
          ),
          const SizedBox(height: 32),
          Text(
            'Qual é sua\nrenda mensal?',
            style: TextStyle(
              color: context.textPrimary,
              fontSize: 30,
              fontWeight: FontWeight.w800,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Isso ajuda a calcular orçamentos e insights. Você pode alterar depois.',
            style: TextStyle(color: context.textSecondary, fontSize: 15),
          ),
          const SizedBox(height: 36),
          TextField(
            controller: ctrl,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: TextStyle(
                color: context.textPrimary,
                fontSize: 22,
                fontWeight: FontWeight.w700),
            decoration: InputDecoration(
              hintText: '0,00',
              prefixText: 'R\$  ',
              prefixStyle: TextStyle(
                  color: context.textSecondary,
                  fontSize: 18,
                  fontWeight: FontWeight.w600),
              filled: true,
              fillColor: context.appCardLight,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: context.primary, width: 2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.blueLight,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline_rounded,
                    color: AppColors.blue, size: 16),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Seus dados ficam somente no dispositivo. Nada é enviado para a nuvem.',
                    style: const TextStyle(color: AppColors.blue, fontSize: 12),
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

// ─── Step 3: Primeira conta ───────────────────────────────────

class _StepConta extends StatelessWidget {
  final TextEditingController nomeCtrl;
  final TextEditingController saldoCtrl;
  final TextEditingController limiteCtrl;
  final String tipo;
  final String cor;
  final int? diaVencimento;
  final int? diaFechamento;
  final List<(String, String)> cores;
  final ValueChanged<String> onTipoChanged;
  final ValueChanged<String> onCorChanged;
  final ValueChanged<int?> onDiaVencimentoChanged;
  final ValueChanged<int?> onDiaFechamentoChanged;

  const _StepConta({
    required this.nomeCtrl,
    required this.saldoCtrl,
    required this.limiteCtrl,
    required this.tipo,
    required this.cor,
    required this.diaVencimento,
    required this.diaFechamento,
    required this.cores,
    required this.onTipoChanged,
    required this.onCorChanged,
    required this.onDiaVencimentoChanged,
    required this.onDiaFechamentoChanged,
  });

  Color _safeColor(String hex, Color fallback) {
    final normalized = hex.replaceAll('#', '').toUpperCase();
    final isValid = RegExp(r'^[0-9A-F]{6}$').hasMatch(normalized);
    if (!isValid) return fallback;
    return Color(int.parse('FF$normalized', radix: 16));
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 40, 28, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _OnboardingIllustration(
            icon: Icons.account_balance_wallet_rounded,
            color: AppColors.blue,
            bgColor: AppColors.blueLight,
          ),
          const SizedBox(height: 32),
          Text(
            'Crie sua\nprimeira conta',
            style: TextStyle(
              color: context.textPrimary,
              fontSize: 30,
              fontWeight: FontWeight.w800,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Adicione uma conta corrente, poupança ou cartão de crédito.',
            style: TextStyle(color: context.textSecondary, fontSize: 15),
          ),
          const SizedBox(height: 28),

          // Tipo
          Text('Tipo de conta',
              style: TextStyle(
                  color: context.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 8),
          Row(
            children: [
              _TipoChip(
                label: 'Corrente',
                icon: Icons.account_balance_rounded,
                selected: tipo == 'corrente',
                onTap: () => onTipoChanged('corrente'),
              ),
              const SizedBox(width: 8),
              _TipoChip(
                label: 'Poupança',
                icon: Icons.savings_rounded,
                selected: tipo == 'poupanca',
                onTap: () => onTipoChanged('poupanca'),
              ),
              const SizedBox(width: 8),
              _TipoChip(
                label: 'Cartão',
                icon: Icons.credit_card_rounded,
                selected: tipo == 'credito',
                onTap: () => onTipoChanged('credito'),
              ),
            ],
          ),
          const SizedBox(height: 18),

          // Nome
          Text('Nome da conta',
              style: TextStyle(
                  color: context.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 8),
          TextField(
            controller: nomeCtrl,
            textCapitalization: TextCapitalization.words,
            style: TextStyle(
                color: context.textPrimary, fontWeight: FontWeight.w600),
            decoration: InputDecoration(
              hintText: 'Ex: Nubank, Bradesco...',
              filled: true,
              fillColor: context.appCardLight,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: context.primary, width: 2),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Saldo inicial
          Text(
            tipo == 'credito' ? 'Fatura atual (R\$)' : 'Saldo atual (R\$)',
            style: TextStyle(
                color: context.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: saldoCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: TextStyle(
                color: context.textPrimary, fontWeight: FontWeight.w600),
            decoration: InputDecoration(
              prefixText: 'R\$ ',
              prefixStyle: TextStyle(color: context.textSecondary),
              filled: true,
              fillColor: context.appCardLight,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: context.primary, width: 2),
              ),
            ),
          ),
          if (tipo == 'credito') ...[
            const SizedBox(height: 16),
            Text(
              'Limite do cartão (R\$)',
              style: TextStyle(
                  color: context.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: limiteCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              style: TextStyle(
                  color: context.textPrimary, fontWeight: FontWeight.w600),
              decoration: InputDecoration(
                prefixText: 'R\$ ',
                prefixStyle: TextStyle(color: context.textSecondary),
                filled: true,
                fillColor: context.appCardLight,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: context.primary, width: 2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _DayPickerField(
                    label: 'Dia de fechamento',
                    value: diaFechamento,
                    onChanged: onDiaFechamentoChanged,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _DayPickerField(
                    label: 'Dia de vencimento',
                    value: diaVencimento,
                    onChanged: onDiaVencimentoChanged,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 18),

          // Cor
          Text('Cor',
              style: TextStyle(
                  color: context.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: cores.map((c) {
              final selected = c.$1 == cor;
              final color = _safeColor(c.$1, context.primary);
              return GestureDetector(
                onTap: () => onCorChanged(c.$1),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color:
                          selected ? context.textPrimary : Colors.transparent,
                      width: 2.5,
                    ),
                    boxShadow: selected
                        ? [
                            BoxShadow(
                              color: color.withOpacity(0.5),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            )
                          ]
                        : null,
                  ),
                  child: selected
                      ? const Icon(Icons.check_rounded,
                          color: Colors.white, size: 16)
                      : null,
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

// ─── Sub-widgets ───────────────────────────────────────────────

class _OnboardingIllustration extends StatelessWidget {
  final IconData icon;
  final Color color;
  final Color bgColor;

  const _OnboardingIllustration({
    required this.icon,
    required this.color,
    required this.bgColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 80,
      height: 80,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Icon(icon, color: color, size: 40),
    );
  }
}

class _TipoChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _TipoChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected
                ? context.primary.withOpacity(0.1)
                : context.appCardLight,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? context.primary : Colors.transparent,
              width: 2,
            ),
          ),
          child: Column(
            children: [
              Icon(icon,
                  color: selected ? context.primary : context.textSecondary,
                  size: 20),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  color: selected ? context.primary : context.textSecondary,
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

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
            style: TextStyle(
                color: context.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w500)),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: context.appCardLight,
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              value: value,
              isExpanded: true,
              dropdownColor: context.appSurface,
              style: TextStyle(color: context.textPrimary, fontSize: 14),
              items: List.generate(31, (i) => i + 1)
                  .map((day) => DropdownMenuItem<int>(
                        value: day,
                        child: Text('$day'),
                      ))
                  .toList(),
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }
}
