import '../data/db/app_db.dart';
import '../data/models/conta.dart';

class AccountRepository {
  const AccountRepository();

  static const instance = AccountRepository();

  Future<List<Conta>> getAll() async {
    await AppDB.recalculateAllAccountBalances();
    return AppDB.getContas();
  }

  bool isManagedBalanceAccount(Conta conta) =>
      AppDB.isManagedBalanceAccountId(conta.id);

  Future<void> save(Conta conta, {bool isUpdate = false}) {
    return isUpdate ? AppDB.updateConta(conta) : AppDB.insertConta(conta);
  }

  Future<void> delete(String id) => AppDB.deleteConta(id);
}
