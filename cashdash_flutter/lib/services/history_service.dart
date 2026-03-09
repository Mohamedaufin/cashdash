import 'storage_service.dart';

class TransactionItem {
  final String title;
  final String category;
  final int amount;
  final String rawEntry;

  TransactionItem({
    required this.title,
    required this.category,
    required this.amount,
    required this.rawEntry,
  });
}

class HistoryBreakdown {
  final List<String> categories;
  final List<double> values;
  final List<TransactionItem> transactions;

  HistoryBreakdown({
    required this.categories,
    required this.values,
    required this.transactions,
  });
}

class HistoryService {
  static HistoryBreakdown getBreakdown({
    required String mode,
    required int index,
    required int week,
    required int month,
    required int year,
  }) {
    final categories = List<String>.from(StorageService.categories);
    final values = List<double>.filled(categories.length, 0.0, growable: true);
    final transactions = <TransactionItem>[];
    double noChoiceValue = 0.0;

    final historyList = StorageService.historyList;

    for (var entry in historyList) {
      final parts = entry.split('|');
      if (parts.isEmpty) continue;

      bool match = false;
      String title = 'Expense';
      String category = 'no choice';
      double amount = 0.0;
      int hWeek = 0, hDay = 0, hMonth = 0, hYear = 0;

      if (parts.length == 7) {
        // Old Format: ATSTMT|category|amount|week|day|month|year
        category = parts[1];
        amount = double.tryParse(parts[2]) ?? 0.0;
        hWeek = int.tryParse(parts[3]) ?? 0;
        hDay = int.tryParse(parts[4]) ?? 0;
        hMonth = int.tryParse(parts[5]) ?? 0;
        hYear = int.tryParse(parts[6]) ?? 0;
      } else if (parts.length >= 9) {
        // New Format: EXP|timestamp|title|category|amount|week|day|month|year
        title = parts[2];
        category = parts[3];
        amount = double.tryParse(parts[4]) ?? 0.0;
        hWeek = int.tryParse(parts[5]) ?? 0;
        hDay = int.tryParse(parts[6]) ?? 0;
        hMonth = int.tryParse(parts[7]) ?? 0;
        hYear = int.tryParse(parts[8]) ?? 0;
      } else {
        continue;
      }

      switch (mode) {
        case 'DAILY':
          match = (hWeek == week && hDay == index && hMonth == month && hYear == year);
          break;
        case 'WEEKLY':
          match = (hWeek == index && hMonth == month && hYear == year);
          break;
        case 'MONTHLY':
          match = (hMonth == index && hYear == year);
          break;
      }

      if (match) {
        transactions.add(TransactionItem(
          title: title,
          category: '(${category.toUpperCase()})',
          amount: amount.toInt(),
          rawEntry: entry,
        ));

        if (category == 'no choice') {
          noChoiceValue += amount;
        } else {
          final idx = categories.indexOf(category);
          if (idx != -1) {
            values[idx] += amount;
          }
        }
      }
    }

    if (noChoiceValue > 0) {
      categories.add('no choice');
      values.add(noChoiceValue);
    }

    return HistoryBreakdown(
      categories: categories,
      values: values,
      transactions: transactions,
    );
  }
}
