import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'storage_service.dart';

class FirebaseService {
  static final _auth = FirebaseAuth.instance;
  static final _db = FirebaseFirestore.instance;

  static User? get currentUser => _auth.currentUser;

  static Future<UserCredential> signIn(String email, String password) async {
    return await _auth.signInWithEmailAndPassword(email: email, password: password);
  }

  static Future<UserCredential> signUp(String email, String password) async {
    return await _auth.createUserWithEmailAndPassword(email: email, password: password);
  }

  static Future<void> signOut() async {
    await _auth.signOut();
  }

  static Future<void> sendPasswordReset(String email) async {
    await _auth.sendPasswordResetEmail(email: email);
  }

  static Future<void> pushAllDataToCloud() async {
    final user = currentUser;
    if (user == null) return;

    final uid = user.uid;
    final userDoc = _db.collection('users').doc(uid);

    // 1. Profile
    await userDoc.collection('config').doc('profile').set({
      'name': StorageService.userName,
      'phone': StorageService.userPhone,
      'password': StorageService.userPassword,
      'setup_complete': !StorageService.isFirstLaunch,
      'account_status': 'active',
      'app_origin': 'flutter_app', // Helper for data structure identification
    }, SetOptions(merge: true));

    // 2. Wallet
    await userDoc.collection('config').doc('wallet').set({
      'initial_balance': StorageService.initialBalance,
      'current_balance': StorageService.walletBalance,
      'next_date_ms': StorageService.nextDateMs,
      'frequency': StorageService.frequency,
    }, SetOptions(merge: true));

    // 3. Categories
    final catMap = <String, dynamic>{};
    for (var cat in StorageService.categories) {
      catMap[cat] = {
        'limit': StorageService.getCategoryLimit(cat),
        'spent': StorageService.getCategorySpent(cat),
      };
    }
    await userDoc.collection('config').doc('categories').set({
      'data': catMap,
      'allocation_categories': StorageService.categories,
    }, SetOptions(merge: true));

    // 4. History
    final historyList = StorageService.historyList;
    final detailedTransactions = <Map<String, dynamic>>[];
    for (var entry in historyList) {
      try {
        final parts = entry.split('|');
        if (parts.length >= 5) {
          detailedTransactions.add({
            'type': parts[0],
            'timestamp': parts[1],
            'merchant': parts[2],
            'category': parts[3],
            'amount': int.tryParse(parts[4]) ?? 0,
          });
        }
      } catch (e) {
        print('Error parsing history entry: $e');
      }
    }
    await userDoc.collection('config').doc('history').set({
      'raw_list': historyList,
      'detailed_transactions': detailedTransactions,
    }, SetOptions(merge: true));
    // 5. Analytics (CategoryWeekData)
    final allPrefs = StorageService.getAllPrefs();
    final analyticsMap = <String, dynamic>{};
    for (var key in allPrefs.keys) {
      if (key.contains('_W')) { // CategoryWeekData pattern: {cat}_W{1-5}
        analyticsMap[key] = allPrefs[key];
      }
    }
    await userDoc.collection('config').doc('analytics').set({
      'CategoryWeekData': analyticsMap,
    }, SetOptions(merge: true));

    // 6. Scanner History
    final scannerHistory = <String, dynamic>{};
    if (allPrefs.containsKey('last_upi')) {
      scannerHistory['last_upi'] = allPrefs['last_upi'];
    }
    // Add any other scanner related prefs here if they exist
    await userDoc.collection('config').doc('history_scanner').set({
      'ScannerHistory': scannerHistory,
    }, SetOptions(merge: true));
  }

  static Future<bool> pullDataFromCloud() async {
    final user = currentUser;
    if (user == null) return false;

    final uid = user.uid;
    final userDoc = _db.collection('users').doc(uid);

    try {
      final profileDoc = await userDoc.collection('config').doc('profile').get();
      if (!profileDoc.exists) return false;

      final data = profileDoc.data()!;
      StorageService.userName = data['name'] ?? '';
      StorageService.userPhone = data['phone'] ?? '';
      StorageService.userPassword = data['password'] ?? '';
      StorageService.isFirstLaunch = !(data['setup_complete'] ?? false);

      final walletDoc = await userDoc.collection('config').doc('wallet').get();
      if (walletDoc.exists) {
        final wData = walletDoc.data()!;
        StorageService.initialBalance = wData['initial_balance'] ?? 0;
        StorageService.walletBalance = wData['current_balance'] ?? 0;
        StorageService.nextDateMs = wData['next_date_ms'] ?? 0;
        StorageService.frequency = wData['frequency'] ?? 30;
      }

      final catDoc = await userDoc.collection('config').doc('categories').get();
      if (catDoc.exists) {
        final cData = catDoc.data()!;
        final dataMap = cData['data'] as Map<String, dynamic>? ?? {};
        final cats = (cData['allocation_categories'] as List?)?.cast<String>() ?? dataMap.keys.toList();
        StorageService.categories = cats;
        for (var cat in cats) {
          final catData = dataMap[cat] as Map<String, dynamic>? ?? {};
          StorageService.setCategoryLimit(cat, catData['limit'] ?? 0);
          StorageService.setCategorySpent(cat, (catData['spent'] ?? 0.0).toDouble());
        }
      }

      final histDoc = await userDoc.collection('config').doc('history').get();
      if (histDoc.exists) {
        final hData = histDoc.data()!;
        StorageService.historyList = (hData['raw_list'] as List?)?.cast<String>() ?? [];
      }

      // 5. Analytics (CategoryWeekData)
      final analyticsDoc = await userDoc.collection('config').doc('analytics').get();
      if (analyticsDoc.exists) {
        final aData = analyticsDoc.data()!;
        final cwdMap = aData['CategoryWeekData'] as Map<String, dynamic>? ?? {};
        for (var key in cwdMap.keys) {
          final val = cwdMap[key];
          if (val is int) await StorageService.setInt(key, val);
        }
      }

      // 6. Scanner History
      final scannerDoc = await userDoc.collection('config').doc('history_scanner').get();
      if (scannerDoc.exists) {
        final sData = scannerDoc.data()!;
        final shMap = sData['ScannerHistory'] as Map<String, dynamic>? ?? {};
        for (var key in shMap.keys) {
          final val = shMap[key];
          if (val is String) await StorageService.setString(key, val);
          else if (val is int) await StorageService.setInt(key, val);
          else if (val is bool) await StorageService.setBool(key, val);
        }
      }

      return true;
    } catch (e) {
      print('Error pulling cloud data: $e');
      return false;
    }
  }

  static void setupAdminListener(Function onWipe) {
    final user = currentUser;
    if (user == null) return;

    _db.collection('users').doc(user.uid).collection('config').doc('profile').snapshots().listen((doc) {
      if (doc.exists && doc.data()?['account_status'] == 'deleted') {
        onWipe();
      }
    });
  }
}
