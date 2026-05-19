import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'dashboard/dashboard_screen.dart';
import 'transactions/transactions_screen.dart';
import 'accounts/accounts_screen.dart';
import 'planning/planning_screen.dart';
import 'settings/settings_screen.dart';
import 'onboarding/onboarding_screen.dart';
import '../utils/app_theme.dart';
import '../utils/app_state.dart';
import '../data/db/app_db.dart';
import '../services/notification_service.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

/// Tempo máximo em background antes de exigir reautenticação.
/// Abaixo desse limite o app volta sem pedir biometria — ideal para
/// quem alterna rapidamente entre apps (copiar código, checar msg, etc.).
/// Altere conforme a política desejada (ex: Duration(minutes: 10)).
const _kGracePeriod = Duration(minutes: 5);

class _MainShellState extends State<MainShell> with WidgetsBindingObserver {
  int _currentIndex = 0;

  bool _locked = false;
  bool _authenticating = false;
  bool _onboardingDone = true; // optimistic: shown only after check
  bool _checkingOnboarding = true;
  final _localAuth = LocalAuthentication();

  final List<GlobalKey> _screenKeys = List.generate(5, (_) => GlobalKey());

  DateTime? _backgroundedAt;
  DateTime? _lastUnlockTime;
  Timer? _notificationSyncDebounce;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AppState.instance.addListener(_onDataChanged);
    _checkOnboarding();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    AppState.instance.removeListener(_onDataChanged);
    _notificationSyncDebounce?.cancel();
    super.dispose();
  }

  void _onDataChanged() {
    _queueNotificationSync();
    if (mounted) setState(() {});
  }

  void _queueNotificationSync() {
    _notificationSyncDebounce?.cancel();
    _notificationSyncDebounce = Timer(const Duration(milliseconds: 400), () {
      NotificationService.syncFromDatabase();
    });
  }

  Future<void> _checkOnboarding() async {
    final config = await AppDB.getConfig();
    final done = config['onboarding_done'] == 'true';
    if (!mounted) return;
    setState(() {
      _onboardingDone = done;
      _checkingOnboarding = false;
    });
    if (done) {
      _queueNotificationSync();
    }
    if (done) _checkLockOnStartup();
  }

  void _completeOnboarding() {
    setState(() => _onboardingDone = true);
    _checkLockOnStartup();
  }

  Future<void> _checkLockOnStartup() async {
    final config = await AppDB.getConfig();
    final biometricoAtivo = config['biometrico_ativo'] == 'true';
    if (!mounted) return;
    if (biometricoAtivo) {
      setState(() => _locked = true);
      await _authenticate();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      // App saiu de foco: usuário trocou de app, apagou tela, etc.
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.inactive:
        // Registra o momento de saída apenas se não estiver em processo de
        // autenticação — o diálogo de biometria em si causa transições
        // inactive/paused que não devem ser contabilizadas como "saída real".
        if (!_locked && !_authenticating) {
          _backgroundedAt = DateTime.now();
        }
        break;
      case AppLifecycleState.resumed:
        _onAppResumed();
        break;
      default:
        break;
    }
  }

  Future<void> _onAppResumed() async {
    _queueNotificationSync();
    final config = await AppDB.getConfig();
    final biometricoAtivo = config['biometrico_ativo'] == 'true';
    if (!mounted || !biometricoAtivo || _locked || _authenticating) return;

    final now = DateTime.now();

    // 1) O diálogo de biometria provoca um ciclo inactive → resumed.
    //    Se acabamos de desbloquear (< 3 s), não bloqueamos de novo.
    if (_lastUnlockTime != null &&
        now.difference(_lastUnlockTime!) < const Duration(seconds: 3)) {
      return;
    }

    // 2) Verifica se o app ficou em background mais do que o período de
    //    tolerância. Se ficou pouco tempo (ex: usuário alt‑tabbed por
    //    segundos para copiar um dado), não exige reautenticação.
    if (_backgroundedAt != null &&
        now.difference(_backgroundedAt!) < _kGracePeriod) {
      _backgroundedAt = null; // reseta para a próxima saída
      return;
    }

    // Período de graça expirado (ou app voltou sem registro de saída):
    // bloqueia e pede autenticação.
    _backgroundedAt = null;
    setState(() => _locked = true);
    await _authenticate();
  }

  Future<void> _authenticate() async {
    if (_authenticating) return;
    if (mounted) setState(() => _authenticating = true);
    try {
      final authenticated = await _localAuth.authenticate(
        localizedReason: 'Confirme sua identidade para acessar o FinanceApp',
        options: const AuthenticationOptions(
          biometricOnly: false,
          stickyAuth: true,
        ),
      );
      if (!mounted) return;
      if (authenticated) {
        setState(() {
          _locked = false;
          _authenticating = false;
          _lastUnlockTime = DateTime.now();
          _backgroundedAt = null; // garante estado limpo após desbloqueio
        });
      } else {
        setState(() => _authenticating = false);
      }
    } catch (_) {
      if (mounted) setState(() => _authenticating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ));

    if (_checkingOnboarding) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (!_onboardingDone) {
      return OnboardingScreen(onComplete: _completeOnboarding);
    }

    if (_locked) {
      return _LockScreen(
        onUnlock: _authenticate,
        authenticating: _authenticating,
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: IndexedStack(
        index: _currentIndex,
        children: [
          DashboardScreen(key: _screenKeys[0]),
          TransactionsScreen(key: _screenKeys[1]),
          AccountsScreen(key: _screenKeys[2]),
          PlanningScreen(key: _screenKeys[3]),
          SettingsScreen(key: _screenKeys[4]),
        ],
      ),
      bottomNavigationBar: _BottomNav(
        currentIndex: _currentIndex,
        onTap: (i) => setState(() => _currentIndex = i),
      ),
    );
  }
}

// ─── Lock Screen ───────────────────────────────────────────────

class _LockScreen extends StatelessWidget {
  final VoidCallback onUnlock;
  final bool authenticating;

  const _LockScreen({required this.onUnlock, required this.authenticating});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  color: AppState.instance.primaryColor.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.lock_rounded,
                  size: 44,
                  color: AppState.instance.primaryColor,
                ),
              ),
              const SizedBox(height: 28),
              const Text(
                'FinanceApp',
                style: TextStyle(
                  color: AppColors.textPrimaryDark,
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Confirme sua identidade para continuar',
                style: TextStyle(
                  color: AppColors.textSecondaryDark,
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 48),
              if (authenticating)
                const CircularProgressIndicator()
              else
                ElevatedButton.icon(
                  onPressed: onUnlock,
                  icon: const Icon(Icons.fingerprint_rounded, size: 22),
                  label: const Text(
                    'Desbloquear',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppState.instance.primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 32, vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                    elevation: 0,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Bottom Nav ────────────────────────────────────────────────

class _BottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const _BottomNav({required this.currentIndex, required this.onTap});

  static const _items = [
    (Icons.home_rounded, Icons.home_outlined, 'Início'),
    (Icons.swap_horiz_rounded, Icons.swap_horiz_outlined, 'Transações'),
    (
      Icons.account_balance_wallet_rounded,
      Icons.account_balance_wallet_outlined,
      'Contas'
    ),
    (Icons.bar_chart_rounded, Icons.bar_chart_outlined, 'Planejar'),
    (Icons.settings_rounded, Icons.settings_outlined, 'Mais'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(
          top: BorderSide(color: AppColors.divider, width: 1),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: List.generate(_items.length, (i) {
              final item = _items[i];
              final active = i == currentIndex;
              return _NavItem(
                iconActive: item.$1,
                iconInactive: item.$2,
                label: item.$3,
                active: active,
                onTap: () => onTap(i),
              );
            }),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData iconActive;
  final IconData iconInactive;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _NavItem({
    required this.iconActive,
    required this.iconInactive,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color =
        active ? AppState.instance.primaryColor : AppColors.textSecondary;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 64,
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        decoration: BoxDecoration(
          color: active
              ? AppState.instance.primaryColor.withOpacity(0.10)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              active ? iconActive : iconInactive,
              size: 24,
              color: color,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: active ? FontWeight.w700 : FontWeight.w400,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
