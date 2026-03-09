import 'package:shared_preferences/shared_preferences.dart';

class StorageService {
  static late SharedPreferences _prefs;

  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  // AppPrefs
  static String get userName => _prefs.getString('user_name') ?? '';
  static set userName(String value) => _prefs.setString('user_name', value);

  static String get userPhone => _prefs.getString('user_phone') ?? '';
  static set userPhone(String value) => _prefs.setString('user_phone', value);

  static String get userPassword => _prefs.getString('user_password') ?? '';
  static set userPassword(String value) => _prefs.setString('user_password', value);

  static bool get isFirstLaunch => _prefs.getBool('isFirstLaunch') ?? true;
  static set isFirstLaunch(bool value) => _prefs.setBool('isFirstLaunch', value);

  // WalletPrefs
  static int get initialBalance => _prefs.getInt('initial_balance') ?? -1;
  static set initialBalance(int value) => _prefs.setInt('initial_balance', value);

  static int get walletBalance => _prefs.getInt('wallet_balance') ?? 0;
  static set walletBalance(int value) => _prefs.setInt('wallet_balance', value);

  // MoneySchedulePrefs
  static int get nextDateMs => _prefs.getInt('next_date') ?? 0;
  static set nextDateMs(int value) => _prefs.setInt('next_date', value);

  static String? get nextMoneyDate {
    final ms = nextDateMs;
    if (ms == 0) return null;
    final date = DateTime.fromMillisecondsSinceEpoch(ms);
    return "${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}";
  }

  static int get frequency => _prefs.getInt('frequency') ?? 30;
  static set frequency(int value) => _prefs.setInt('frequency', value);

  static bool get cycleInitialized => _prefs.getBool('cycle_initialized') ?? false;
  static set cycleInitialized(bool value) => _prefs.setBool('cycle_initialized', value);

  // CategoryPrefs
  static List<String> get categories => _prefs.getStringList('categories') ?? [];
  static set categories(List<String> value) => _prefs.setStringList('categories', value);

  static int getCategoryLimit(String category) => _prefs.getInt('LIMIT_$category') ?? 0;
  static void setCategoryLimit(String category, int limit) => _prefs.setInt('LIMIT_$category', limit);

  // GraphData / Spending
  static double getCategorySpent(String category) => _prefs.getDouble('SPENT_$category') ?? 0.0;
  static void setCategorySpent(String category, double spent) => _prefs.setDouble('SPENT_$category', spent);

  static List<String> get historyList => _prefs.getStringList('HISTORY_LIST') ?? [];
  static set historyList(List<String> value) => _prefs.setStringList('HISTORY_LIST', value);

  /// Alias used by CategoryAnalysisScreen / DetailHistoryScreen
  static List<String> get rawHistoryEntries => historyList;

  // Generic accessors for dynamic keys
  static String? getString(String key) => _prefs.getString(key);
  static Future<void> setString(String key, String value) => _prefs.setString(key, value);
  static double getDouble(String key, {double defaultValue = 0.0}) => _prefs.getDouble(key) ?? defaultValue;
  static int getInt(String key, {int defaultValue = 0}) => _prefs.getInt(key) ?? defaultValue;
  static Future<void> setDouble(String key, double value) => _prefs.setDouble(key, value);
  static Future<void> setInt(String key, int value) => _prefs.setInt(key, value);
  static Future<void> setBool(String key, bool value) => _prefs.setBool(key, value);

  static Map<String, dynamic> getAllPrefs() {
    final keys = _prefs.getKeys();
    final Map<String, dynamic> prefsMap = {};
    for (String key in keys) {
      prefsMap[key] = _prefs.get(key);
    }
    return prefsMap;
  }

  // Generic reset
  static Future<void> clearAll() async {
    await _prefs.clear();
  }
}
