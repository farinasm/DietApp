import "package:flutter/material.dart";
import "package:google_fonts/google_fonts.dart";

import "food_db.dart";
import "combined_db.dart";
import "user_recipes_repo.dart";

import "planner.dart";
import "day_plan.dart";
import "week_plan.dart";
import "user_recipes_screen.dart";
import "menu_editor.dart";

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final userRepo = SharedPrefsUserRecipesRepo();
  await userRepo.init();

  runApp(DietApp(userRepo: userRepo));
}

class DietApp extends StatelessWidget {
  final UserRecipesRepo userRepo;
  const DietApp({super.key, required this.userRepo});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: "Plan",
      theme: AppTheme.theme(),
      home: HomeShell(userRepo: userRepo),
    );
  }
}

/// =====================
/// THEME (Apple Health-ish)
/// =====================
class AppTheme {
  static const bg = Color(0xFFF2F2F7);
  static const text = Color(0xFF0B0B0F);
  static const sub = Color(0xFF6B7280);

  static const blue = Color(0xFF0A84FF);

  static ThemeData theme() {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: blue, brightness: Brightness.light),
      scaffoldBackgroundColor: bg,
      appBarTheme: const AppBarTheme(
        backgroundColor: bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        iconTheme: IconThemeData(color: text),
      ),
    );

    return base.copyWith(
      textTheme: GoogleFonts.interTextTheme(base.textTheme).copyWith(
        headlineLarge: GoogleFonts.inter(fontSize: 34, fontWeight: FontWeight.w800, color: text),
        titleLarge: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.w800, color: text),
        titleMedium: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w800, color: text),
        bodyMedium: GoogleFonts.inter(fontSize: 14, height: 1.35, color: text),
        bodySmall: GoogleFonts.inter(fontSize: 12, height: 1.25, color: sub),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFEFEFF4),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        labelStyle: const TextStyle(color: sub),
      ),
    );
  }
}

/// =====================
/// HOME SHELL (Día / Semana / Mis platos)
/// =====================

class HomeShell extends StatefulWidget {
  final UserRecipesRepo userRepo;
  const HomeShell({super.key, required this.userRepo});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int tab = 0;

  late final CombinedDB db = CombinedDB(
    InMemoryFoodDatabase(),
    widget.userRepo,
  );

  DayTargets targets = DayTargets(kcal: 2200, p: 150, c: 230, f: 70);

  late WeeklyPlan weekly;

  @override
  void initState() {
    super.initState();
    weekly = _generateWeekly();
  }

  WeeklyPlan _generateWeekly() {
    final baseSeed = DateTime.now().millisecondsSinceEpoch;
    return WeeklyPlan(
      kcalTarget: targets.kcal,
      pTarget: targets.p,
      cTarget: targets.c,
      fTarget: targets.f,
      days: List.generate(7, (i) => generateDay(db, targets, seed: baseSeed + i * 9973)),
    );
  }

  void _updateTargets(DayTargets t) {
    setState(() {
      targets = t;
      weekly = _generateWeekly();
    });
  }

  void _regenWeek() => setState(() => weekly = _generateWeekly());

  void _regenToday() {
    setState(() {
      final idx = _todayIndexMonday0();
      weekly.days[idx] = generateDay(db, targets);
    });
  }

  int _todayIndexMonday0() {
    // DateTime.weekday: Mon=1..Sun=7
    final w = DateTime.now().weekday;
    return (w - 1).clamp(0, 6);
  }

  // ---- helpers for week grid ----
  MealPlanItem _getCell(int dayIndex, MealSlot slot) => weekly.days[dayIndex].firstWhere((m) => m.slot == slot);

  void _setCell(int dayIndex, MealSlot slot, MealPlanItem newItem) {
    setState(() {
      final idx = weekly.days[dayIndex].indexWhere((m) => m.slot == slot);
      weekly.days[dayIndex][idx] = newItem;
    });
  }

  void _swapCells(int dayA, MealSlot slotA, int dayB, MealSlot slotB) {
    setState(() {
      final iA = weekly.days[dayA].indexWhere((m) => m.slot == slotA);
      final iB = weekly.days[dayB].indexWhere((m) => m.slot == slotB);
      final tmp = weekly.days[dayA][iA];
      weekly.days[dayA][iA] = weekly.days[dayB][iB];
      weekly.days[dayB][iB] = tmp;
    });
  }

  // abre editor “bonito” para una celda (reusa UI de día)
  void _openMenuEditor(BuildContext context, int dayIndex, MealSlot slot) async {
    final meal = _getCell(dayIndex, slot);

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MenuEditorScreen(
          db: db,
          dayTitle: WeekPlanStrings.dayLong(dayIndex),
          slot: slot,
          meal: meal,
          targets: targets,
          onChanged: (updated) => _setCell(dayIndex, slot, updated),
          onRegenerate: () {
            setState(() {
              final share = slotShare[slot] ?? 0.25;
              final slotTarget = targets.macros * share;

              final used = weekly.days[dayIndex].where((x) => x.slot != slot).map((x) => x.recipe.id).toSet();
              final candidates = db.recipesFor(slot).where((r) => !used.contains(r.id)).toList();
              final pool = candidates.isEmpty ? db.recipesFor(slot) : candidates;
              final recipe = pool[(DateTime.now().microsecondsSinceEpoch % pool.length)];

              final opt = optimizeMeal(db, slot, recipe, initialAmounts(recipe), slotTarget);
              final updated = MealPlanItem(slot: slot, recipe: recipe, amounts: opt);

              _setCell(dayIndex, slot, updated);
            });
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final todayIdx = _todayIndexMonday0();

    final screens = [
      PlanScreenEditable(
        db: db,
        title: DayPlanStrings.todayTitleLongEs(), // "domingo, 25 de enero de 2026" etc.
        getDay: () => weekly.days[todayIdx],
        setDay: (d) => setState(() => weekly.days[todayIdx] = d),
        targets: targets,
        onEditTargets: _updateTargets,
        onRegenerate: _regenToday,
      ),
      WeekGridScreen(
        db: db,
        weekly: weekly,
        getCell: (dayIndex, slot) => _getCell(dayIndex, slot),
        setCell: (dayIndex, slot, item) => _setCell(dayIndex, slot, item),
        onSwapCells: (dayA, slotA, dayB, slotB) => _swapCells(dayA, slotA, dayB, slotB),
        onOpenCellEditor: (ctx, dayIndex, slot) => _openMenuEditor(ctx, dayIndex, slot),
        onEditTargets: (kcal, p, c, f) => _updateTargets(DayTargets(kcal: kcal, p: p, c: c, f: f)),
        onRegenerateWeek: _regenWeek,
      ),
      UserRecipesScreen(db: db),
    ];

    return Scaffold(
      body: screens[tab],
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (i) => setState(() => tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.today_rounded), label: "Day"),
          NavigationDestination(icon: Icon(Icons.view_week_rounded), label: "Week"),
          NavigationDestination(icon: Icon(Icons.restaurant_menu_rounded), label: "Meals"),
        ],
      ),
    );
  }
}

/// Helpers de strings para reutilizar (evita meter lógica en widgets)
class DayPlanStrings {
  static String todayTitleLongEs([DateTime? now]) {
    final d = (now ?? DateTime.now());
    const dow = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"];
    const months = [
      "january",
      "february",
      "march",
      "april",
      "may",
      "june",
      "july",
      "august",
      "september",
      "october",
      "november",
      "december"
    ];

    final dayName = dow[d.weekday - 1];
    final day = d.day;
    final monthName = months[d.month - 1];
    final year = d.year;

    return "$dayName, $day de $monthName de $year";
  }
}

/// Para no duplicar arrays de nombres en week_plan.dart / main.dart
class WeekPlanStrings {
  static const _long = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"];
  static String dayLong(int i) => _long[i.clamp(0, 6)];
}
