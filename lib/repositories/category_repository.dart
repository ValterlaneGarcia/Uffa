import '../data/db/app_db.dart';

class CategoryRepository {
  const CategoryRepository();

  static const instance = CategoryRepository();

  Future<List<Map<String, dynamic>>> getAll() => AppDB.getCategorias();

  Future<List<String>> getNames() => AppDB.getNomesCategorias();

  Future<void> save(Map<String, dynamic> category) =>
      AppDB.upsertCategoria(category);

  Future<bool> delete(String id) => AppDB.deleteCategoria(id);

  Future<void> updateOrder(String id, int ordem) =>
      AppDB.updateCategoriaOrdem(id, ordem);
}
