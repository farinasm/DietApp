import "dart:math";
import "package:flutter/material.dart";

import "food_db.dart";
import "planner.dart";
import "combined_db.dart";

/// =====================================================
/// 1) MENU EDITOR (editar un menú del día: martes comida)
/// =====================================================

class MenuEditorScreen extends StatefulWidget {
  final DB db;
  final String dayTitle;
  final MealSlot slot;
  final MealPlanItem meal;
  final DayTargets targets;

  final void Function(MealPlanItem updated) onChanged;
  final VoidCallback onRegenerate;

  const MenuEditorScreen({
    super.key,
    required this.db,
    required this.dayTitle,
    required this.slot,
    required this.meal,
    required this.targets,
    required this.onChanged,
    required this.onRegenerate,
  });

  @override
  State<MenuEditorScreen> createState() => _MenuEditorScreenState();
}

class _MenuEditorScreenState extends State<MenuEditorScreen> {
  late MealPlanItem current = widget.meal;

  void _adjustIngredient(String ingredientId, double delta) {
    final ri = current.recipe.items.firstWhere((x) => x.ingredientId == ingredientId);
    final cur = current.amounts[ingredientId] ?? ri.baseAmount;
    final next = (cur + delta).clamp(ri.minAmount, ri.maxAmount).toDouble();

    final newAmounts = Map<String, double>.from(current.amounts);
    newAmounts[ingredientId] = next;

    setState(() => current = current.copyWith(amounts: newAmounts));
    widget.onChanged(current);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final title = "${widget.dayTitle} · ${slotTitle(widget.slot)}";

    // Orden alfabético por nombre del ingrediente (para el card)
    final items = [...current.recipe.items]
      ..sort((a, b) {
        final an = widget.db.ingredients[a.ingredientId]!.name.toLowerCase();
        final bn = widget.db.ingredients[b.ingredientId]!.name.toLowerCase();
        return an.compareTo(bn);
      });

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar.large(
            title: Text(title, style: t.headlineLarge),
            actions: [
              IconButton(
                tooltip: "Regenerar menú",
                icon: const Icon(Icons.refresh_rounded),
                onPressed: () {
                  widget.onRegenerate();
                  Navigator.pop(context);
                },
              ),
              const SizedBox(width: 8),
            ],
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SectionHeader(
                    title: "Editar menú",
                    subtitle: "Ajusta cantidades o regenera esta comida",
                    trailing: TextButton(
                      onPressed: () {
                        widget.onRegenerate();
                        Navigator.pop(context);
                      },
                      child: const Text("Regenerar"),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _MealCard(
                    db: widget.db,
                    meal: current,
                    sortedItems: items,
                    onRegen: () {
                      widget.onRegenerate();
                      Navigator.pop(context);
                    },
                    onAdjust: (id, d) => _adjustIngredient(id, d),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// =====================================================
/// 2) RECIPE EDITOR (crear/editar plato del usuario)
///    - MULTI-SLOT: slots: List<MealSlot>
/// =====================================================

class RecipeEditorScreen extends StatefulWidget {
  final CombinedDB db;
  final RecipeTemplate? initial;

  const RecipeEditorScreen({
    super.key,
    required this.db,
    required this.initial,
  });

  @override
  State<RecipeEditorScreen> createState() => _RecipeEditorScreenState();
}

class _RecipeEditorScreenState extends State<RecipeEditorScreen> {
  late final TextEditingController nameCtrl;

  // ✅ ahora multi-slot
  Set<MealSlot> slots = {MealSlot.lunch};

  // ingredientId -> amount (g o ud)
  final Map<String, double> amounts = {};

  // ingredientId -> role (para planner)
  final Map<String, MacroRole> roles = {};

  @override
  void initState() {
    super.initState();

    final init = widget.initial;
    nameCtrl = TextEditingController(text: init?.name ?? "");

    if (init != null) {
      // ✅ init.slots en vez de init.slot
      slots = init.slots.toSet();
      if (slots.isEmpty) slots = {MealSlot.lunch};

      for (final ri in init.items) {
        amounts[ri.ingredientId] = ri.baseAmount;
        roles[ri.ingredientId] = ri.role;
      }
    }
  }

  @override
  void dispose() {
    nameCtrl.dispose();
    super.dispose();
  }

  String _newId() => "u_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(999999)}";

  void _addIngredient(String id) {
    if (amounts.containsKey(id)) return;
    final ing = widget.db.ingredients[id]!;
    setState(() {
      amounts[id] = ing.unit == Unit.piece ? 1.0 : 100.0;
      roles[id] = _suggestRole(ing);
    });
  }

  void _removeIngredient(String id) {
    setState(() {
      amounts.remove(id);
      roles.remove(id);
    });
  }

  void _toggleSlot(MealSlot s) {
    setState(() {
      if (slots.contains(s)) {
        if (slots.length > 1) slots.remove(s); // siempre mínimo 1
      } else {
        slots.add(s);
      }
    });
  }

  MacroRole _suggestRole(Ingredient ing) {
    final m = ing.macrosPerUnit;
    if (m.p >= max(m.c, m.f)) return MacroRole.protein;
    if (m.c >= max(m.p, m.f)) return MacroRole.carbs;
    if (m.f >= max(m.p, m.c)) return MacroRole.fat;
    return MacroRole.neutral;
  }

  void _save() {
    final name = nameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Ponle un nombre al plato.")));
      return;
    }
    if (amounts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Añade al menos un ingrediente.")));
      return;
    }

    final items = amounts.entries.map((e) {
      final id = e.key;
      final amt = e.value;

      final ing = widget.db.ingredients[id]!;
      final step = ing.unit == Unit.piece ? 1.0 : 10.0;

      return RecipeIngredient(
        ingredientId: id,
        role: roles[id] ?? MacroRole.neutral,
        baseAmount: amt,
        minAmount: 0,
        maxAmount: ing.unit == Unit.piece ? 10 : 500,
        step: step,
      );
    }).toList();

    // orden alfabético por nombre de ingrediente
    items.sort((a, b) {
      final an = widget.db.ingredients[a.ingredientId]!.name.toLowerCase();
      final bn = widget.db.ingredients[b.ingredientId]!.name.toLowerCase();
      return an.compareTo(bn);
    });

    final out = RecipeTemplate(
      id: widget.initial?.id ?? _newId(),
      name: name,
      // ✅ slots (list) en vez de slot
      slots: slots.toList()..sort((a, b) => a.index.compareTo(b.index)),
      items: items,
    );

    Navigator.pop(context, out);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    // disponibles ordenados A-Z por nombre
    final availableIds = widget.db.ingredients.keys
        .where((id) => !amounts.containsKey(id))
        .toList()
      ..sort((a, b) {
        final an = widget.db.ingredients[a]!.name.toLowerCase();
        final bn = widget.db.ingredients[b]!.name.toLowerCase();
        return an.compareTo(bn);
      });

    // seleccionados A-Z por nombre
    final selected = amounts.keys.toList()
      ..sort((a, b) {
        final an = widget.db.ingredients[a]!.name.toLowerCase();
        final bn = widget.db.ingredients[b]!.name.toLowerCase();
        return an.compareTo(bn);
      });

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar.large(
            title: Text(widget.initial == null ? "Nuevo plato" : "Editar plato", style: t.headlineLarge),
            actions: [
              IconButton(tooltip: "Guardar", onPressed: _save, icon: const Icon(Icons.check_rounded)),
              const SizedBox(width: 8),
            ],
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Column(
                children: [
                  _Card(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("Nombre", style: t.titleMedium),
                        const SizedBox(height: 8),
                        TextField(
                          controller: nameCtrl,
                          decoration: const InputDecoration(labelText: "Ej. Pollo + arroz"),
                        ),
                        const SizedBox(height: 14),
                        Text("Momentos", style: t.titleMedium),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          children: MealSlot.values.map((s) {
                            final isOn = slots.contains(s);
                            return FilterChip(
                              selected: isOn,
                              label: Text(slotTitle(s)),
                              onSelected: (_) => _toggleSlot(s),
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _Card(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("Ingredientes", style: t.titleMedium),
                        const SizedBox(height: 6),
                        Text(
                          "Añade ingredientes y ajusta cantidades. El rol ayuda al optimizador (proteína/carbs/grasa).",
                          style: t.bodySmall,
                        ),
                        const SizedBox(height: 10),
                        _AddIngredientRow(
                          db: widget.db,
                          allIds: availableIds,
                          onAdd: _addIngredient,
                        ),
                        const SizedBox(height: 12),
                        if (selected.isEmpty)
                          const Text(
                            "No has añadido ingredientes.",
                            style: TextStyle(color: Color(0xFF6B7280), fontWeight: FontWeight.w700),
                          )
                        else
                          Column(
                            children: selected.map((id) {
                              final ing = widget.db.ingredients[id]!;
                              final amt = amounts[id] ?? 0;
                              final role = roles[id] ?? MacroRole.neutral;

                              return Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: _IngredientRow(
                                  ingredient: ing,
                                  amount: amt,
                                  role: role,
                                  onAmountChanged: (v) => setState(() => amounts[id] = v),
                                  onRoleChanged: (r) => setState(() => roles[id] = r),
                                  onRemove: () => _removeIngredient(id),
                                ),
                              );
                            }).toList(),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: FilledButton(onPressed: _save, child: const Text("Guardar")),
                  ),
                  const SizedBox(height: 28),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// =====================================================
/// UI bits (shared)
/// =====================================================

class _SectionHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget trailing;

  const _SectionHeader({required this.title, required this.subtitle, required this.trailing});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Row(
      children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: t.titleLarge),
            const SizedBox(height: 2),
            Text(subtitle, style: t.bodySmall),
          ]),
        ),
        trailing,
      ],
    );
  }
}

class _MealCard extends StatelessWidget {
  final DB db;
  final MealPlanItem meal;
  final List<RecipeIngredient> sortedItems;
  final VoidCallback onRegen;
  final void Function(String ingredientId, double delta) onAdjust;

  const _MealCard({
    required this.db,
    required this.meal,
    required this.sortedItems,
    required this.onRegen,
    required this.onAdjust,
  });

  @override
  Widget build(BuildContext context) {
    final m = macrosForRecipeAmounts(db, meal.recipe, meal.amounts);

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(slotTitle(meal.slot), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              const Spacer(),
              IconButton(onPressed: onRegen, tooltip: "Regenerar", icon: const Icon(Icons.refresh_rounded)),
            ],
          ),
          Text(meal.recipe.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          _SubSection(
            title: "Ingredientes",
            child: Column(
              children: sortedItems.map((ri) {
                final ing = db.ingredients[ri.ingredientId]!;
                final amt = meal.amounts[ri.ingredientId] ?? ri.baseAmount;

                final label = ing.unit == Unit.piece
                    ? "${amt.round()} ${unitLabel(ing.unit)}"
                    : "${(amt / 5).round() * 5} ${unitLabel(ing.unit)}";

                final showButtons = ri.isVariable;

                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(ing.name, style: const TextStyle(fontWeight: FontWeight.w800)),
                            const SizedBox(height: 2),
                            Text(_roleLabel(ri.role),
                                style: const TextStyle(color: Color(0xFF6B7280), fontSize: 12, fontWeight: FontWeight.w700)),
                          ],
                        ),
                      ),
                      if (showButtons) ...[
                        _MiniIconButton(icon: Icons.remove_rounded, onTap: () => onAdjust(ri.ingredientId, -ri.step)),
                        const SizedBox(width: 6),
                      ],
                      Text(label, style: const TextStyle(color: Color(0xFF6B7280), fontWeight: FontWeight.w800)),
                      if (showButtons) ...[
                        const SizedBox(width: 6),
                        _MiniIconButton(icon: Icons.add_rounded, onTap: () => onAdjust(ri.ingredientId, ri.step)),
                      ],
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 12),
          _SubSection(
            title: "Macros",
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _Pill(text: "${m.kcal.round()} kcal"),
                _Pill(text: "P ${m.p.round()}g"),
                _Pill(text: "C ${m.c.round()}g"),
                _Pill(text: "F ${m.f.round()}g"),
              ],
            ),
          ),
        ],
      ),
    );
  }

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

class _SubSection extends StatelessWidget {
  final String title;
  final Widget child;

  const _SubSection({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFEFEFF4),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: Color(0xFF6B7280))),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
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

class _Pill extends StatelessWidget {
  final String text;
  const _Pill({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFEFEFF4),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(text, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
    );
  }
}

class _MiniIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _MiniIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.black.withOpacity(0.08)),
        ),
        child: Icon(icon, size: 18),
      ),
    );
  }
}

/// --------- Widgets específicos del RecipeEditorScreen ----------

class _AddIngredientRow extends StatefulWidget {
  final DB db;
  final List<String> allIds;
  final void Function(String ingredientId) onAdd;

  const _AddIngredientRow({
    required this.db,
    required this.allIds,
    required this.onAdd,
  });

  @override
  State<_AddIngredientRow> createState() => _AddIngredientRowState();
}

class _AddIngredientRowState extends State<_AddIngredientRow> {
  String? selected;

  @override
  void didUpdateWidget(covariant _AddIngredientRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (selected != null && !widget.allIds.contains(selected)) {
      selected = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final ids = [...widget.allIds]
      ..sort((a, b) {
        final an = widget.db.ingredients[a]!.name.toLowerCase();
        final bn = widget.db.ingredients[b]!.name.toLowerCase();
        return an.compareTo(bn);
      });

    return Row(
      children: [
        Expanded(
          child: DropdownButtonFormField<String>(
            value: selected,
            items: ids
                .map((id) => DropdownMenuItem(
                      value: id,
                      child: Text(widget.db.ingredients[id]!.name),
                    ))
                .toList(),
            onChanged: (v) => setState(() => selected = v),
            decoration: const InputDecoration(labelText: "Añadir ingrediente"),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          height: 48,
          child: FilledButton(
            onPressed: selected == null ? null : () => widget.onAdd(selected!),
            child: const Text("Añadir"),
          ),
        ),
      ],
    );
  }
}

class _IngredientRow extends StatelessWidget {
  final Ingredient ingredient;
  final double amount;
  final MacroRole role;

  final void Function(double) onAmountChanged;
  final void Function(MacroRole) onRoleChanged;
  final VoidCallback onRemove;

  const _IngredientRow({
    required this.ingredient,
    required this.amount,
    required this.role,
    required this.onAmountChanged,
    required this.onRoleChanged,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final unit = unitLabel(ingredient.unit);
    final text = _fmt(amount, ingredient.unit);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFEFEFF4),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(ingredient.name, style: const TextStyle(fontWeight: FontWeight.w900))),
              IconButton(onPressed: onRemove, icon: const Icon(Icons.close_rounded), tooltip: "Quitar"),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: "Cantidad ($unit)"),
                  controller: TextEditingController(text: text)
                    ..selection = TextSelection.fromPosition(TextPosition(offset: text.length)),
                  onChanged: (s) {
                    final v = double.tryParse(s.trim().replaceAll(",", ".")) ?? amount;
                    onAmountChanged(v);
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: DropdownButtonFormField<MacroRole>(
                  value: role,
                  items: MacroRole.values.map((r) => DropdownMenuItem(value: r, child: Text(_roleLabel(r)))).toList(),
                  onChanged: (v) {
                    if (v != null) onRoleChanged(v);
                  },
                  decoration: const InputDecoration(labelText: "Rol"),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _fmt(double x, Unit u) {
    if (u == Unit.piece) return x.round().toString();
    final r = x.roundToDouble();
    if ((x - r).abs() < 1e-6) return r.toStringAsFixed(0);
    return x.toStringAsFixed(1);
  }

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
