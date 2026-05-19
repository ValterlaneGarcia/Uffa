import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/transaction.dart';
import '../models/conta.dart';
import '../models/orcamento.dart';

class AppDB {
  static Database? _db;

  static Future<Database> get db async {
    _db ??= await _init();
    return _db!;
  }

  static Future<Database> _init() async {
    final path = join(await getDatabasesPath(), 'financeapp_v2.db');
    return openDatabase(
      path,
      version: 9,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  static Future<void> _onCreate(Database db, int version) async {
    await _createTables(db);
    await _insertDefaults(db);
  }

  static Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE transacoes ADD COLUMN recorrencia INTEGER NOT NULL DEFAULT 0');
      await db.execute('ALTER TABLE transacoes ADD COLUMN recorrencia_grupo_id TEXT');
    }
    if (oldVersion < 3) {
      await db.execute('ALTER TABLE contas ADD COLUMN saldo REAL NOT NULL DEFAULT 0');
      await db.execute('ALTER TABLE contas ADD COLUMN icone TEXT');
      await _createMetasTable(db);
    }
    if (oldVersion < 4) {
      await db.execute('ALTER TABLE contas ADD COLUMN dia_vencimento INTEGER');
      await db.execute('ALTER TABLE contas ADD COLUMN dia_fechamento INTEGER');
    }
    if (oldVersion < 5) {
      // Config keys for renda base scheduling; no schema change needed.
      // Existing rows are preserved. Nothing to alter.
    }
    if (oldVersion < 6) {
      await _createCategoriasTable(db);
      await _insertDefaultCategorias(db);
    }
    if (oldVersion < 7) {
      await _createRecorrenciaExcecoesTable(db);
    }
    if (oldVersion < 8) {
      await db.execute('ALTER TABLE contas ADD COLUMN saldo_inicial REAL NOT NULL DEFAULT 0');
      // Migrate: copy current saldo to saldo_inicial for existing accounts that have no transactions
      // (accounts with transactions will be recalculated on next open)
    }
    if (oldVersion < 9) {
      await db.execute('ALTER TABLE orcamentos ADD COLUMN rollover INTEGER NOT NULL DEFAULT 0');
    }
  }

  static Future<void> _createTables(Database db) async {
    await db.execute('''
      CREATE TABLE transacoes (
        id TEXT PRIMARY KEY,
        valor REAL NOT NULL,
        banco TEXT NOT NULL DEFAULT 'geral',
        parcelas INTEGER NOT NULL DEFAULT 1,
        primeira_parcela TEXT NOT NULL,
        categoria TEXT DEFAULT '',
        tipo INTEGER NOT NULL DEFAULT 0,
        descricao TEXT,
        recorrencia INTEGER NOT NULL DEFAULT 0,
        recorrencia_grupo_id TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE contas (
        id TEXT PRIMARY KEY,
        nome TEXT NOT NULL,
        limite REAL NOT NULL DEFAULT 0,
        saldo REAL NOT NULL DEFAULT 0,
        saldo_inicial REAL NOT NULL DEFAULT 0,
        tipo TEXT NOT NULL DEFAULT 'corrente',
        cor TEXT NOT NULL DEFAULT 'FF3B82F6',
        icone TEXT,
        dia_vencimento INTEGER,
        dia_fechamento INTEGER
      )
    ''');
    await db.execute('''
      CREATE TABLE orcamentos (
        id TEXT PRIMARY KEY,
        categoria TEXT NOT NULL,
        limite REAL NOT NULL,
        mes INTEGER NOT NULL,
        ano INTEGER NOT NULL,
        rollover INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE config (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
    await _createMetasTable(db);
    await _createCategoriasTable(db);

    await _createRecorrenciaExcecoesTable(db);

    // Indexes for performance
    await db.execute('CREATE INDEX idx_transacoes_data ON transacoes(primeira_parcela)');
    await db.execute('CREATE INDEX idx_transacoes_banco ON transacoes(banco)');
  }

  static Future<void> _createRecorrenciaExcecoesTable(Database db) async {
    await db.execute('''\n      CREATE TABLE IF NOT EXISTS recorrencia_excecoes (\n        id TEXT PRIMARY KEY,\n        transacao_id TEXT NOT NULL,\n        ano INTEGER NOT NULL,\n        mes INTEGER NOT NULL\n      )\n    ''');
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_excecoes_tx_mes ON recorrencia_excecoes(transacao_id, ano, mes)',
    );
  }

  static Future<void> _createMetasTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS metas (
        id TEXT PRIMARY KEY,
        nome TEXT NOT NULL,
        valor_alvo REAL NOT NULL,
        valor_atual REAL NOT NULL DEFAULT 0,
        icone TEXT DEFAULT 'flag',
        cor TEXT DEFAULT '22C55E',
        prazo TEXT
      )
    ''');
  }

  static Future<void> _createCategoriasTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS categorias (
        id TEXT PRIMARY KEY,
        nome TEXT NOT NULL,
        icone TEXT NOT NULL DEFAULT 'category',
        cor TEXT NOT NULL DEFAULT '6B7280',
        tipo TEXT NOT NULL DEFAULT 'ambos',
        ordem INTEGER NOT NULL DEFAULT 0,
        padrao INTEGER NOT NULL DEFAULT 0
      )
    ''');
  }

  static const _defaultCategorias = [
    ('Alimentação',    'restaurant',               'F59E0B', 'despesa',  0),
    ('Moradia',        'home',                     '3B82F6', 'despesa',  1),
    ('Transporte',     'directions_car',           '8B5CF6', 'despesa',  2),
    ('Saúde',          'favorite',                 '06B6D4', 'despesa',  3),
    ('Lazer',          'sports_esports',           'EC4899', 'despesa',  4),
    ('Entretenimento', 'tv',                       'EF4444', 'despesa',  5),
    ('Educação',       'school',                   '6366F1', 'despesa',  6),
    ('Assinatura',     'subscriptions',            '8B5CF6', 'despesa',  7),
    ('Vestuário',      'checkroom',                'EC4899', 'despesa',  8),
    ('Viagem',         'flight',                   '3B82F6', 'despesa',  9),
    ('Salário',        'account_balance_wallet',   '22C55E', 'receita', 10),
    ('Freelance',      'work',                     '22C55E', 'receita', 11),
    ('Investimentos',  'trending_up',              '22C55E', 'receita', 12),
    ('Outros',         'category',                 '6B7280', 'ambos',   13),
  ];

  static Future<void> _insertDefaultCategorias(Database db) async {
    for (final (nome, icone, cor, tipo, ordem) in _defaultCategorias) {
      await db.insert('categorias', {
        'id': 'cat_$nome',
        'nome': nome,
        'icone': icone,
        'cor': cor,
        'tipo': tipo,
        'ordem': ordem,
        'padrao': 1,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }

  static Future<void> _insertDefaults(Database db) async {
    await db.insert('config', {'key': 'nome_usuario', 'value': 'Usuário'});
    await db.insert('config', {'key': 'notificacoes_ativas', 'value': 'true'});
    await db.insert('config', {'key': 'dias_aviso_antecipado', 'value': '3'});
    await _insertDefaultCategorias(db);
  }

  // ── TRANSAÇÕES ──────────────────────────────────────────────

  static Future<List<Transacao>> getTransacoes() async {
    final maps = await (await db).query('transacoes', orderBy: 'primeira_parcela DESC');
    return maps.map((m) => Transacao.fromMap(m)).toList();
  }

  static Future<List<Transacao>> getTransacoesQueImpactamMes(int ano, int mes) async {
    final inicioMes = DateTime(ano, mes, 1).toIso8601String();
    final fimMes = DateTime(ano, mes + 1, 0).toIso8601String();

    final maps = await (await db).rawQuery('''
      SELECT * FROM transacoes
      WHERE
        -- Recorrentes: trazidas sempre, valorNoMes decide se entram
        recorrencia > 0
        -- Não-recorrentes: só as que começam DENTRO ou ANTES do fim do mês
        -- e APÓS o início do mês (evita mostrar transações de meses passados
        -- que não são recorrentes)
        OR (
          recorrencia = 0
          AND date(primeira_parcela) <= date(?)
          AND date(primeira_parcela, '+' || (parcelas - 1) || ' months') >= date(?)
        )
    ''', [fimMes, inicioMes]);

    // Load skip-list for this month
    final excecoesMaps = await (await db).query(
      'recorrencia_excecoes',
      where: 'ano = ? AND mes = ?',
      whereArgs: [ano, mes],
    );
    final excecoes = excecoesMaps.map((e) => e['transacao_id'] as String).toSet();

    return maps
        .map((m) => Transacao.fromMap(m))
        .where((t) => !excecoes.contains(t.id))
        .where((t) => t.valorNoMes(ano, mes) != 0)
        .toList();
  }

  static Future<List<Transacao>> getTransacoesByBanco(String bancoId) async {
    final maps = await (await db).query(
      'transacoes',
      where: 'banco = ?',
      whereArgs: [bancoId],
      orderBy: 'primeira_parcela DESC',
    );
    return maps.map((m) => Transacao.fromMap(m)).toList();
  }

  static Future<List<Transacao>> getTransacoesByCategoria(String categoria) async {
    final maps = await (await db).query(
      'transacoes',
      where: 'categoria = ?',
      whereArgs: [categoria],
      orderBy: 'primeira_parcela DESC',
    );
    return maps.map((m) => Transacao.fromMap(m)).toList();
  }

  /// Determines the effective billing month for a credit card transaction.
  /// If the transaction date is on or after the closing day, it falls into
  /// the next month's invoice. Returns the adjusted DateTime.
  static DateTime _dataCreditoEfetiva(DateTime dataTransacao, Conta conta) {
    final diaFechamento = conta.diaFechamento;
    if (diaFechamento == null || diaFechamento <= 0) return dataTransacao;

    if (dataTransacao.day >= diaFechamento) {
      // Move to next month
      return DateTime(dataTransacao.year, dataTransacao.month + 1, dataTransacao.day);
    }
    return dataTransacao;
  }

  static Future<void> insertTransacao(Transacao t) async {
    Transacao transacaoFinal = t;

    // For credit card expenses, adjust the date based on closing day
    if (t.valor < 0 && t.banco != 'geral' && t.banco.isNotEmpty) {
      final contaMaps = await (await db).query('contas', where: 'id = ?', whereArgs: [t.banco]);
      if (contaMaps.isNotEmpty) {
        final conta = Conta.fromMap(contaMaps.first);
        if (conta.tipo == 'credito') {
          final dataEfetiva = _dataCreditoEfetiva(t.primeiraParcela, conta);
          if (dataEfetiva != t.primeiraParcela) {
            transacaoFinal = t.copyWith(primeiraParcela: dataEfetiva);
          }
        }
      }
    }

    await (await db).insert('transacoes', transacaoFinal.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
    await _recalcularSaldoConta(transacaoFinal.banco);
  }

  static Future<void> updateTransacao(Transacao t) async {
    final old = await _getTransacaoById(t.id);

    Transacao transacaoFinal = t;

    // For credit card expenses, adjust the date based on closing day
    if (t.valor < 0 && t.banco != 'geral' && t.banco.isNotEmpty) {
      final contaMaps = await (await db).query('contas', where: 'id = ?', whereArgs: [t.banco]);
      if (contaMaps.isNotEmpty) {
        final conta = Conta.fromMap(contaMaps.first);
        if (conta.tipo == 'credito') {
          final dataEfetiva = _dataCreditoEfetiva(t.primeiraParcela, conta);
          if (dataEfetiva != t.primeiraParcela) {
            transacaoFinal = t.copyWith(primeiraParcela: dataEfetiva);
          }
        }
      }
    }

    await (await db).update('transacoes', transacaoFinal.toMap(), where: 'id = ?', whereArgs: [transacaoFinal.id]);
    if (old != null && old.banco != transacaoFinal.banco) {
      await _recalcularSaldoConta(old.banco);
    }
    await _recalcularSaldoConta(transacaoFinal.banco);
  }

  static Future<void> deleteTransacao(String id) async {
    final t = await _getTransacaoById(id);
    await (await db).delete('transacoes', where: 'id = ?', whereArgs: [id]);
    if (t != null) await _recalcularSaldoConta(t.banco);
  }

  static Future<void> deleteTransacaoMes(String id, int ano, int mes) async {
    final t = await _getTransacaoById(id);
    if (t == null) return;

    if (t.recorrencia != Recorrencia.nenhuma) {
      if (t.primeiraParcela.year == ano && t.primeiraParcela.month == mes) {
        // Deleting the first occurrence: advance the start date to the next occurrence.
        final rawNext = DateTime(ano, mes + 1, 1);
        final lastDay = DateTime(rawNext.year, rawNext.month + 1, 0).day;
        final next = DateTime(rawNext.year, rawNext.month, t.primeiraParcela.day.clamp(1, lastDay));
        final updated = t.copyWith(primeiraParcela: next);
        await updateTransacao(updated);
      } else {
        // Deleting a future/intermediate occurrence: insert into skip-list.
        await (await db).insert(
          'recorrencia_excecoes',
          {
            'id': '${id}_${ano}_$mes',
            'transacao_id': id,
            'ano': ano,
            'mes': mes,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    } else {
      await deleteTransacao(id);
    }
  }

  static Future<void> _recalcularSaldoConta(String bancoId) async {
    if (bancoId == 'geral' || bancoId.isEmpty) return;

    final contaMaps = await (await db).query('contas', where: 'id = ?', whereArgs: [bancoId]);
    if (contaMaps.isEmpty) return;
    final conta = Conta.fromMap(contaMaps.first);

    final txMaps = await (await db).query('transacoes', where: 'banco = ?', whereArgs: [bancoId]);
    final transacoes = txMaps.map((m) => Transacao.fromMap(m)).toList();

    final now = DateTime.now();
    double novoSaldo;

    // Load ALL skip-list entries for this account's transactions upfront
    final todasExcecoesMaps = await (await db).rawQuery('''
      SELECT re.transacao_id, re.ano, re.mes
      FROM recorrencia_excecoes re
      INNER JOIN transacoes t ON t.id = re.transacao_id
      WHERE t.banco = ?
    ''', [bancoId]);
    // Build a set of "transacaoId|ano|mes" for fast lookup
    final excecoes = <String>{};
    for (final e in todasExcecoesMaps) {
      excecoes.add('${e['transacao_id']}|${e['ano']}|${e['mes']}');
    }

    if (conta.tipo == 'credito') {
      // Saldo devedor do cartão = soma de todas as despesas registradas
      // menos todos os pagamentos registrados. SEM filtro de data.
      //
      // Por que sem filtro de data?
      // ─────────────────────────────────────────────────────────────────
      // O app desloca artificialmente a data de compras feitas após o dia
      // de fechamento para o mês seguinte (para agrupamento de fatura).
      // Exemplo: fechamento dia 5, compra no dia 18/05 → gravada como 18/06.
      // Se filtrarmos "apenas datas <= hoje (18/05)", essa despesa seria
      // ignorada porque 18/06 > 18/05, deixando o saldo zerado.
      //
      // Da mesma forma, pagamentos são gravados com a data de vencimento
      // da fatura (ex: dia 25/06), que é futura. Filtrar por data excluiria
      // o pagamento e o saldo nunca diminuiria após pagar.
      //
      // A data ajustada serve apenas para agrupar corretamente na tela de
      // fatura; para o saldo devedor o que importa é: a transação existe?
      // Se sim, ela compõe o saldo — independente da data armazenada.
      //
      // Para compras parceladas, somamos apenas as parcelas cujo número
      // de meses a partir da primeiraParcela já ocorreu (parcela já "caiu"),
      // evitando inflar o saldo com parcelas futuras ainda não devidas.
      double totalDespesas = 0.0;
      double totalPagamentos = 0.0;
      final mesAtual = DateTime(now.year, now.month);

      for (final t in transacoes) {
        if (t.valor > 0) {
          // Pagamento: sempre conta — data é apenas referência da fatura
          totalPagamentos += t.valor;
        } else {
          // Despesa
          if (t.recorrencia == Recorrencia.nenhuma) {
            // Soma cada parcela cuja competência (mês/ano) já chegou ou é atual.
            // Usamos o mês da parcela (não o dia exato) para não penalizar
            // compras deslocadas para o próximo mês pelo mecanismo de fechamento.
            for (int i = 0; i < t.parcelas; i++) {
              final mesParcela = DateTime(
                t.primeiraParcela.year,
                t.primeiraParcela.month + i,
              );
              // Parcela competente = mês já chegou (passado ou atual)
              if (!mesParcela.isAfter(mesAtual)) {
                totalDespesas += t.valorParcela.abs();
              }
            }
          } else {
            // Recorrentes: soma ocorrências até o mês atual
            final inicio = DateTime(t.primeiraParcela.year, t.primeiraParcela.month);
            var cursor = inicio;
            while (!cursor.isAfter(mesAtual)) {
              if (!excecoes.contains('${t.id}|${cursor.year}|${cursor.month}')) {
                totalDespesas += t.valorNoMes(cursor.year, cursor.month).abs();
              }
              cursor = DateTime(cursor.year, cursor.month + 1);
            }
          }
        }
      }

      // Saldo devedor = despesas acumuladas − pagamentos efetuados (≥ 0)
      novoSaldo = (totalDespesas - totalPagamentos).clamp(0.0, double.infinity);
    } else {
      // Saldo = saldo inicial + soma de todas as ocorrências REAIS até hoje.
      // Para transações recorrentes/semanais, somamos mês a mês desde o início,
      // respeitando a skip-list de exceções.
      double movimentacao = 0.0;
      for (final t in transacoes) {
        if (t.recorrencia == Recorrencia.semanal ||
            t.recorrencia == Recorrencia.mensal ||
            t.recorrencia == Recorrencia.anual) {
          // Soma cada mês desde a primeira parcela até o mês atual
          final inicio = DateTime(t.primeiraParcela.year, t.primeiraParcela.month);
          var cursor = inicio;
          while (!cursor.isAfter(DateTime(now.year, now.month))) {
            // Pula meses que foram excluídos individualmente (skip-list)
            if (!excecoes.contains('${t.id}|${cursor.year}|${cursor.month}')) {
              movimentacao += t.valorNoMes(cursor.year, cursor.month);
            }
            cursor = DateTime(cursor.year, cursor.month + 1);
          }
        } else {
          // Não-recorrente: soma parcelas já vencidas até hoje
          for (int i = 0; i < t.parcelas; i++) {
            final rawDate = DateTime(
              t.primeiraParcela.year,
              t.primeiraParcela.month + i,
              1,
            );
            final lastDay = DateTime(rawDate.year, rawDate.month + 1, 0).day;
            final dt = DateTime(rawDate.year, rawDate.month, t.primeiraParcela.day.clamp(1, lastDay));
            if (!dt.isAfter(now)) {
              movimentacao += t.valorParcela;
            }
          }
        }
      }
      novoSaldo = conta.saldoInicial + movimentacao;
    }

    await (await db).update(
      'contas',
      {'saldo': novoSaldo},
      where: 'id = ?',
      whereArgs: [bancoId],
    );
  }

  static Future<Transacao?> _getTransacaoById(String id) async {
    final maps = await (await db).query('transacoes', where: 'id = ?', whereArgs: [id]);
    if (maps.isEmpty) return null;
    return Transacao.fromMap(maps.first);
  }

  // ── CONTAS ──────────────────────────────────────────────────

  static Future<List<Conta>> getContas() async {
    final maps = await (await db).query('contas');
    return maps.map((m) => Conta.fromMap(m)).toList();
  }

  static Future<void> insertConta(Conta c) async {
    // saldo_inicial captures the manually entered opening balance.
    // The saldo column will be recalculated from saldo_inicial + transactions.
    final conta = c.copyWith(saldoInicial: c.saldo);
    await (await db).insert('contas', conta.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
    // Recalculate in case there are transactions already linked to this account.
    await _recalcularSaldoConta(c.id);
  }

  static Future<void> updateConta(Conta c) async {
    // Preserve existing saldo_inicial if the user didn't touch the opening balance field.
    // The caller (edit form) passes saldoInicial from the original account.
    await (await db).update('contas', c.toMap(), where: 'id = ?', whereArgs: [c.id]);
    // Recalculate saldo from saldo_inicial + transactions
    await _recalcularSaldoConta(c.id);
  }

  static Future<void> deleteConta(String id) async {
    await (await db).delete('contas', where: 'id = ?', whereArgs: [id]);
  }

  // ── ORÇAMENTOS ──────────────────────────────────────────────

  static Future<List<Orcamento>> getOrcamentos({int? mes, int? ano}) async {
    String? where;
    List<Object?>? args;
    if (mes != null && ano != null) {
      where = 'mes = ? AND ano = ?';
      args = [mes, ano];
    }
    final maps = await (await db).query('orcamentos', where: where, whereArgs: args);
    return maps.map((m) => Orcamento.fromMap(m)).toList();
  }

  static Future<void> upsertOrcamento(Orcamento o) async {
    await (await db).insert('orcamentos', o.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<void> deleteOrcamento(String id) async {
    await (await db).delete('orcamentos', where: 'id = ?', whereArgs: [id]);
  }

  /// Retorna o limite efetivo de um orçamento com rollover para o mês/ano alvo.
  /// Se o orçamento tiver rollover=true, acumula o saldo não gasto dos meses
  /// anteriores (retroativamente até a criação do orçamento na mesma categoria).
  /// 
  /// [gastoNoMes] é uma função que retorna o gasto real de uma categoria num mês.
  static Future<double> getLimiteEfetivo(
    Orcamento orcamento,
    Future<double> Function(String categoria, int ano, int mes) gastoNoMes,
  ) async {
    if (!orcamento.rollover) return orcamento.limite;

    // Busca o orçamento mais antigo da mesma categoria para saber o ponto de partida
    final todos = await getOrcamentos();
    final mesmaCat = todos
        .where((o) => o.categoria == orcamento.categoria && o.rollover)
        .toList()
      ..sort((a, b) {
        final dateA = DateTime(a.ano, a.mes);
        final dateB = DateTime(b.ano, b.mes);
        return dateA.compareTo(dateB);
      });

    if (mesmaCat.isEmpty) return orcamento.limite;

    // Mês mais antigo com rollover desta categoria
    final inicio = mesmaCat.first;
    final inicioDate = DateTime(inicio.ano, inicio.mes);
    final alvoDate = DateTime(orcamento.ano, orcamento.mes);

    if (!inicioDate.isBefore(alvoDate)) return orcamento.limite;

    // Acumula saldo não gasto mês a mês
    double rolloverAcumulado = 0;
    DateTime cursor = inicioDate;

    while (cursor.isBefore(alvoDate)) {
      // Encontra o orçamento deste mês para a categoria
      final orcMes = mesmaCat.firstWhere(
        (o) => o.ano == cursor.year && o.mes == cursor.month,
        orElse: () => Orcamento(
          categoria: orcamento.categoria,
          limite: orcamento.limite,
          mes: cursor.month,
          ano: cursor.year,
          rollover: true,
        ),
      );

      final limiteComRollover = orcMes.limite + rolloverAcumulado;
      final gasto = await gastoNoMes(orcamento.categoria, cursor.year, cursor.month);
      final sobra = limiteComRollover - gasto;
      // Apenas acumula sobra positiva (não permite déficit virar rollover negativo)
      rolloverAcumulado = sobra > 0 ? sobra : 0;

      // Próximo mês
      cursor = DateTime(cursor.year, cursor.month + 1);
    }

    return orcamento.limite + rolloverAcumulado;
  }

  // ── METAS ───────────────────────────────────────────────────

  static Future<List<Meta>> getMetas() async {
    final maps = await (await db).query('metas');
    return maps.map((m) => Meta.fromMap(m)).toList();
  }

  static Future<void> upsertMeta(Meta m) async {
    await (await db).insert('metas', m.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<void> deleteMeta(String id) async {
    await (await db).delete('metas', where: 'id = ?', whereArgs: [id]);
  }

  // ── CATEGORIAS ──────────────────────────────────────────────

  /// Returns all categories sorted by [ordem].
  static Future<List<Map<String, dynamic>>> getCategorias() async {
    return (await db).query('categorias', orderBy: 'ordem ASC, nome ASC');
  }

  /// Returns only the category names, sorted.
  static Future<List<String>> getNomesCategorias() async {
    final rows = await getCategorias();
    return rows.map((r) => r['nome'] as String).toList();
  }

  /// Inserts or replaces a category.
  static Future<void> upsertCategoria(Map<String, dynamic> cat) async {
    await (await db).insert('categorias', cat,
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Deletes a custom (non-default) category by id.
  /// Returns false if the category is a default one (cannot be deleted).
  static Future<bool> deleteCategoria(String id) async {
    final rows = await (await db).query('categorias',
        where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return false;
    if ((rows.first['padrao'] as int) == 1) return false; // protect defaults
    await (await db).delete('categorias', where: 'id = ?', whereArgs: [id]);
    return true;
  }

  /// Reorders a category by updating its [ordem] field.
  static Future<void> updateCategoriaOrdem(String id, int ordem) async {
    await (await db).update('categorias', {'ordem': ordem},
        where: 'id = ?', whereArgs: [id]);
  }

  // ── CONFIG ──────────────────────────────────────────────────

  static Future<Map<String, String>> getConfig() async {
    final maps = await (await db).query('config');
    return {for (var m in maps) m['key'] as String: m['value'] as String};
  }

  static Future<void> setConfig(String key, String value) async {
    await (await db).insert('config', {'key': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<String?> getConfigValue(String key) async {
    final maps = await (await db).query('config', where: 'key = ?', whereArgs: [key]);
    if (maps.isEmpty) return null;
    return maps.first['value'] as String;
  }

  // ── RENDA BASE ──────────────────────────────────────────────
  // ID fixo para a conta-salário criada automaticamente
  static const String _rendaContaId = 'conta_renda_base';

  /// Calcula o n-ésimo dia útil (seg-sex) de um mês.
  static DateTime _nthWeekday(int ano, int mes, int n) {
    int count = 0;
    DateTime d = DateTime(ano, mes, 1);
    while (true) {
      if (d.weekday >= 1 && d.weekday <= 5) {
        count++;
        if (count == n) return d;
      }
      d = d.add(const Duration(days: 1));
    }
  }

  /// Cria/atualiza a conta-salário e a transação recorrente mensal de renda.
  /// [valor]        — valor da renda em reais
  /// [diaFixo]      — dia do mês (1–31), ou null se usar dia útil
  /// [nthDiaUtil]   — qual dia útil (ex.: 5), usado quando diaFixo == null
  static Future<void> salvarRendaBase({
    required double valor,
    int? diaFixo,
    int? nthDiaUtil,
  }) async {
    final database = await db;

    // 1. Cria ou atualiza a conta "Salário"
    final contaExistente = await database.query(
      'contas',
      where: 'id = ?',
      whereArgs: [_rendaContaId],
    );
    if (contaExistente.isEmpty) {
      await database.insert('contas', {
        'id': _rendaContaId,
        'nome': 'Salário',
        'limite': 0,
        'saldo': 0,
        'saldo_inicial': 0,
        'tipo': 'corrente',
        'cor': '22C55E',
        'icone': 'salario',
        'dia_vencimento': null,
        'dia_fechamento': null,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    } else {
      // Garante que o nome/tipo estão corretos mesmo se o usuário editou
      await database.update(
        'contas',
        {'nome': 'Salário', 'tipo': 'corrente', 'cor': '22C55E'},
        where: 'id = ?',
        whereArgs: [_rendaContaId],
      );
    }

    // 2. Remove a transação recorrente anterior de renda (se existir)
    await database.delete(
      'transacoes',
      where: 'banco = ? AND tipo = ? AND recorrencia = ?',
      whereArgs: [_rendaContaId, 0 /* entrada */, 2 /* mensal */],
    );

    // 3. Calcula a data da primeira ocorrência sempre no mês atual,
    // garantindo que a recorrência mensal cubra o mês corrente e todos os seguintes.
    final now = DateTime.now();
    DateTime primeiraData;
    if (diaFixo != null) {
      primeiraData = DateTime(now.year, now.month, diaFixo.clamp(1, 28));
    } else {
      final n = nthDiaUtil ?? 5;
      primeiraData = _nthWeekday(now.year, now.month, n);
    }

    // 4. Insere a transação recorrente mensal
    final txId = 'renda_base_tx';
    await database.insert('transacoes', {
      'id': txId,
      'valor': valor,
      'banco': _rendaContaId,
      'parcelas': 1,
      'primeira_parcela': primeiraData.toIso8601String(),
      'categoria': 'Salário',
      'tipo': 0, // TipoTransacao.entrada
      'descricao': 'Renda mensal base',
      'recorrencia': 2, // Recorrencia.mensal
      'recorrencia_grupo_id': null,
    }, conflictAlgorithm: ConflictAlgorithm.replace);

    // 5. Persiste a configuração
    await setConfig('receita_base', valor.toString());
    await setConfig('receita_base_dia_fixo', diaFixo?.toString() ?? '');
    await setConfig('receita_base_dia_util', nthDiaUtil?.toString() ?? '');

    // 6. Recalcula o saldo da conta
    await _recalcularSaldoConta(_rendaContaId);
  }

  /// Remove a conta-salário e todas as transações vinculadas.
  static Future<void> removerRendaBase() async {
    final database = await db;
    await database.delete('transacoes', where: 'banco = ?', whereArgs: [_rendaContaId]);
    await database.delete('contas', where: 'id = ?', whereArgs: [_rendaContaId]);
    await setConfig('receita_base', '');
    await setConfig('receita_base_dia_fixo', '');
    await setConfig('receita_base_dia_util', '');
  }
}