import 'package:uuid/uuid.dart';

class Orcamento {
  final String id;
  final String categoria;
  final double limite;
  final int mes;
  final int ano;
  /// Se true, o saldo não utilizado do mês anterior é somado ao limite deste mês.
  final bool rollover;

  Orcamento({
    String? id,
    required this.categoria,
    required this.limite,
    required this.mes,
    required this.ano,
    this.rollover = false,
  }) : id = id ?? const Uuid().v4();

  Map<String, dynamic> toMap() => {
        'id': id,
        'categoria': categoria,
        'limite': limite,
        'mes': mes,
        'ano': ano,
        'rollover': rollover ? 1 : 0,
      };

  factory Orcamento.fromMap(Map<String, dynamic> m) => Orcamento(
        id: m['id'],
        categoria: m['categoria'],
        limite: (m['limite'] as num).toDouble(),
        mes: m['mes'],
        ano: m['ano'],
        rollover: (m['rollover'] as int? ?? 0) == 1,
      );
}

class Meta {
  final String id;
  String nome;
  double valorAlvo;
  double valorAtual;
  String icone;
  String cor;
  DateTime? prazo;

  Meta({
    String? id,
    required this.nome,
    required this.valorAlvo,
    this.valorAtual = 0,
    this.icone = 'flag',
    this.cor = '22C55E',
    this.prazo,
  }) : id = id ?? const Uuid().v4();

  double get progresso => valorAlvo > 0 ? (valorAtual / valorAlvo).clamp(0.0, 1.0) : 0;

  Map<String, dynamic> toMap() => {
        'id': id,
        'nome': nome,
        'valor_alvo': valorAlvo,
        'valor_atual': valorAtual,
        'icone': icone,
        'cor': cor,
        'prazo': prazo?.toIso8601String(),
      };

  factory Meta.fromMap(Map<String, dynamic> m) => Meta(
        id: m['id'],
        nome: m['nome'],
        valorAlvo: (m['valor_alvo'] as num).toDouble(),
        valorAtual: (m['valor_atual'] as num? ?? 0).toDouble(),
        icone: m['icone'] ?? 'flag',
        cor: m['cor'] ?? '22C55E',
        prazo: m['prazo'] != null ? DateTime.parse(m['prazo']) : null,
      );
}
