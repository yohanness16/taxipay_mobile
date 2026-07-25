import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/expense.dart';
import '../services/expense_tracker.dart';
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

Color _categoryColor(ExpenseCategory c) {
  switch (c) {
    case ExpenseCategory.fuel:
      return Colors.deepOrange;
    case ExpenseCategory.maintenance:
      return Colors.blueGrey;
    case ExpenseCategory.insurance:
      return Colors.indigo;
    case ExpenseCategory.other:
      return Colors.grey;
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
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
          padding: EdgeInsets.only(
            left: 20, right: 20, top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
              ),
              const SizedBox(height: 16),
              Text('Add expense', style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: ExpenseCategory.values.map((c) {
                  final selected = c == category;
                  final color = _categoryColor(c);
                  return ChoiceChip(
                    label: Text(c.label),
                    avatar: Icon(_categoryIcon(c), size: 16, color: selected ? Colors.white : color),
                    selected: selected,
                    selectedColor: color,
                    labelStyle: TextStyle(color: selected ? Colors.white : color, fontWeight: FontWeight.w600),
                    backgroundColor: color.withOpacity(0.1),
                    onSelected: (_) => setModalState(() => category = c),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: amountCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Amount (ETB)', prefixIcon: Icon(Icons.payments_outlined)),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descCtrl,
                decoration: const InputDecoration(labelText: 'Description', prefixIcon: Icon(Icons.edit_note)),
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.calendar_today, size: 18),
                title: Text('Date: ${DateFormat.yMMMd().format(date)}'),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: ctx,
                    initialDate: date,
                    firstDate: DateTime(2024),
                    lastDate: DateTime.now().add(const Duration(days: 1)),
                  );
                  if (picked != null) setModalState(() => date = picked);
                },
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
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
        icon: const Icon(Icons.add),
        label: const Text('Add expense'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _expenses.isEmpty
              ? const EmptyState(
                  icon: Icons.receipt_long_outlined,
                  title: 'No expenses logged yet',
                  subtitle: 'Track fuel, maintenance, and other costs to see your real profit.',
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _expenses.length + 1,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      if (i == 0) {
                        return FadeSlideIn(
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.deepOrange.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Row(
                              children: [
                                const IconBadge(icon: Icons.receipt_long_rounded, color: Colors.deepOrange),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text('Total expenses', style: TextStyle(color: Colors.deepOrange, fontSize: 12)),
                                      Text('${total.toStringAsFixed(0)} ETB', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }
                      final e = _expenses[i - 1];
                      final color = _categoryColor(e.category);
                      return FadeSlideIn(
                        index: i,
                        delayStepMs: 25,
                        child: Card(
                          child: ListTile(
                            leading: IconBadge(icon: _categoryIcon(e.category), color: color),
                            title: Text('${e.amount.toStringAsFixed(0)} ETB · ${e.category.label}'),
                            subtitle: Text(e.description ?? DateFormat.yMMMd().format(e.expenseDate)),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () async {
                                await context.read<ExpenseTracker>().deleteExpense(e.id!);
                                await _load();
                              },
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
