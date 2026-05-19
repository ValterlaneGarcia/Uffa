import 'package:uuid/uuid.dart';

enum TipoTransacao { entrada, saida, saldo, receita, investimento }

enum Recorrencia { nenhuma, semanal, mensal, anual }

class Transacao {
  final String id;
  double valor;
  String banco;
  int parcelas;
  DateTime primeiraParcela;
  String categoria;
  TipoTransacao tipo;
  String? descricao;
  Recorrencia recorrencia;
  String? recorrenciaGrupoId; // links recurring instances

  Transacao({
    String? id,
    required this.valor,
    required this.banco,
    required this.parcelas,
    required this.primeiraParcela,
    this.categoria = '',
    required this.tipo,
    this.descricao,
    this.recorrencia = Recorrencia.nenhuma,
    this.recorrenciaGrupoId,
  }) : id = id ?? const Uuid().v4();

  double get valorParcela => parcelas > 0 ? valor / parcelas : valor;
  bool get isDespesa => valor < 0;
  bool get isReceita => valor > 0;
  bool get isRecorrente => recorrencia != Recorrencia.nenhuma;

  double valorNoMes(int ano, int mes) {
    // Recurrent: always shows if started before or in this month
    if (recorrencia == Recorrencia.mensal) {
      final inicio = DateTime(primeiraParcela.year, primeiraParcela.month);
      final alvo = DateTime(ano, mes);
      if (!alvo.isBefore(inicio)) return valor;
      return 0;
    }
    if (recorrencia == Recorrencia.anual) {
      if (primeiraParcela.month == mes && primeiraParcela.year <= ano) {
        return valor;
      }
      return 0;
    }
    if (recorrencia == Recorrencia.semanal) {
      final inicio = DateTime(primeiraParcela.year, primeiraParcela.month);
      final alvo = DateTime(ano, mes);
      if (alvo.isBefore(inicio)) return 0;
      // Count how many times the weekday of primeiraParcela occurs in the target month,
      // respecting the start date when the month is the first one.
      int count = 0;
      final int targetWeekday = primeiraParcela.weekday;
      final DateTime startOfCount = (alvo == inicio) ? primeiraParcela : DateTime(ano, mes, 1);
      final DateTime endOfMonth = DateTime(ano, mes + 1, 0);
      DateTime d = startOfCount;
      while (!d.isAfter(endOfMonth)) {
        if (d.weekday == targetWeekday) count++;
        d = d.add(const Duration(days: 1));
      }
      return valor * count;
    }
    // Installments
    for (int i = 0; i < parcelas; i++) {
      final rawDate = DateTime(
        primeiraParcela.year,
        primeiraParcela.month + i,
        1,
      );
      final lastDay = DateTime(rawDate.year, rawDate.month + 1, 0).day;
      final dt = DateTime(rawDate.year, rawDate.month, primeiraParcela.day.clamp(1, lastDay));
      if (dt.year == ano && dt.month == mes) return valorParcela;
    }
    return 0;
  }

  Transacao copyWith({
    String? id,
    double? valor,
    String? banco,
    int? parcelas,
    DateTime? primeiraParcela,
    String? categoria,
    TipoTransacao? tipo,
    String? descricao,
    Recorrencia? recorrencia,
    String? recorrenciaGrupoId,
  }) {
    return Transacao(
      id: id ?? this.id,
      valor: valor ?? this.valor,
      banco: banco ?? this.banco,
      parcelas: parcelas ?? this.parcelas,
      primeiraParcela: primeiraParcela ?? this.primeiraParcela,
      categoria: categoria ?? this.categoria,
      tipo: tipo ?? this.tipo,
      descricao: descricao ?? this.descricao,
      recorrencia: recorrencia ?? this.recorrencia,
      recorrenciaGrupoId: recorrenciaGrupoId ?? this.recorrenciaGrupoId,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'valor': valor,
        'banco': banco,
        'parcelas': parcelas,
        'primeira_parcela': primeiraParcela.toIso8601String(),
        'categoria': categoria,
        'tipo': tipo.index,
        'descricao': descricao,
        'recorrencia': recorrencia.index,
        'recorrencia_grupo_id': recorrenciaGrupoId,
      };

  factory Transacao.fromMap(Map<String, dynamic> m) => Transacao(
        id: m['id'],
        valor: (m['valor'] as num).toDouble(),
        banco: m['banco'] ?? 'geral',
        parcelas: m['parcelas'] ?? 1,
        primeiraParcela: DateTime.parse(m['primeira_parcela']),
        categoria: m['categoria'] ?? '',
        tipo: TipoTransacao.values[m['tipo'] ?? 0],
        descricao: m['descricao'],
        recorrencia: Recorrencia.values[m['recorrencia'] ?? 0],
        recorrenciaGrupoId: m['recorrencia_grupo_id'],
      );
}