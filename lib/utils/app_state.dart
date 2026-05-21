import 'package:flutter/material.dart';
import '../repositories/settings_repository.dart';

// ─── Preset de tema nomeado ────────────────────────────────────────────────
// Cada preset agrupa: nome, cor primária (hex sem alpha) e modo claro/escuro.
// O preset 'Padrão' representa o estado de fábrica do app.

class AppThemePreset {
  final String name;
  final String hex; // cor primária sem alpha, ex: '16A34A'
  final ThemeMode mode;
  final IconData icon;

  const AppThemePreset({
    required this.name,
    required this.hex,
    required this.mode,
    required this.icon,
  });

  Color get color => _colorFromHex(hex, AppThemePreset.defaultPreset.hex);

  static const defaultPreset = AppThemePreset(
    name: 'Padrão',
    hex: '16A34A',
    mode: ThemeMode.light,
    icon: Icons.eco_rounded,
  );

  static const List<AppThemePreset> all = [
    defaultPreset,
    AppThemePreset(
      name: 'Oceano',
      hex: '0284C7',
      mode: ThemeMode.light,
      icon: Icons.water_rounded,
    ),
    AppThemePreset(
      name: 'Meia-noite',
      hex: '6366F1',
      mode: ThemeMode.dark,
      icon: Icons.nights_stay_rounded,
    ),
    AppThemePreset(
      name: 'Aurora',
      hex: 'EC4899',
      mode: ThemeMode.dark,
      icon: Icons.auto_awesome_rounded,
    ),
    AppThemePreset(
      name: 'Ambar',
      hex: 'D97706',
      mode: ThemeMode.light,
      icon: Icons.wb_sunny_rounded,
    ),
    AppThemePreset(
      name: 'Floresta',
      hex: '059669',
      mode: ThemeMode.dark,
      icon: Icons.forest_rounded,
    ),
    AppThemePreset(
      name: 'Rubi',
      hex: 'DC2626',
      mode: ThemeMode.dark,
      icon: Icons.favorite_rounded,
    ),
    AppThemePreset(
      name: 'Ciano',
      hex: '0891B2',
      mode: ThemeMode.light,
      icon: Icons.waves_rounded,
    ),
  ];
}

/// Global notifier: any screen that mutates data calls [AppState.notify()].
class AppState extends ChangeNotifier {
  AppState._();
  static final AppState instance = AppState._();
  static const _settingsRepository = SettingsRepository.instance;
  final ChangeNotifier _dataNotifier = ChangeNotifier();

  // ── Theme ─────────────────────────────────────────────────────
  ThemeMode _themeMode = ThemeMode.light;
  ThemeMode get themeMode => _themeMode;

  // ── Primary color (hex sem alpha, ex: '16A34A') ───────────────
  String _primaryColorHex = AppThemePreset.defaultPreset.hex;
  String get primaryColorHex => _primaryColorHex;
  Color get primaryColor =>
      _colorFromHex(_primaryColorHex, AppThemePreset.defaultPreset.hex);

  // ── Balance visibility (global, persisted) ────────────────────
  bool _balanceVisible = true;
  bool get balanceVisible => _balanceVisible;

  /// Preset ativo, ou null se combinação cor+modo não bate com nenhum preset.
  AppThemePreset? get activePreset {
    final dark = _themeMode == ThemeMode.dark;
    for (final p in AppThemePreset.all) {
      if (p.hex == _primaryColorHex && (p.mode == ThemeMode.dark) == dark) {
        return p;
      }
    }
    return null;
  }

  static ChangeNotifier get dataChanges => instance._dataNotifier;
  static void notifyDataChanged() => instance._dataNotifier.notifyListeners();
  static void notify() => notifyDataChanged();

  static Future<void> loadPreferences() async {
    final config = await _settingsRepository.getConfig();

    final darkMode = config['tema_escuro'] == 'true';
    instance._themeMode = darkMode ? ThemeMode.dark : ThemeMode.light;

    final colorHex = config['cor_primaria'];
    if (colorHex != null && colorHex.isNotEmpty) {
      instance._primaryColorHex =
          _sanitizeHex(colorHex, AppThemePreset.defaultPreset.hex);
    }

    final balanceHidden = config['saldos_ocultos'] == 'true';
    instance._balanceVisible = !balanceHidden;
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    await _settingsRepository.setConfig(
        'tema_escuro', (mode == ThemeMode.dark).toString());
    notifyListeners();
  }

  Future<void> setPrimaryColor(String hexWithoutAlpha) async {
    _primaryColorHex =
        _sanitizeHex(hexWithoutAlpha, AppThemePreset.defaultPreset.hex);
    await _settingsRepository.setConfig('cor_primaria', _primaryColorHex);
    notifyListeners();
  }

  /// Aplica um preset completo (cor + modo) de uma so vez.
  Future<void> applyPreset(AppThemePreset preset) async {
    _primaryColorHex = preset.hex;
    _themeMode = preset.mode;
    await _settingsRepository.setConfig('cor_primaria', preset.hex);
    await _settingsRepository.setConfig(
        'tema_escuro', (preset.mode == ThemeMode.dark).toString());
    notifyListeners();
  }

  /// Reseta cor e modo para o padrao de fabrica.
  Future<void> resetToDefault() => applyPreset(AppThemePreset.defaultPreset);

  Future<void> toggleBalanceVisibility() async {
    _balanceVisible = !_balanceVisible;
    await _settingsRepository.setConfig(
        'saldos_ocultos', (!_balanceVisible).toString());
    notifyListeners();
  }
}

String _sanitizeHex(String value, String fallback) {
  final normalized = value.trim().replaceFirst(RegExp(r'^#'), '').toUpperCase();
  final withoutAlpha =
      normalized.length == 8 ? normalized.substring(2) : normalized;
  return RegExp(r'^[0-9A-F]{6}$').hasMatch(withoutAlpha)
      ? withoutAlpha
      : fallback;
}

Color _colorFromHex(String value, String fallback) {
  final hex = _sanitizeHex(value, fallback);
  return Color(int.parse('FF$hex', radix: 16));
}
