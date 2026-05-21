import '../data/db/app_db.dart';
import '../data/models/orcamento.dart';
import '../services/finance_service.dart';

class PlanningRepository {
  const PlanningRepository();

  static const instance = PlanningRepository();

  Future<List<Meta>> getMetas() => AppDB.getMetas();

  Future<void> saveMeta(Meta meta) => AppDB.upsertMeta(meta);

  Future<void> deleteMeta(String id) => AppDB.deleteMeta(id);

  Future<List<Orcamento>> getOrcamentos({int? mes, int? ano}) =>
      AppDB.getOrcamentos(mes: mes, ano: ano);

  Future<void> saveOrcamento(Orcamento orcamento) =>
      AppDB.upsertOrcamento(orcamento);

  Future<void> deleteOrcamento(String id) => AppDB.deleteOrcamento(id);

  Future<List<OrcamentoComRollover>> getOrcamentosComRollover(
    int ano,
    int mes,
  ) =>
      FinanceServiceOrcamento.getOrcamentosComRollover(ano, mes);
}
