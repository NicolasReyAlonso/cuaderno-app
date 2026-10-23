/// Comidas: alimentos y platos (valores por 100 g) y el diario del día.
library;

double _d(dynamic v) => (v as num?)?.toDouble() ?? 0;

/// Comidas del día en el orden en que se muestran. Clave = valor de la API.
const meals = [
  ('desayuno', 'Desayuno'),
  ('almuerzo', 'Almuerzo'),
  ('merienda', 'Merienda'),
  ('cena', 'Cena'),
  ('picoteo', 'Picoteo'),
];

/// Comida que toca por la hora: la que se propone al añadir desde arriba.
String mealForHour(int hour) => switch (hour) {
      < 11 => 'desayuno',
      < 16 => 'almuerzo',
      < 20 => 'merienda',
      _ => 'cena',
    };

/// Valores por 100 g de algo que se puede apuntar: un alimento o un plato.
class Per100 {
  final double kcal, protein, carbs, fat;
  const Per100(this.kcal, this.protein, this.carbs, this.fat);
  ({double kcal, double protein}) forGrams(double g) => (kcal: kcal * g / 100, protein: protein * g / 100);
}

class Food {
  final String id, name, category;
  final Per100 per100;
  final int defaultPortionG;
  final bool mine;
  const Food({required this.id, required this.name, required this.category, required this.per100, required this.defaultPortionG, required this.mine});

  factory Food.fromJson(Map<String, dynamic> j) => Food(
        id: j['id'] as String,
        name: j['name'] as String,
        category: j['category'] as String,
        per100: Per100(_d(j['kcal']), _d(j['protein']), _d(j['carbs']), _d(j['fat'])),
        defaultPortionG: j['default_portion_g'] as int,
        mine: j['mine'] as bool? ?? false,
      );
}

class DishIngredient {
  final String? foodId; // null si el alimento se borró: el plato guarda su copia
  final String name;
  final double grams, kcal, protein; // ya calculados para esos gramos
  const DishIngredient({required this.foodId, required this.name, required this.grams, required this.kcal, required this.protein});

  factory DishIngredient.fromJson(Map<String, dynamic> j) => DishIngredient(
        foodId: j['food_id'] as String?,
        name: j['name'] as String,
        grams: _d(j['grams']),
        kcal: _d(j['kcal']),
        protein: _d(j['protein']),
      );
}

class Dish {
  final String id, name;
  final int servings, servingG;
  final double? cookedWeightG;
  final double totalKcal, totalProtein;
  final Per100 per100;
  final List<DishIngredient> ingredients;
  const Dish({
    required this.id,
    required this.name,
    required this.servings,
    required this.servingG,
    required this.per100,
    this.cookedWeightG,
    this.totalKcal = 0,
    this.totalProtein = 0,
    this.ingredients = const [],
  });

  factory Dish.fromJson(Map<String, dynamic> j) => Dish(
        id: j['id'] as String,
        name: j['name'] as String,
        servings: j['servings'] as int,
        servingG: j['serving_g'] as int,
        cookedWeightG: (j['cooked_weight_g'] as num?)?.toDouble(),
        totalKcal: _d(j['total_kcal']),
        totalProtein: _d(j['total_protein']),
        per100: Per100(_d(j['per100_kcal']), _d(j['per100_protein']), _d(j['per100_carbs']), _d(j['per100_fat'])),
        ingredients: [for (final i in j['ingredients'] as List? ?? const []) DishIngredient.fromJson(i as Map<String, dynamic>)],
      );
}

class IngredientDraft {
  final String? foodId;
  final String name;
  final double kcalPer100, proteinPer100;
  double grams;
  IngredientDraft({required this.foodId, required this.name, required this.kcalPer100, required this.proteinPer100, required this.grams});

  factory IngredientDraft.fromFood(Food f, double grams) =>
      IngredientDraft(foodId: f.id, name: f.name, kcalPer100: f.per100.kcal, proteinPer100: f.per100.protein, grams: grams);

  /// De un plato guardado: los valores por 100 g salen de los ya calculados para sus gramos.
  factory IngredientDraft.fromDish(DishIngredient i) => IngredientDraft(
        foodId: i.foodId,
        name: i.name,
        kcalPer100: i.grams > 0 ? i.kcal / i.grams * 100 : 0,
        proteinPer100: i.grams > 0 ? i.protein / i.grams * 100 : 0,
        grams: i.grams,
      );

  double get kcal => kcalPer100 * grams / 100;
  double get protein => proteinPer100 * grams / 100;
}

/// Plato en edición. Los totales siguen la misma cuenta que el backend (dish_out):
/// el peso es el cocinado si lo hay o, si no, la suma de los ingredientes en crudo.
class DishDraft {
  final String? id;
  String name;
  int servings;
  double? cookedWeightG;
  final List<IngredientDraft> ingredients;
  DishDraft({this.id, this.name = '', this.servings = 1, this.cookedWeightG, List<IngredientDraft>? ingredients}) : ingredients = ingredients ?? [];

  factory DishDraft.fromDish(Dish d) => DishDraft(
      id: d.id, name: d.name, servings: d.servings, cookedWeightG: d.cookedWeightG, ingredients: [for (final i in d.ingredients) IngredientDraft.fromDish(i)]);

  double get kcal => ingredients.fold(0, (s, i) => s + i.kcal);
  double get protein => ingredients.fold(0, (s, i) => s + i.protein);
  double get rawWeight => ingredients.fold(0, (s, i) => s + i.grams);
  // Un peso cocinado no válido no cuenta aquí; problem() lo avisa al guardar
  double get weight => (cookedWeightG ?? 0) > 0 ? cookedWeightG! : (rawWeight > 0 ? rawWeight : 1);
  int get servingG => servings > 0 ? (weight / servings).round() : 0;
  double get kcalPerServing => servings > 0 ? kcal / servings : 0;
  double get proteinPerServing => servings > 0 ? protein / servings : 0;

  String? problem() {
    if (name.trim().isEmpty) return 'Ponle un nombre al plato.';
    if (servings < 1 || servings > 50) return 'Las raciones van de 1 a 50.';
    if (ingredients.isEmpty) return 'Añade al menos un ingrediente.';
    for (final i in ingredients) {
      if (i.foodId == null) return '«${i.name}» ya no existe como alimento. Quítalo o añádelo de nuevo.';
      if (i.grams <= 0 || i.grams > 20000) return 'Revisa los gramos de «${i.name}».';
    }
    final c = cookedWeightG;
    if (c != null && (c <= 0 || c > 50000)) return 'Revisa el peso cocinado.';
    return null;
  }

  Map<String, dynamic> toJson() => {
        'name': name.trim(),
        'servings': servings,
        'cooked_weight_g': cookedWeightG,
        'ingredients': [for (final i in ingredients) {'food_id': i.foodId, 'grams': i.grams}],
      };
}

/// Datos de un alimento propio escritos a mano (valores por 100 g, con coma decimal).
/// Devuelve el JSON para POST /foods o el primer problema, en una frase.
({Map<String, dynamic>? json, String? error}) foodInput({
  required String name,
  required String kcal,
  required String protein,
  required String carbs,
  required String fat,
  required String portion,
}) {
  double? num(String s) => s.trim().isEmpty ? 0 : double.tryParse(s.trim().replaceAll(',', '.'));
  if (name.trim().isEmpty) return (json: null, error: 'Ponle un nombre al alimento.');
  final k = num(kcal), p = num(protein), c = num(carbs), f = num(fat), g = num(portion);
  if (kcal.trim().isEmpty || k == null || k < 0 || k > 950) return (json: null, error: 'Las kcal por 100 g van de 0 a 950.');
  for (final (label, v) in [('proteína', p), ('carbohidratos', c), ('grasa', f)]) {
    if (v == null || v < 0 || v > 100) return (json: null, error: 'Los gramos de $label por 100 g van de 0 a 100.');
  }
  if (p! + c! + f! > 100) return (json: null, error: 'Proteína, carbohidratos y grasa suman más de 100 g por cada 100 g.');
  if (g == null || g < 1 || g > 5000 || g != g.roundToDouble()) return (json: null, error: 'La ración es un número entero de gramos, de 1 a 5000.');
  return (
    json: {'name': name.trim(), 'kcal': k, 'protein': p, 'carbs': c, 'fat': f, 'default_portion_g': g.toInt()},
    error: null,
  );
}

class DiaryItem {
  final String id, meal, name;
  final double grams, kcal, protein, carbs, fat;
  const DiaryItem({required this.id, required this.meal, required this.name, required this.grams, required this.kcal, required this.protein, required this.carbs, required this.fat});

  factory DiaryItem.fromJson(Map<String, dynamic> j) => DiaryItem(
        id: j['id'] as String,
        meal: j['meal'] as String,
        name: j['name'] as String,
        grams: _d(j['grams']),
        kcal: _d(j['kcal']),
        protein: _d(j['protein']),
        carbs: _d(j['carbs']),
        fat: _d(j['fat']),
      );
}

class DiaryDay {
  final DateTime date;
  final List<DiaryItem> items;
  final double kcal, protein, carbs, fat;
  final int kcalTarget, proteinTarget;
  const DiaryDay({required this.date, required this.items, required this.kcal, required this.protein, required this.carbs, required this.fat, required this.kcalTarget, required this.proteinTarget});

  factory DiaryDay.fromJson(Map<String, dynamic> j) => DiaryDay(
        date: DateTime.parse(j['date'] as String),
        items: [for (final i in j['items'] as List) DiaryItem.fromJson(i as Map<String, dynamic>)],
        kcal: _d(j['kcal']),
        protein: _d(j['protein']),
        carbs: _d(j['carbs']),
        fat: _d(j['fat']),
        kcalTarget: j['kcal_target'] as int,
        proteinTarget: j['protein_target_g'] as int,
      );

  List<DiaryItem> itemsOf(String meal) => [for (final i in items) if (i.meal == meal) i];
  double kcalOf(String meal) => itemsOf(meal).fold(0, (s, i) => s + i.kcal);
}

/// Gramos escritos a mano: acepta coma decimal. null si no es un número entre 0 (excluido) y 5000.
double? parseGrams(String text) {
  final v = double.tryParse(text.trim().replaceAll(',', '.'));
  return v == null || v <= 0 || v > 5000 ? null : v;
}
