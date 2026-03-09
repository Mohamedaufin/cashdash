import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_service.dart';

class SupportTicket {
  final String id;
  final String query;
  final String response;
  final String timestamp;
  final bool isResponded;

  SupportTicket({
    required this.id,
    required this.query,
    required this.response,
    required this.timestamp,
    required this.isResponded,
  });

  factory SupportTicket.fromMap(String id, Map<String, dynamic> map) {
    return SupportTicket(
      id: id,
      query: map['query'] ?? '',
      response: map['response'] ?? '',
      timestamp: map['timestamp'] ?? '',
      isResponded: map['status'] == 'responded',
    );
  }
}

class NotificationService {
  static final _db = FirebaseFirestore.instance;

  static Stream<List<SupportTicket>> getTicketsStream() {
    final user = FirebaseService.currentUser;
    if (user == null) return Stream.value([]);

    return _db
        .collection('users')
        .doc(user.uid)
        .collection('support')
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) => SupportTicket.fromMap(doc.id, doc.data())).toList();
    });
  }

  static Future<void> sendQuery(String query) async {
    final user = FirebaseService.currentUser;
    if (user == null) return;

    final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
    await _db.collection('users').doc(user.uid).collection('support').add({
      'query': query,
      'response': 'Waiting for admin response...',
      'status': 'pending',
      'timestamp': timestamp,
    });
  }
}
