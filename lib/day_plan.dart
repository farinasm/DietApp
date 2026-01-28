import "dart:math";
import "package:flutter/material.dart";

import "food_db.dart";
import "planner.dart";

class PlanScreenEditable extends StatefulWidget {
  final DB db;

  /// Título grande (ej. "domingo, 25 de enero de 2026")
  final String title;

  final List<MealPlanItem> Function() getDay;
  final void Function(List<MealPlanItem>) setDay;

  final DayTargets targets;
  final void Function(DayTargets) onEditTargets;
  final VoidCallback onRegenerate;

  const PlanScreenEditable({
    super.key,
    required this.db,
    required this.title,
    required this.getDay,
    required this.setDay,
    required this.targets,
    required this.onEditTargets,
    required this.onRegenerate,
  });

  @override
  State<PlanScreenEditable> createState() => _PlanScreenEditableState();
}

class _PlanScreenEditableState extends State<PlanScreenEditable> {
  List<MealPlanItem> get day => widget.getDay();
  Macros get totals => totalMacros(widget.db, day);

  Future<void> _editTargets() async {
    final res = await showModalBottomSheet<DayTargets>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _TargetsSheet(initial: widget.targets),
    );
    if (res != null) widget.onEditTargets(res);
  }

  void _regenAllThisDay() {
    widget.onRegenerate();
    setState(() {});
  }

  void _regenSlot(MealSlot slot) {
    // Si no hay recetas para ese slot, no hacemos nada.
    final pool0 = widget.db.recipesFor(slot);
    if (pool0.isEmpty) return;

    final rng = Random();
    final current = List<MealPlanItem>.from(day);

    // evita repetir receta ya usada ese día (si se puede)
    final used = current.where((x) => x.slot != slot).map((x) => x.recipe.id).toSet();
    final candidates = pool0.where((r) => !used.contains(r.id)).toList();
    final pool = candidates.isEmpty ? pool0 : candidates;

    final recipe = pool[rng.nextInt(pool.length)];

    final share = slotShare[slot] ?? 0.25;
    final slotTarget = widget.targets.macros * share;

    // ✅ CAMBIO: firma nueva optimizeMeal(db, slot, recipe, start, target)
    final opt = optimizeMeal(widget.db, slot, recipe, initialAmounts(recipe), slotTarget);

    final idx = current.indexWhere((x) => x.slot == slot);
    current[idx] = MealPlanItem(slot: slot, recipe: recipe, amounts: opt);

    final reopt = optimizeDay(widget.db, current, widget.targets, iterations: 800);
    widget.setDay(reopt);
    setState(() {});
  }

  /// NO reopt global automáticamente al tocar +/− para que no se “deshaga”
  void _adjustIngredient(MealSlot slot, String ingredientId, double delta) {
    final current = List<MealPlanItem>.from(day);
    final idx = current.indexWhere((x) => x.slot == slot);
    final meal = current[idx];
    final ri = meal.recipe.items.firstWhere((x) => x.ingredientId == ingredientId);

    final cur = meal.amounts[ingredientId] ?? ri.baseAmount;
    final next = (cur + delta).clamp(ri.minAmount, ri.maxAmount).toDouble();

    final newAmounts = Map<String, double>.from(meal.amounts);
    newAmounts[ingredientId] = next;

    current[idx] = meal.copyWith(amounts: newAmounts);
    widget.setDay(current);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    return CustomScrollView(
      slivers: [
        SliverAppBar.large(
          title: Text(widget.title, style: t.headlineLarge),
          actions: [
            IconButton(onPressed: _editTargets, tooltip: "Targets", icon: const Icon(Icons.tune_rounded)),
            IconButton(onPressed: _regenAllThisDay, tooltip: "Regenerate day", icon: const Icon(Icons.refresh_rounded)),
            const SizedBox(width: 8),
          ],
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Column(
              children: [
                _SummaryCard(targets: widget.targets.macros, total: totals),
                const SizedBox(height: 12),
                _SectionHeader(
                  title: "Meals",
                  subtitle: "Dishes + amounts adjusted to your macros",
                  trailing: TextButton(onPressed: _regenAllThisDay, child: const Text("Regenerate")),
                ),
                const SizedBox(height: 6),
              ],
            ),
          ),
        ),
        SliverList.separated(
          itemCount: day.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, i) {
            final item = day[i];
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _MealCard(
                db: widget.db,
                meal: item,
                onRegen: () => _regenSlot(item.slot),
                onAdjust: (ingredientId, delta) => _adjustIngredient(item.slot, ingredientId, delta),
              ),
            );
          },
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }
}

/// =====================
/// Widgets (día)
/// =====================

class _SummaryCard extends StatelessWidget {
  final Macros targets;
  final Macros total;

  const _SummaryCard({required this.targets, required this.total});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Today's Targets", style: t.titleMedium),
          const SizedBox(height: 12),
          _Bar(label: "kcal", value: total.kcal, target: targets.kcal, color: const Color(0xFF0A84FF)),
          const SizedBox(height: 10),
          _Bar(label: "Protein", value: total.p, target: targets.p, color: const Color(0xFF34C759)),
          const SizedBox(height: 10),
          _Bar(label: "Carbs", value: total.c, target: targets.c, color: const Color(0xFFFF9F0A)),
          const SizedBox(height: 10),
          _Bar(label: "Fat", value: total.f, target: targets.f, color: const Color(0xFFAF52DE)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _StatPill(title: "kcal", value: "${total.kcal.round()} / ${targets.kcal.round()}")),
              const SizedBox(width: 8),
              Expanded(child: _StatPill(title: "P", value: "${total.p.round()} / ${targets.p.round()} g")),
              const SizedBox(width: 8),
              Expanded(child: _StatPill(title: "C", value: "${total.c.round()} / ${targets.c.round()} g")),
              const SizedBox(width: 8),
              Expanded(child: _StatPill(title: "F", value: "${total.f.round()} / ${targets.f.round()} g")),
            ],
          ),
        ],
      ),
    );
  }
}

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
  final VoidCallback onRegen;
  final void Function(String ingredientId, double delta) onAdjust;

  const _MealCard({required this.db, required this.meal, required this.onRegen, required this.onAdjust});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final m = macrosForRecipeAmounts(db, meal.recipe, meal.amounts);

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(slotTitle(meal.slot), style: t.titleMedium),
              const Spacer(),
              IconButton(onPressed: onRegen, tooltip: "Regenerate", icon: const Icon(Icons.refresh_rounded)),
            ],
          ),
          Text(meal.recipe.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),

          _SubSection(
            title: "Ingredients",
            child: Column(
              children: meal.recipe.items.map((ri) {
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
                            Text(_roleLabel(ri.role), style: const TextStyle(color: Color(0xFF6B7280), fontSize: 12, fontWeight: FontWeight.w700)),
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
        return "protein";
      case MacroRole.carbs:
        return "carbs";
      case MacroRole.fat:
        return "fat";
      case MacroRole.veg:
        return "vegetables";
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

class _TargetsSheet extends StatefulWidget {
  final DayTargets initial;
  const _TargetsSheet({required this.initial});

  @override
  State<_TargetsSheet> createState() => _TargetsSheetState();
}

class _TargetsSheetState extends State<_TargetsSheet> {
  late final TextEditingController kcal;
  late final TextEditingController p;
  late final TextEditingController c;
  late final TextEditingController f;

  @override
  void initState() {
    super.initState();
    kcal = TextEditingController(text: widget.initial.kcal.round().toString());
    p = TextEditingController(text: widget.initial.p.round().toString());
    c = TextEditingController(text: widget.initial.c.round().toString());
    f = TextEditingController(text: widget.initial.f.round().toString());
  }

  @override
  void dispose() {
    kcal.dispose();
    p.dispose();
    c.dispose();
    f.dispose();
    super.dispose();
  }

  double _d(TextEditingController x) => double.tryParse(x.text.trim().replaceAll(",", ".")) ?? 0;

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
          const Align(
            alignment: Alignment.centerLeft,
            child: Text("Edit Targets", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: TextField(controller: kcal, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "kcal"))),
              const SizedBox(width: 10),
              Expanded(child: TextField(controller: p, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "Protein (g)"))),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: TextField(controller: c, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "Carbs (g)"))),
              const SizedBox(width: 10),
              Expanded(child: TextField(controller: f, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "Fat (g)"))),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton(
              onPressed: () {
                Navigator.pop(
                  context,
                  DayTargets(
                    kcal: max(1.0, _d(kcal)),
                    p: max(1.0, _d(p)),
                    c: max(1.0, _d(c)),
                    f: max(1.0, _d(f)),
                  ),
                );
              },
              child: const Text("Save"),
            ),
          ),
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

class _Bar extends StatelessWidget {
  final String label;
  final double value;
  final double target;
  final Color color;

  const _Bar({required this.label, required this.value, required this.target, required this.color});

  @override
  Widget build(BuildContext context) {
    final pct = (value / max(1.0, target)).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
            const Spacer(),
            Text("${value.round()} / ${target.round()}", style: const TextStyle(color: Color(0xFF6B7280), fontWeight: FontWeight.w700)),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: Container(
            height: 10,
            color: Colors.black.withOpacity(0.06),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: pct,
              child: Container(color: color),
            ),
          ),
        ),
      ],
    );
  }
}

class _StatPill extends StatelessWidget {
  final String title;
  final String value;
  const _StatPill({required this.title, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFEFEFF4),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: Color(0xFF6B7280))),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
        ],
      ),
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

/// Usa GestureDetector (más “a prueba de balas” que InkWell si no hay Material encima)
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
