import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/notification_service.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  String? _currentUserId;
  List<Map<String, dynamic>> _notifications = [];
  bool _isLoading = true;
  StreamSubscription<QuerySnapshot>? _notificationSubscription;
  Set<String> _deletedProductIds = {};

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  @override
  void dispose() {
    _notificationSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadUserData() async {
    final prefs = await SharedPreferences.getInstance();
    _currentUserId = prefs.getString('current_user_id') ?? 
                     prefs.getString('signup_user_id');
    
    if (_currentUserId != null && _currentUserId!.isNotEmpty) {
      _setupRealtimeListener();
      _loadNotifications();
    } else {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _setupRealtimeListener() {
    if (_currentUserId == null || _currentUserId!.isEmpty) return;
    
    // Cancel existing listener if any
    _notificationSubscription?.cancel();

    final firestore = FirebaseFirestore.instanceFor(
      app: Firebase.app(),
      databaseId: 'marketsafe',
    );

    _notificationSubscription = firestore
        .collection('notifications')
        .where('userId', isEqualTo: _currentUserId)
        .snapshots()
        .listen(
          (QuerySnapshot snapshot) {
            print('🔔 Real-time update: ${snapshot.docs.length} notifications');
            
            // Handle document changes properly
            final notifications = snapshot.docs.map((doc) {
              final data = doc.data() as Map<String, dynamic>;
              print('🔔 Real-time notification: ${data['title']} - ${data['status']} (ID: ${doc.id})');
              return data;
            }).toList();
            
            // Sort by createdAt in descending order (newest first)
            notifications.sort((a, b) {
              final aTime = a['createdAt'] as Timestamp?;
              final bTime = b['createdAt'] as Timestamp?;
              if (aTime == null && bTime == null) return 0;
              if (aTime == null) return 1;
              if (bTime == null) return -1;
              return bTime.compareTo(aTime);
            });
            
            if (mounted) {
              setState(() {
                _notifications = notifications;
                _isLoading = false;
              });
              print('🔔 Updated notifications list with ${notifications.length} items');
            }
          },
          onError: (error) {
            print('❌ Real-time listener error: $error');
            if (mounted) {
              setState(() {
                _isLoading = false;
              });
            }
          },
        );
  }

  Future<void> _loadNotifications() async {
    try {
      setState(() {
        _isLoading = true;
      });

      final prefs = await SharedPreferences.getInstance();
      _currentUserId = prefs.getString('signup_user_id') ?? 
                      prefs.getString('current_user_id') ?? '';
      
      print('👤 NotificationsScreen user ID: $_currentUserId');
      
      if (_currentUserId == null || _currentUserId!.isEmpty) {
        print('❌ No user ID found - cannot load notifications');
        setState(() {
          _isLoading = false;
        });
        return;
      }

      print('🔔 Loading notifications for user: $_currentUserId');
      
      // Load existing notifications only (don't create new ones)
      final notifications = await NotificationService.getUserNotifications(_currentUserId!);
      print('📬 Loaded ${notifications.length} existing notifications');
      
      // Set up real-time listener for immediate updates
      _setupRealtimeListener();
      
      // Check which products still exist
      await _checkProductExistence(notifications);
      
      if (mounted) {
        setState(() {
          _notifications = notifications;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('❌ Error loading notifications: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _markAsRead(String notificationId) async {
    await NotificationService.markAsRead(notificationId);
    // Real-time listener will update the UI
    await _loadNotifications(); // Refresh the list
  }

  Future<void> _markAllAsRead() async {
    if (_currentUserId != null && _currentUserId!.isNotEmpty) {
      await NotificationService.markAllAsRead(_currentUserId!);
      // Real-time listener will update the UI
      await _loadNotifications(); // Refresh the list
    }
  }

  Future<void> _deleteAllNotifications() async {
    if (_currentUserId == null || _currentUserId!.isEmpty) return;

    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning, color: Colors.red),
            SizedBox(width: 8),
            Text('Delete All Notifications'),
          ],
        ),
        content: const Text(
          'Are you sure you want to delete all notifications? This action cannot be undone.',
          style: TextStyle(fontSize: 16),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete All', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        // Show loading indicator
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const Center(
            child: CircularProgressIndicator(color: Colors.red),
          ),
        );

        // Delete all notifications
        await NotificationService.deleteAllNotifications(_currentUserId!);
        
        // Clear local state immediately
        setState(() {
          _notifications.clear();
        });
        
        // Close loading dialog
        if (mounted) Navigator.of(context).pop();
        
        // Show success message
        _showSnackBar('All notifications deleted successfully');
      } catch (e) {
        // Close loading dialog
        if (mounted) Navigator.of(context).pop();
        
        // Show error message
        _showSnackBar('Error deleting notifications: $e');
      }
    }
  }

  void _showSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  String _formatTimestamp(dynamic timestamp) {
    try {
      DateTime dateTime;
      if (timestamp is Timestamp) {
        dateTime = timestamp.toDate();
      } else if (timestamp is String) {
        dateTime = DateTime.parse(timestamp);
      } else {
        return 'Just now';
      }

      final now = DateTime.now();
      final difference = now.difference(dateTime);

      if (difference.inDays > 7) {
        return '${dateTime.day}/${dateTime.month}/${dateTime.year}';
      } else if (difference.inDays > 0) {
        return '${difference.inDays} day${difference.inDays > 1 ? 's' : ''} ago';
      } else if (difference.inHours > 0) {
        return '${difference.inHours} hour${difference.inHours > 1 ? 's' : ''} ago';
      } else if (difference.inMinutes > 0) {
        return '${difference.inMinutes} minute${difference.inMinutes > 1 ? 's' : ''} ago';
      } else {
        return 'Just now';
      }
    } catch (e) {
      return 'Just now';
    }
  }

  Color _getStatusColor(String? status) {
    switch (status) {
      case 'approved':
        return Colors.green;
      case 'rejected':
        return Colors.red;
      case 'pending':
        return Colors.orange;
      case 'deleted':
        return Colors.grey;
      default:
        return Colors.blue;
    }
  }

  IconData _getStatusIcon(String? status) {
    switch (status) {
      case 'approved':
        return Icons.check_circle;
      case 'rejected':
        return Icons.cancel;
      case 'pending':
        return Icons.hourglass_empty;
      case 'deleted':
        return Icons.delete;
      default:
        return Icons.info;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
        child: Column(
          children: [
            // Top bar (transparent like message screen)
            Padding(
              padding: const EdgeInsets.only(left: 16, right: 16, top: 30, bottom: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const SizedBox(width: 24), // Spacer to balance the layout
                  const Text(
                    'Notifications',
                    style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  Row(
                    children: [
                      if (_notifications.any((n) => (n['isRead'] ?? false) == false))
                        TextButton(
                          onPressed: _markAllAsRead,
                          child: const Text(
                            'Mark All Read',
                            style: TextStyle(color: Colors.white),
                          ),
                        ),
                      if (_notifications.isNotEmpty)
                        PopupMenuButton<String>(
                          onSelected: (value) async {
                            if (value == 'mark_all_read') {
                              await _markAllAsRead();
                            } else if (value == 'delete_all') {
                              await _deleteAllNotifications();
                            }
                          },
                          itemBuilder: (context) => [
                            if (_notifications.any((n) => (n['isRead'] ?? false) == false))
                              const PopupMenuItem(
                                value: 'mark_all_read',
                                child: Row(
                                  children: [
                                    Icon(Icons.mark_email_read, color: Colors.white),
                                    SizedBox(width: 8),
                                    Text('Mark All as Read'),
                                  ],
                                ),
                              ),
                            const PopupMenuItem(
                              value: 'delete_all',
                              child: Row(
                                children: [
                                  Icon(Icons.delete_forever, color: Colors.red),
                                  SizedBox(width: 8),
                                  Text('Delete All Notifications', style: TextStyle(color: Colors.red)),
                                ],
                              ),
                            ),
                          ],
                          icon: const Icon(Icons.more_vert, color: Colors.white),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            // Notifications content
            Expanded(
              child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.black, Color(0xFF1a1a1a), Color(0xFF2B0000)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            stops: [0.0, 0.5, 1.0],
          ),
        ),
        child: _currentUserId == null || _currentUserId!.isEmpty
            ? const Center(
                child: Text(
                  'Please log in to view notifications',
                  style: TextStyle(color: Colors.white),
                ),
              )
            : _isLoading
                ? const Center(
                    child: CircularProgressIndicator(
                      color: Colors.red,
                    ),
                  )
                : _notifications.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.notifications_none,
                              size: 64,
                              color: Colors.grey[600],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No notifications yet',
                              style: TextStyle(
                                color: Colors.grey[400],
                                fontSize: 18,
                              ),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadNotifications,
                        color: Colors.red,
                        child: ListView.builder(
                          padding: const EdgeInsets.all(8),
                          itemCount: _notifications.length,
                          itemBuilder: (context, index) {
                            final notification = _notifications[index];
                            final isRead = notification['isRead'] ?? false;
                            final title = notification['title'] ?? 'Notification';
                            final message = notification['message'] ?? '';
                            final status = notification['status'] as String?;
                            final timestamp = notification['createdAt'];
                            final productId = notification['productId']?.toString() ?? '';
                            final isProductDeleted = _deletedProductIds.contains(productId);

                            return Card(
                              margin: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              color: isRead 
                                  ? Colors.grey[900] 
                                  : Colors.grey[850]?.withOpacity(0.9),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: InkWell(
                                onTap: () {
                                  if (!isRead) {
                                    _markAsRead(notification['id'] ?? '');
                                  }
                                  // Show product preview
                                  _showProductPreview(notification);
                                },
                                borderRadius: BorderRadius.circular(12),
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      // Status icon
                                      Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: _getStatusColor(status)
                                              .withOpacity(0.2),
                                          shape: BoxShape.circle,
                                        ),
                                        child: Icon(
                                          _getStatusIcon(status),
                                          color: _getStatusColor(status),
                                          size: 24,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      // Notification content
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                // Status indicator dot
                                                Container(
                                                  width: 8,
                                                  height: 8,
                                                  decoration: BoxDecoration(
                                                    color: isProductDeleted 
                                                        ? Colors.orange
                                                        : _getStatusColor(status),
                                                    shape: BoxShape.circle,
                                                  ),
                                                ),
                                                const SizedBox(width: 12),
                                                Expanded(
                                                  child: Text(
                                                    isProductDeleted 
                                                        ? '$title (Deleted)'
                                                        : title,
                                                    style: TextStyle(
                                                      color: isProductDeleted ? Colors.orange : Colors.white,
                                                      fontSize: 16,
                                                      fontWeight: isRead
                                                          ? FontWeight.normal
                                                          : FontWeight.bold,
                                                    ),
                                                  ),
                                                ),
                                                if (!isRead)
                                                  Container(
                                                    width: 8,
                                                    height: 8,
                                                    decoration: const BoxDecoration(
                                                      color: Colors.red,
                                                      shape: BoxShape.circle,
                                                    ),
                                                  ),
                                              ],
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              isProductDeleted 
                                                  ? 'Product no longer available'
                                                  : message,
                                              style: TextStyle(
                                                color: isProductDeleted ? Colors.orange : Colors.grey[300],
                                                fontSize: 14,
                                              ),
                                              maxLines: 3,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            const SizedBox(height: 8),
                                            Text(
                                              _formatTimestamp(timestamp),
                                              style: TextStyle(
                                                color: Colors.grey[500],
                                                fontSize: 12,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            // Arrow indicator
                                            Row(
                                              mainAxisAlignment: MainAxisAlignment.end,
                                              children: [
                                                Icon(
                                                  Icons.arrow_forward_ios,
                                                  color: Colors.grey[400],
                                                  size: 14,
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }

  Future<void> _checkProductExistence(List<Map<String, dynamic>> notifications) async {
    try {
      final productIds = notifications
          .where((n) => n['productId'] != null && n['productId'].toString().isNotEmpty)
          .map((n) => n['productId'].toString())
          .toSet();

      if (productIds.isEmpty) return;

      print('🔍 Checking existence of ${productIds.length} products...');

      final List<String> deletedIds = [];

      for (String productId in productIds) {
        final doc = await FirebaseFirestore.instanceFor(
          app: Firebase.app(),
          databaseId: 'marketsafe',
        ).collection('products').doc(productId).get();
        if (!doc.exists) {
          deletedIds.add(productId);
        }
      }

      setState(() {
        _deletedProductIds = deletedIds.toSet();
      });

      print('🔍 Found ${deletedIds.length} deleted products: $deletedIds');
    } catch (e) {
      print('❌ Error checking product existence: $e');
    }
  }

  Future<void> _showProductPreview(Map<String, dynamic> notification) async {
    try {
      final productId = notification['productId'];
      print('🔍 Notification productId: $productId');
      print('🔍 Full notification data: $notification');
      
      if (productId == null || productId.isEmpty) {
        _showSnackBar('Product information not available');
        return;
      }

      // Show loading dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(color: Colors.red),
        ),
      );

      print('🔍 Fetching product from Firestore with ID: $productId');
      
      // Try to fetch product with the original ID first
      print('🔍 Using marketsafe database for query...');
      DocumentSnapshot? productDoc = await FirebaseFirestore.instanceFor(
        app: Firebase.app(),
        databaseId: 'marketsafe',
      ).collection('products').doc(productId).get();
      
      print('🔍 Query completed. Document exists: ${productDoc.exists}');
      print('🔍 Document ID: ${productDoc.id}');
      print('🔍 Document data keys: ${(productDoc.data() as Map<String, dynamic>?)?.keys.toList()}');

      print('🔍 Product document exists: ${productDoc.exists}');
      print('🔍 Product document data: ${productDoc.data()}');

      // If product not found and it's a legacy complex ID, try to find by title and seller
      print('🔍 Checking if fallback lookup needed...');
      print('🔍 Product exists: ${productDoc.exists}');
      print('🔍 Product ID contains "_user_": ${productId.contains('_user_')}');
      
      if (!productDoc.exists) {
        print('🔄 Product not found, trying alternative lookup...');
        
        final productTitle = notification['productTitle'] ?? '';
        final userId = notification['userId'] ?? '';
        
        print('🔍 Product title from notification: "$productTitle"');
        print('🔍 User ID from notification: "$userId"');
        
        if (productTitle.isNotEmpty && userId.isNotEmpty) {
          print('🔍 Searching for product by title: "$productTitle" and seller: "$userId"');
          
          // Try to find product by title and seller ID
          final querySnapshot = await FirebaseFirestore.instanceFor(
            app: Firebase.app(),
            databaseId: 'marketsafe',
          ).collection('products')
              .where('title', isEqualTo: productTitle)
              .where('sellerId', isEqualTo: userId)
              .limit(1)
              .get();
          
          print('🔍 Alternative lookup found ${querySnapshot.docs.length} products');
          
          if (querySnapshot.docs.isNotEmpty) {
            productDoc = querySnapshot.docs.first;
            print('✅ Found product using alternative lookup: ${productDoc.id}');
          } else {
            print('❌ No product found with alternative lookup');
            
            // Let's try a broader search to see what products exist for this user
            print('🔍 Trying broader search for this user...');
            final userProductsQuery = await FirebaseFirestore.instanceFor(
              app: Firebase.app(),
              databaseId: 'marketsafe',
            ).collection('products')
                .where('sellerId', isEqualTo: userId)
                .limit(5)
                .get();
            
            print('🔍 Found ${userProductsQuery.docs.length} products for this user:');
            for (var doc in userProductsQuery.docs) {
              final data = doc.data();
              print('  - ID: ${doc.id}');
              print('  - Title: "${data['title']}"');
              print('  - Seller ID: ${data['sellerId']}');
              print('  - Status: ${data['status']}');
              print('  - Moderation Status: ${data['moderationStatus']}');
            }
            
            // Also try to find the product by the exact ID from the notification
            print('🔍 Trying to find product by exact ID: $productId');
            final exactProductDoc = await FirebaseFirestore.instanceFor(
              app: Firebase.app(),
              databaseId: 'marketsafe',
            ).collection('products')
                .doc(productId)
                .get();
            print('🔍 Exact product lookup result: ${exactProductDoc.exists}');
            if (exactProductDoc.exists) {
              final data = exactProductDoc.data()!;
              print('  - Exact product title: "${data['title']}"');
              print('  - Exact product seller: ${data['sellerId']}');
            }
            
            // Also try searching by title only (case insensitive)
            print('🔍 Trying case-insensitive title search...');
            final titleQuery = await FirebaseFirestore.instanceFor(
              app: Firebase.app(),
              databaseId: 'marketsafe',
            ).collection('products')
                .where('title', isEqualTo: productTitle.toLowerCase())
                .limit(3)
                .get();
            
            print('🔍 Case-insensitive title search found ${titleQuery.docs.length} products');
            for (var doc in titleQuery.docs) {
              final data = doc.data();
              print('  - ID: ${doc.id}');
              print('  - Title: "${data['title']}"');
              print('  - Seller ID: ${data['sellerId']}');
            }
          }
        } else {
          print('❌ Missing product title or user ID for alternative lookup');
        }
      } else if (!productDoc.exists) {
        print('❌ Product not found and no fallback available');
      }

      // Close loading dialog
      if (mounted) Navigator.of(context).pop();

      if (!productDoc.exists) {
        // Product no longer exists - show dialog with options
        if (mounted) {
          _showProductNotFoundDialog(notification);
        }
        return;
      }

      final productData = productDoc.data() as Map<String, dynamic>;
      
      // Show product preview dialog
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => _ProductPreviewDialog(
            productData: productData,
            notification: notification,
          ),
        );
      }
    } catch (e) {
      // Close loading dialog if still open
      if (mounted) Navigator.of(context).pop();
      print('❌ Error loading product: $e');
      _showSnackBar('Error loading product: $e');
    }
  }

  void _showProductNotFoundDialog(Map<String, dynamic> notification) {
    final productTitle = notification['productTitle'] ?? 'Unknown Product';
    final status = notification['status'] ?? 'unknown';
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning, color: Colors.orange),
            SizedBox(width: 8),
            Text('Product Not Found'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('The product "$productTitle" is no longer available.'),
            SizedBox(height: 8),
            if (status == 'pending')
              Container(
                padding: EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info, color: Colors.blue, size: 16),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'This appears to be a pending product that was never successfully created or was deleted during processing.',
                        style: TextStyle(color: Colors.blue.shade700, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              )
            else ...[
              Text('This usually happens when:'),
              SizedBox(height: 4),
              Text('• The product was deleted by the seller'),
              Text('• The product was removed by administrators'),
              Text('• The product expired or was automatically removed'),
            ],
            SizedBox(height: 12),
            if (status == 'deleted')
              Container(
                padding: EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info, color: Colors.red, size: 16),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'This product was deleted by administrators.',
                        style: TextStyle(color: Colors.red.shade700, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Close'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _deleteNotification(notification);
            },
            child: Text('Delete Notification', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteNotification(Map<String, dynamic> notification) async {
    try {
      final notificationId = notification['id'];
      if (notificationId != null) {
        print('🗑️ Deleting notification: $notificationId');
        
        // Delete all notifications
        
        // Delete from database
        await NotificationService.deleteNotification(notificationId);
        
        // Remove from local state immediately
        setState(() {
          _notifications.removeWhere((n) => n['id'] == notificationId);
          // Deletion complete
        });
        
        _showSnackBar('Notification deleted');
        print('✅ Notification deleted successfully');
      }
    } catch (e) {
      print('❌ Error deleting notification: $e');
      _showSnackBar('Error deleting notification');
      
      // Error handling complete
    }
  }
}

class _ProductPreviewDialog extends StatelessWidget {
  final Map<String, dynamic> productData;
  final Map<String, dynamic> notification;

  const _ProductPreviewDialog({
    required this.productData,
    required this.notification,
  });

  @override
  Widget build(BuildContext context) {
    final title = productData['title'] ?? 'Untitled Product';
    final description = productData['description'] ?? 'No description';
    final price = productData['price']?.toString() ?? '0';
    final status = notification['status'] ?? 'unknown';
    final rejectionReason = notification['rejectionReason'] ?? '';

    return Dialog(
      backgroundColor: const Color(0xFF1A1A1A),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8,
          maxWidth: MediaQuery.of(context).size.width * 0.9,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                color: Color(0xFF2E0000),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _getStatusIcon(status),
                    color: _getStatusColor(status),
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Product Preview',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          _getStatusText(status),
                          style: TextStyle(
                            color: _getStatusColor(status),
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, color: Colors.white),
                  ),
                ],
              ),
            ),
            
            // Content
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Product Title
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    
                    // Price
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.red),
                      ),
                      child: Text(
                        '₱$price',
                        style: const TextStyle(
                          color: Colors.red,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    
                    // Description
                    const Text(
                      'Description:',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      description,
                      style: const TextStyle(
                        color: Colors.grey,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 16),
                    
                    // Status Information
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: _getStatusColor(status).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _getStatusColor(status),
                          width: 1,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                _getStatusIcon(status),
                                color: _getStatusColor(status),
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                _getStatusText(status),
                                style: TextStyle(
                                  color: _getStatusColor(status),
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          if (status == 'rejected' && rejectionReason.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            const Text(
                              'Rejection Reason:',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              rejectionReason,
                              style: const TextStyle(
                                color: Colors.grey,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'pending':
        return Colors.orange;
      case 'approved':
        return Colors.green;
      case 'rejected':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status) {
      case 'pending':
        return Icons.schedule;
      case 'approved':
        return Icons.check_circle;
      case 'rejected':
        return Icons.cancel;
      default:
        return Icons.info;
    }
  }
  String _getStatusText(String status) {
    switch (status) {
      case 'pending':
        return 'Under Review';
      case 'approved':
        return 'Approved';
      case 'rejected':
        return 'Rejected';
      default:
        return 'Unknown Status';
    }
  }
}
