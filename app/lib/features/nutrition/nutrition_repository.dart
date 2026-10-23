import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api.dart';
import '../workout/workout_repository.dart' show isoDate;
import 'models.dart';

class NutritionRepository {
  NutritionRepository(this._dio);
  final Dio _dio;

  Future<List<Dish>> dishes() async {
    final r = await _dio.get<List<dynamic>>('/dishes');
    return [for (final d in r.data!) Dish.fromJson(d as Map<String, dynamic>)];
  }

  /// Tus alimentos (el backend los pone primero en la búsqueda).
  Future<List<Food>> myFoods() async => [for (final f in await searchFoods(limit: 100)) if (f.mine) f];

  Future<List<Food>> searchFoods({String q = '', int limit = 40}) async {
    final r = await _dio.get<List<dynamic>>('/foods', queryParameters: {'q': q, 'limit': limit});
    return [for (final f in r.data!) Food.fromJson(f as Map<String, dynamic>)];
  }

  Future<Food> createFood(Map<String, dynamic> json) async {
    final r = await _dio.post<Map<String, dynamic>>('/foods', data: json);
    return Food.fromJson(r.data!);
  }

  Future<void> deleteFood(String id) => _dio.delete<void>('/foods/$id');

  /// Crea el plato si no tiene id; si lo tiene, lo sustituye.
  Future<Dish> saveDish(DishDraft d) async {
    final r = d.id == null
        ? await _dio.post<Map<String, dynamic>>('/dishes', data: d.toJson())
        : await _dio.put<Map<String, dynamic>>('/dishes/${d.id}', data: d.toJson());
    return Dish.fromJson(r.data!);
  }

  Future<void> deleteDish(String id) => _dio.delete<void>('/dishes/$id');

  Future<DiaryDay> day(DateTime date) async {
    final r = await _dio.get<Map<String, dynamic>>('/diary/${isoDate(date)}');
    return DiaryDay.fromJson(r.data!);
  }

  /// Apunta [grams] de un alimento o de un plato (uno de los dos).
  Future<void> addItem(DateTime date, String meal, double grams, {String? foodId, String? dishId}) =>
      _dio.post<void>('/diary/${isoDate(date)}/items', data: {
        'meal': meal,
        'grams': grams,
        if (foodId != null) 'food_id': foodId,
        if (dishId != null) 'dish_id': dishId,
      });

  Future<void> deleteItem(String id) => _dio.delete<void>('/diary/items/$id');
}

final nutritionRepositoryProvider = Provider<NutritionRepository>((ref) => NutritionRepository(ref.watch(dioProvider)));

final diaryDayProvider = FutureProvider.autoDispose.family<DiaryDay, DateTime>(
  (ref, date) => ref.watch(nutritionRepositoryProvider).day(date),
);

final foodSearchProvider = FutureProvider.autoDispose.family<List<Food>, String>(
  (ref, q) => ref.watch(nutritionRepositoryProvider).searchFoods(q: q),
);

final dishesProvider = FutureProvider.autoDispose<List<Dish>>((ref) => ref.watch(nutritionRepositoryProvider).dishes());

final myFoodsProvider = FutureProvider.autoDispose<List<Food>>((ref) => ref.watch(nutritionRepositoryProvider).myFoods());

/// Tras crear o borrar alimentos o platos: búsquedas y listas cambian.
void refreshFoods(WidgetRef ref) {
  ref.invalidate(foodSearchProvider);
  ref.invalidate(myFoodsProvider);
  ref.invalidate(dishesProvider);
}
