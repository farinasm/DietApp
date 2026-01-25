import "dart:math";
import "package:flutter/material.dart";

import "combined_db.dart";
import "food_db.dart";

class UserRecipesScreen extends StatefulWidget {
  final CombinedDB db;
  const UserRecipesScreen({super.key, required this.db});

  @override
  State<UserRecipesScreen> createState() => _UserRecipesScreenState();
}

class _UserRecipesScreenState extends State<UserRecipesScreen> {
  List<RecipeTemplate> get _recipes => widget.db.userRecipes;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    return CustomScrollView(
      slivers: [
        SliverAppBar.large(
          title: Text("Platos", style: t.headlineLarge),
          actions: [
            IconButton(
              tooltip: "Nuevo plato",
              icon: const Icon(Icons.add_rounded),
              onPressed: () async {
                final created = await _openEditor(context, null);
                if (created != null) {
                  await widget.db.upsertUserRecipe(created);
                  if (mounted) setState(() {});
                }
              },
            ),
            const SizedBox(width: 8),
          ],
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: _Card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Tus platos (persisten en móvil + web)", style: t.titleMedium),
                  const SizedBox(height: 6),
                  Text("Crea platos y el planificador los usará para generar DÍA y SEMANA.", style: t.bodySmall),
                ],
              ),
            ),
          ),
        ),
        if (_recipes.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _Card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("Aún no tienes platos.", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                    const SizedBox(height: 8),
                    const Text("Crea al menos 1 plato para cada momento (Desayuno/Comida/Snack/Cena)."),
                    const SizedBox(height: 10),
                    FilledButton.icon(
                      onPressed: () async {
                        final created = await _openEditor(context, null);
                        if (created != null) {
                          await widget.db.upsertUserRecipe(created);
                          if (mounted) setState(() {});
                        }
                      },
                      icon: const Icon(Icons.add_rounded),
                      label: const Text("Crear primer plato"),
                    ),
                  ],
                ),
              ),
            ),
          )
        else
          SliverList.separated(
            itemCount: _recipes.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, i) {
              final r = _recipes[i];
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _Card(
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(r.name, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 6,
                            children: r.slots
                                .map((s) => _Chip(text: slotTitle(s)))
                                .toList(),
                          ),
                          const SizedBox(height: 6),
                          Text("${r.items.length} ingredientes", style: const TextStyle(color: Color(0xFF6B7280))),
                        ]),
                      ),
                      IconButton(
                        tooltip: "Editar",
                        icon: const Icon(Icons.edit_rounded),
                        onPressed: () async {
                          final updated = await _openEditor(context, r);
                          if (updated != null) {
                            await widget.db.upsertUserRecipe(updated);
                            if (mounted) setState(() {});
                          }
                        },
                      ),
                      IconButton(
                        tooltip: "Borrar",
                        icon: const Icon(Icons.delete_outline_rounded),
                        onPressed: () async {
                          await widget.db.deleteUserRecipe(r.id);
                          if (mounted) setState(() {});
                        },
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }

  Future<RecipeTemplate?> _openEditor(BuildContext context, RecipeTemplate? existing) async {
    return showModalBottomSheet<RecipeTemplate>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _RecipeEditorSheet(db: widget.db, initial: existing),
    );
  }
}

/// =====================
/// Editor Sheet
/// =====================

class _RecipeEditorSheet extends StatefulWidget {
  final CombinedDB db;
  final RecipeTemplate? initial;
  const _RecipeEditorSheet({required this.db, required this.initial});

  @override
  State<_RecipeEditorSheet> createState() => _RecipeEditorSheetState();
}

class _RecipeEditorSheetState extends State<_RecipeEditorSheet> {
  late final TextEditingController name =
      TextEditingController(text: widget.initial?.name ?? "");

  late List<MealSlot> slots =
      widget.initial?.slots.toList() ?? [MealSlot.lunch];

  late List<RecipeIngredient> items =
      widget.initial?.items.toList() ??
          [
            const RecipeIngredient(
              ingredientId: "chicken",
              role: MacroRole.protein,
              baseAmount: 150,
              minAmount: 100,
              maxAmount: 250,
              step: 20,
            )
          ];

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + pad),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 44, height: 5, decoration: BoxDecoration(color: Colors.black12, borderRadius: BorderRadius.circular(999))),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(widget.initial == null ? "Nuevo plato" : "Editar plato",
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          ),
          const SizedBox(height: 12),

          TextField(
            controller: name,
            decoration: const InputDecoration(labelText: "Nombre del plato"),
          ),
          const SizedBox(height: 12),

          Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: MealSlot.values.map((s) {
                final selected = slots.contains(s);
                return FilterChip(
                  label: Text(slotTitle(s)),
                  selected: selected,
                  onSelected: (v) {
                    setState(() {
                      if (v) {
                        if (!slots.contains(s)) slots.add(s);
                      } else {
                        slots.remove(s);
                        if (slots.isEmpty) slots = [MealSlot.lunch];
                      }
                    });
                  },
                );
              }).toList(),
            ),
          ),

          const SizedBox(height: 14),

          Align(
            alignment: Alignment.centerLeft,
            child: Row(
              children: [
                const Text("Ingredientes", style: TextStyle(fontWeight: FontWeight.w900)),
                const Spacer(),
                TextButton.icon(
                  onPressed: () {
                    final firstIng = widget.db.ingredients.keys.first;
                    setState(() {
                      items.add(RecipeIngredient(
                        ingredientId: firstIng,
                        role: MacroRole.neutral,
                        baseAmount: widget.db.ingredients[firstIng]!.unit == Unit.piece ? 1 : 100,
                        minAmount: 0,
                        maxAmount: widget.db.ingredients[firstIng]!.unit == Unit.piece ? 6 : 400,
                        step: widget.db.ingredients[firstIng]!.unit == Unit.piece ? 1 : 20,
                      ));
                    });
                  },
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text("Añadir"),
                ),
              ],
            ),
          ),

          const SizedBox(height: 8),

          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 340),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final ri = items[i];
                return _IngredientEditorRow(
                  db: widget.db,
                  ri: ri,
                  onChanged: (newRi) => setState(() => items[i] = newRi),
                  onDelete: () => setState(() => items.removeAt(i)),
                );
              },
            ),
          ),

          const SizedBox(height: 14),

          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton(
              onPressed: () {
                final id = widget.initial?.id ?? "u_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(9999)}";
                final nm = name.text.trim();
                if (nm.isEmpty) return;

                final cleanedSlots = slots.isEmpty ? [MealSlot.lunch] : slots.toList();
                final cleanedItems = items.where((x) => widget.db.ingredients.containsKey(x.ingredientId)).toList();
                if (cleanedItems.isEmpty) return;

                Navigator.pop(
                  context,
                  RecipeTemplate(id: id, name: nm, slots: cleanedSlots, items: cleanedItems),
                );
              },
              child: const Text("Guardar"),
            ),
          ),
        ],
      ),
    );
  }
}

class _IngredientEditorRow extends StatelessWidget {
  final CombinedDB db;
  final RecipeIngredient ri;
  final void Function(RecipeIngredient) onChanged;
  final VoidCallback onDelete;

  const _IngredientEditorRow({
    required this.db,
    required this.ri,
    required this.onChanged,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final ing = db.ingredients[ri.ingredientId]!;
    final isPiece = ing.unit == Unit.piece;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFEFEFF4),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: ri.ingredientId,
                  isExpanded: true,
                  items: (db.ingredients.values.toList()
                        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase())))
                      .map((x) => DropdownMenuItem(value: x.id, child: Text(x.name)))
                      .toList(),
                  onChanged: (v) {
                    if (v == null) return;
                    final ing2 = db.ingredients[v]!;
                    final isPiece2 = ing2.unit == Unit.piece;
                    onChanged(RecipeIngredient(
                      ingredientId: v,
                      role: ri.role,
                      baseAmount: isPiece2 ? 1 : 100,
                      minAmount: 0,
                      maxAmount: isPiece2 ? 8 : 500,
                      step: isPiece2 ? 1 : 20,
                    ));
                  },
                  decoration: const InputDecoration(labelText: "Ingrediente"),
                ),
              ),
              IconButton(onPressed: onDelete, icon: const Icon(Icons.close_rounded)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<MacroRole>(
                  value: ri.role,
                  items: MacroRole.values
                      .map((r) => DropdownMenuItem(value: r, child: Text(_roleLabel(r))))
                      .toList(),
                  onChanged: (v) => onChanged(_copy(role: v ?? ri.role)),
                  decoration: const InputDecoration(labelText: "Rol"),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextFormField(
                  initialValue: ri.step.toStringAsFixed(0),
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: "Paso (${unitLabel(ing.unit)})"),
                  onChanged: (v) => onChanged(_copy(step: _d(v, ri.step))),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  initialValue: ri.baseAmount.toStringAsFixed(0),
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: "Base (${unitLabel(ing.unit)})"),
                  onChanged: (v) => onChanged(_copy(baseAmount: _d(v, ri.baseAmount))),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextFormField(
                  initialValue: ri.minAmount.toStringAsFixed(0),
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: "Min (${unitLabel(ing.unit)})"),
                  onChanged: (v) => onChanged(_copy(minAmount: _d(v, ri.minAmount))),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextFormField(
                  initialValue: ri.maxAmount.toStringAsFixed(0),
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: "Max (${unitLabel(ing.unit)})"),
                  onChanged: (v) => onChanged(_copy(maxAmount: _d(v, ri.maxAmount))),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              isPiece ? "Unidad: piezas" : "Unidad: gramos (macros por 100g)",
              style: const TextStyle(color: Color(0xFF6B7280), fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  RecipeIngredient _copy({
    String? ingredientId,
    MacroRole? role,
    double? baseAmount,
    double? minAmount,
    double? maxAmount,
    double? step,
  }) {
    return RecipeIngredient(
      ingredientId: ingredientId ?? ri.ingredientId,
      role: role ?? ri.role,
      baseAmount: baseAmount ?? ri.baseAmount,
      minAmount: minAmount ?? ri.minAmount,
      maxAmount: maxAmount ?? ri.maxAmount,
      step: step ?? ri.step,
    );
  }

  static double _d(String v, double fallback) => double.tryParse(v.trim().replaceAll(",", ".")) ?? fallback;

  static String _roleLabel(MacroRole r) {
    switch (r) {
      case MacroRole.protein:
        return "proteína";
      case MacroRole.carbs:
        return "carbs";
      case MacroRole.fat:
        return "grasa";
      case MacroRole.veg:
        return "verduras";
      case MacroRole.neutral:
        return "extra";
    }
  }
}

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withOpacity(0.06)),
      ),
      child: child,
    );
  }
}

class _Chip extends StatelessWidget {
  final String text;
  const _Chip({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFEFEFF4),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(text, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12)),
    );
  }
}
