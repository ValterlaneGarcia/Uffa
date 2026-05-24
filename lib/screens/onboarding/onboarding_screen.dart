import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:uuid/uuid.dart';

import '../../data/models/conta.dart';
import '../../repositories/account_repository.dart';
import '../../repositories/settings_repository.dart';
import '../../utils/app_state.dart';
import '../../utils/app_theme.dart';
import '../../utils/formatters.dart';
import '../../widgets/common.dart';

class OnboardingScreen extends StatefulWidget {
  final VoidCallback onComplete;

  const OnboardingScreen({super.key, required this.onComplete});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

enum _IncomeMode { fixedDay, businessDay }

class _OnboardingScreenState extends State<OnboardingScreen> {
  static const _accountRepository = AccountRepository.instance;
  static const _settingsRepository = SettingsRepository.instance;

  final _pageController = PageController();
  final _nomeCtrl = TextEditingController();
  final _rendaCtrl = TextEditingController();
  final _contaNomeCtrl = TextEditingController();
  final _contaSaldoCtrl = TextEditingController(text: '0,00');
  final _contaLimiteCtrl = TextEditingController(text: '0,00');

  int _page = 0;
  bool _saving = false;

  _IncomeMode _incomeMode = _IncomeMode.fixedDay;
  int _incomeFixedDay = 5;
  int _incomeBusinessDay = 5;

  String _contaTipo = 'corrente';
  String _contaCor = '16A34A';
  String? _contaIcone = 'nubank';
  int _contaDiaVencimento = 10;
  int _contaDiaFechamento = 5;

  BancoInfo get _selectedBank => bancosConhecidos.firstWhere(
        (bank) => bank.icone == _contaIcone,
        orElse: () => bancosConhecidos.last,
      );

  @override
  void initState() {
    super.initState();
    _contaNomeCtrl.text = 'Nubank';
    _contaCor = '8A05BE';
  }

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

  Future<void> _goToPage(int page) async {
    setState(() => _page = page);
    await _pageController.animateToPage(
      page,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  void _selectBank(BancoInfo bank) {
    setState(() {
      _contaIcone = bank.icone;
      _contaCor = bank.cor;
      if (bank.icone != 'outros') {
        _contaNomeCtrl.text = bank.nome;
      } else if (_contaNomeCtrl.text.trim().isEmpty) {
        _contaNomeCtrl.text = 'Conta principal';
      }
    });
  }

  bool _validateCurrentStep() {
    if (_page == 1 && _nomeCtrl.text.trim().isEmpty) {
      HapticFeedback.mediumImpact();
      showAppSnack(context, 'Digite seu nome para continuar', isError: true);
      return false;
    }
    if (_page == 2) {
      final renda = parseBRL(_rendaCtrl.text) ?? 0;
      if (renda <= 0) {
        HapticFeedback.mediumImpact();
        showAppSnack(
          context,
          'Informe sua renda mensal para continuar',
          isError: true,
        );
        return false;
      }
    }
    if (_page == 3 && _contaTipo == 'credito') {
      final limite = parseBRL(_contaLimiteCtrl.text) ?? 0;
      if (limite <= 0) {
        HapticFeedback.mediumImpact();
        showAppSnack(
          context,
          'Informe o limite do cartão para continuar',
          isError: true,
        );
        return false;
      }
    }
    return true;
  }

  Future<void> _next() async {
    if (!_validateCurrentStep()) return;
    if (_page < 3) {
      await _goToPage(_page + 1);
      return;
    }
    await _finish(createFirstAccount: true);
  }

  Future<void> _back() async {
    if (_page == 0) return;
    await _goToPage(_page - 1);
  }

  Future<void> _finish({required bool createFirstAccount}) async {
    if (_saving) return;
    if (!createFirstAccount && !_validateCurrentStep() && _page != 3) return;

    setState(() => _saving = true);
    try {
      final nome = _nomeCtrl.text.trim();
      if (nome.isNotEmpty) {
        await _settingsRepository.setConfig('nome_usuario', nome);
      }

      final renda = parseBRL(_rendaCtrl.text) ?? 0;
      if (renda > 0) {
        await _settingsRepository.saveIncomeBase(
          valor: renda,
          diaFixo: _incomeMode == _IncomeMode.fixedDay ? _incomeFixedDay : null,
          nthDiaUtil: _incomeMode == _IncomeMode.businessDay
              ? _incomeBusinessDay
              : null,
        );
      }

      if (createFirstAccount) {
        final saldo = parseBRL(_contaSaldoCtrl.text) ?? 0;
        final limite = parseBRL(_contaLimiteCtrl.text) ?? 0;
        final conta = Conta(
          id: const Uuid().v4(),
          nome: _contaNomeCtrl.text.trim().isEmpty
              ? (_selectedBank.icone == 'outros'
                  ? 'Conta principal'
                  : _selectedBank.nome)
              : _contaNomeCtrl.text.trim(),
          limite: _contaTipo == 'credito' ? limite : 0,
          saldo: _contaTipo == 'credito' ? saldo : saldo,
          saldoInicial: _contaTipo == 'credito' ? 0 : saldo,
          tipo: _contaTipo,
          cor: _contaCor,
          icone: _contaIcone,
          diaVencimento: _contaTipo == 'credito' ? _contaDiaVencimento : null,
          diaFechamento: _contaTipo == 'credito' ? _contaDiaFechamento : null,
        );
        await _accountRepository.save(conta);
      }

      await _settingsRepository.setConfig('onboarding_done', 'true');
      await AppState.loadPreferences();
      AppState.notifyDataChanged();

      if (mounted) widget.onComplete();
    } catch (e) {
      if (!mounted) return;
      showAppSnack(
        context,
        'Não foi possível concluir o onboarding: $e',
        isError: true,
      );
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final showBack = _page > 0;
    return Scaffold(
      backgroundColor: const Color(0xFFF7FBF8),
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFFFFFFF), Color(0xFFF2FBF5)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
                child: Row(
                  children: [
                    SizedBox(
                      width: 40,
                      child: showBack
                          ? IconButton(
                              onPressed: _saving ? null : _back,
                              icon: Icon(
                                Icons.arrow_back_ios_new_rounded,
                                color: context.textPrimary,
                                size: 18,
                              ),
                            )
                          : null,
                    ),
                    Expanded(
                      child: _OnboardingDots(current: _page, total: 4),
                    ),
                    const SizedBox(width: 40),
                  ],
                ),
              ),
              Expanded(
                child: PageView(
                  controller: _pageController,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    _WelcomeStep(onStart: _saving ? null : _next),
                    _NameStep(controller: _nomeCtrl),
                    _IncomeStep(
                      controller: _rendaCtrl,
                      mode: _incomeMode,
                      fixedDay: _incomeFixedDay,
                      businessDay: _incomeBusinessDay,
                      onModeChanged: (mode) =>
                          setState(() => _incomeMode = mode),
                      onFixedDayChanged: (value) =>
                          setState(() => _incomeFixedDay = value),
                      onBusinessDayChanged: (value) =>
                          setState(() => _incomeBusinessDay = value),
                    ),
                    _AccountStep(
                      nomeCtrl: _contaNomeCtrl,
                      saldoCtrl: _contaSaldoCtrl,
                      limiteCtrl: _contaLimiteCtrl,
                      tipo: _contaTipo,
                      selectedBankIcon: _contaIcone,
                      selectedColorHex: _contaCor,
                      diaVencimento: _contaDiaVencimento,
                      diaFechamento: _contaDiaFechamento,
                      onTipoChanged: (tipo) =>
                          setState(() => _contaTipo = tipo),
                      onBankSelected: _selectBank,
                      onDiaVencimentoChanged: (value) =>
                          setState(() => _contaDiaVencimento = value),
                      onDiaFechamentoChanged: (value) =>
                          setState(() => _contaDiaFechamento = value),
                    ),
                  ],
                ),
              ),
              if (_page > 0)
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                  child: Column(
                    children: [
                      GradientButton(
                        label: _page == 3 ? 'Continuar' : 'Continuar',
                        loading: _saving,
                        onPressed: _saving ? null : _next,
                      ),
                      if (_page == 3) ...[
                        const SizedBox(height: 12),
                        TextButton(
                          onPressed: _saving
                              ? null
                              : () => _finish(createFirstAccount: false),
                          child: Text(
                            'Adicionar conta depois',
                            style: TextStyle(
                              color: context.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OnboardingDots extends StatelessWidget {
  final int current;
  final int total;

  const _OnboardingDots({required this.current, required this.total});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(total, (index) {
        final active = index == current;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          width: active ? 22 : 9,
          height: 9,
          margin: const EdgeInsets.symmetric(horizontal: 5),
          decoration: BoxDecoration(
            color: active ? context.primary : const Color(0xFFD9DDE3),
            borderRadius: BorderRadius.circular(999),
          ),
        );
      }),
    );
  }
}

class _WelcomeStep extends StatelessWidget {
  final VoidCallback? onStart;

  const _WelcomeStep({this.onStart});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 12, 28, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 10),
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    _IllustrationCard(
                      assetPath: 'assets/onboarding/welcome_wallet.svg',
                    ),
                    const SizedBox(height: 36),
                    Text(
                      'Bem-vindo ao\nseu novo jeito de\ncuidar do dinheiro',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: context.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Organize suas finanças, acompanhe seus gastos e alcance seus objetivos com mais tranquilidade.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: context.textSecondary,
                        fontSize: 14,
                        height: 1.6,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          GradientButton(
            label: 'Vamos começar',
            onPressed: onStart,
          ),
        ],
      ),
    );
  }
}

class _NameStep extends StatelessWidget {
  final TextEditingController controller;

  const _NameStep({required this.controller});

  @override
  Widget build(BuildContext context) {
    return _StepShell(
      assetPath: 'assets/onboarding/profile_circle.svg',
      badgeIcon: Icons.person_rounded,
      title: 'Para começar,\nqual é o seu nome?',
      subtitle: 'Assim podemos personalizar sua experiência.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _FieldLabel('Nome completo'),
          const SizedBox(height: 10),
          _AppTextField(
            controller: controller,
            hintText: 'Digite seu nome',
            autofocus: true,
            textCapitalization: TextCapitalization.words,
          ),
        ],
      ),
    );
  }
}

class _IncomeStep extends StatelessWidget {
  final TextEditingController controller;
  final _IncomeMode mode;
  final int fixedDay;
  final int businessDay;
  final ValueChanged<_IncomeMode> onModeChanged;
  final ValueChanged<int> onFixedDayChanged;
  final ValueChanged<int> onBusinessDayChanged;

  const _IncomeStep({
    required this.controller,
    required this.mode,
    required this.fixedDay,
    required this.businessDay,
    required this.onModeChanged,
    required this.onFixedDayChanged,
    required this.onBusinessDayChanged,
  });

  @override
  Widget build(BuildContext context) {
    return _StepShell(
      assetPath: 'assets/onboarding/income_card.svg',
      badgeIcon: Icons.payments_rounded,
      title: 'Qual é a sua\nrenda mensal?',
      subtitle:
          'Essa informação nos ajuda a criar sua renda base e melhores insights.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _FieldLabel('Valor da renda mensal'),
          const SizedBox(height: 10),
          _AppTextField(
            controller: controller,
            hintText: '0,00',
            prefixText: 'R\$ ',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            autofocus: true,
          ),
          const SizedBox(height: 22),
          _FieldLabel('Quando você recebe?'),
          const SizedBox(height: 8),
          Text(
            'Escolha a opção que melhor te descreve.',
            style: TextStyle(color: context.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 14),
          _SelectableInfoCard(
            icon: Icons.calendar_today_rounded,
            title: 'Dia fixo do mês',
            subtitle: 'Recebo sempre no mesmo dia do mês',
            selected: mode == _IncomeMode.fixedDay,
            onTap: () => onModeChanged(_IncomeMode.fixedDay),
          ),
          const SizedBox(height: 12),
          _SelectableInfoCard(
            icon: Icons.event_repeat_rounded,
            title: 'Dia útil',
            subtitle: 'Recebo de acordo com a posição no mês útil',
            selected: mode == _IncomeMode.businessDay,
            onTap: () => onModeChanged(_IncomeMode.businessDay),
          ),
          const SizedBox(height: 18),
          _FieldLabel(
            mode == _IncomeMode.fixedDay
                ? 'Dia do recebimento'
                : 'Qual dia útil?',
          ),
          const SizedBox(height: 10),
          if (mode == _IncomeMode.fixedDay)
            _DropdownField<int>(
              value: fixedDay,
              items: List.generate(31, (index) => index + 1),
              labelBuilder: (value) => 'Dia $value',
              onChanged: (value) {
                if (value != null) onFixedDayChanged(value);
              },
            )
          else
            _DropdownField<int>(
              value: businessDay,
              items: const [1, 2, 3, 4, 5],
              labelBuilder: (value) => '$valueº dia útil',
              onChanged: (value) {
                if (value != null) onBusinessDayChanged(value);
              },
            ),
        ],
      ),
    );
  }
}

class _AccountStep extends StatelessWidget {
  final TextEditingController nomeCtrl;
  final TextEditingController saldoCtrl;
  final TextEditingController limiteCtrl;
  final String tipo;
  final String? selectedBankIcon;
  final String selectedColorHex;
  final int diaVencimento;
  final int diaFechamento;
  final ValueChanged<String> onTipoChanged;
  final ValueChanged<BancoInfo> onBankSelected;
  final ValueChanged<int> onDiaVencimentoChanged;
  final ValueChanged<int> onDiaFechamentoChanged;

  const _AccountStep({
    required this.nomeCtrl,
    required this.saldoCtrl,
    required this.limiteCtrl,
    required this.tipo,
    required this.selectedBankIcon,
    required this.selectedColorHex,
    required this.diaVencimento,
    required this.diaFechamento,
    required this.onTipoChanged,
    required this.onBankSelected,
    required this.onDiaVencimentoChanged,
    required this.onDiaFechamentoChanged,
  });

  Color _hexToColor(String hex) {
    return Color(int.parse('FF$hex', radix: 16));
  }

  @override
  Widget build(BuildContext context) {
    return _StepShell(
      assetPath: 'assets/onboarding/accounts_grid.svg',
      badgeIcon: Icons.account_balance_rounded,
      title: 'Quais contas você\nusa no dia a dia?',
      subtitle:
          'Adicione sua primeira conta para centralizar tudo em um só lugar.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _FieldLabel('Selecione seu banco / instituição'),
          const SizedBox(height: 12),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: bancosConhecidos.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 0.95,
            ),
            itemBuilder: (context, index) {
              final bank = bancosConhecidos[index];
              final selected = bank.icone == selectedBankIcon;
              final color = _hexToColor(bank.cor);
              return GestureDetector(
                onTap: () => onBankSelected(bank),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: selected ? color : const Color(0xFFE5E7EB),
                      width: selected ? 2 : 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: selected
                            ? color.withValues(alpha: 0.12)
                            : Colors.black.withValues(alpha: 0.03),
                        blurRadius: 18,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.account_balance_rounded,
                          color: color,
                          size: 20,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        bank.nome,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: context.textPrimary,
                          fontSize: 11,
                          fontWeight:
                              selected ? FontWeight.w700 : FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 20),
          _FieldLabel('Tipo de conta'),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _TypeCard(
                  label: 'Corrente',
                  icon: Icons.account_balance_wallet_rounded,
                  selected: tipo == 'corrente',
                  onTap: () => onTipoChanged('corrente'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _TypeCard(
                  label: 'Poupança',
                  icon: Icons.savings_rounded,
                  selected: tipo == 'poupanca',
                  onTap: () => onTipoChanged('poupanca'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _TypeCard(
                  label: 'Cartão',
                  icon: Icons.credit_card_rounded,
                  selected: tipo == 'credito',
                  onTap: () => onTipoChanged('credito'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _FieldLabel('Nome da conta'),
          const SizedBox(height: 10),
          _AppTextField(
            controller: nomeCtrl,
            hintText: 'Ex.: Nubank, Inter, Carteira...',
            textCapitalization: TextCapitalization.words,
          ),
          const SizedBox(height: 16),
          _FieldLabel(
            tipo == 'credito'
                ? 'Saldo atual da fatura (opcional)'
                : 'Saldo atual (opcional)',
          ),
          const SizedBox(height: 10),
          _AppTextField(
            controller: saldoCtrl,
            hintText: '0,00',
            prefixText: 'R\$ ',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
          if (tipo == 'credito') ...[
            const SizedBox(height: 16),
            _FieldLabel('Limite do cartão'),
            const SizedBox(height: 10),
            _AppTextField(
              controller: limiteCtrl,
              hintText: '0,00',
              prefixText: 'R\$ ',
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _DropdownBlock(
                    label: 'Dia de fechamento',
                    child: _DropdownField<int>(
                      value: diaFechamento,
                      items: List.generate(31, (index) => index + 1),
                      labelBuilder: (value) => 'Dia $value',
                      onChanged: (value) {
                        if (value != null) onDiaFechamentoChanged(value);
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _DropdownBlock(
                    label: 'Dia de vencimento',
                    child: _DropdownField<int>(
                      value: diaVencimento,
                      items: List.generate(31, (index) => index + 1),
                      labelBuilder: (value) => 'Dia $value',
                      onChanged: (value) {
                        if (value != null) onDiaVencimentoChanged(value);
                      },
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _StepShell extends StatelessWidget {
  final String assetPath;
  final IconData badgeIcon;
  final String title;
  final String subtitle;
  final Widget child;

  const _StepShell({
    required this.assetPath,
    required this.badgeIcon,
    required this.title,
    required this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 8, 28, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _IllustrationCard(assetPath: assetPath, badgeIcon: badgeIcon),
          const SizedBox(height: 28),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: context.textPrimary,
              fontSize: 19,
              fontWeight: FontWeight.w800,
              height: 1.32,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: context.textSecondary,
              fontSize: 14,
              height: 1.55,
            ),
          ),
          const SizedBox(height: 28),
          Align(
            alignment: Alignment.centerLeft,
            child: child,
          ),
        ],
      ),
    );
  }
}

class _IllustrationCard extends StatelessWidget {
  final String assetPath;
  final IconData? badgeIcon;

  const _IllustrationCard({
    required this.assetPath,
    this.badgeIcon,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.topCenter,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(18, 28, 18, 18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(32),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 28,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: SvgPicture.asset(
            assetPath,
            height: 210,
            fit: BoxFit.contain,
          ),
        ),
        if (badgeIcon != null)
          Positioned(
            top: 10,
            child: Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: const Color(0xFFE8F9EE),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF16A34A).withValues(alpha: 0.08),
                    blurRadius: 12,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Icon(badgeIcon, color: const Color(0xFF16A34A), size: 28),
            ),
          ),
      ],
    );
  }
}

class _SelectableInfoCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  const _SelectableInfoCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? context.primary : const Color(0xFFE5E7EB),
            width: selected ? 1.8 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: selected
                  ? context.primary.withValues(alpha: 0.08)
                  : Colors.black.withValues(alpha: 0.03),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: selected
                    ? context.primary.withValues(alpha: 0.10)
                    : const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                icon,
                color: selected ? context.primary : context.textSecondary,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: context.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: context.textSecondary,
                      fontSize: 12,
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? context.primary : const Color(0xFFD1D5DB),
                  width: 2,
                ),
              ),
              child: selected
                  ? Center(
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: context.primary,
                          shape: BoxShape.circle,
                        ),
                      ),
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _TypeCard extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _TypeCard({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        decoration: BoxDecoration(
          color:
              selected ? context.primary.withValues(alpha: 0.08) : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? context.primary : const Color(0xFFE5E7EB),
            width: selected ? 1.8 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              color: selected ? context.primary : context.textSecondary,
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                color: selected ? context.primary : context.textSecondary,
                fontSize: 12,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String text;

  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        color: context.textPrimary,
        fontSize: 13,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _AppTextField extends StatelessWidget {
  final TextEditingController controller;
  final String hintText;
  final String? prefixText;
  final TextInputType? keyboardType;
  final TextCapitalization textCapitalization;
  final bool autofocus;

  const _AppTextField({
    required this.controller,
    required this.hintText,
    this.prefixText,
    this.keyboardType,
    this.textCapitalization = TextCapitalization.none,
    this.autofocus = false,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      textCapitalization: textCapitalization,
      autofocus: autofocus,
      style: TextStyle(
        color: context.textPrimary,
        fontSize: 16,
        fontWeight: FontWeight.w600,
      ),
      decoration: InputDecoration(
        hintText: hintText,
        prefixText: prefixText,
        prefixStyle: TextStyle(
          color: context.textSecondary,
          fontWeight: FontWeight.w600,
        ),
        hintStyle: TextStyle(color: context.textTertiary),
        filled: true,
        fillColor: Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: context.primary, width: 1.8),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
        ),
      ),
    );
  }
}

class _DropdownBlock extends StatelessWidget {
  final String label;
  final Widget child;

  const _DropdownBlock({
    required this.label,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FieldLabel(label),
        const SizedBox(height: 10),
        child,
      ],
    );
  }
}

class _DropdownField<T> extends StatelessWidget {
  final T value;
  final List<T> items;
  final String Function(T value) labelBuilder;
  final ValueChanged<T?> onChanged;

  const _DropdownField({
    required this.value,
    required this.items,
    required this.labelBuilder,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          dropdownColor: context.appSurface,
          borderRadius: BorderRadius.circular(18),
          style: TextStyle(
            color: context.textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
          items: items
              .map(
                (item) => DropdownMenuItem<T>(
                  value: item,
                  child: Text(labelBuilder(item)),
                ),
              )
              .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }
}
