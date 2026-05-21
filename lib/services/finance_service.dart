import '../data/db/app_db.dart';
import '../data/models/transaction.dart';
import '../data/models/conta.dart';
import '../data/models/orcamento.dart';
import '../repositories/account_repository.dart';
import '../repositories/planning_repository.dart';
import '../repositories/settings_repository.dart';
import '../repositories/transaction_repository.dart';
import '../utils/formatters.dart';

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

  double get percentualReceitasNoMes {
    final total = receitas + despesas;
    if (total <= 0) return 0;
    return (receitas / total) * 100;
  }

  double get percentualDespesasNoMes {
    final total = receitas + despesas;
    if (total <= 0) return 0;
    return (despesas / total) * 100;
  }
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

class DashboardData {
  final MonthlySummary summary;
  final List<Map<String, double>> yearly;
  final List<Conta> contas;
  final List<Transacao> recentes;
  final String nomeUsuario;

  const DashboardData({
    required this.summary,
    required this.yearly,
    required this.contas,
    required this.recentes,
    required this.nomeUsuario,
  });
}

class PlanningData {
  final MonthlySummary summary;
  final List<Meta> metas;
  final List<OrcamentoComRollover> orcamentos;
  final List<Map<String, double>> yearly;

  const PlanningData({
    required this.summary,
    required this.metas,
    required this.orcamentos,
    required this.yearly,
  });
}

class DashboardReminder {
  final String title;
  final String subtitle;
  final TipoInsight type;

  const DashboardReminder({
    required this.title,
    required this.subtitle,
    required this.type,
  });
}

class FinanceService {
  static const _transactions = TransactionRepository.instance;
  static const _accounts = AccountRepository.instance;
  static const _planning = PlanningRepository.instance;
  static const _settings = SettingsRepository.instance;

  static Future<MonthlySummary> getMonthlySummary(int ano, int mes) async {
    final transacoes = await _transactions.getForMonth(ano, mes);
    double despesas = 0;
    double receitas = 0;
    final Map<String, double> despCat = {};
    final Map<String, double> recCat = {};

    for (final t in transacoes) {
      if (t.isTransferencia) continue;
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
    final prev = await _transactions.getForMonth(prevAno, prevMes);
    double prevDespesas = 0;
    double prevReceitas = 0;
    for (final t in prev) {
      if (t.isTransferencia) continue;
      final v = t.valorNoMes(prevAno, prevMes);
      if (v < 0) {
        prevDespesas += v.abs();
      } else if (v > 0) {
        prevReceitas += v;
      }
    }

    return MonthlySummary(
      receitas: receitas,
      despesas: despesas,
      saldo: receitas - despesas,
      variacaoReceitas: prevReceitas > 0
          ? ((receitas - prevReceitas) / prevReceitas) * 100
          : 0,
      variacaoDespesas: prevDespesas > 0
          ? ((despesas - prevDespesas) / prevDespesas) * 100
          : 0,
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
        .map((s) =>
            {'receitas': s.receitas, 'despesas': s.despesas, 'saldo': s.saldo})
        .toList();
  }

  static Future<ContaSummary> getContaSummary(
      Conta conta, int ano, int mes) async {
    final all = await _transactions.getByAccount(conta.id);
    double totalGasto = 0;
    for (final t in all) {
      if (t.isTransferencia) continue;
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
    final contas = await _accounts.getAll();
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
      final pct = summary.despesas > 0
          ? (top.value / summary.despesas * 100).round()
          : 0;
      insights.add(InsightFinanceiro(
        tipo: TipoInsight.gastoAlto,
        titulo: 'Maior gasto: ${top.key}',
        descricao: '${top.key} representa $pct% das suas despesas este mês.',
        valor: top.value,
      ));
    }

    // Savings rate
    if (summary.receitas > 0) {
      final taxaPoupanca =
          ((summary.receitas - summary.despesas) / summary.receitas * 100);
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

  static Future<DashboardData> loadDashboardData(DateTime selectedMonth) async {
    final summary =
        await getMonthlySummary(selectedMonth.year, selectedMonth.month);
    final yearly = await getYearlyComparison(selectedMonth.year);
    final contas = await _accounts.getAll();
    final recentes = await _transactions.getAll();
    recentes.sort((a, b) => b.primeiraParcela.compareTo(a.primeiraParcela));
    final nomeUsuario =
        await _settings.getConfigValue('nome_usuario') ?? 'Usuário';

    return DashboardData(
      summary: summary,
      yearly: yearly,
      contas: contas,
      recentes: recentes.take(5).toList(),
      nomeUsuario: nomeUsuario,
    );
  }

  static Future<List<DashboardReminder>> getDashboardReminders() async {
    final now = DateTime.now();
    final contas = await _accounts.getAll();
    final orcamentos = await _planning.getOrcamentosComRollover(
      now.year,
      now.month,
    );
    final reminders = <DashboardReminder>[];

    for (final item in orcamentos) {
      final percent = (item.percentualUsado * 100).round();
      if (item.estourado) {
        reminders.add(DashboardReminder(
          title: 'Orçamento estourado: ${item.orcamento.categoria}',
          subtitle:
              'Gasto ${fmtBRL(item.gastoReal)} para um limite efetivo de ${fmtBRL(item.limiteEfetivo)}.',
          type: TipoInsight.alertaGasto,
        ));
      } else if (percent >= 100) {
        reminders.add(DashboardReminder(
          title: 'Limite concluído: ${item.orcamento.categoria}',
          subtitle: 'Você já consumiu 100% do orçamento deste mês.',
          type: TipoInsight.gastoAlto,
        ));
      } else if (percent >= 80) {
        reminders.add(DashboardReminder(
          title: '${item.orcamento.categoria} com $percent% comprometido',
          subtitle:
              'Restam ${fmtBRL(item.saldoDisponivel.clamp(0, double.infinity))} neste orçamento.',
          type: TipoInsight.alertaSaldo,
        ));
      }
    }

    for (final conta in contas.where((c) => c.tipo == 'credito')) {
      final diaVencimento = conta.diaVencimento;
      if (diaVencimento == null || diaVencimento <= 0) continue;

      final dueDate = DateTime(
        now.year,
        now.month,
        diaVencimento.clamp(1, DateTime(now.year, now.month + 1, 0).day),
      );
      final dias =
          dueDate.difference(DateTime(now.year, now.month, now.day)).inDays;
      if (dias < 0) {
        reminders.add(DashboardReminder(
          title: 'Fatura vencida: ${conta.nome}',
          subtitle: 'O vencimento foi em ${dueDate.day}/${dueDate.month}.',
          type: TipoInsight.alertaGasto,
        ));
      } else if (dias <= 3) {
        reminders.add(DashboardReminder(
          title: 'Fatura perto do vencimento: ${conta.nome}',
          subtitle:
              dias == 0 ? 'O vencimento e hoje.' : 'Vence em $dias dia(s).',
          type: TipoInsight.alertaSaldo,
        ));
      }
    }

    return reminders;
  }

  static Future<PlanningData> loadPlanningData(DateTime selectedMonth) async {
    final summary =
        await getMonthlySummary(selectedMonth.year, selectedMonth.month);
    final metas = await _planning.getMetas();
    final orcamentos = await _planning.getOrcamentosComRollover(
      selectedMonth.year,
      selectedMonth.month,
    );
    final yearly = await getYearlyComparison(selectedMonth.year);

    return PlanningData(
      summary: summary,
      metas: metas,
      orcamentos: orcamentos,
      yearly: yearly,
    );
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
  double get percentualUsado =>
      limiteEfetivo > 0 ? (gastoReal / limiteEfetivo).clamp(0.0, 1.0) : 0;
  bool get estourado => gastoReal > limiteEfetivo;
}

class FinanceServiceOrcamento {
  /// Retorna o gasto de uma categoria num mês específico.
  static Future<double> getGastoCategoria(
      String categoria, int ano, int mes) async {
    final transacoes =
        await TransactionRepository.instance.getForMonth(ano, mes);
    double total = 0;
    for (final t in transacoes) {
      if (t.categoria == categoria) {
        final v = t.valorNoMes(ano, mes);
        if (v < 0 && !t.isTransferencia) total += v.abs();
      }
    }
    return total;
  }

  /// Retorna todos os orçamentos do mês enriquecidos com rollover e gasto real.
  static Future<List<OrcamentoComRollover>> getOrcamentosComRollover(
      int ano, int mes) async {
    final orcamentos = await PlanningRepository.instance.getOrcamentos(
      mes: mes,
      ano: ano,
    );
    final todosOrcamentos = await PlanningRepository.instance.getOrcamentos();
    final result = <OrcamentoComRollover>[];
    final gastosCache = <String, Map<int, double>>{};

    for (final o in orcamentos) {
      final orcamentosDaCategoria = todosOrcamentos
          .where((item) => item.categoria == o.categoria)
          .toList();
      final primeiroRollover = orcamentosDaCategoria
          .where((item) => item.rollover)
          .fold<Orcamento?>(null, (menor, item) {
        if (menor == null) return item;
        final itemDate = DateTime(item.ano, item.mes);
        final menorDate = DateTime(menor.ano, menor.mes);
        return itemDate.isBefore(menorDate) ? item : menor;
      });
      final inicio = primeiroRollover == null
          ? DateTime(ano, mes)
          : DateTime(primeiroRollover.ano, primeiroRollover.mes);
      final gastosPorMes = gastosCache.putIfAbsent(
        o.categoria,
        () => {},
      );
      if (gastosPorMes.isEmpty) {
        gastosPorMes.addAll(await AppDB.getGastosMensaisCategoria(
          categoria: o.categoria,
          inicio: inicio,
          fim: DateTime(ano, mes),
        ));
      }

      final limiteEfetivo = AppDB.calcularLimiteEfetivoComGastos(
        orcamento: o,
        orcamentosDaCategoria: orcamentosDaCategoria,
        gastosPorMes: gastosPorMes,
      );
      final gastoReal = gastosPorMes[AppDB.monthKey(ano, mes)] ?? 0;
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
