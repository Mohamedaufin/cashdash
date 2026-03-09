import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'package:intl/intl.dart';
import '../theme/app_colors.dart';

class NotificationScreen extends StatefulWidget {
  const NotificationScreen({super.key});

  @override
  State<NotificationScreen> createState() => _NotificationScreenState();
}

class _NotificationScreenState extends State<NotificationScreen> {
  String _currentFilter = 'all'; // 'all', 'responded', 'pending'
  List<DocumentSnapshot> _allDocs = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _markAllAsRead();
    _loadNotifications();
  }

  void _markAllAsRead() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final db = FirebaseFirestore.instance;
    final docs = await db
        .collection('users')
        .doc(user.uid)
        .collection('notifications')
        .where('read', isEqualTo: false)
        .get();

    if (docs.docs.isNotEmpty) {
      final batch = db.batch();
      for (var doc in docs.docs) {
        batch.update(doc.reference, {'read': true});
      }
      await batch.commit();
      debugPrint("All notifications marked as read.");
    }
  }

  void _loadNotifications() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final db = FirebaseFirestore.instance;

    db
        .collection('users')
        .doc(user.uid)
        .collection('notifications')
        .orderBy('timestamp', descending: true)
        .get()
        .then((snapshot) {
      if (snapshot.docs.isEmpty) {
        if (mounted) {
          setState(() {
            _allDocs = [];
            _isLoading = false;
          });
        }
        return;
      }

      final rawDocs = snapshot.docs;

      // Silent background cleanup for legacy duplicates
      final Map<String, List<DocumentSnapshot>> groupedDocs = {};
      for (var doc in rawDocs) {
        final q = (doc.data()['query'] as String?)?.trim() ?? "";
        final s = (doc.data()['subject'] as String?)?.trim() ?? "";
        final key = "$s|$q";
        if (groupedDocs.containsKey(key)) {
          groupedDocs[key]!.add(doc);
        } else {
          groupedDocs[key] = [doc];
        }
      }

      final docsToDelete = <DocumentSnapshot>[];
      for (var group in groupedDocs.values) {
        if (group.length > 1) {
          final respondedDoc = group.cast<DocumentSnapshot?>().firstWhere(
                (doc) => (doc?.data() as Map<String, dynamic>)['reply'] != null && 
                         (doc?.data() as Map<String, dynamic>)['reply'] != 'Waiting for reply...',
                orElse: () => null,
              );
              
          final docToKeep = respondedDoc ?? 
                            group.reduce((a, b) => 
                              ((a.data() as Map<String, dynamic>)['timestamp'] ?? 0) > 
                              ((b.data() as Map<String, dynamic>)['timestamp'] ?? 0) ? a : b);

          for (var d in group) {
            if (d.id != docToKeep.id) docsToDelete.add(d);
          }
        }
      }

      if (docsToDelete.isNotEmpty) {
        final batch = db.batch();
        for (var d in docsToDelete) {
          batch.delete(d.reference);
        }
        batch.commit();
      }

      if (mounted) {
        setState(() {
          _allDocs = rawDocs.where((doc) => !docsToDelete.any((d) => d.id == doc.id)).toList();
          _isLoading = false;
        });
      }
    }).catchError((error) {
       if (mounted) {
          setState(() {
             _isLoading = false;
          });
       }
    });
  }

  void _deleteNotification(DocumentSnapshot doc) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final db = FirebaseFirestore.instance;
    final queryToDelete = (doc.data() as Map<String, dynamic>)['query'] ?? 'No query';

    final snapshot = await db
        .collection('users')
        .doc(user.uid)
        .collection('notifications')
        .where('query', isEqualTo: queryToDelete)
        .get();

    final batch = db.batch();
    for (var d in snapshot.docs) {
      batch.delete(d.reference);
    }
    await batch.commit();

    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Query deleted")));
    _loadNotifications();
  }

  void _showDeleteDialog(DocumentSnapshot doc, VoidCallback onCancel) {
    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 20),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 30),
            decoration: BoxDecoration(
              color: const Color(0xFF1E2642),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white.withOpacity(0.15), width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.5),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                )
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Delete query?',
                  style: TextStyle(
                    fontSize: 22,
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 15),
                const Text(
                  'Remove this query from your history?',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    color: Color(0xFFA0A0A0),
                  ),
                ),
                const SizedBox(height: 30),
                Row(
                  children: [
                    Expanded(
                      child: _glassButton(
                        'Cancel',
                        onTap: () {
                          Navigator.pop(context);
                          onCancel();
                        },
                      ),
                    ),
                    const SizedBox(width: 15),
                    Expanded(
                      child: _glassButton(
                        'Delete',
                        onTap: () {
                          Navigator.pop(context);
                          _deleteNotification(doc);
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _glassButton(String label, {required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 50,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: Colors.white.withOpacity(0.08),
          border: Border.all(color: Colors.white.withOpacity(0.15), width: 1),
        ),
        child: Center(
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  List<DocumentSnapshot> get _filteredDocs {
    if (_currentFilter == 'responded') {
      return _allDocs.where((doc) {
        final reply = (doc.data() as Map<String, dynamic>)['reply'];
        return reply != null && reply != 'Waiting for reply...';
      }).toList();
    } else if (_currentFilter == 'pending') {
      return _allDocs.where((doc) {
        final reply = (doc.data() as Map<String, dynamic>)['reply'];
        return reply == null || reply == 'Waiting for reply...';
      }).toList();
    }
    return _allDocs;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: Colors.blue)),
      );
    }

    final filtered = _filteredDocs;

    return Scaffold(
      backgroundColor: Colors.transparent, // We wrap entirely in container with gradient
      body: Container(
        decoration: const BoxDecoration(
          gradient: AppColors.mainBackgroundGradient,
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 25.0, vertical: 15.0),
                child: Row(
                  children: [
                    _circularGlassBtn(
                      icon: Icons.arrow_back,
                      onTap: () => Navigator.pop(context),
                    ),
                    const Expanded(
                      child: Center(
                        child: Text(
                          'Notifications',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 55), // Balance space for back button
                  ],
                ),
              ),

              if (_allDocs.isNotEmpty) ...[
                // Filter Bar
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 25.0, vertical: 10.0),
                  child: Row(
                    children: [
                      _filterChip('All', 'all'),
                      const SizedBox(width: 8),
                      _filterChip('Responded', 'responded'),
                      const SizedBox(width: 8),
                      _filterChip('Pending', 'pending'),
                    ],
                  ),
                ),
              ],

              // Content Area
              Expanded(
                child: _buildContentArea(filtered),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContentArea(List<DocumentSnapshot> filtered) {
    // 1. COMPLETELY EMPTY STATE
    if (_allDocs.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(40.0),
          child: Text(
            "No notifications yet.\n\nWe'll notify you when your support\nqueries are resolved!",
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFF607DA5),
              fontSize: 16,
              height: 1.5,
            ),
          ),
        ),
      );
    }

    // 2. FILTERED EMPTY STATE
    if (filtered.isEmpty) {
      String msg = "";
      if (_currentFilter == 'pending') msg = "All your queries have been responded!";
      if (_currentFilter == 'responded') msg = "No queries have been answered yet.";
      
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(40.0),
          child: Text(
            msg,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF607DA5),
              fontSize: 16,
              height: 1.5,
            ),
          ),
        ),
      );
    }

    // 3. RESULTS STATE
    return ListView.builder(
      padding: const EdgeInsets.all(25.0),
      itemCount: filtered.length,
      itemBuilder: (context, index) {
        final doc = filtered[index];
        final data = doc.data() as Map<String, dynamic>;
        
        final String queryText = data['query'] ?? "No query";
        final String replyText = data['reply'] ?? "Waiting for reply...";
        final String subjectText = data['subject'] ?? "General Help";
        final int timestamp = data['timestamp'] ?? 0;
        final bool isUnreadLocally = data['read'] == false;

        final bool isPending = replyText == "Waiting for reply...";

        final Color accentColor = isPending ? const Color(0xFFFFD93D) : const Color(0xFF4ADE80);
        final String titleText = isPending ? "Waiting for response" : "Query responded";

        String timeString = "";
        if (timestamp > 0) {
          final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
          timeString = DateFormat('dd MMM, hh:mm a').format(date);
        }

        final bool shouldAnimatePop = isUnreadLocally && !isPending;

        Widget itemCard = Container(
          margin: const EdgeInsets.only(bottom: 20),
          decoration: BoxDecoration(
            color: const Color(0xFF1E2642),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(0.08), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Left Accent Bar
              Container(
                width: 6,
                decoration: BoxDecoration(
                  color: accentColor,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(16),
                    bottomLeft: Radius.circular(16),
                  ),
                ),
              ),
              // Content
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Title and Time
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            titleText,
                            style: TextStyle(
                              color: accentColor,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            timeString,
                            style: const TextStyle(
                              color: Color(0xFF88A0C0),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 15),
                      // Query Text
                      HtmlWidget(
                         "<b>Subject:</b> $subjectText<br><br><b>Question:</b> $queryText",
                         textStyle: const TextStyle(color: Colors.white, fontSize: 14, height: 1.4),
                      ),
                      
                      if (!isPending) ...[
                        const SizedBox(height: 15),
                        const Divider(color: Color(0xFF303A5F), thickness: 1),
                        const SizedBox(height: 15),
                        HtmlWidget(
                           "<font color='#4ADE80'><b>Response</b></font><br><br><font color='#E0EBF5'>$replyText</font>",
                           textStyle: const TextStyle(fontSize: 14, height: 1.4),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        );

        // Wrap in Dismissible for right-to-left swipe to delete
        // Note: Using a custom key using the document ID
        return Dismissible(
          key: Key(doc.id),
          direction: DismissDirection.endToStart,
          confirmDismiss: (direction) async {
            bool deleteConfirmed = false;
            // The method _showDeleteDialog doesn't traditionally return a Future<bool> 
            // from the dialog itself based on the old imperative native mapping 
            // but we can wrap it in a Completer or just use showDialog correctly:
            final bool? result = await showDialog<bool>(
              context: context,
               barrierColor: Colors.black54,
              builder: (BuildContext context) {
                return Dialog(
                  backgroundColor: Colors.transparent,
                  insetPadding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 30),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E2642),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: Colors.white.withOpacity(0.15), width: 1.5),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.5),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        )
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Delete query?',
                          style: TextStyle(
                            fontSize: 22,
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 15),
                        const Text(
                          'Remove this query from your history?',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 16,
                            color: Color(0xFFA0A0A0),
                          ),
                        ),
                        const SizedBox(height: 30),
                        Row(
                          children: [
                            Expanded(
                              child: _glassButton(
                                'Cancel',
                                onTap: () => Navigator.of(context).pop(false),
                              ),
                            ),
                            const SizedBox(width: 15),
                            Expanded(
                              child: _glassButton(
                                'Delete',
                                onTap: () => Navigator.of(context).pop(true),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            );

            if (result == true) {
              _deleteNotification(doc);
              return true;
            }
            return false;
          },
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            color: Colors.transparent, // Background doesn't need color as the card swipes away
          ),
          child: _PopAnimationWidget(
            shouldAnimate: shouldAnimatePop,
            child: IntrinsicHeight(child: itemCard),
          ),
        );
      },
    );
  }

  Widget _filterChip(String label, String filterValue) {
    bool isActive = _currentFilter == filterValue;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            _currentFilter = filterValue;
          });
        },
        child: Container(
          height: 40,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withOpacity(0.1), width: 1),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color: isActive ? Colors.white : const Color(0xFF606880),
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }

  Widget _circularGlassBtn({required IconData icon, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 50,
        height: 50,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withOpacity(0.1),
          border: Border.all(color: Colors.white.withOpacity(0.15), width: 1.2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Center(
          child: Icon(icon, color: Colors.white, size: 24),
        ),
      ),
    );
  }
}

class _PopAnimationWidget extends StatefulWidget {
  final bool shouldAnimate;
  final Widget child;

  const _PopAnimationWidget({required this.shouldAnimate, required this.child});

  @override
  State<_PopAnimationWidget> createState() => _PopAnimationWidgetState();
}

class _PopAnimationWidgetState extends State<_PopAnimationWidget> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    _scaleAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.05), weight: 50),
      TweenSequenceItem(tween: Tween(begin: 1.05, end: 1.0), weight: 50),
    ]).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

    if (widget.shouldAnimate) {
      Future.delayed(const Duration(milliseconds: 300), () {
         if (mounted) {
           _controller.forward().then((_) {
             if (mounted) _controller.reverse();
           });
         }
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.shouldAnimate) return widget.child;

    return ScaleTransition(
      scale: _scaleAnimation,
      child: widget.child,
    );
  }
}
