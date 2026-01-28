import "dart:math";
import "package:flutter/material.dart";

import "food_db.dart";
import "planner.dart";

/// =====================
/// WEEKLY PLAN MODEL
/// =====================

class WeeklyPlan {
  final double kcalTarget;
  final double pTarget;
  final double cTarget;
  final double fTarget;

  final List<List<MealPlanItem>> days; // 7 días, cada uno List<MealPlanItem>

  WeeklyPlan({
    required this.kcalTarget,
    required this.pTarget,
    required this.cTarget,
    required this.fTarget,
    required this.days,
  });

  Macros get targets => Macros(kcal: kcalTarget, p: pTarget, c: cTarget, f: fTarget);
}

/// =====================
/// WEEK GRID SCREEN
/// =====================

class WeekGridScreen extends StatelessWidget {
  final DB db;
  final WeeklyPlan weekly;

  final MealPlanItem Function(int dayIndex, MealSlot slot) getCell;
  final void Function(int dayIndex, MealSlot slot, MealPlanItem newItem) setCell;

  final void Function(int dayA, MealSlot slotA, int dayB, MealSlot slotB) onSwapCells;
  final void Function(BuildContext ctx, int dayIndex, MealSlot slot) onOpenCellEditor;

  final void Function(double kcal, double p, double c, double f) onEditTargets;
  final VoidCallback onRegenerateWeek;

  const WeekGridScreen({
    super.key,
    required this.db,
    required this.weekly,
    required this.getCell,
    required this.setCell,
    required this.onSwapCells,
    required this.onOpenCellEditor,
    required this.onEditTargets,
    required this.onRegenerateWeek,
  });

  static const dayNamesShort = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];
  static const dayNamesLong = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"];

  int _todayIndex0Mon() => DateTime.now().weekday - 1; // Mon=0..Sun=6

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    // altura dinámica “de verdad” para la tabla (4 filas)
    final screenH = MediaQuery.sizeOf(context).height;
    final approxGridH = screenH * 0.58;
    final rows = MealSlot.values.length; // 4
    final headerAndGaps = 56.0;
    final cellHeight = max(74.0, (approxGridH - headerAndGaps) / rows);

    final today = _todayIndex0Mon().clamp(0, 6);

    return CustomScrollView(
      slivers: [
        SliverAppBar.large(
          title: Text("Week", style: t.headlineLarge),
          actions: [
            IconButton(
              tooltip: "Targets",
              icon: const Icon(Icons.tune_rounded),
              onPressed: () async {
                final res = await showModalBottomSheet<_TargetsResult>(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (_) => _TargetsSheet(
                    initialKcal: weekly.kcalTarget,
                    initialP: weekly.pTarget,
                    initialC: weekly.cTarget,
                    initialF: weekly.fTarget,
                  ),
                );
                if (res != null) onEditTargets(res.kcal, res.p, res.c, res.f);
              },
            ),
            IconButton(
              tooltip: "Regenerate week",
              icon: const Icon(Icons.refresh_rounded),
              onPressed: onRegenerateWeek,
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
                  Text("Week (drag to swap)", style: t.titleMedium),
                  const SizedBox(height: 6),
                  Text("Tap a cell to edit THAT meal (e.g. Lunch on Tuesday).", style: t.bodySmall),
                ],
              ),
            ),
          ),
        ),

        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: _WeekGrid(
              db: db,
              weekly: weekly,
              todayIndex: today,
              cellHeight: cellHeight,
              getCell: getCell,
              onSwapCells: onSwapCells,
              onOpenCellEditor: onOpenCellEditor,
            ),
          ),
        ),

        // anillos al final de cada día
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
            child: _WeekRingsRow(
              db: db,
              weekly: weekly,
              todayIndex: today,
            ),
          ),
        ),

        const SliverToBoxAdapter(child: SizedBox(height: 28)),
      ],
    );
  }
}

/// =====================
/// GRID
/// =====================

class _WeekGrid extends StatelessWidget {
  final DB db;
  final WeeklyPlan weekly;
  final int todayIndex;

  final double cellHeight;

  final MealPlanItem Function(int dayIndex, MealSlot slot) getCell;
  final void Function(int dayA, MealSlot slotA, int dayB, MealSlot slotB) onSwapCells;
  final void Function(BuildContext ctx, int dayIndex, MealSlot slot) onOpenCellEditor;

  const _WeekGrid({
    required this.db,
    required this.weekly,
    required this.todayIndex,
    required this.cellHeight,
    required this.getCell,
    required this.onSwapCells,
    required this.onOpenCellEditor,
  });

  static const dayNames = WeekGridScreen.dayNamesShort;

  @override
  Widget build(BuildContext context) {
    final slots = MealSlot.values;

    // No scroll interno -> mejora drag
    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      child: Column(
        children: [
          Row(
            children: [
              const SizedBox(width: 86),
              for (int d = 0; d < 7; d++)
                Expanded(
                  child: Center(
                    child: Text(
                      dayNames[d],
                      style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF6B7280)),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),

          for (final slot in slots) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 86,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(
                      _slotShort(slot),
                      style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF6B7280)),
                    ),
                  ),
                ),
                for (int day = 0; day < 7; day++)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                      child: SizedBox(
                        height: cellHeight,
                        child: _Cell(
                          dayIndex: day,
                          slot: slot,
                          item: getCell(day, slot),
                          highlightToday: day == todayIndex,
                          onOpen: () => onOpenCellEditor(context, day, slot),
                          onSwap: (fromDay, fromSlot) => onSwapCells(fromDay, fromSlot, day, slot),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  static String _slotShort(MealSlot s) {
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
}

class _DragPayload {
  final int dayIndex;
  final MealSlot slot;
  const _DragPayload(this.dayIndex, this.slot);
}

class _Cell extends StatelessWidget {
  final int dayIndex;
  final MealSlot slot;
  final MealPlanItem item;
  final bool highlightToday;

  final VoidCallback onOpen;
  final void Function(int fromDay, MealSlot fromSlot) onSwap;

  const _Cell({
    required this.dayIndex,
    required this.slot,
    required this.item,
    required this.highlightToday,
    required this.onOpen,
    required this.onSwap,
  });

  @override
  Widget build(BuildContext context) {
    final title = item.recipe.name;

    return DragTarget<_DragPayload>(
      onWillAccept: (data) => data != null && !(data.dayIndex == dayIndex && data.slot == slot),
      onAccept: (data) => onSwap(data.dayIndex, data.slot),
      builder: (context, candidate, _) {
        final isOver = candidate.isNotEmpty;

        return Draggable<_DragPayload>(
          data: _DragPayload(dayIndex, slot),
          // IMPORTANT: en móvil, Draggable empieza al tocar: eso “bloquea” taps.
          // Solución minimal: dejamos tap en child, y drag con mouse/finger igual.
          feedback: Material(
            color: Colors.transparent,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 170),
              child: _CellCard(title: title, isGhost: false, highlight: true, highlightToday: highlightToday),
            ),
          ),
          childWhenDragging: _CellCard(title: title, isGhost: true, highlight: false, highlightToday: highlightToday),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onOpen,
            child: _CellCard(
              title: title,
              isGhost: false,
              highlight: isOver,
              highlightToday: highlightToday,
            ),
          ),
        );
      },
    );
  }
}

class _CellCard extends StatelessWidget {
  final String title;
  final bool isGhost;
  final bool highlight;
  final bool highlightToday;

  const _CellCard({
    required this.title,
    required this.isGhost,
    required this.highlight,
    required this.highlightToday,
  });

  static const _todayBg = Color(0xFFFFF2CC); // “amarillo roto” suave

  @override
  Widget build(BuildContext context) {
    final bg = isGhost
        ? const Color(0xFFEFEFF4)
        : (highlightToday ? _todayBg.withOpacity(0.55) : Colors.white);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 110),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: highlight ? Colors.black.withOpacity(0.20) : Colors.black.withOpacity(0.06),
          width: highlight ? 1.5 : 1.0,
        ),
      ),
      child: Align(
        alignment: Alignment.topLeft,
        child: Text(
          title,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 12.8,
            color: isGhost ? const Color(0xFF9CA3AF) : const Color(0xFF0B0B0F),
            height: 1.12,
          ),
        ),
      ),
    );
  }
}

/// =====================
/// Rings row (one per day)
/// =====================

class _WeekRingsRow extends StatelessWidget {
  final DB db;
  final WeeklyPlan weekly;
  final int todayIndex;

  const _WeekRingsRow({
    required this.db,
    required this.weekly,
    required this.todayIndex,
  });

  @override
  Widget build(BuildContext context) {
    // cards iguales por día, en una fila
    return Row(
      children: [
        for (int d = 0; d < 7; d++) ...[
          Expanded(
            child: _DayRingsCard(
              label: WeekGridScreen.dayNamesShort[d],
              isToday: d == todayIndex,
              total: totalMacros(db, weekly.days[d]),
              targets: weekly.targets,
            ),
          ),
          if (d != 6) const SizedBox(width: 8),
        ],
      ],
    );
  }
}

class _DayRingsCard extends StatelessWidget {
  final String label;
  final bool isToday;
  final Macros total;
  final Macros targets;

  const _DayRingsCard({
    required this.label,
    required this.isToday,
    required this.total,
    required this.targets,
  });

  static const _todayBg = Color(0xFFFFF2CC);

  double _pct(double v, double t) => (v / max(1.0, t)).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    final kcalPct = _pct(total.kcal, targets.kcal);
    final pPct = _pct(total.p, targets.p);
    final cPct = _pct(total.c, targets.c);
    final fPct = _pct(total.f, targets.f);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        color: isToday ? _todayBg.withOpacity(0.55) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black.withOpacity(0.06)),
      ),
      child: Column(
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF6B7280), fontSize: 12)),
          const SizedBox(height: 8),
          _MacroRings(
            kcalPct: kcalPct,
            pPct: pPct,
            cPct: cPct,
            fPct: fPct,
            kcalText: total.kcal.round().toString(),
          ),
          const SizedBox(height: 6),
          Text(
            "${total.p.round()}P · ${total.c.round()}C · ${total.f.round()}F",
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: Color(0xFF6B7280)),
          ),
        ],
      ),
    );
  }
}

class _MacroRings extends StatelessWidget {
  final double kcalPct, pPct, cPct, fPct;
  final String kcalText;

  const _MacroRings({
    required this.kcalPct,
    required this.pPct,
    required this.cPct,
    required this.fPct,
    required this.kcalText,
  });

  @override
  Widget build(BuildContext context) {
    // 4 anillos concéntricos: kcal + P + C + F
    // (pequeños, estilo Apple-ish)
    return SizedBox(
      width: 52,
      height: 52,
      child: Stack(
        alignment: Alignment.center,
        children: [
          _Ring(value: kcalPct, size: 52, stroke: 6, color: const Color(0xFF0A84FF)), // kcal
          _Ring(value: pPct, size: 40, stroke: 6, color: const Color(0xFF34C759)),    // P
          _Ring(value: cPct, size: 28, stroke: 6, color: const Color(0xFFFF9F0A)),    // C
          _Ring(value: fPct, size: 16, stroke: 6, color: const Color(0xFFAF52DE)),    // F
          Text(
            kcalText,
            style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w900, color: Color(0xFF0B0B0F)),
          ),
        ],
      ),
    );
  }
}

class _Ring extends StatelessWidget {
  final double value;
  final double size;
  final double stroke;
  final Color color;

  const _Ring({
    required this.value,
    required this.size,
    required this.stroke,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CircularProgressIndicator(
        value: value.clamp(0.0, 1.0),
        strokeWidth: stroke,
        backgroundColor: Colors.black.withOpacity(0.06),
        valueColor: AlwaysStoppedAnimation(color),
      ),
    );
  }
}

/// =====================
/// Targets sheet (week)
/// =====================

class _TargetsResult {
  final double kcal, p, c, f;
  _TargetsResult(this.kcal, this.p, this.c, this.f);
}

class _TargetsSheet extends StatefulWidget {
  final double initialKcal, initialP, initialC, initialF;
  const _TargetsSheet({
    required this.initialKcal,
    required this.initialP,
    required this.initialC,
    required this.initialF,
  });

  @override
  State<_TargetsSheet> createState() => _TargetsSheetState();
}

class _TargetsSheetState extends State<_TargetsSheet> {
  late final TextEditingController kcal = TextEditingController(text: widget.initialKcal.round().toString());
  late final TextEditingController p = TextEditingController(text: widget.initialP.round().toString());
  late final TextEditingController c = TextEditingController(text: widget.initialC.round().toString());
  late final TextEditingController f = TextEditingController(text: widget.initialF.round().toString());

  double _d(TextEditingController x) => double.tryParse(x.text.trim().replaceAll(",", ".")) ?? 0;

  @override
  void dispose() {
    kcal.dispose();
    p.dispose();
    c.dispose();
    f.dispose();
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
          const Align(
            alignment: Alignment.centerLeft,
            child: Text("Edit Targets", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
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
                  _TargetsResult(
                    _d(kcal).clamp(1, 99999).toDouble(),
                    _d(p).clamp(1, 99999).toDouble(),
                    _d(c).clamp(1, 99999).toDouble(),
                    _d(f).clamp(1, 99999).toDouble(),
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
