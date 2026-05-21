import '../data/db/app_db.dart';

class SettingsRepository {
  const SettingsRepository();

  static const instance = SettingsRepository();

  Future<Map<String, String>> getConfig() => AppDB.getConfig();

  Future<String?> getConfigValue(String key) => AppDB.getConfigValue(key);

  Future<void> setConfig(String key, String value) =>
      AppDB.setConfig(key, value);

  Future<void> saveIncomeBase({
    required double valor,
    int? diaFixo,
    int? nthDiaUtil,
  }) =>
      AppDB.salvarRendaBase(
        valor: valor,
        diaFixo: diaFixo,
        nthDiaUtil: nthDiaUtil,
      );

  Future<void> removeIncomeBase() => AppDB.removerRendaBase();

  Future<void> clearTransactionsData() => AppDB.clearTransactionsData();
}
