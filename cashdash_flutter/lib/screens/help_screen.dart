import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

import '../theme/app_colors.dart';
import '../services/storage_service.dart';

class HelpScreen extends StatefulWidget {
  const HelpScreen({super.key});

  @override
  State<HelpScreen> createState() => _HelpScreenState();
}

class _HelpScreenState extends State<HelpScreen> {
  // ── UI Helpers ────────────────────────────────────────────────────────────

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        title,
        style: const TextStyle(
          color: Color(0xFFB0C8FF),
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildFaqBlock(List<Map<String, String>> faqs) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(15),
      margin: const EdgeInsets.only(bottom: 25),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.1), width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: faqs.map((faq) {
          final isLast = faq == faqs.last;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                faq['q']!,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                faq['a']!,
                style: const TextStyle(
                  color: Color(0xFFD1E1FF),
                  fontSize: 14,
                ),
              ),
              if (!isLast) const SizedBox(height: 12),
            ],
          );
        }).toList(),
      ),
    );
  }

  // ── Contact Dialog ───────────────────────────────────────────────────────

  void _showContactDialog() {
    final name = StorageService.userName.isNotEmpty ? StorageService.userName : "User";
    final currentUser = FirebaseAuth.instance.currentUser;
    final email = currentUser?.email ?? "No Email";
    final currentTime = DateFormat('dd MMM yyyy, hh:mm a').format(DateTime.now());

    final subjectCtrl = TextEditingController();
    final queryCtrl = TextEditingController();

    bool isSubmitting = false;

    showDialog(
      context: context,
      builder: (_) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              backgroundColor: Colors.transparent,
              child: Container(
                width: MediaQuery.of(context).size.width - 60,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF1E3A70), Color(0xFF0A1640)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white.withOpacity(0.2), width: 1.2),
                ),
                padding: const EdgeInsets.all(20),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Contact Support',
                        style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 15),
                      Text('Name: $name', style: const TextStyle(color: Colors.white70)),
                      Text('Time: $currentTime', style: const TextStyle(color: Colors.white70)),
                      Text('Email: $email', style: const TextStyle(color: Colors.white70)),
                      const SizedBox(height: 15),

                      _buildDialogInput(subjectCtrl, 'Subject', maxLines: 1),
                      const SizedBox(height: 10),
                      _buildDialogInput(queryCtrl, 'Your Query/Issue details', maxLines: 4),

                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF4AA3FF),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: isSubmitting
                              ? null
                              : () {
                                  final subject = subjectCtrl.text.trim();
                                  final query = queryCtrl.text.trim();

                                  if (subject.isEmpty) {
                                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter a subject')));
                                    return;
                                  }
                                  if (query.isEmpty) {
                                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please mention your query')));
                                    return;
                                  }

                                  setDialogState(() {
                                    isSubmitting = true;
                                  });
                                  
                                  _submitQueryToFirestore(name, currentTime, email, subject, query);
                                  Navigator.pop(context);
                                },
                          child: Text(
                            isSubmitting ? 'Submitting...' : 'Submit',
                            style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildDialogInput(TextEditingController ctrl, String hint, {int maxLines = 1}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.2),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: TextField(
        controller: ctrl,
        maxLines: maxLines,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: Colors.white38),
          contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
          border: InputBorder.none,
        ),
      ),
    );
  }

  Future<void> _submitQueryToFirestore(String name, String time, String email, String subject, String query) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final pipedreamUrl = "https://eorutjgz6wo78f1.m.pipedream.net";
    final timestamp = DateTime.now().millisecondsSinceEpoch;

    // Save to Firestore
    final notificationData = {
      "name": name,
      "email": email,
      "time": time,
      "subject": subject,
      "query": query,
      "timestamp": timestamp,
      "read": false,
      "reply": "Waiting for reply..."
    };

    try {
      await FirebaseFirestore.instance
          .collection("users")
          .doc(user.uid)
          .collection("notifications")
          .doc(timestamp.toString())
          .set(notificationData);
    } catch (_) {}

    // Send to webhook
    final payload = {
      "uid": user.uid,
      "name": name,
      "email": email,
      "time": time,
      "subject": subject,
      "query": query,
      "timestamp": timestamp
    };

    try {
      final response = await http.post(
        Uri.parse(pipedreamUrl),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(payload),
      );

      if (mounted) {
        if (response.statusCode >= 200 && response.statusCode < 300) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Query sent! We\'ll notify you when we reply.')));
        } else {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Submission failed (Code ${response.statusCode}). Check your URL.')));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Network error: Make sure to set your Pipedream URL!')));
      }
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent, // Immersive container below
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: AppColors.mainBackgroundGradient,
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(25, 30, 25, 20),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        width: 45,
                        height: 45,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.12),
                          border: Border.all(color: Colors.white.withOpacity(0.15), width: 1.2),
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 10, offset: const Offset(0, 4))
                          ],
                        ),
                        child: const Icon(Icons.arrow_back, color: Colors.white),
                      ),
                    ),
                    const SizedBox(width: 20),
                    const Text(
                      'Help Center',
                      style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),

              // Scrollable Content
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // General FAQs
                      _buildSectionTitle('General FAQs'),
                      _buildFaqBlock([
                        {
                          'q': 'Q: What exactly does CashDash do?',
                          'a': "A: CashDash helps you visualize how fast you run out of money in your current lifestyle. You scan QR codes to pay, and the app instantly logs it to deduct your 'Wallet' and tracks it in 'History'."
                        },
                        {
                          'q': 'Q: Do I need an internet connection to use the app?',
                          'a': "A: To use the automatic QR scanner smoothly, yes. However, you can use the 'Rigor Tracker' to log manual expenses completely offline, and they'll sync to the cloud later."
                        },
                        {
                          'q': 'Q: Is my financial data secure?',
                          'a': "A: Yes! Your data is privately locked to your Google account using Firebase Authentication. There is no bank-linking or raw transaction scraping."
                        },
                        {
                          'q': 'Q: If I get a new phone or reinstall, do I lose my data?',
                          'a': "A: No! Everything is silently backed up to the cloud. Just log back in with the exact same Google account and all your money, history, and categories will reappear instantly."
                        },
                      ]),

                      // Home Dashboard
                      _buildSectionTitle('Home Dashboard'),
                      _buildFaqBlock([
                        {
                          'q': 'Q: What is the big Wallet Circle for?',
                          'a': "A: It's your fuel gauge. It shows how much money you have left vs what you started with. If it's completely empty, you have spent your planned budget!"
                        },
                        {
                          'q': 'Q: How do I scan and pay?',
                          'a': "A: Tap the Scanner card at the bottom of the home screen. After capturing a merchant's QR, enter the amount, and CashDash will transfer you to your UPI app to finish the payment. The amount is auto-logged!"
                        },
                        {
                          'q': 'Q: What is the Rigor Tracker (Hand Icon)?',
                          'a': "A: The Rigor Tracker allows you to manually add expenses that weren't paid via QR scanning (like handing over physical cash, or an online subscription)."
                        },
                        {
                          'q': 'Q: How do I undo a mistake transaction?',
                          'a': "A: Open the Rigor Tracker. At the top right, there is an 'Undo' button that will delete your most recently scanned or logged transaction and refund your wallet."
                        },
                        {
                          'q': 'Q: Can I delete an old transaction from last week?',
                          'a': "A: No, the Undo button ONLY protects you against accidental double-scans or fat-finger typos on your absolute most recent transaction. This restriction guarantees accounting rigor so you can't erase your real spending habits!"
                        },
                      ]),

                      // Allocator
                      _buildSectionTitle('Allocator (Categories)'),
                      _buildFaqBlock([
                        {
                          'q': 'Q: How do I set a sub-budget?',
                          'a': "A: Add a category (like 'Food'). Then click the 'Limit: ₹0' text on the category card. You can set an exact cap, like ₹5000."
                        },
                        {
                          'q': 'Q: My category bar turned red, what does it mean?',
                          'a': "A: Red means danger! You have spent more than the limit you set for this specific category. Time to cut back on that expense."
                        },
                        {
                          'q': 'Q: How do I delete or rename a category?',
                          'a': "A: To DELETE: Swipe the category card left-to-right off the screen.\nTo RENAME: Press and hold your finger on the category card for a second."
                        },
                        {
                          'q': 'Q: What is the \'Overall\' category?',
                          'a': "A: 'Overall' is a permanent, master category that tracks the sum of ALL your expenses combined. You cannot delete or rename it. If you don't pick a specific category when logging an expense, it defaults to Overall."
                        },
                      ]),

                      // History
                      _buildSectionTitle('History & Graphing'),
                      _buildFaqBlock([
                        {
                          'q': 'Q: How do I see a breakdown of a specific day?',
                          'a': "A: TAP on any green bar in the graph! It will open a detailed screen showing every individual transaction made that day (or week/month)."
                        },
                        {
                          'q': 'Q: Can I see a graph for only \'Travel\'?',
                          'a': "A: Yes! Look for the 'Overall' button at the top right of the history screen. Tap it to filter the graph to a specific category."
                        },
                        {
                          'q': 'Q: How do I jump back to an old month?',
                          'a': "A: Tap the button displaying the current date (e.g., '14/10/2026'). A calendar will pop up allowing you to warp to any past week or year."
                        },
                        {
                          'q': 'Q: My graph is completely empty, is my data lost?',
                          'a': "A: No! You are likely viewing a month/week where you didn't log anything, or you have a specific category filter applied at the top right (like 'Food') that has no expenses for that period. Switch the top-right filter back to 'Overall' to see all data."
                        },
                      ]),

                      // Menu & Profile
                      _buildSectionTitle('Menu & Profile'),
                      _buildFaqBlock([
                        {
                          'q': 'Q: What does \'Money Schedule\' do?',
                          'a': "A: Use this to set your 'Payday' or Allowance frequency (e.g., every 30 days). When that day arrives, CashDash will automatically 'Roll Over' by resetting your Wallet to full and clearing your category spent amounts for the new cycle!"
                        },
                        {
                          'q': 'Q: How do I change my starting budget?',
                          'a': "A: Go to the Menu and tap 'Wallet Update'. This lets you inject more cash or reset your baseline starting amount."
                        },
                        {
                          'q': 'Q: Where do I see support replies?',
                          'a': "A: You'll receive a Push Notification when we reply. Alternatively, tap the Bell icon in the Menu to view your full support history."
                        },
                      ]),

                      // Contact Support Button
                      GestureDetector(
                        onTap: _showContactDialog,
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 20),
                          margin: const EdgeInsets.only(bottom: 30),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.white.withOpacity(0.1), width: 1.2),
                          ),
                          child: const Center(
                            child: Text(
                              'Still stuck? Contact Support',
                              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
