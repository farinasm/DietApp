import "dart:math";
import "food_db.dart";

/// =====================
/// TARGETS
/// =====================

class DayTargets {
  double kcal, p, c, f;
  DayTargets({required this.kcal, required this.p, required this.c, required this.f});
  Macros get macros => Macros(kcal: kcal, p: p, c: c, f: f);
}

/// =====================
/// SLOT CONSTRAINTS + SHARE (aquí para evitar conflictos)
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

const Map<MealSlot, double> slotShare = {
  MealSlot.breakfast: 0.25,
  MealSlot.lunch: 0.35,
  MealSlot.snack: 0.10,
  MealSlot.dinner: 0.30,
};

bool respectsSlotConstraints(MealSlot slot, Macros m) {
  final cons = slotConstraints[slot];
  if (cons == null) return true;
  if (m.kcal < cons.minKcal || m.kcal > cons.maxKcal) return false;
  if (m.p < cons.minP) return false;
  return true;
}

/// =====================
/// MACROS HELPERS
/// =====================

Macros macrosForRecipeAmounts(DB db, RecipeTemplate recipe, Map<String, double> amounts) {
  Macros total = Macros.zero;
  for (final ri in recipe.items) {
    final ing = db.ingredients[ri.ingredientId];
    if (ing == null) continue;
    final amt = amounts[ri.ingredientId] ?? 0;
    total = total + ing.macrosForAmount(amt);
  }
  return total;
}

Macros totalMacros(DB db, List<MealPlanItem> day) {
  Macros t = Macros.zero;
  for (final m in day) {
    t = t + macrosForRecipeAmounts(db, m.recipe, m.amounts);
  }
  return t;
}

/// =====================
/// SCORE
/// =====================

double scoreDistance(Macros a, Macros target) {
  final diff = a - target;

  double pen(double x, {double over = 3.0, double under = 1.0}) {
    if (x > 0) return x * over;
    return (-x) * under;
  }

  final kcalPen = pen(diff.kcal, over: 2.0, under: 1.0);
  final pPen = pen(diff.p, over: 5.5, under: 1.4);
  final cPen = pen(diff.c, over: 2.6, under: 1.1);
  final fPen = pen(diff.f, over: 2.6, under: 1.1);

  return (kcalPen * 0.45) + (pPen * 3.2) + (cPen * 1.2) + (fPen * 1.2);
}

/// =====================
/// AMOUNTS HELPERS
/// =====================

Map<String, double> initialAmounts(RecipeTemplate r) => {for (final it in r.items) it.ingredientId: it.baseAmount};

Map<String, double> clampAmounts(RecipeTemplate r, Map<String, double> amts) {
  final out = Map<String, double>.from(amts);
  for (final it in r.items) {
    final v = out[it.ingredientId] ?? it.baseAmount;
    out[it.ingredientId] = v.clamp(it.minAmount, it.maxAmount).toDouble();
  }
  return out;
}

/// =====================
/// PLACEHOLDERS (compatibles con RecipeTemplate(slots: ...))
/// =====================

RecipeTemplate _emptyRecipe(MealSlot slot) => RecipeTemplate(
      id: "_empty_${slot.name}",
      name: "(No recipe. Go add some!)",
      slots: [slot],
      items: const [],
    );

MealPlanItem _emptyMeal(MealSlot slot) => MealPlanItem(slot: slot, recipe: _emptyRecipe(slot), amounts: const {});
bool _isEmptyMeal(MealPlanItem m) => m.recipe.id.startsWith("_empty_");

/// =====================
/// OPTIMIZE MEAL
/// =====================

Map<String, double> optimizeMeal(
  DB db,
  MealSlot slot,
  RecipeTemplate recipe,
  Map<String, double> start,
  Macros slotTarget, {
  int iterations = 170,
}) {
  if (recipe.items.isEmpty) return const {};

  Map<String, double> best = clampAmounts(recipe, start);
  Macros bestM = macrosForRecipeAmounts(db, recipe, best);
  double bestScore = scoreDistance(bestM, slotTarget);

  bool isAdjustable(RecipeIngredient ri) =>
      ri.isVariable && (ri.role == MacroRole.protein || ri.role == MacroRole.carbs || ri.role == MacroRole.fat);

  void tryDelta(RecipeIngredient ri, double delta) {
    final next = Map<String, double>.from(best);
    final cur = next[ri.ingredientId] ?? ri.baseAmount;
    final n = (cur + delta).clamp(ri.minAmount, ri.maxAmount).toDouble();
    if ((n - cur).abs() < 1e-9) return;
    next[ri.ingredientId] = n;

    final m = macrosForRecipeAmounts(db, recipe, next);
    if (!respectsSlotConstraints(slot, m)) return;

    final s = scoreDistance(m, slotTarget);
    if (s + 1e-9 < bestScore) {
      best = next;
      bestM = m;
      bestScore = s;
    }
  }

  for (int i = 0; i < iterations; i++) {
    final before = bestScore;
    final residual = slotTarget - bestM;

    for (final ri in recipe.items.where(isAdjustable)) {
      double dir = 0;
      if (ri.role == MacroRole.protein) dir = residual.p >= 0 ? 1 : -1;
      if (ri.role == MacroRole.carbs) dir = residual.c >= 0 ? 1 : -1;
      if (ri.role == MacroRole.fat) dir = residual.f >= 0 ? 1 : -1;
      if (dir != 0) tryDelta(ri, dir * ri.step);
    }

    if (bestScore == before) break;
  }

  return best;
}

/// =====================
/// OPTIMIZE DAY
/// =====================

List<MealPlanItem> optimizeDay(DB db, List<MealPlanItem> day, DayTargets targets, {int iterations = 1200}) {
  var bestDay = day;
  var bestTotal = totalMacros(db, bestDay);
  var bestScore = scoreDistance(bestTotal, targets.macros);

  bool isAdjustable(RecipeIngredient ri) =>
      ri.isVariable && (ri.role == MacroRole.protein || ri.role == MacroRole.carbs || ri.role == MacroRole.fat);

  for (int it = 0; it < iterations; it++) {
    final residual = targets.macros - bestTotal;

    MealPlanItem? bestMealCandidate;
    Map<String, double>? bestAmountsCandidate;
    double bestMoveScore = bestScore;

    for (final meal in bestDay) {
      if (_isEmptyMeal(meal)) continue;

      for (final ri in meal.recipe.items.where(isAdjustable)) {
        final cur = meal.amounts[ri.ingredientId] ?? ri.baseAmount;

        double dir = 0;
        if (ri.role == MacroRole.protein) dir = residual.p >= 0 ? 1 : -1;
        if (ri.role == MacroRole.carbs) dir = residual.c >= 0 ? 1 : -1;
        if (ri.role == MacroRole.fat) dir = residual.f >= 0 ? 1 : -1;
        if (dir == 0) continue;

        for (final mult in const [1.0, 2.0]) {
          final next = (cur + dir * ri.step * mult).clamp(ri.minAmount, ri.maxAmount).toDouble();
          if ((next - cur).abs() < 1e-9) continue;

          final newAmounts = Map<String, double>.from(meal.amounts);
          newAmounts[ri.ingredientId] = next;

          final candidateDay = bestDay.map((m) {
            if (m.slot == meal.slot) return m.copyWith(amounts: newAmounts);
            return m;
          }).toList();

          final slotM = macrosForRecipeAmounts(db, meal.recipe, newAmounts);
          if (!respectsSlotConstraints(meal.slot, slotM)) continue;

          final candTotal = totalMacros(db, candidateDay);
          final candScore = scoreDistance(candTotal, targets.macros);

          if (candScore + 1e-9 < bestMoveScore) {
            bestMoveScore = candScore;
            bestMealCandidate = meal;
            bestAmountsCandidate = newAmounts;
          }
        }
      }
    }

    if (bestMealCandidate == null || bestAmountsCandidate == null) break;

    bestDay = bestDay.map((m) {
      if (m.slot == bestMealCandidate!.slot) return m.copyWith(amounts: bestAmountsCandidate!);
      return m;
    }).toList();

    bestTotal = totalMacros(db, bestDay);
    bestScore = bestMoveScore;
  }

  return bestDay;
}

/// =====================
/// GENERATE DAY
/// =====================

List<MealPlanItem> generateDay(DB db, DayTargets targets, {int? seed}) {
  final rng = Random(seed ?? DateTime.now().millisecondsSinceEpoch);
  final chosen = <MealPlanItem>[];
  final usedRecipeIds = <String>{};

  for (final slot in MealSlot.values) {
    final slotRecipes = db.recipesFor(slot);

    if (slotRecipes.isEmpty) {
      chosen.add(_emptyMeal(slot));
      continue;
    }

    final candidates = slotRecipes.where((r) => !usedRecipeIds.contains(r.id)).toList();
    final pool = candidates.isEmpty ? slotRecipes : candidates;
    final recipe = pool[rng.nextInt(pool.length)];
    usedRecipeIds.add(recipe.id);

    final share = slotShare[slot] ?? 0.25;
    final slotTarget = targets.macros * share;

    final optAmounts = optimizeMeal(db, slot, recipe, initialAmounts(recipe), slotTarget);
    chosen.add(MealPlanItem(slot: slot, recipe: recipe, amounts: optAmounts));
  }

  return optimizeDay(db, chosen, targets, iterations: 1200);
}
