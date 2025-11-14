import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/follow_service.dart';
import '../services/product_service.dart';
import '../services/report_service.dart';
import '../services/message_service.dart';
import '../models/product_model.dart';
import 'product_preview_screen.dart';
import 'followers_following_screen.dart';
import 'conversation_screen.dart';

class UserProfileViewScreen extends StatefulWidget {
  final String targetUserId;
  final String? targetUsername;

  const UserProfileViewScreen({
    super.key,
    required this.targetUserId,
    this.targetUsername,
  });

  @override
  State<UserProfileViewScreen> createState() => _UserProfileViewScreenState();
}

class _UserProfileViewScreenState extends State<UserProfileViewScreen> {
  Map<String, dynamic>? _userData;
  bool _isLoading = true;
  bool _isFollowing = false;
  bool _isFollowLoading = false;
  Map<String, int> _followCounts = {'followers': 0, 'following': 0};
  List<Product> _userProducts = [];
  bool _isLoadingProducts = false;
  
  // Report dialog state
  final TextEditingController _reportReasonController = TextEditingController();
  String? _selectedReportReason;
  bool _isReporting = false;

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _loadUserProducts();
  }

  Future<void> _loadUserData() async {
    try {
      setState(() {
        _isLoading = true;
      });

      // Get user data
      final userDoc = await FirebaseFirestore.instanceFor(
        app: Firebase.app(),
        databaseId: 'marketsafe',
      ).collection('users').doc(widget.targetUserId).get();

      if (userDoc.exists) {
        setState(() {
          _userData = userDoc.data();
        });

        // Check if current user is following this user
        final isFollowing = await FollowService.isFollowing(widget.targetUserId);
        
        // Get follow counts
        final followCounts = await FollowService.getFollowCounts(widget.targetUserId);

        setState(() {
          _isFollowing = isFollowing;
          _followCounts = followCounts;
        });
      }
    } catch (e) {
      print('❌ Error loading user data: $e');
      _showErrorSnackBar('Failed to load user profile');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _loadUserProducts() async {
    try {
      setState(() {
        _isLoadingProducts = true;
      });

      print('🔍 Loading products for user: ${widget.targetUserId}');
      
      // Fetch user's products
      final allProducts = await ProductService.getUserProducts(widget.targetUserId);
      
      // Filter products: only show approved and active products
      final filteredProducts = allProducts.where((product) {
        return product.moderationStatus == 'approved' && product.status == 'active';
      }).toList();
      
      setState(() {
        _userProducts = filteredProducts;
        _isLoadingProducts = false;
      });
      
      print('✅ Loaded ${filteredProducts.length} approved products for user (${allProducts.length} total)');
    } catch (e) {
      print('❌ Error loading user products: $e');
      setState(() {
        _isLoadingProducts = false;
      });
    }
  }

  Future<void> _toggleFollow() async {
    if (_isFollowLoading) return;

    setState(() {
      _isFollowLoading = true;
    });

    try {
      bool success;
      if (_isFollowing) {
        success = await FollowService.unfollowUser(widget.targetUserId);
        if (success) {
          // Refresh follow counts from database to ensure accuracy
          final followCounts = await FollowService.getFollowCounts(widget.targetUserId);
          setState(() {
            _isFollowing = false;
            _followCounts = followCounts;
          });
          _showSuccessSnackBar('Unfollowed ${_userData?['username'] ?? 'user'}');
        }
      } else {
        success = await FollowService.followUser(widget.targetUserId);
        if (success) {
          // Refresh follow counts from database to ensure accuracy
          final followCounts = await FollowService.getFollowCounts(widget.targetUserId);
          setState(() {
            _isFollowing = true;
            _followCounts = followCounts;
          });
          _showSuccessSnackBar('Following ${_userData?['username'] ?? 'user'}');
        }
      }

      if (!success) {
        _showErrorSnackBar('Failed to ${_isFollowing ? 'unfollow' : 'follow'} user');
      }
    } catch (e) {
      print('❌ Error toggling follow: $e');
      _showErrorSnackBar('An error occurred');
    } finally {
      setState(() {
        _isFollowLoading = false;
      });
    }
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  String _getDisplayName() {
    if (_userData == null) return "NAME";
    
    // Try to get full name first, then fallback to individual fields
    final fullName = _userData!['fullName'] ?? '';
    if (fullName.isNotEmpty) return fullName.toUpperCase();
    
    final firstName = _userData!['firstName'] ?? '';
    final lastName = _userData!['lastName'] ?? '';
    if (firstName.isNotEmpty || lastName.isNotEmpty) {
      return '${firstName.toUpperCase()} ${lastName.toUpperCase()}'.trim();
    }
    
    final username = _userData!['username'] ?? '';
    if (username.isNotEmpty) return username.toUpperCase();
    
    return "NAME";
  }

  String _getUsername() {
    if (_userData == null) return "@username";
    
    final username = _userData!['username'] ?? '';
    if (username.isNotEmpty) return '@${username.toLowerCase()}';
    
    return "@username";
  }

  Widget _buildStatItem(String number, String label, bool? isFollowers) {
    Widget content = Column(
      children: [
        Text(
          number,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
          ),
        ),
      ],
    );

    // Make followers and following clickable
    if (isFollowers != null && widget.targetUserId.isNotEmpty) {
      return GestureDetector(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => FollowersFollowingScreen(
                userId: widget.targetUserId,
                username: _getUsername(),
                isFollowers: isFollowers,
              ),
            ),
          );
        },
        child: content,
      );
    }

    return content;
  }

  Widget _buildFollowButton() {
    return GestureDetector(
      onTap: _isFollowLoading ? null : _toggleFollow,
      child: Container(
        height: 40,
        decoration: BoxDecoration(
          color: _isFollowing ? Colors.transparent : Colors.red,
          border: Border.all(
            color: _isFollowing ? Colors.white : Colors.red,
            width: 1,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: _isFollowLoading
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                )
              : Text(
                  _isFollowing ? 'Following' : 'Follow',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildMessageButton() {
    return GestureDetector(
      onTap: _navigateToMessage,
      child: Container(
        height: 40,
        decoration: BoxDecoration(
          color: Colors.red,
          border: Border.all(
            color: Colors.red,
            width: 1,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Center(
          child: Text(
            'Message',
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _navigateToMessage() async {
    try {
      // Get current user ID
      final prefs = await SharedPreferences.getInstance();
      final currentUserId = prefs.getString('signup_user_id') ?? 
                            prefs.getString('current_user_id') ?? '';
      
      if (currentUserId.isEmpty) {
        _showErrorSnackBar('Unable to identify current user');
        return;
      }

      // Don't allow messaging yourself
      if (currentUserId == widget.targetUserId) {
        _showErrorSnackBar('You cannot message yourself');
        return;
      }

      // Show loading indicator
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(color: Colors.red),
        ),
      );

      // Get or create conversation
      final conversationId = await MessageService.getOrCreateConversation(
        currentUserId,
        widget.targetUserId,
      );

      // Get other user data
      final otherUser = {
        'userId': widget.targetUserId,
        'username': _userData?['username'] ?? widget.targetUsername ?? 'User',
        'profilePictureUrl': _userData?['profilePictureUrl'],
        'email': _userData?['email'],
      };

      // Close loading dialog
      if (mounted) Navigator.of(context).pop();

      // Navigate to conversation screen
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ConversationScreen(
              conversationId: conversationId,
              otherUser: otherUser,
              currentUserId: currentUserId,
            ),
          ),
        );
      }
    } catch (e) {
      // Close loading dialog if still open
      if (mounted) Navigator.of(context).pop();
      print('❌ Error navigating to message: $e');
      _showErrorSnackBar('Failed to open conversation: $e');
    }
  }

  Widget _buildProfileImage() {
    final profilePhotoUrl = _userData?['profilePictureUrl'];
    
    Widget imageWidget;
    if (profilePhotoUrl != null && profilePhotoUrl.toString().isNotEmpty) {
      imageWidget = CircleAvatar(
        radius: 60,
        backgroundColor: Colors.grey[800],
        backgroundImage: NetworkImage(profilePhotoUrl),
      );
    } else {
      imageWidget = CircleAvatar(
        radius: 60,
        backgroundColor: Colors.grey[800],
        child: const Icon(
          Icons.person,
          size: 60,
          color: Colors.white,
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: Colors.white.withOpacity(0.3),
          width: 2,
        ),
      ),
      child: imageWidget,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: const Color(0xFF2B0000),
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
          title: Text(
            _userData?['username'] ?? 'User Profile',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.more_vert, color: Colors.white),
              onPressed: () {
                _showMoreOptions();
              },
            ),
          ],
        ),
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Color(0xFF0A0A0A),
                Color(0xFF1A0000),
                Color(0xFF2B0000),
              ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: [0.0, 0.5, 1.0],
            ),
          ),
          child: _isLoading
              ? const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                )
              : _userData == null
                  ? const Center(
                      child: Text(
                        'User not found',
                        style: TextStyle(color: Colors.white, fontSize: 18),
                      ),
                    )
                  : SingleChildScrollView(
                      child: Column(
                        children: [
                          // Profile Information Section
                          Container(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              children: [
                                // Profile Picture - Centered and Clean
                                Center(
                                  child: _buildProfileImage(),
                                ),
                                const SizedBox(height: 20),
                                // User Details - Centered
                                Center(
                                  child: Column(
                                    children: [
                                      Text(
                                        _getDisplayName(),
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 24,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        _getUsername(),
                                        style: const TextStyle(
                                          color: Colors.grey,
                                          fontSize: 16,
                                          fontWeight: FontWeight.normal,
                                        ),
                                      ),
                                      const SizedBox(height: 20),
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          _buildStatItem(_userProducts.length.toString(), "posts", null),
                                          const SizedBox(width: 30),
                                          _buildStatItem(_followCounts['followers'].toString(), "followers", true),
                                          const SizedBox(width: 30),
                                          _buildStatItem(_followCounts['following'].toString(), "following", false),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 20),
                                // Follow and Message Buttons
                                Row(
                                  children: [
                                    Expanded(
                                      child: _buildFollowButton(),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: _buildMessageButton(),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          // Content Display Area
                          Container(
                            child: Column(
                              children: [
                                // Content Type Selector
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 20),
                                  child: Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(8),
                                        child: Column(
                                          children: [
                                            const Icon(
                                              Icons.grid_on,
                                              color: Colors.white,
                                              size: 24,
                                            ),
                                            const SizedBox(height: 4),
                                            Container(
                                              width: 40,
                                              height: 2,
                                              color: Colors.white,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                // Products Grid
                                _isLoadingProducts
                                    ? const Padding(
                                        padding: EdgeInsets.all(40),
                                        child: CircularProgressIndicator(color: Colors.white),
                                      )
                                    : _userProducts.isEmpty
                                        ? Padding(
                                            padding: const EdgeInsets.all(40),
                                            child: Text(
                                              'No posts yet',
                                              style: TextStyle(
                                                color: Colors.white.withOpacity(0.5),
                                                fontSize: 16,
                                              ),
                                            ),
                                          )
                                        : GridView.builder(
                                            shrinkWrap: true,
                                            physics: const NeverScrollableScrollPhysics(),
                                            padding: const EdgeInsets.all(16),
                                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                              crossAxisCount: 3,
                                              crossAxisSpacing: 2,
                                              mainAxisSpacing: 2,
                                              childAspectRatio: 1,
                                            ),
                                            itemCount: _userProducts.length,
                                            itemBuilder: (context, index) {
                                              final product = _userProducts[index];
                                              return GestureDetector(
                                                onTap: () async {
                                                  // Get current user ID
                                                  final prefs = await SharedPreferences.getInstance();
                                                  final currentUserId = prefs.getString('signup_user_id') ?? 
                                                                      prefs.getString('current_user_id') ?? '';
                                                  
                                                  // Convert Product to Map format expected by ProductPreviewScreen
                                                  final productMap = {
                                                    'id': product.id,
                                                    'title': product.title,
                                                    'price': product.price.toString(),
                                                    'description': product.description,
                                                    'details': product.description,
                                                    'date': _formatProductDate(product.createdAt),
                                                    'userId': product.sellerId,
                                                    'sellerName': product.sellerName,
                                                    'imageUrls': product.imageUrls.isNotEmpty 
                                                        ? product.imageUrls 
                                                        : (product.imageUrl.isNotEmpty ? [product.imageUrl] : []),
                                                    'videoUrl': product.videoUrl,
                                                    'videoThumbnailUrl': product.videoThumbnailUrl,
                                                    'mediaType': product.mediaType,
                                                  };
                                                  
                                                  Navigator.push(
                                                    context,
                                                    MaterialPageRoute(
                                                      builder: (context) => ProductPreviewScreen(
                                                        product: productMap,
                                                        currentUserId: currentUserId,
                                                      ),
                                                    ),
                                                  );
                                                },
                                                child: Container(
                                                  decoration: BoxDecoration(
                                                    color: Colors.grey[900],
                                                    image: product.imageUrls.isNotEmpty
                                                        ? DecorationImage(
                                                            image: NetworkImage(product.imageUrls[0]),
                                                            fit: BoxFit.cover,
                                                          )
                                                        : (product.imageUrl.isNotEmpty
                                                            ? DecorationImage(
                                                                image: NetworkImage(product.imageUrl),
                                                                fit: BoxFit.cover,
                                                              )
                                                            : null),
                                                  ),
                                                  child: product.imageUrls.isEmpty && product.imageUrl.isEmpty
                                                      ? const Center(
                                                          child: Icon(
                                                            Icons.image,
                                                            color: Colors.grey,
                                                          ),
                                                        )
                                                      : null,
                                                ),
                                              );
                                            },
                                          ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
        ),
      ),
    );
  }

  void _showMoreOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.report, color: Colors.red),
              title: const Text('Report User', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                _showReportDialog();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showReportDialog() {
    _selectedReportReason = null;
    _reportReasonController.clear();
    
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: Colors.grey[900],
          title: const Text('Report User', style: TextStyle(color: Colors.white)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Why are you reporting this user?',
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                ),
                const SizedBox(height: 16),
                // Predefined reasons
                _buildReportOption(
                  'Inappropriate Content',
                  'inappropriate_content',
                  _selectedReportReason,
                  (value) => setDialogState(() => _selectedReportReason = value),
                ),
                _buildReportOption(
                  'Spam or Scam',
                  'spam_scam',
                  _selectedReportReason,
                  (value) => setDialogState(() => _selectedReportReason = value),
                ),
                _buildReportOption(
                  'Harassment or Bullying',
                  'harassment',
                  _selectedReportReason,
                  (value) => setDialogState(() => _selectedReportReason = value),
                ),
                _buildReportOption(
                  'Fake Account',
                  'fake_account',
                  _selectedReportReason,
                  (value) => setDialogState(() => _selectedReportReason = value),
                ),
                _buildReportOption(
                  'Selling Prohibited Items',
                  'prohibited_items',
                  _selectedReportReason,
                  (value) => setDialogState(() => _selectedReportReason = value),
                ),
                _buildReportOption(
                  'Other',
                  'other',
                  _selectedReportReason,
                  (value) => setDialogState(() => _selectedReportReason = value),
                ),
                const SizedBox(height: 16),
                // Custom reason text field
                if (_selectedReportReason == 'other' || _selectedReportReason != null)
                  TextField(
                    controller: _reportReasonController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Please provide more details...',
                      hintStyle: TextStyle(color: Colors.grey[600]),
                      filled: true,
                      fillColor: Colors.grey[800],
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.all(12),
                    ),
                    maxLines: 3,
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: _isReporting ? null : () {
                Navigator.pop(context);
                _selectedReportReason = null;
                _reportReasonController.clear();
              },
              child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
            ),
            TextButton(
              onPressed: _isReporting ? null : () async {
                if (_selectedReportReason == null) {
                  _showErrorSnackBar('Please select a reason');
                  return;
                }
                
                if (_selectedReportReason == 'other' && _reportReasonController.text.trim().isEmpty) {
                  _showErrorSnackBar('Please provide details for your report');
                  return;
                }
                
                setDialogState(() => _isReporting = true);
                
                final success = await ReportService.reportUser(
                  reportedUserId: widget.targetUserId,
                  reason: _selectedReportReason!,
                  customReason: _reportReasonController.text.trim(),
                );
                
                if (mounted) {
                  Navigator.pop(context);
                  _selectedReportReason = null;
                  _reportReasonController.clear();
                  
                  if (success) {
                    _showSuccessSnackBar('User reported successfully. Admin will review your report.');
                  } else {
                    _showErrorSnackBar('Failed to submit report. Please try again.');
                  }
                }
                
                setDialogState(() => _isReporting = false);
              },
              child: _isReporting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.red,
                      ),
                    )
                  : const Text('Submit Report', style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReportOption(String label, String value, String? selected, Function(String?) onChanged) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () => onChanged(value),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: selected == value ? Colors.red.withOpacity(0.2) : Colors.grey[800],
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected == value ? Colors.red : Colors.transparent,
              width: 2,
            ),
          ),
          child: Row(
            children: [
              Icon(
                selected == value ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                color: selected == value ? Colors.red : Colors.grey[400],
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: selected == value ? Colors.white : Colors.grey[300],
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _reportReasonController.dispose();
    super.dispose();
  }

  String _formatProductDate(DateTime? date) {
    if (date == null) return '';
    final now = DateTime.now();
    final difference = now.difference(date);
    
    if (difference.inDays == 0) {
      if (difference.inHours == 0) {
        if (difference.inMinutes == 0) {
          return 'Just now';
        }
        return '${difference.inMinutes}m ago';
      }
      return '${difference.inHours}h ago';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    } else if (difference.inDays < 30) {
      return '${(difference.inDays / 7).floor()}w ago';
    } else if (difference.inDays < 365) {
      return '${(difference.inDays / 30).floor()}mo ago';
    } else {
      return '${(difference.inDays / 365).floor()}y ago';
    }
  }
}
