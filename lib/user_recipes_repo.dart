import "dart:convert";
import "package:shared_preferences/shared_preferences.dart";

import "food_db.dart";

abstract class UserRecipesRepo {
  List<RecipeTemplate> get allRecipes;

  Future<void> init();
  Future<void> upsert(RecipeTemplate recipe);
  Future<void> deleteById(String id);
}

class SharedPrefsUserRecipesRepo implements UserRecipesRepo {
  static const _key = "user_recipes_v2"; // <- bump versión porque cambia el schema
  final List<RecipeTemplate> _cache = [];

  @override
  List<RecipeTemplate> get allRecipes => List.unmodifiable(_cache);

  @override
  Future<void> init() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_key);
    _cache
      ..clear()
      ..addAll(_decodeList(raw));
  }

  @override
  Future<void> upsert(RecipeTemplate recipe) async {
    final idx = _cache.indexWhere((r) => r.id == recipe.id);
    if (idx >= 0) {
      _cache[idx] = recipe;
    } else {
      _cache.add(recipe);
    }
    await _persist();
  }

  @override
  Future<void> deleteById(String id) async {
    _cache.removeWhere((r) => r.id == id);
    await _persist();
  }

  Future<void> _persist() async {
    final sp = await SharedPreferences.getInstance();
    final jsonStr = jsonEncode(_cache.map(_recipeToJson).toList());
    await sp.setString(_key, jsonStr);
  }

  List<RecipeTemplate> _decodeList(String? raw) {
    if (raw == null || raw.trim().isEmpty) return [];
    try {
      final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
      return list.map(_recipeFromJson).toList();
    } catch (_) {
      return [];
    }
  }

  Map<String, dynamic> _recipeToJson(RecipeTemplate r) => {
        "id": r.id,
        "name": r.name,
        "slots": r.slots.map((s) => s.index).toList(),
        "items": r.items.map(_riToJson).toList(),
      };

  RecipeTemplate _recipeFromJson(Map<String, dynamic> j) {
    final slotIdxs = ((j["slots"] ?? const []) as List).cast<dynamic>();
    final slots = slotIdxs.map((x) => MealSlot.values[(x as num).toInt().clamp(0, MealSlot.values.length - 1)]).toList();

    return RecipeTemplate(
      id: (j["id"] ?? "") as String,
      name: (j["name"] ?? "") as String,
      slots: slots.isEmpty ? [MealSlot.lunch] : slots, // fallback safe
      items: ((j["items"] ?? const []) as List).cast<Map<String, dynamic>>().map(_riFromJson).toList(),
    );
  }

  Map<String, dynamic> _riToJson(RecipeIngredient ri) => {
        "ingredientId": ri.ingredientId,
        "role": ri.role.index,
        "baseAmount": ri.baseAmount,
        "minAmount": ri.minAmount,
        "maxAmount": ri.maxAmount,
        "step": ri.step,
      };

  RecipeIngredient _riFromJson(Map<String, dynamic> j) => RecipeIngredient(
        ingredientId: (j["ingredientId"] ?? "") as String,
        role: MacroRole.values[((j["role"] ?? 0) as num).toInt().clamp(0, MacroRole.values.length - 1)],
        baseAmount: (j["baseAmount"] as num).toDouble(),
        minAmount: (j["minAmount"] as num).toDouble(),
        maxAmount: (j["maxAmount"] as num).toDouble(),
        step: (j["step"] as num).toDouble(),
      );
}
