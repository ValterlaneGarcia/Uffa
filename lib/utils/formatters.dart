import 'package:intl/intl.dart';

final NumberFormat brl = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
final DateFormat dtFmt = DateFormat('dd/MM/yyyy');
final DateFormat monthFmt = DateFormat('MMMM yyyy', 'pt_BR');

String fmtBRL(double v) => brl.format(v);
double? parseBRL(String text) {
  final normalized = text
      .trim()
      .replaceAll('R\$', '')
      .replaceAll(' ', '')
      .replaceAll('.', '')
      .replaceAll(',', '.');
  if (normalized.isEmpty) return null;
  return double.tryParse(normalized);
}

String fmtBRLCompact(double v) {
  if (v.abs() >= 1000) {
    return 'R\$ ${(v / 1000).toStringAsFixed(1)}k';
  }
  return brl.format(v);
}

const List<String> mesesAbrev = [
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

const List<String> mesesFull = [
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

String mesAnoLabel(DateTime d) => '${mesesFull[d.month - 1]} ${d.year}';
String mesAbrevLabel(DateTime d) => '${mesesAbrev[d.month - 1]} ${d.year}';
