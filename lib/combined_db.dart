import "food_db.dart";
import "user_recipes_repo.dart";

class CombinedDB implements DB {
  final DB base;
  final UserRecipesRepo userRepo;

  CombinedDB(this.base, this.userRepo);

  @override
  Map<String, Ingredient> get ingredients => base.ingredients;

  @override
  List<RecipeTemplate> get allRecipes => [...base.allRecipes, ...userRepo.allRecipes];

  // ✅ CAMBIO MÍNIMO: ordenar por lo que se displayea (name)
  int _byName(RecipeTemplate a, RecipeTemplate b) {
    final an = a.name.toLowerCase();
    final bn = b.name.toLowerCase();
    final c = an.compareTo(bn);
    return c != 0 ? c : a.id.compareTo(b.id); // tie-break estable
  }

  @override
  List<RecipeTemplate> recipesFor(MealSlot slot) {
    final out = allRecipes.where((r) => r.supports(slot)).toList();
    out.sort(_byName);
    return out;
  }

  // ---- helpers para UI ----
  // ✅ CAMBIO MÍNIMO: también en “Tus platos”
  List<RecipeTemplate> get userRecipes {
    final out = userRepo.allRecipes.toList();
    out.sort(_byName);
    return out;
  }

  Future<void> upsertUserRecipe(RecipeTemplate recipe) => userRepo.upsert(recipe);

  Future<void> deleteUserRecipe(String id) => userRepo.deleteById(id);
}
