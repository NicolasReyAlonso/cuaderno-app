import 'package:cuaderno/features/nutrition/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parseGrams acepta coma decimal y rechaza lo que no son gramos', () {
    expect(parseGrams('120'), 120);
    expect(parseGrams(' 62,5 '), 62.5);
    expect(parseGrams('62.5'), 62.5);
    for (final bad in ['', '0', '-5', 'cien', '5001']) {
      expect(parseGrams(bad), isNull, reason: bad);
    }
  });

  test('mealForHour propone la comida por la hora', () {
    expect([7, 13, 18, 22].map(mealForHour), ['desayuno', 'almuerzo', 'merienda', 'cena']);
  });

  test('Per100.forGrams escala los valores por 100 g', () {
    final v = const Per100(89, 1.1, 23, 0.3).forGrams(120);
    expect(v.kcal, closeTo(106.8, 0.001));
    expect(v.protein, closeTo(1.32, 0.001));
  });

  test('DiaryDay con el formato de la API, agrupado por comida', () {
    final day = DiaryDay.fromJson({
      'date': '2026-10-20',
      'items': [
        {'id': 'a', 'meal': 'almuerzo', 'name': 'Arroz marisco', 'grams': 407, 'kcal': 467.2, 'protein': 30.1, 'carbs': 60, 'fat': 9},
        {'id': 'b', 'meal': 'desayuno', 'name': 'Plátano', 'grams': 120, 'kcal': 106.8, 'protein': 1.3, 'carbs': 27.6, 'fat': 0.4},
        {'id': 'c', 'meal': 'almuerzo', 'name': 'Skyr', 'grams': 150, 'kcal': 94.5, 'protein': 16.5, 'carbs': 6, 'fat': 0},
      ],
      'kcal': 668.5,
      'protein': 47.9,
      'carbs': 93.6,
      'fat': 9.4,
      'kcal_target': 2000,
      'protein_target_g': 160,
    });
    expect(day.itemsOf('almuerzo').map((i) => i.name), ['Arroz marisco', 'Skyr']);
    expect(day.kcalOf('almuerzo'), closeTo(561.7, 0.001));
    expect(day.itemsOf('cena'), isEmpty);
    expect((day.kcalTarget, day.proteinTarget), (2000, 160));
  });

  test('Food y Dish con el formato de la API', () {
    final f = Food.fromJson({
      'id': 'b:skyr', 'name': 'Skyr natural', 'category': 'Lácteos', 'kcal': 63, 'protein': 11, 'carbs': 4, 'fat': 0.2,
      'default_portion_g': 150, 'mine': false,
    });
    expect((f.per100.kcal, f.defaultPortionG, f.mine), (63.0, 150, false));
    final d = Dish.fromJson({
      'id': 'x', 'name': 'Arroz marisco', 'servings': 3, 'cooked_weight_g': 1200, 'ingredients': [], 'total_kcal': 1377,
      'total_protein': 90, 'per100_kcal': 114.8, 'per100_protein': 7.5, 'per100_carbs': 18, 'per100_fat': 2, 'serving_g': 400,
    });
    expect((d.servingG, d.per100.kcal), (400, 114.8));
  });

  test('DishDraft calcula la ración como el backend: peso cocinado o, si no, crudo', () {
    final d = DishDraft(name: 'Arroz marisco', servings: 3, ingredients: [
      IngredientDraft(foodId: 'b:arroz_crudo', name: 'Arroz', kcalPer100: 350, proteinPer100: 7, grams: 300),
      IngredientDraft(foodId: 'b:gambas', name: 'Gambas', kcalPer100: 109, proteinPer100: 24, grams: 300),
    ]);
    expect(d.kcal, closeTo(1377, 0.001));
    expect(d.servingG, 200); // 600 g en crudo ÷ 3
    d.cookedWeightG = 1200;
    expect(d.servingG, 400);
    expect(d.kcalPerServing, closeTo(459, 0.001));
    expect(d.problem(), isNull);
    expect(d.toJson()['ingredients'], [
      {'food_id': 'b:arroz_crudo', 'grams': 300.0},
      {'food_id': 'b:gambas', 'grams': 300.0},
    ]);
    d.cookedWeightG = -1; // lo que deja un texto no válido
    expect(d.servingG, 200);
    expect(d.problem(), 'Revisa el peso cocinado.');
  });

  test('DishDraft.fromDish recupera los valores por 100 g de cada ingrediente', () {
    final dish = Dish.fromJson({
      'id': 'x', 'name': 'Tortilla', 'servings': 2, 'cooked_weight_g': null, 'total_kcal': 300, 'total_protein': 20,
      'per100_kcal': 150, 'per100_protein': 10, 'per100_carbs': 1, 'per100_fat': 11, 'serving_g': 100,
      'ingredients': [
        {'food_id': 'b:huevo', 'name': 'Huevo', 'grams': 200, 'kcal': 286, 'protein': 25},
        {'food_id': null, 'name': 'Aceite viejo', 'grams': 5, 'kcal': 45, 'protein': 0},
      ],
    });
    final d = DishDraft.fromDish(dish);
    expect(d.ingredients.first.kcalPer100, closeTo(143, 0.001));
    d.ingredients.first.grams = 100;
    expect(d.ingredients.first.protein, closeTo(12.5, 0.001));
    expect(d.problem(), '«Aceite viejo» ya no existe como alimento. Quítalo o añádelo de nuevo.');
  });

  test('foodInput valida como el backend y acepta coma decimal', () {
    final ok = foodInput(name: ' Skyr ', kcal: '63', protein: '11', carbs: '4,2', fat: '', portion: '150');
    expect(ok.error, isNull);
    expect(ok.json, {'name': 'Skyr', 'kcal': 63.0, 'protein': 11.0, 'carbs': 4.2, 'fat': 0.0, 'default_portion_g': 150});
    String? err({String name = 'X', String kcal = '100', String protein = '10', String carbs = '10', String fat = '1', String portion = '100'}) =>
        foodInput(name: name, kcal: kcal, protein: protein, carbs: carbs, fat: fat, portion: portion).error;
    expect(err(name: ''), 'Ponle un nombre al alimento.');
    expect(err(kcal: ''), contains('kcal'));
    expect(err(kcal: '1000'), contains('kcal'));
    expect(err(protein: 'mucha'), contains('proteína'));
    expect(err(protein: '60', carbs: '50'), contains('suman más de 100'));
    expect(err(portion: '12,5'), contains('entero'));
  });
}
