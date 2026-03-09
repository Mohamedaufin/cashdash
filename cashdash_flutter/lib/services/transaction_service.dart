import '../services/storage_service.dart';
import '../services/firebase_service.dart';
import '../services/history_service.dart';

class TransactionService {
  static Future<void> saveExpense({
    required String category,
    required int amount,
    required String merchant,
    DateTime? date,
  }) async {
    final now = date ?? DateTime.now();
    final String timestamp = now.millisecondsSinceEpoch.toString();

    // Standardized Monday=0 (matches native Android refinement)
    final int hDay = now.weekday - 1; // 0=Mon, 6=Sun
    final int hMonth = now.month - 1;
    final int hYear = now.year;
    
    // Proper week calculation logic (mimics native Android)
    final firstDayOfMonth = DateTime(now.year, now.month, 1);
    final int hWeek = ((now.day + firstDayOfMonth.weekday - 2) / 7).floor();
    final int weekSlot = hWeek + 1;

    // 1. Deduct from wallet
    StorageService.walletBalance -= amount;

    // 2. Update category spent
    final double oldSpent = StorageService.getCategorySpent(category);
    StorageService.setCategorySpent(category, oldSpent + amount);

    // 3. Update time-based keys
    final dailyKey = 'DAY_${hWeek}_${hDay}_${hMonth}_$hYear';
    StorageService.setDouble(dailyKey, StorageService.getDouble(dailyKey) + amount);

    final weeklyKey = 'WEEK_${hWeek}_${hMonth}_$hYear';
    StorageService.setDouble(weeklyKey, StorageService.getDouble(weeklyKey) + amount);

    final monthlyKey = 'MONTH_${hMonth}_$hYear';
    StorageService.setDouble(monthlyKey, StorageService.getDouble(monthlyKey) + amount);

    final categoryWeekKey = '${category}_W$weekSlot';
    StorageService.setInt(categoryWeekKey, StorageService.getInt(categoryWeekKey) + amount);
    
    final String entry = 'EXP|$timestamp|$merchant|$category|$amount|$hWeek|$hDay|$hMonth|$hYear';
    final history = StorageService.historyList;
    history.add(entry);
    StorageService.historyList = history;

    await FirebaseService.pushAllDataToCloud();
  }

  static Future<void> updateTransactionTitle(TransactionItem tx, String newTitle) async {
    final history = StorageService.historyList;
    final index = history.indexOf(tx.rawEntry);
    if (index != -1) {
      final parts = tx.rawEntry.split('|');
      if (parts.length >= 9) {
        parts[2] = newTitle;
        history[index] = parts.join('|');
        StorageService.historyList = history;
        await FirebaseService.pushAllDataToCloud();
      }
    }
  }

  static Future<void> updateTransactionAmount(TransactionItem tx, int newAmount) async {
    final history = StorageService.historyList;
    final index = history.indexOf(tx.rawEntry);
    if (index != -1) {
      final parts = tx.rawEntry.split('|');
      if (parts.length >= 9) {
        final oldAmount = int.tryParse(parts[4]) ?? 0;
        final difference = newAmount - oldAmount;
        
        // Update Wallet
        StorageService.walletBalance -= difference;
        
        // Update Aggregates
        final cat = parts[3];
        final hWeek = int.tryParse(parts[5]) ?? 0;
        final hDay = int.tryParse(parts[6]) ?? 0;
        final hMonth = int.tryParse(parts[7]) ?? 0;
        final hYear = int.tryParse(parts[8]) ?? 0;
        
        if (cat != 'no choice') {
          StorageService.setCategorySpent(cat, StorageService.getCategorySpent(cat) + difference);
          final weekKey = '${cat}_W${hWeek + 1}';
          StorageService.setInt(weekKey, StorageService.getInt(weekKey) + difference);
        }
        
        final dKey = 'DAY_${hWeek}_${hDay}_${hMonth}_$hYear';
        final wKey = 'WEEK_${hWeek}_${hMonth}_$hYear';
        final mKey = 'MONTH_${hMonth}_$hYear';
        
        StorageService.setDouble(dKey, StorageService.getDouble(dKey) + difference);
        StorageService.setDouble(wKey, StorageService.getDouble(wKey) + difference);
        StorageService.setDouble(mKey, StorageService.getDouble(mKey) + difference);
        
        // Update History String
        parts[4] = newAmount.toString();
        history[index] = parts.join('|');
        StorageService.historyList = history;
        
        await FirebaseService.pushAllDataToCloud();
      }
    }
  }

  static Future<void> reallocateTransaction({
    required TransactionItem transaction,
    required String newCategory,
  }) async {
    final parts = transaction.rawEntry.split('|');
    if (parts.length < 9) return; // Only new format supported for now

    final oldCategory = parts[3];
    final amount = int.tryParse(parts[4]) ?? 0;
    final hWeek = int.tryParse(parts[5]) ?? 0;
    final weekSlot = hWeek + 1;

    if (oldCategory == newCategory) return;

    // 1. Reconcile category totals
    if (oldCategory != 'no choice') {
      final double oldSpent = StorageService.getCategorySpent(oldCategory);
      StorageService.setCategorySpent(oldCategory, (oldSpent - amount).clamp(0.0, double.infinity));
      
      final String oldCatWeekKey = '${oldCategory}_W$weekSlot';
      final int oldCatWeekVal = StorageService.getInt(oldCatWeekKey);
      StorageService.setInt(oldCatWeekKey, (oldCatWeekVal - amount).clamp(0, 9999999).toInt());
    }

    if (newCategory != 'no choice') {
      final double newSpent = StorageService.getCategorySpent(newCategory);
      StorageService.setCategorySpent(newCategory, newSpent + amount);
      
      final String newCatWeekKey = '${newCategory}_W$weekSlot';
      final int newCatWeekVal = StorageService.getInt(newCatWeekKey);
      StorageService.setInt(newCatWeekKey, newCatWeekVal + amount);
    }

    // 2. Update HISTORY_LIST
    final history = StorageService.historyList;
    final index = history.indexOf(transaction.rawEntry);
    if (index != -1) {
      parts[3] = newCategory;
      history[index] = parts.join('|');
      StorageService.historyList = history;
    }

    // 3. Sync
    await FirebaseService.pushAllDataToCloud();
  }

  static Future<void> deleteTransaction(TransactionItem transaction) async {
    final parts = transaction.rawEntry.split('|');
    if (parts.length < 9) return;

    final category = parts[3];
    final amount = int.tryParse(parts[4]) ?? 0;
    final weekIndex = int.tryParse(parts[5]) ?? 0;
    final dayIndex = int.tryParse(parts[6]) ?? 0;
    final monthIndex = int.tryParse(parts[7]) ?? 0;
    final year = int.tryParse(parts[8]) ?? 0;
    final weekSlot = weekIndex + 1;

    // 1. Restore wallet balance
    StorageService.walletBalance += amount;

    // 2. Reduce category spent
    if (category != 'no choice') {
      final oldSpent = StorageService.getCategorySpent(category);
      StorageService.setCategorySpent(category, (oldSpent - amount).clamp(0.0, double.infinity));

      final catWeekKey = '${category}_W$weekSlot';
      final oldCatWeek = StorageService.getInt(catWeekKey);
      StorageService.setInt(catWeekKey, (oldCatWeek - amount).clamp(0, 9999999).toInt());
    }

    // 3. Reduce time-series aggregates
    final dayKey = 'DAY_${weekIndex}_${dayIndex}_${monthIndex}_$year';
    final weekKey = 'WEEK_${weekIndex}_${monthIndex}_$year';
    final monthKey = 'MONTH_${monthIndex}_$year';

    StorageService.setDouble(dayKey, (StorageService.getDouble(dayKey) - amount).clamp(0.0, double.infinity));
    StorageService.setDouble(weekKey, (StorageService.getDouble(weekKey) - amount).clamp(0.0, double.infinity));
    StorageService.setDouble(monthKey, (StorageService.getDouble(monthKey) - amount).clamp(0.0, double.infinity));

    // 4. Remove from history list
    final history = StorageService.historyList;
    history.remove(transaction.rawEntry);
    StorageService.historyList = history;

    // 5. Sync
    await FirebaseService.pushAllDataToCloud();
  }
}
