import "package:flutter/material.dart";

/// =====================
/// DATA MODEL (shared)
/// =====================

class Macros {
  final double kcal;
  final double p;
  final double c;
  final double f;

  const Macros({required this.kcal, required this.p, required this.c, required this.f});

  static const zero = Macros(kcal: 0, p: 0, c: 0, f: 0);

  Macros operator +(Macros o) => Macros(kcal: kcal + o.kcal, p: p + o.p, c: c + o.c, f: f + o.f);
  Macros operator -(Macros o) => Macros(kcal: kcal - o.kcal, p: p - o.p, c: c - o.c, f: f - o.f);
  Macros operator *(double m) => Macros(kcal: kcal * m, p: p * m, c: c * m, f: f * m);
}

enum Unit { g, piece }
String unitLabel(Unit u) => u == Unit.g ? "g" : "u";

enum MacroRole { protein, carbs, fat, veg, neutral }

/// If unit==g: macrosPerUnit is per 100g.
/// If unit==piece: macrosPerUnit is per 1 piece/unit.
class Ingredient {
  final String id;
  final String name;
  final Unit unit;
  final Macros macrosPerUnit;

  const Ingredient({required this.id, required this.name, required this.unit, required this.macrosPerUnit});

  Macros macrosForAmount(double amount) {
    if (unit == Unit.g) {
      final factor = amount / 100.0;
      return macrosPerUnit * factor;
    } else {
      return macrosPerUnit * amount;
    }
  }
}

class RecipeIngredient {
  final String ingredientId;
  final MacroRole role;
  final double baseAmount;
  final double minAmount;
  final double maxAmount;
  final double step;

  const RecipeIngredient({
    required this.ingredientId,
    required this.role,
    required this.baseAmount,
    required this.minAmount,
    required this.maxAmount,
    required this.step,
  });

  bool get isVariable => (maxAmount - minAmount).abs() > 1e-9;
}

enum MealSlot { breakfast, lunch, snack, dinner }

String slotTitle(MealSlot s) {
  switch (s) {
    case MealSlot.breakfast:
      return "Breakfast";
    case MealSlot.lunch:
      return "Lunch";
    case MealSlot.snack:
      return "Snack";
    case MealSlot.dinner:
      return "Dinner";
  }
}

/// ✅ Ahora una receta vale para uno o varios momentos:
class RecipeTemplate {
  final String id;
  final String name;
  final List<MealSlot> slots; // <- multi-slot
  final List<RecipeIngredient> items;

  const RecipeTemplate({
    required this.id,
    required this.name,
    required this.slots,
    required this.items,
  });

  bool supports(MealSlot slot) => slots.contains(slot);
}

class MealPlanItem {
  final MealSlot slot; // slot REAL del plan (desayuno/comida/snack/cena)
  final RecipeTemplate recipe;
  final Map<String, double> amounts; // ingredientId -> amount

  const MealPlanItem({required this.slot, required this.recipe, required this.amounts});

  MealPlanItem copyWith({Map<String, double>? amounts}) =>
      MealPlanItem(slot: slot, recipe: recipe, amounts: amounts ?? this.amounts);
}

/// =====================
/// CONSTRAINTS (shared)
/// =====================

class SlotConstraints {
  final double minKcal;
  final double maxKcal;
  final double minP;
  const SlotConstraints({required this.minKcal, required this.maxKcal, required this.minP});
}

const Map<MealSlot, SlotConstraints> slotConstraints = {
  MealSlot.breakfast: SlotConstraints(minKcal: 350, maxKcal: 600, minP: 30),
  MealSlot.lunch: SlotConstraints(minKcal: 600, maxKcal: 1000, minP: 35),
  MealSlot.snack: SlotConstraints(minKcal: 120, maxKcal: 380, minP: 20),
  MealSlot.dinner: SlotConstraints(minKcal: 500, maxKcal: 950, minP: 30),
};


/// =====================
/// FOOD DATABASE (in-memory for MVP)
/// =====================

abstract class FoodDatabase {
  Map<String, Ingredient> get ingredients;
  List<RecipeTemplate> get allRecipes;
  List<RecipeTemplate> recipesFor(MealSlot slot);
}

class InMemoryFoodDatabase implements FoodDatabase {
  @override
  final Map<String, Ingredient> ingredients = {
    // =====================
    // PROTEIN / DAIRY
    // =====================
    "chicken": Ingredient(id: "chicken", name: "Chicken", unit: Unit.g, macrosPerUnit: const Macros(kcal: 165, p: 31, c: 0, f: 3.6)),
    "turkey": Ingredient(id: "turkey", name: "Turkey (Cooked)", unit: Unit.g, macrosPerUnit: const Macros(kcal: 135, p: 29, c: 0, f: 1.5)),
    "torsk": Ingredient(id: "torsk", name: "Cod", unit: Unit.g, macrosPerUnit: const Macros(kcal: 82, p: 18, c: 0, f: 0.7)),
    "salmon": Ingredient(id: "salmon", name: "Salmon", unit: Unit.g, macrosPerUnit: const Macros(kcal: 208, p: 20, c: 0, f: 13)),
    "beef": Ingredient(id: "beef", name: "Beef", unit: Unit.g, macrosPerUnit: const Macros(kcal: 250, p: 26, c: 0, f: 17)),
    "chicken_mince": Ingredient(id: "chicken_mince", name: "Chicken Mince", unit: Unit.g, macrosPerUnit: const Macros(kcal: 165, p: 16, c: 0, f: 7.5)),
    "beef_mince": Ingredient(id: "beef_mince", name: "Beef Mince", unit: Unit.g, macrosPerUnit: const Macros(kcal: 176, p: 20, c: 0, f: 5)),
    "whey": Ingredient(id: "whey", name: "Whey", unit: Unit.g, macrosPerUnit: const Macros(kcal: 400, p: 80, c: 8, f: 6)),

    "eggs": Ingredient(id: "eggs", name: "Egg", unit: Unit.piece, macrosPerUnit: const Macros(kcal: 70, p: 6.3, c: 0.4, f: 5)),
    "egg_white": Ingredient(id: "egg_white", name: "Egg white", unit: Unit.piece, macrosPerUnit: const Macros(kcal: 17, p: 3.6, c: 0.2, f: 0.0)),
    "skyr": Ingredient(id: "skyr", name: "Skyr (1u)", unit: Unit.piece, macrosPerUnit: const Macros(kcal: 160, p: 16, c: 10, f: 0)),
    "yogurt_natural": Ingredient(id: "yogurt_natural", name: "Natural Yogurt", unit: Unit.g, macrosPerUnit: const Macros(kcal: 60, p: 4, c: 5, f: 3)),
    "cottage": Ingredient(id: "cottage", name: "Cottage cheese", unit: Unit.g, macrosPerUnit: const Macros(kcal: 90, p: 12, c: 3, f: 2)),
    "parmesan": Ingredient(id: "parmesan", name: "Parmesan cheese", unit: Unit.g, macrosPerUnit: const Macros(kcal: 431, p: 38, c: 4, f: 29)),

    // =====================
    // CARBS
    // =====================
    "rice_dry": Ingredient(id: "rice_dry", name: "Rice (dry)", unit: Unit.g, macrosPerUnit: const Macros(kcal: 360, p: 7, c: 80, f: 1)),
    "couscous_dry": Ingredient(id: "couscous_dry", name: "Couscous (dry)", unit: Unit.g, macrosPerUnit: const Macros(kcal: 376, p: 12, c: 77, f: 0.6)),
    "pasta_dry": Ingredient(id: "pasta_dry", name: "Fullkorn Pasta (dry)", unit: Unit.g, macrosPerUnit: const Macros(kcal: 350, p: 13, c: 70, f: 2.5)),
    "potato": Ingredient(id: "potato", name: "Potato", unit: Unit.g, macrosPerUnit: const Macros(kcal: 77, p: 2.0, c: 17, f: 0.1)),
    "cereal_bar": Ingredient(id: "cereal_bar", name: "Cereal Bar", unit: Unit.piece, macrosPerUnit: const Macros(kcal: 110, p: 2, c: 18, f: 3)),
    "tortilla": Ingredient(id: "tortilla", name: "Tortilla", unit: Unit.piece, macrosPerUnit: const Macros(kcal: 170, p: 6, c: 28, f: 4)),
    "bread_whole": Ingredient(id: "bread_whole", name: "Bread (whole)", unit: Unit.piece, macrosPerUnit: const Macros(kcal: 90, p: 4, c: 16, f: 1.5)),
    "knekk": Ingredient(id: "knekk", name: "Crisp Bread", unit: Unit.piece, macrosPerUnit: const Macros(kcal: 45, p: 1.5, c: 8, f: 0.7)),

    // =====================
    // FATS
    // =====================
    "olive_oil": Ingredient(id: "olive_oil", name: "Olive Oil", unit: Unit.g, macrosPerUnit: const Macros(kcal: 884, p: 0, c: 0, f: 100)),
    "nuts": Ingredient(id: "nuts", name: "Nuts", unit: Unit.g, macrosPerUnit: const Macros(kcal: 654, p: 15, c: 14, f: 65)),
    "avocado_half": Ingredient(id: "avocado_half", name: "Avocado (1/2)", unit: Unit.piece, macrosPerUnit: const Macros(kcal: 120, p: 1.5, c: 6, f: 10.5)),

    // =====================
    // VEG / EXTRAS
    // =====================
    "berries": Ingredient(id: "berries", name: "Berries", unit: Unit.g, macrosPerUnit: const Macros(kcal: 50, p: 1, c: 12, f: 0.3)),
    "veg_mixed": Ingredient(id: "veg_mixed", name: "Mixed Vegetables", unit: Unit.g, macrosPerUnit: const Macros(kcal: 35, p: 2, c: 7, f: 0.2)),
    "broccoli": Ingredient(id: "broccoli", name: "Broccoli", unit: Unit.g, macrosPerUnit: const Macros(kcal: 35, p: 2.8, c: 7, f: 0.4)),
    "spinach": Ingredient(id: "spinach", name: "Spinach", unit: Unit.g, macrosPerUnit: const Macros(kcal: 23, p: 2.9, c: 3.6, f: 0.4)),
    "mushrooms": Ingredient(id: "mushrooms", name: "Mushrooms", unit: Unit.g, macrosPerUnit: const Macros(kcal: 22, p: 3.1, c: 3.3, f: 0.3)),
    "onion": Ingredient(id: "onion", name: "Onion", unit: Unit.g, macrosPerUnit: const Macros(kcal: 40, p: 1.1, c: 9.3, f: 0.1)),
    "carrot": Ingredient(id: "carrot", name: "Carrot", unit: Unit.g, macrosPerUnit: const Macros(kcal: 41, p: 0.9, c: 10, f: 0.2)),
    "pepper": Ingredient(id: "pepper", name: "Pepper", unit: Unit.g, macrosPerUnit: const Macros(kcal: 31, p: 1.0, c: 6.0, f: 0.3)),
    "passata": Ingredient(id: "passata", name: "Passata", unit: Unit.g, macrosPerUnit: const Macros(kcal: 29, p: 1.4, c: 5.3, f: 0.2)),
    "lemon": Ingredient(id: "lemon", name: "Lemon", unit: Unit.g, macrosPerUnit: const Macros(kcal: 29, p: 1.1, c: 9.3, f: 0.3)),
  };

  /// ✅ Sin recetas por defecto: el usuario empieza de 0
  @override
  final List<RecipeTemplate> allRecipes = const [];

  @override
  List<RecipeTemplate> recipesFor(MealSlot slot) => allRecipes.where((r) => r.supports(slot)).toList();
}

/// Alias (para UI)
typedef DB = FoodDatabase;

/// (Solo para evitar warning “unused import” si alguien copia este archivo suelto)
final _ = Colors.transparent;
