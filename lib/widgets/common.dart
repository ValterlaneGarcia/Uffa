import 'package:flutter/material.dart';
import '../utils/app_theme.dart';
import '../utils/formatters.dart';

/// Primary action button – solid green, full-width
class GradientButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final IconData? icon;

  const GradientButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: ElevatedButton(
        onPressed: loading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: context.primary,
          disabledBackgroundColor: context.textTertiary,
          foregroundColor: Colors.white,
          elevation: 0,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: loading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                    color: Colors.white, strokeWidth: 2),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 20),
                    const SizedBox(width: 8),
                  ],
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

/// Card container – white with subtle border shadow
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets? padding;
  final VoidCallback? onTap;
  final Color? color;
  final BorderRadius? borderRadius;

  const AppCard({
    super.key,
    required this.child,
    this.padding,
    this.onTap,
    this.color,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    final br = borderRadius ?? BorderRadius.circular(16);
    Widget w = Container(
      padding: padding ?? const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: color ?? context.appCard,
        borderRadius: br,
        border: Border.all(color: context.appDivider, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );
    if (onTap != null) {
      w = InkWell(
        onTap: onTap,
        borderRadius: br,
        child: w,
      );
    }
    return w;
  }
}

/// Section header – dark title + optional tappable action
class SectionHeader extends StatelessWidget {
  final String title;
  final String? action;
  final VoidCallback? onAction;

  const SectionHeader({
    super.key,
    required this.title,
    this.action,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: context.textPrimary,
          ),
        ),
        if (action != null)
          GestureDetector(
            onTap: onAction,
            child: Text(
              action!,
              style: TextStyle(
                fontSize: 13,
                color: context.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
      ],
    );
  }
}

void showAppSnack(
  BuildContext context,
  String message, {
  bool isError = false,
  IconData? icon,
  Color? backgroundColor,
}) {
  final messenger = ScaffoldMessenger.of(context);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              icon ??
                  (isError
                      ? Icons.error_outline_rounded
                      : Icons.check_circle_outline_rounded),
              color: Colors.white,
              size: 18,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
        backgroundColor:
            backgroundColor ?? (isError ? AppColors.red : context.textPrimary),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
}

class LegendDot extends StatelessWidget {
  final Color color;
  final String label;

  const LegendDot({
    super.key,
    required this.color,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(fontSize: 11, color: context.textSecondary),
        ),
      ],
    );
  }
}

class MonthNavigator extends StatelessWidget {
  final DateTime selectedMonth;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback? onTap;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final Color? iconColor;
  final EdgeInsetsGeometry padding;
  final double borderRadius;
  final double fontSize;

  const MonthNavigator({
    super.key,
    required this.selectedMonth,
    required this.onPrev,
    required this.onNext,
    this.onTap,
    this.backgroundColor,
    this.foregroundColor,
    this.iconColor,
    this.padding = const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
    this.borderRadius = 20,
    this.fontSize = 12,
  });

  @override
  Widget build(BuildContext context) {
    final fg = foregroundColor ?? context.textPrimary;
    final ic = iconColor ?? context.textSecondary;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: backgroundColor ?? context.appCardLight,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: Icon(Icons.chevron_left, color: ic, size: 18),
            onPressed: onPrev,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            padding: EdgeInsets.zero,
          ),
          GestureDetector(
            onTap: onTap,
            child: Text(
              mesAbrevLabel(selectedMonth),
              style: TextStyle(
                color: fg,
                fontSize: fontSize,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          IconButton(
            icon: Icon(Icons.chevron_right, color: ic, size: 18),
            onPressed: onNext,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            padding: EdgeInsets.zero,
          ),
        ],
      ),
    );
  }
}

/// Month selector pill
class MonthSelectorPill extends StatelessWidget {
  final DateTime selectedMonth;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback? onTap;

  const MonthSelectorPill({
    super.key,
    required this.selectedMonth,
    required this.onPrev,
    required this.onNext,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return MonthNavigator(
      selectedMonth: selectedMonth,
      onPrev: onPrev,
      onNext: onNext,
      onTap: onTap,
    );
  }
}

/// Empty state widget
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  /// Optional accent color for the icon rings. Defaults to primary color.
  final Color? accentColor;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
    this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final color = accentColor ?? context.primary;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 48),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Layered concentric rings illustration
            Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.07),
                    shape: BoxShape.circle,
                  ),
                ),
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.12),
                    shape: BoxShape.circle,
                  ),
                ),
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.18),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 26, color: color),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              title,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: context.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 8),
              Text(
                subtitle!,
                style: TextStyle(
                    fontSize: 13, color: context.textSecondary, height: 1.5),
                textAlign: TextAlign.center,
              ),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 28),
              FilledButton.icon(
                onPressed: onAction,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: Text(actionLabel!),
                style: FilledButton.styleFrom(
                  backgroundColor: color,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  textStyle: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 14),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Loading state
class LoadingState extends StatelessWidget {
  const LoadingState({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: CircularProgressIndicator(
        color: context.primary,
        strokeWidth: 2,
      ),
    );
  }
}

class ErrorState extends StatelessWidget {
  final String title;
  final String? message;
  final VoidCallback? onRetry;

  const ErrorState({
    super.key,
    this.title = 'Erro ao carregar dados',
    this.message,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: AppColors.red.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.error_outline_rounded,
                color: AppColors.red,
                size: 28,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: context.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            if (message != null && message!.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                message!,
                style: TextStyle(
                  fontSize: 13,
                  color: context.textSecondary,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
            ],
            if (onRetry != null) ...[
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Tentar novamente'),
                style: FilledButton.styleFrom(
                  backgroundColor: context.primary,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Value display with optional masking
class ValueDisplay extends StatelessWidget {
  final double value;
  final bool visible;
  final double fontSize;
  final Color? color;
  final String prefix;

  const ValueDisplay({
    super.key,
    required this.value,
    this.visible = true,
    this.fontSize = 28,
    this.color,
    this.prefix = '',
  });

  @override
  Widget build(BuildContext context) {
    return Text(
      visible ? '$prefix${_fmt(value)}' : 'R\$ ••••••',
      style: TextStyle(
        fontSize: fontSize,
        fontWeight: FontWeight.w800,
        color: color ?? context.textPrimary,
        letterSpacing: -0.5,
      ),
    );
  }

  String _fmt(double v) {
    final abs = v.abs();
    final sign = v < 0 ? '-' : '';
    return '$sign${_brl(abs)}';
  }

  String _brl(double v) {
    return 'R\$ ${v.toStringAsFixed(2).replaceAll('.', ',').replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.')}';
  }
}

/// Category icon + color helper
class CategoriaHelper {
  static const Map<String, IconData> _iconMap = {
    'restaurant': Icons.restaurant_rounded,
    'home': Icons.home_rounded,
    'directions_car': Icons.directions_car_rounded,
    'favorite': Icons.favorite_rounded,
    'sports_esports': Icons.sports_esports_rounded,
    'tv': Icons.tv_rounded,
    'school': Icons.school_rounded,
    'account_balance_wallet': Icons.account_balance_wallet_rounded,
    'work': Icons.work_rounded,
    'trending_up': Icons.trending_up_rounded,
    'category': Icons.category_rounded,
    'subscriptions': Icons.subscriptions_rounded,
    'checkroom': Icons.checkroom_rounded,
    'flight': Icons.flight_rounded,
    'local_grocery_store': Icons.local_grocery_store_rounded,
    'phone_android': Icons.phone_android_rounded,
    'fitness_center': Icons.fitness_center_rounded,
    'pets': Icons.pets_rounded,
    'child_care': Icons.child_care_rounded,
    'coffee': Icons.coffee_rounded,
    'sports_bar': Icons.sports_bar_rounded,
    'music_note': Icons.music_note_rounded,
    'palette': Icons.palette_rounded,
    'construction': Icons.construction_rounded,
    'attach_money': Icons.attach_money_rounded,
  };

  static const _map = {
    'Alimentação': (Icons.restaurant_rounded, Color(0xFFF59E0B)),
    'Moradia': (Icons.home_rounded, Color(0xFF2563EB)),
    'Transporte': (Icons.directions_car_rounded, Color(0xFF7C3AED)),
    'Saúde': (Icons.favorite_rounded, Color(0xFF0891B2)),
    'Lazer': (Icons.sports_esports_rounded, Color(0xFFEC4899)),
    'Entretenimento': (Icons.tv_rounded, Color(0xFFDC2626)),
    'Educação': (Icons.school_rounded, Color(0xFF4F46E5)),
    'Salário': (Icons.account_balance_wallet_rounded, Color(0xFF16A34A)),
    'Freelance': (Icons.work_rounded, Color(0xFF16A34A)),
    'Investimentos': (Icons.trending_up_rounded, Color(0xFF16A34A)),
    'Outros': (Icons.category_rounded, Color(0xFF6B7280)),
    'Assinatura': (Icons.subscriptions_rounded, Color(0xFF7C3AED)),
    'Vestuário': (Icons.checkroom_rounded, Color(0xFFEC4899)),
    'Viagem': (Icons.flight_rounded, Color(0xFF2563EB)),
  };

  static final Map<String, (IconData, Color)> _cache = {};

  static void loadFromRows(List<Map<String, dynamic>> rows) {
    _cache.clear();
    for (final r in rows) {
      final nome = r['nome'] as String;
      final corHex = r['cor'] as String? ?? '6B7280';
      final iconeKey = r['icone'] as String? ?? 'category';
      final icon = _iconMap[iconeKey] ?? Icons.category_rounded;
      final color = Color(int.parse('FF$corHex', radix: 16));
      _cache[nome] = (icon, color);
    }
  }

  static (IconData, Color) get(String categoria) {
    if (_cache.containsKey(categoria)) return _cache[categoria]!;
    if (_map.containsKey(categoria)) return _map[categoria]!;
    final lower = categoria.toLowerCase();
    for (final entry in {..._cache, ..._map}.entries) {
      if (lower.contains(entry.key.toLowerCase()) ||
          entry.key.toLowerCase().contains(lower)) {
        return entry.value;
      }
    }
    return (Icons.circle_outlined, const Color(0xFF6B7280));
  }

  static Color getColor(String categoria) => get(categoria).$2;
  static IconData getIcon(String categoria) => get(categoria).$1;

  static IconData iconFromName(String name) =>
      _iconMap[name] ?? Icons.category_rounded;

  static List<(String, IconData)> get availableIcons =>
      _iconMap.entries.map((e) => (e.key, e.value)).toList();

  static const List<String> todas = [
    'Alimentação',
    'Moradia',
    'Transporte',
    'Saúde',
    'Lazer',
    'Entretenimento',
    'Educação',
    'Vestuário',
    'Viagem',
    'Assinatura',
    'Salário',
    'Freelance',
    'Investimentos',
    'Outros',
  ];
}
