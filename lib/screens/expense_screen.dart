import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/expense.dart';
import '../services/expense_tracker.dart';
import '../theme/app_theme.dart';
import '../widgets/modern_widgets.dart';

IconData _categoryIcon(ExpenseCategory c) {
  switch (c) {
    case ExpenseCategory.fuel:
      return Icons.local_gas_station_rounded;
    case ExpenseCategory.maintenance:
      return Icons.build_rounded;
    case ExpenseCategory.insurance:
      return Icons.shield_rounded;
    case ExpenseCategory.other:
      return Icons.receipt_long_rounded;
  }
}

/// Category accents come from the design system rather than raw Material
/// swatches -- deepOrange/blueGrey/indigo/grey sat outside the brand's hue
/// family and the greys in particular disappeared on the dark surface.
/// Kept in sync with the identical helper in reports_screen.dart.
Color _categoryColor(ExpenseCategory c) {
  switch (c) {
    case ExpenseCategory.fuel:
      return AppTheme.accentAmber;
    case ExpenseCategory.maintenance:
      return AppTheme.info;
    case ExpenseCategory.insurance:
      return AppTheme.violet;
    case ExpenseCategory.other:
      return AppTheme.teal;
  }
}

class ExpenseScreen extends StatefulWidget {
  const ExpenseScreen({super.key, this.showAppBar = true});

  final bool showAppBar;

  @override
  State<ExpenseScreen> createState() => _ExpenseScreenState();
}

class _ExpenseScreenState extends State<ExpenseScreen> {
  List<Expense> _expenses = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final expenses = await context.read<ExpenseTracker>().getExpenses();
    if (!mounted) return;
    setState(() {
      _expenses = expenses;
      _loading = false;
    });
  }

  Future<void> _addExpense() async {
    ExpenseCategory category = ExpenseCategory.fuel;
    final amountCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    DateTime date = DateTime.now();

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.rXl)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
          padding: EdgeInsets.only(
            left: AppTheme.s5,
            right: AppTheme.s5,
            top: AppTheme.s3,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + AppTheme.s5,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: ctx.faintText.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(AppTheme.s1),
                  ),
                ),
              ),
              const SizedBox(height: AppTheme.s5),
              Row(
                children: [
                  const IconBadge(icon: Icons.receipt_long_rounded, color: AppTheme.accentAmber),
                  const SizedBox(width: AppTheme.s3),
                  Text('Add expense', style: Theme.of(ctx).textTheme.titleLarge),
                ],
              ),
              const SizedBox(height: AppTheme.s5),
              Wrap(
                spacing: AppTheme.s2,
                runSpacing: AppTheme.s2,
                children: ExpenseCategory.values.map((c) {
                  final selected = c == category;
                  final color = _categoryColor(c);
                  final onSelected = ctx.isDark ? Colors.black : Colors.white;
                  return ChoiceChip(
                    label: Text(c.label),
                    avatar: Icon(_categoryIcon(c), size: 16, color: selected ? onSelected : color),
                    selected: selected,
                    showCheckmark: false,
                    selectedColor: color,
                    side: BorderSide(color: selected ? color : ctx.hairline),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.rSm)),
                    labelStyle: TextStyle(
                      color: selected ? onSelected : color,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                    backgroundColor: ctx.tintedSurface(color),
                    onSelected: (_) => setModalState(() => category = c),
                  );
                }).toList(),
              ),
              const SizedBox(height: AppTheme.s4),
              TextField(
                controller: amountCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Amount (ETB)',
                  prefixIcon: Icon(Icons.payments_outlined),
                ),
              ),
              const SizedBox(height: AppTheme.s3),
              TextField(
                controller: descCtrl,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  prefixIcon: Icon(Icons.edit_note),
                ),
              ),
              const SizedBox(height: AppTheme.s3),
              SoftCard(
                radius: AppTheme.rMd,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppTheme.s4,
                  vertical: AppTheme.s3,
                ),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: ctx,
                    initialDate: date,
                    firstDate: DateTime(2024),
                    lastDate: DateTime.now().add(const Duration(days: 1)),
                  );
                  if (picked != null) setModalState(() => date = picked);
                },
                child: Row(
                  children: [
                    Icon(Icons.calendar_today, size: 18, color: ctx.subtleText),
                    const SizedBox(width: AppTheme.s3),
                    Expanded(
                      child: Text(
                        'Date: ${DateFormat.yMMMd().format(date)}',
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded, size: 20, color: ctx.faintText),
                  ],
                ),
              ),
              const SizedBox(height: AppTheme.s5),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: AppTheme.s3),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Save expense'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (saved != true) return;
    final amount = double.tryParse(amountCtrl.text);
    if (amount == null || amount <= 0) return;
    if (!mounted) return;

    await context.read<ExpenseTracker>().addExpense(
          Expense(
            category: category,
            amount: amount,
            description: descCtrl.text.trim().isEmpty ? null : descCtrl.text.trim(),
            expenseDate: date,
          ),
        );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final total = _expenses.fold<double>(0, (s, e) => s + e.amount);

    return Scaffold(
      appBar: widget.showAppBar ? AppBar(title: const Text('Expenses')) : null,
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'expense_fab',
        onPressed: _addExpense,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.rMd)),
        icon: const Icon(Icons.add),
        label: const Text('Add expense'),
      ),
      body: _loading
          ? const _ExpenseListSkeleton()
          : _expenses.isEmpty
              ? const EmptyState(
                  icon: Icons.receipt_long_outlined,
                  title: 'No expenses logged yet',
                  subtitle: 'Track fuel, maintenance, and other costs to see your real profit.',
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(
                        AppTheme.s4, AppTheme.s2, AppTheme.s4, AppTheme.s8 * 3),
                    itemCount: _expenses.length + 1,
                    separatorBuilder: (_, __) => const SizedBox(height: AppTheme.s2),
                    itemBuilder: (context, i) {
                      if (i == 0) {
                        return FadeSlideIn(
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: AppTheme.s2),
                            child: SoftCard(
                              accent: AppTheme.accentAmber,
                              radius: AppTheme.rXl,
                              child: Row(
                                children: [
                                  const IconBadge(
                                      icon: Icons.receipt_long_rounded, color: AppTheme.accentAmber),
                                  const SizedBox(width: AppTheme.s3),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Total expenses',
                                          style: TextStyle(
                                            color: context.subtleText,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        FittedBox(
                                          fit: BoxFit.scaleDown,
                                          alignment: Alignment.centerLeft,
                                          child: CountUpText(
                                            value: total,
                                            suffix: ' ETB',
                                            style: const TextStyle(
                                              fontSize: 20,
                                              fontWeight: FontWeight.w800,
                                              letterSpacing: -0.4,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }
                      final e = _expenses[i - 1];
                      final color = _categoryColor(e.category);
                      return FadeSlideIn(
                        index: i,
                        delayStepMs: 25,
                        child: _ExpenseRow(
                          expense: e,
                          color: color,
                          onDelete: () async {
                            await context.read<ExpenseTracker>().deleteExpense(e.id!);
                            await _load();
                          },
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}

/// One logged expense. The amount leads the row because that's what a driver
/// scans for; the category and date sit underneath as supporting metadata.
class _ExpenseRow extends StatelessWidget {
  const _ExpenseRow({required this.expense, required this.color, required this.onDelete});

  final Expense expense;
  final Color color;
  final Future<void> Function() onDelete;

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      padding: const EdgeInsets.fromLTRB(AppTheme.s3, AppTheme.s3, AppTheme.s2, AppTheme.s3),
      child: Row(
        children: [
          IconBadge(icon: _categoryIcon(expense.category), color: color, size: 42),
          const SizedBox(width: AppTheme.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${expense.amount.toStringAsFixed(0)} ETB · ${expense.category.label}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14.5,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  expense.description ?? DateFormat.yMMMd().format(expense.expenseDate),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: context.subtleText, fontSize: 12.5, height: 1.3),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppTheme.s1),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            color: context.faintText,
            iconSize: 20,
            visualDensity: VisualDensity.compact,
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}

/// Placeholder rows shown while expenses load -- keeps the total card and
/// list rhythm on screen instead of collapsing to a lone centred spinner.
class _ExpenseListSkeleton extends StatelessWidget {
  const _ExpenseListSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(AppTheme.s4, AppTheme.s2, AppTheme.s4, AppTheme.s8 * 3),
      physics: const NeverScrollableScrollPhysics(),
      children: [
        const SkeletonBox(height: 76, radius: AppTheme.rXl),
        const SizedBox(height: AppTheme.s4),
        for (int i = 0; i < 6; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: AppTheme.s2),
            child: FadeSlideIn(
              index: i,
              child: SoftCard(
                padding: const EdgeInsets.all(AppTheme.s3),
                child: Row(
                  children: const [
                    SkeletonBox(height: 42, width: 42, radius: 21),
                    SizedBox(width: AppTheme.s3),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SkeletonBox(height: 12, width: 160, radius: AppTheme.s1),
                          SizedBox(height: AppTheme.s2),
                          SkeletonBox(height: 10, width: 100, radius: AppTheme.s1),
                        ],
                      ),
                    ),
                    SizedBox(width: AppTheme.s2),
                    SkeletonBox(height: 20, width: 20, radius: AppTheme.s1),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
