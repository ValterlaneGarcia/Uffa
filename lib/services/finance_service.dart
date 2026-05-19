import '../data/db/app_db.dart';
import '../data/models/transaction.dart';
import '../data/models/conta.dart';
import '../data/models/orcamento.dart';

class MonthlySummary {
  final double receitas;
  final double despesas;
  final double saldo;
  final double variacaoReceitas;
  final double variacaoDespesas;
  final Map<String, double> despesasPorCategoria;
  final Map<String, double> receitasPorCategoria;

  const MonthlySummary({
    required this.receitas,
    required this.despesas,
    required this.saldo,
    required this.variacaoReceitas,
    required this.variacaoDespesas,
    required this.despesasPorCategoria,
    required this.receitasPorCategoria,
  });
}

class ContaSummary {
  final Conta conta;
  final double totalGasto; // this month
  final double saldoCalculado;
  final List<Transacao> transacoesRecentes;

  const ContaSummary({
    required this.conta,
    required this.totalGasto,
    required this.saldoCalculado,
    required this.transacoesRecentes,
  });
}

class FinanceService {
  static Future<MonthlySummary> getMonthlySummary(int ano, int mes) async {
    final transacoes = await AppDB.getTransacoesQueImpactamMes(ano, mes);
    double despesas = 0;
    double receitas = 0;
    final Map<String, double> despCat = {};
    final Map<String, double> recCat = {};

    for (final t in transacoes) {
      final v = t.valorNoMes(ano, mes);
      if (v < 0) {
        despesas += v.abs();
        despCat[t.categoria] = (despCat[t.categoria] ?? 0) + v.abs();
      } else if (v > 0) {
        receitas += v;
        recCat[t.categoria] = (recCat[t.categoria] ?? 0) + v;
      }
    }

    // Previous month
    final prevMes = mes == 1 ? 12 : mes - 1;
    final prevAno = mes == 1 ? ano - 1 : ano;
    final prev = await AppDB.getTransacoesQueImpactamMes(prevAno, prevMes);
    double prevDespesas = 0;
    double prevReceitas = 0;
    for (final t in prev) {
      final v = t.valorNoMes(prevAno, prevMes);
      if (v < 0) prevDespesas += v.abs();
      else if (v > 0) prevReceitas += v;
    }

    return MonthlySummary(
      receitas: receitas,
      despesas: despesas,
      saldo: receitas - despesas,
      variacaoReceitas: prevReceitas > 0 ? ((receitas - prevReceitas) / prevReceitas) * 100 : 0,
      variacaoDespesas: prevDespesas > 0 ? ((despesas - prevDespesas) / prevDespesas) * 100 : 0,
      despesasPorCategoria: despCat,
      receitasPorCategoria: recCat,
    );
  }

  static Future<List<Map<String, double>>> getYearlyComparison(int ano) async {
    final futures = List.generate(
      12,
      (i) => getMonthlySummary(ano, i + 1),
    );
    final results = await Future.wait(futures);
    return results
        .map((s) => {'receitas': s.receitas, 'despesas': s.despesas, 'saldo': s.saldo})
        .toList();
  }

  static Future<ContaSummary> getContaSummary(Conta conta, int ano, int mes) async {
    final all = await AppDB.getTransacoesByBanco(conta.id);
    double totalGasto = 0;
    for (final t in all) {
      final v = t.valorNoMes(ano, mes);
      if (v < 0) totalGasto += v.abs();
    }
    final recentes = all.take(10).toList();
    return ContaSummary(
      conta: conta,
      totalGasto: totalGasto,
      saldoCalculado: conta.saldo,
      transacoesRecentes: recentes,
    );
  }

  static Future<double> getTotalPatrimonio() async {
    final contas = await AppDB.getContas();
    double total = 0;
    for (final c in contas) {
      if (c.tipo == 'credito') {
        total -= c.saldo; // credit card debt
      } else {
        total += c.saldo;
      }
    }
    return total;
  }

  static Future<List<InsightFinanceiro>> getInsights(int ano, int mes) async {
    final summary = await getMonthlySummary(ano, mes);
    final insights = <InsightFinanceiro>[];

    // Top spending category
    if (summary.despesasPorCategoria.isNotEmpty) {
      final top = summary.despesasPorCategoria.entries
          .reduce((a, b) => a.value > b.value ? a : b);
      final pct = summary.despesas > 0 ? (top.value / summary.despesas * 100).round() : 0;
      insights.add(InsightFinanceiro(
        tipo: TipoInsight.gastoAlto,
        titulo: 'Maior gasto: ${top.key}',
        descricao: '${top.key} representa $pct% das suas despesas este mês.',
        valor: top.value,
      ));
    }

    // Savings rate
    if (summary.receitas > 0) {
      final taxaPoupanca = ((summary.receitas - summary.despesas) / summary.receitas * 100);
      if (taxaPoupanca < 10) {
        insights.add(InsightFinanceiro(
          tipo: TipoInsight.alertaSaldo,
          titulo: 'Taxa de poupança baixa',
          descricao:
              'Você está poupando apenas ${taxaPoupanca.toStringAsFixed(0)}% da renda. O ideal é pelo menos 20%.',
          valor: summary.saldo,
        ));
      } else if (taxaPoupanca >= 20) {
        insights.add(InsightFinanceiro(
          tipo: TipoInsight.positivo,
          titulo: 'Ótima taxa de poupança!',
          descricao:
              'Você está poupando ${taxaPoupanca.toStringAsFixed(0)}% da renda. Continue assim!',
          valor: summary.saldo,
        ));
      }
    }

    // Expenses vs income ratio
    if (summary.receitas > 0 && summary.despesas > summary.receitas * 0.9) {
      insights.add(InsightFinanceiro(
        tipo: TipoInsight.alertaGasto,
        titulo: 'Despesas altas',
        descricao:
            'Suas despesas representam ${(summary.despesas / summary.receitas * 100).toStringAsFixed(0)}% da renda. Revise seus gastos.',
        valor: summary.despesas,
      ));
    }

    return insights;
  }
}

enum TipoInsight { gastoAlto, alertaSaldo, alertaGasto, positivo, dica }

class InsightFinanceiro {
  final TipoInsight tipo;
  final String titulo;
  final String descricao;
  final double valor;

  const InsightFinanceiro({
    required this.tipo,
    required this.titulo,
    required this.descricao,
    required this.valor,
  });
}

/// Orçamento enriquecido com o limite efetivo (após rollover) e o gasto real do mês.
class OrcamentoComRollover {
  final Orcamento orcamento;
  /// Limite base + saldo acumulado de meses anteriores (se rollover=true).
  final double limiteEfetivo;
  /// Quanto foi gasto nesta categoria no mês.
  final double gastoReal;
  /// Saldo acumulado de meses anteriores (limiteEfetivo - orcamento.limite).
  final double rolloverAcumulado;

  const OrcamentoComRollover({
    required this.orcamento,
    required this.limiteEfetivo,
    required this.gastoReal,
    required this.rolloverAcumulado,
  });

  double get saldoDisponivel => limiteEfetivo - gastoReal;
  double get percentualUsado => limiteEfetivo > 0 ? (gastoReal / limiteEfetivo).clamp(0.0, 1.0) : 0;
  bool get estourado => gastoReal > limiteEfetivo;
}

class FinanceServiceOrcamento {
  /// Retorna o gasto de uma categoria num mês específico.
  static Future<double> getGastoCategoria(String categoria, int ano, int mes) async {
    final transacoes = await AppDB.getTransacoesQueImpactamMes(ano, mes);
    double total = 0;
    for (final t in transacoes) {
      if (t.categoria == categoria) {
        final v = t.valorNoMes(ano, mes);
        if (v < 0) total += v.abs();
      }
    }
    return total;
  }

  /// Retorna todos os orçamentos do mês enriquecidos com rollover e gasto real.
  static Future<List<OrcamentoComRollover>> getOrcamentosComRollover(int ano, int mes) async {
    final orcamentos = await AppDB.getOrcamentos(mes: mes, ano: ano);
    final result = <OrcamentoComRollover>[];

    for (final o in orcamentos) {
      final limiteEfetivo = await AppDB.getLimiteEfetivo(o, getGastoCategoria);
      final gastoReal = await getGastoCategoria(o.categoria, ano, mes);
      result.add(OrcamentoComRollover(
        orcamento: o,
        limiteEfetivo: limiteEfetivo,
        gastoReal: gastoReal,
        rolloverAcumulado: limiteEfetivo - o.limite,
      ));
    }

    return result;
  }
}
