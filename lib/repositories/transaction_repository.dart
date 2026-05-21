import '../data/db/app_db.dart';
import '../data/models/transaction.dart';

class TransactionRepository {
  const TransactionRepository();

  static const instance = TransactionRepository();

  Future<List<Transacao>> getAll() => AppDB.getTransacoes();

  Future<List<Transacao>> getForMonth(int ano, int mes) =>
      AppDB.getTransacoesQueImpactamMes(ano, mes);

  Future<List<Transacao>> getByAccount(String accountId) =>
      AppDB.getTransacoesByBanco(accountId);

  Future<void> save(Transacao transacao, {bool isUpdate = false}) {
    return isUpdate
        ? AppDB.updateTransacao(transacao)
        : AppDB.insertTransacao(transacao);
  }

  Future<void> delete(String id) => AppDB.deleteTransacao(id);

  Future<void> deleteMonthOccurrence(String id, int ano, int mes) =>
      AppDB.deleteTransacaoMes(id, ano, mes);

  Future<void> insertTransfer({
    required Transacao saida,
    required Transacao entrada,
  }) =>
      AppDB.insertTransferencia(saida: saida, entrada: entrada);
}
