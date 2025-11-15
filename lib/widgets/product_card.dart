import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import '../models/product_model.dart';
import '../screens/edit_product_screen.dart';
import '../screens/product_preview_screen.dart';
import '../screens/user_profile_view_screen.dart' as profile_screen;
import '../services/product_service.dart';
import '../services/comment_service.dart';
import '../services/follow_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'image_swiper.dart';
import '../services/media_download_service.dart';

class ProductCard extends StatefulWidget {
  final Product product;
  final VoidCallback onRefresh;
  final double selectedMin;
  final double selectedMax;

  const ProductCard({
    super.key,
    required this.product,
    required this.onRefresh,
    required this.selectedMin,
    required this.selectedMax,
  });

  @override
  State<ProductCard> createState() => _ProductCardState();
}

class _ProductCardState extends State<ProductCard> with WidgetsBindingObserver {
  late Product _currentProduct;
  String? _currentUserId;
  bool _isLiking = false;
  bool _isFollowing = false;
  bool _isFollowLoading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _currentProduct = widget.product;
    _debugSharedPreferences();
    _debugProductInfo();
    _initializeUserAndFollowStatus();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // Refresh follow status when app comes back to foreground
    if (state == AppLifecycleState.resumed) {
      _checkFollowStatus();
    }
  }

  @override
  void didUpdateWidget(ProductCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If product changed, update and refresh follow status
    if (oldWidget.product.id != widget.product.id) {
      _currentProduct = widget.product;
      _initializeUserAndFollowStatus();
    } else {
      // Even if product is the same, refresh follow status to ensure accuracy
      _checkFollowStatus();
    }
  }

  Future<void> _initializeUserAndFollowStatus() async {
    await _getCurrentUserId();
    // Check follow status after user ID is retrieved
    _checkFollowStatus();
  }

  // Debug method to check product info on widget init
  void _debugProductInfo() {
    print('🔍 ProductCard init - Product info:');
    print('  - Product ID: ${_currentProduct.id}');
    print('  - Product Title: ${_currentProduct.title}');
    print('  - Seller ID: ${_currentProduct.sellerId}');
    print('  - Seller Name: ${_currentProduct.sellerName}');
    print('  - Seller Profile Picture URL: ${_currentProduct.sellerProfilePictureUrl}');
    print('  - Profile Picture URL is null: ${_currentProduct.sellerProfilePictureUrl == null}');
    print('  - Profile Picture URL is empty: ${_currentProduct.sellerProfilePictureUrl?.isEmpty ?? true}');
    
    // Check if this is the current user's product
    _checkIfCurrentUserProduct();
  }

  // Check if this is the current user's product and debug their profile picture
  Future<void> _checkIfCurrentUserProduct() async {
    final prefs = await SharedPreferences.getInstance();
    final currentUserId = prefs.getString('current_user_id') ?? prefs.getString('signup_user_id');
    
    if (_currentProduct.sellerId == currentUserId) {
      print('🔍 This is current user\'s product - debugging profile picture:');
      print('  - Current user ID: $currentUserId');
      print('  - Profile photo URL from SharedPreferences: ${prefs.getString('profile_photo_url')}');
      print('  - Current user profile picture from SharedPreferences: ${prefs.getString('current_user_profile_picture')}');
      print('  - Signup user profile picture from SharedPreferences: ${prefs.getString('signup_user_profile_picture')}');
    }
  }

  // Debug method to check SharedPreferences on widget init
  Future<void> _debugSharedPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    print('🔍 ProductCard init - All SharedPreferences:');
    final allKeys = prefs.getKeys();
    for (String key in allKeys) {
      print('  - $key: ${prefs.getString(key)}');
    }
  }

  Future<String?> _getCurrentUserId() async {
    final prefs = await SharedPreferences.getInstance();
    final currentUserId = prefs.getString('current_user_id');
    final signupUserId = prefs.getString('signup_user_id');
    final userId = currentUserId ?? signupUserId;
    
    print('🔍 ProductCard: Getting current user ID:');
    print('  - current_user_id: $currentUserId');
    print('  - signup_user_id: $signupUserId');
    print('  - Final userId: $userId');
    
    setState(() {
      _currentUserId = userId;
    });
    return userId;
  }

  Future<String> _getCurrentUserName() async {
    final prefs = await SharedPreferences.getInstance();
    final currentUserName = prefs.getString('current_user_name');
    final signupUserName = prefs.getString('signup_user_name');
    
    print('🔍 Getting username:');
    print('  - current_user_name: $currentUserName');
    print('  - signup_user_name: $signupUserName');
    
    // If we have a username in SharedPreferences, use it
    if (currentUserName != null || signupUserName != null) {
      final username = currentUserName ?? signupUserName ?? 'Anonymous';
      print('  - Final username from SharedPreferences: $username');
      return username;
    }
    
    // If no username in SharedPreferences, try to get it from Firestore
    final userId = prefs.getString('current_user_id') ?? prefs.getString('signup_user_id');
    if (userId != null) {
      print('  - No username in SharedPreferences, fetching from Firestore for user: $userId');
      try {
        final userData = await ProductService.getUserData(userId);
        if (userData != null && userData['username'] != null) {
          final username = userData['username'];
          print('  - Found username in Firestore: $username');
          // Store it in SharedPreferences for future use
          await prefs.setString('current_user_name', username);
          return username;
        }
      } catch (e) {
        print('  - Error fetching username from Firestore: $e');
      }
    }
    
    print('  - Final username: Anonymous (fallback)');
    return 'Anonymous';
  }

  // Follow functionality methods
  Future<void> _checkFollowStatus() async {
    if (_currentUserId == null || _currentUserId == _currentProduct.sellerId) return;
    
    try {
      final isFollowing = await FollowService.isFollowing(_currentProduct.sellerId);
      if (mounted) {
        setState(() {
          _isFollowing = isFollowing;
        });
      }
    } catch (e) {
      print('❌ Error checking follow status: $e');
    }
  }

  Future<void> _toggleFollow() async {
    if (_isFollowLoading || _currentUserId == null || _currentUserId == _currentProduct.sellerId) return;

    setState(() {
      _isFollowLoading = true;
    });

    try {
      bool success;
      if (_isFollowing) {
        success = await FollowService.unfollowUser(_currentProduct.sellerId);
        if (success) {
          setState(() {
            _isFollowing = false;
          });
          _showSuccessSnackBar('Unfollowed ${_currentProduct.sellerName}');
        }
      } else {
        success = await FollowService.followUser(_currentProduct.sellerId);
        if (success) {
          setState(() {
            _isFollowing = true;
          });
          _showSuccessSnackBar('Following ${_currentProduct.sellerName}');
        }
      }

      if (!success) {
        _showErrorSnackBar('Failed to ${_isFollowing ? 'unfollow' : 'follow'} user');
      }
    } catch (e) {
      print('❌ Error toggling follow: $e');
      _showErrorSnackBar('An error occurred');
    } finally {
      if (mounted) {
        setState(() {
          _isFollowLoading = false;
        });
      }
    }
  }

  void _navigateToUserProfile() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => profile_screen.UserProfileViewScreen(
          targetUserId: _currentProduct.sellerId,
          targetUsername: _currentProduct.sellerName,
        ),
      ),
    );
  }


  void _handleDownload() {
    // Check if product has video
    if (_currentProduct.mediaType == 'video' && 
        _currentProduct.videoUrl != null && 
        _currentProduct.videoUrl!.isNotEmpty) {
      // Download video
      MediaDownloadService.showDownloadDialog(
        context: context,
        mediaUrl: _currentProduct.videoUrl!,
        productTitle: _currentProduct.title,
        isVideo: true,
        productId: _currentProduct.id,
      );
    } 
    // Check if product has images
    else if (_currentProduct.imageUrls.isNotEmpty) {
      // Download first image
      MediaDownloadService.showDownloadDialog(
        context: context,
        mediaUrl: _currentProduct.imageUrls[0],
        productTitle: _currentProduct.title,
        isVideo: false,
        productId: _currentProduct.id,
      );
    } 
    // No media available
    else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No media available to download'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Future<int> _getTotalCommentCount() async {
    try {
      // Get count from CommentService (includes replies)
      final newCommentCount = await CommentService.getCommentCount(_currentProduct.id);
      // Get count from old comments
      final oldCommentCount = _currentProduct.comments.length;
      // Total = new comments (which includes replies) + old comments
      return newCommentCount + oldCommentCount;
    } catch (e) {
      print('❌ Error getting comment count: $e');
      return _currentProduct.comments.length;
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

  Future<String> _getCurrentUserProfilePicture() async {
    final prefs = await SharedPreferences.getInstance();
    
    // Priority 1: Check SharedPreferences for profile photo URL
    final profilePhotoUrl = prefs.getString('profile_photo_url');
    if (profilePhotoUrl != null && profilePhotoUrl.isNotEmpty) {
      return profilePhotoUrl;
    }
    
    // Priority 2: Check other SharedPreferences keys
    final currentUserProfilePicture = prefs.getString('current_user_profile_picture');
    final signupUserProfilePicture = prefs.getString('signup_user_profile_picture');
    
    if (currentUserProfilePicture != null && currentUserProfilePicture.isNotEmpty) {
      return currentUserProfilePicture;
    }
    
    if (signupUserProfilePicture != null && signupUserProfilePicture.isNotEmpty) {
      return signupUserProfilePicture;
    }
    
    // Priority 3: Fetch from Firestore
    final userId = prefs.getString('current_user_id') ?? prefs.getString('signup_user_id');
    if (userId != null) {
      try {
        final userData = await ProductService.getUserData(userId);
        if (userData != null && userData['profilePictureUrl'] != null) {
          final profilePicture = userData['profilePictureUrl'];
          // Store it in SharedPreferences for future use
          await prefs.setString('profile_photo_url', profilePicture);
          return profilePicture;
        }
      } catch (e) {
        // Silent fail - return empty string
      }
    }
    
    return '';
  }


  Future<void> _toggleLike() async {
    if (_currentUserId == null || _isLiking) return;
    
    setState(() {
      _isLiking = true;
    });

    try {
      final success = await ProductService.toggleLike(_currentProduct.id, _currentUserId!);
      if (success) {
        // Refresh the product data
        final updatedProduct = await ProductService.getProductById(_currentProduct.id);
        if (updatedProduct != null) {
          setState(() {
            _currentProduct = updatedProduct;
          });
        }
      }
    } catch (e) {
      print('Error toggling like: $e');
    } finally {
      setState(() {
        _isLiking = false;
      });
    }
  }

  void _showCommentsDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A0000),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => _CommentsDialog(
        product: _currentProduct,
        currentUserId: _currentUserId,
        getCurrentUserName: _getCurrentUserName,
        getCurrentUserProfilePicture: _getCurrentUserProfilePicture,
        onCommentAdded: (updatedProduct) {
          setState(() {
            _currentProduct = updatedProduct;
          });
        },
      ),
    );
  }

  void _showProductMenu(BuildContext context, Product product) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A0000),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 4,
              width: 40,
              decoration: BoxDecoration(
                color: Colors.white30,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.edit, color: Colors.white),
              title: const Text(
                'Edit Product',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () {
                Navigator.pop(context);
                _editProduct(context, product);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text(
                'Delete Product',
                style: TextStyle(color: Colors.red),
              ),
              onTap: () {
                Navigator.pop(context);
                _deleteProduct(context, product);
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  void _editProduct(BuildContext context, Product product) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EditProductScreen(product: product),
      ),
    ).then((_) {
      // Refresh products after editing
      widget.onRefresh();
    });
  }

  void _deleteProduct(BuildContext context, Product product) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A0000),
        title: const Text(
          'Delete Product',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          'Are you sure you want to delete "${product.title}"? This action cannot be undone.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white70),
            ),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await _confirmDelete(product);
            },
            child: const Text(
              'Delete',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(Product product) async {
    try {
      final success = await ProductService.deleteProduct(product.id);
      
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Product deleted successfully'),
            backgroundColor: Colors.green,
          ),
        );
        // Refresh the product list
        widget.onRefresh();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to delete product'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // Navigate to product preview screen
  void _navigateToProductPreview() async {
    // Get current user ID directly if not available
    String? userId = _currentUserId;
    if (userId == null || userId.isEmpty) {
      print('🔍 ProductCard: _currentUserId is null/empty, fetching directly...');
      userId = await _getCurrentUserId();
      print('🔍 ProductCard: Direct fetch result: $userId');
    }
    
    if (userId == null || userId.isEmpty) {
      print('❌ ProductCard: Current user ID is null or empty, cannot navigate to product preview');
      print('  - _currentUserId: $_currentUserId');
      print('  - Direct fetch result: $userId');
      return;
    }
    
    print('🔍 ProductCard: Navigating to product preview');
    print('  - Current User ID: $userId');
    print('  - Product ID: ${_currentProduct.id}');
    print('  - Seller ID: ${_currentProduct.sellerId}');
    
    // Convert Product to Map for ProductPreviewScreen
    final productMap = {
      'id': _currentProduct.id,
      'title': _currentProduct.title,
      'price': _currentProduct.price.toString(),
      'description': _currentProduct.description,
      'details': _currentProduct.description,
      'date': _formatProductDate(_currentProduct.createdAt),
      'userId': _currentProduct.sellerId,
      'sellerName': _currentProduct.sellerName,
      'imageUrls': _currentProduct.imageUrls,
      'videoUrl': _currentProduct.videoUrl,
      'videoThumbnailUrl': _currentProduct.videoThumbnailUrl,
      'mediaType': _currentProduct.mediaType,
    };
    
    print('  - Product Map: $productMap');
    
    print('🔍 ProductCard: About to navigate to ProductPreviewScreen');
    print('  - Passing currentUserId: $userId');
    
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ProductPreviewScreen(
          product: productMap,
          currentUserId: userId!,
        ),
      ),
    );
  }

  // Format date for product display
  String _formatProductDate(DateTime? date) {
    if (date == null) return 'Unknown Date';
    
    final months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    
    return '${months[date.month - 1]} ${date.day} ${date.year}';
  }

  // Show video player dialog
  void _showVideoPlayer() {
    if (_currentProduct.videoUrl == null || _currentProduct.videoUrl!.isEmpty) {
      return;
    }
    
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => _VideoPlayerDialog(
        videoUrl: _currentProduct.videoUrl!,
        productTitle: _currentProduct.title,
      ),
    );
  }

  // Build media display based on product type
  Widget _buildMediaDisplay() {
    // If it's a video product, show video thumbnail
    if (_currentProduct.mediaType == 'video' && 
        _currentProduct.videoThumbnailUrl != null && 
        _currentProduct.videoThumbnailUrl!.isNotEmpty) {
      return Container(
        height: 300,
        width: double.infinity,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                _currentProduct.videoThumbnailUrl!,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    color: Colors.black,
                    child: const Center(
                      child: Icon(Icons.video_library, color: Colors.white54, size: 50),
                    ),
                  );
                },
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  );
                },
              ),
            ),
            // Video play button overlay
            Center(
              child: GestureDetector(
                onTap: () => _showVideoPlayer(),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.6),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.play_arrow,
                    color: Colors.white,
                    size: 48,
                  ),
                ),
              ),
            ),
            // Video badge
            Positioned(
              top: 8,
              right: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.red,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'VIDEO',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }
    
    // For image products, use ImageSwiper
    return ImageSwiper(
      imageUrls: _currentProduct.imageUrls.isNotEmpty 
          ? _currentProduct.imageUrls 
          : (_currentProduct.imageUrl.isNotEmpty
              ? [_currentProduct.imageUrl]
              : []),
      height: 300,
      showDots: true,
      showCounter: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isInPriceRange = _currentProduct.price >= widget.selectedMin && 
                          _currentProduct.price <= widget.selectedMax;
    
    print('🔍 ProductCard: ${_currentProduct.title} - Price: ${_currentProduct.price}, Range: ${widget.selectedMin}-${widget.selectedMax}, InRange: $isInPriceRange');
    
    if (!isInPriceRange) {
      print('❌ ProductCard: ${_currentProduct.title} filtered out due to price range');
      return const SizedBox.shrink();
    }
    
    return FutureBuilder<String?>(
      future: _getCurrentUserId(),
      builder: (context, snapshot) {
        final currentUserId = snapshot.data;
        final isOwner = currentUserId == _currentProduct.sellerId;
        
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          color: const Color(0xFF1A0000),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ListTile(
                leading: GestureDetector(
                  onTap: isOwner ? null : _navigateToUserProfile,
                  child: CircleAvatar(
                    radius: 20,
                    backgroundColor: Colors.white24,
                    backgroundImage: (_currentProduct.sellerProfilePictureUrl != null && 
                                    _currentProduct.sellerProfilePictureUrl!.isNotEmpty)
                        ? NetworkImage(_currentProduct.sellerProfilePictureUrl!)
                        : null,
                    child: (_currentProduct.sellerProfilePictureUrl == null || 
                           _currentProduct.sellerProfilePictureUrl!.isEmpty)
                        ? Text(
                            _currentProduct.sellerName.isNotEmpty 
                                ? _currentProduct.sellerName[0].toUpperCase()
                                : 'U',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          )
                        : null,
                  ),
                ),
                title: GestureDetector(
                  onTap: isOwner ? null : _navigateToUserProfile,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _currentProduct.sellerName.isNotEmpty 
                            ? _currentProduct.sellerName 
                            : 'Unknown Seller',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                      ),
                      if (_currentProduct.sellerUsername != null && _currentProduct.sellerUsername!.isNotEmpty)
                        Text(
                          '@${_currentProduct.sellerUsername}',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.7),
                            fontSize: 12,
                            fontWeight: FontWeight.normal,
                          ),
                        ),
                    ],
                  ),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isOwner) ...[
                      IconButton(
                        icon: const Icon(
                          Icons.more_vert,
                          color: Colors.white,
                        ),
                        onPressed: () => _showProductMenu(context, _currentProduct),
                      ),
                    ] else ...[
                      // Follow Button
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _isFollowing ? Colors.grey[800] : Colors.red,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          minimumSize: const Size(80, 32),
                        ),
                        onPressed: _isFollowLoading ? null : _toggleFollow,
                        child: _isFollowLoading
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(_isFollowing ? 'Following' : 'Follow'),
                      ),
                      const SizedBox(width: 8),
                      // Three-dot menu for buyers
                      PopupMenuButton<String>(
                        icon: const Icon(Icons.more_vert, color: Colors.white),
                        color: Colors.grey[900],
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        onSelected: (value) {
                          if (value == 'download') {
                            _handleDownload();
                          }
                        },
                        itemBuilder: (BuildContext context) => [
                          PopupMenuItem<String>(
                            value: 'download',
                            child: Row(
                              children: [
                                const Icon(Icons.download, color: Colors.white, size: 20),
                                const SizedBox(width: 12),
                                Text(
                                  'Download photo',
                                  style: TextStyle(
                                    color: Colors.grey[300],
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12.0),
                child: Text(
                  _currentProduct.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12.0),
                child: Text(
                  "₱${_currentProduct.price.toStringAsFixed(0)}",
                  style: const TextStyle(
                      color: Colors.greenAccent,
                      fontSize: 16,
                      fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 8),
              // Use ImageSwiper for images and separate video widget
              _buildMediaDisplay(),
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12.0, vertical: 8.0),
                child: Row(
                  children: [
                    IconButton(
                      icon: Icon(
                        _currentProduct.likedBy.contains(_currentUserId) 
                            ? Icons.favorite 
                            : Icons.favorite_border,
                        color: _currentProduct.likedBy.contains(_currentUserId) 
                            ? Colors.red 
                            : Colors.white,
                      ),
                      onPressed: _isLiking ? null : _toggleLike,
                    ),
                    Text(
                      "${_currentProduct.likedBy.length}",
                      style: const TextStyle(color: Colors.white),
                    ),
                    const SizedBox(width: 10),
                    IconButton(
                      icon: const Icon(Icons.mode_comment_outlined, color: Colors.white),
                      onPressed: _showCommentsDialog,
                    ),
                    FutureBuilder<int>(
                      future: _getTotalCommentCount(),
                      builder: (context, snapshot) {
                        final count = snapshot.data ?? _currentProduct.comments.length;
                        return Text(
                          "$count",
                          style: const TextStyle(color: Colors.white),
                        );
                      },
                    ),
                    const Spacer(),
                    // Only show Make Offer button for buyers (not sellers)
                    if (!isOwner)
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white54),
                        ),
                        onPressed: () => _navigateToProductPreview(),
                        child: const Text("MAKE OFFER"),
                      ),
                    if (!isOwner) const SizedBox(width: 10),
                    IconButton(
                      icon: const Icon(Icons.bookmark_border, color: Colors.white),
                      onPressed: () {},
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12.0),
                child: _DescriptionText(
                  text: _currentProduct.description,
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }
}

class _DescriptionText extends StatefulWidget {
  final String text;

  const _DescriptionText({required this.text});

  @override
  State<_DescriptionText> createState() => _DescriptionTextState();
}

class _DescriptionTextState extends State<_DescriptionText> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.text,
          style: const TextStyle(color: Colors.white70),
          maxLines: _isExpanded ? null : 2,
          overflow: _isExpanded ? null : TextOverflow.ellipsis,
        ),
        if (widget.text.length > 100) // Only show "See more" if text is long enough
          GestureDetector(
            onTap: () {
              setState(() {
                _isExpanded = !_isExpanded;
              });
            },
            child: Text(
              _isExpanded ? "See less" : "See more",
              style: const TextStyle(
                color: Colors.red,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
      ],
    );
  }
}

class _CommentsDialog extends StatefulWidget {
  final Product product;
  final String? currentUserId;
  final Future<String> Function() getCurrentUserName;
  final Future<String> Function() getCurrentUserProfilePicture;
  final Function(Product) onCommentAdded;

  const _CommentsDialog({
    required this.product,
    required this.currentUserId,
    required this.getCurrentUserName,
    required this.getCurrentUserProfilePicture,
    required this.onCommentAdded,
  });

  @override
  State<_CommentsDialog> createState() => _CommentsDialogState();
}

class _CommentsDialogState extends State<_CommentsDialog> {
  final TextEditingController _commentController = TextEditingController();
  late Product _currentProduct;
  bool _isAddingComment = false;
  List<Map<String, dynamic>> _comments = [];
  bool _isLoadingComments = true;
  Map<String, TextEditingController> _replyControllers = {};
  Map<String, bool> _showReplyInput = {};
  Map<String, bool> _showReplies = {};
  Map<String, bool> _isReplying = {};
  String? _currentUserId;

  @override
  void initState() {
    super.initState();
    _currentProduct = widget.product;
    _loadCurrentUserId();
    _loadComments();
  }
  
  Future<void> _loadCurrentUserId() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _currentUserId = prefs.getString('current_user_id') ?? 
                      prefs.getString('signup_user_id');
    });
  }

  @override
  void dispose() {
    _commentController.dispose();
    for (var controller in _replyControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _loadComments() async {
    try {
      setState(() {
        _isLoadingComments = true;
      });

      // Load ALL comments from database (including those that should be replies)
      List<Map<String, dynamic>> allCommentsFromDB = [];
      try {
        final allCommentsSnapshot = await FirebaseFirestore.instanceFor(
          app: Firebase.app(),
          databaseId: 'marketsafe',
        )
            .collection('comments')
            .where('productId', isEqualTo: widget.product.id)
            .where('isDeleted', isEqualTo: false)
            .get();
        
        print('🔍 Total comments in database for this product: ${allCommentsSnapshot.docs.length}');
        
        // Separate top-level comments and replies
        List<Map<String, dynamic>> topLevelComments = [];
        List<Map<String, dynamic>> orphanReplies = []; // Replies that couldn't be linked to parent
        
        for (var doc in allCommentsSnapshot.docs) {
          final data = doc.data();
          final commentData = Map<String, dynamic>.from(data);
          commentData['commentId'] = doc.id;
          final parentId = data['parentCommentId'];
          
          print('  - Comment ${doc.id}: parentCommentId=$parentId, username=${data['username']}, content=${data['content']}');
          
          if (parentId == null) {
            // Check if this is actually a reply to an old comment (starts with "Replying to")
            final content = data['content'] ?? '';
            if (content.toString().startsWith('Replying to ')) {
              orphanReplies.add(commentData);
            } else {
              topLevelComments.add(commentData);
            }
          } else {
            // This is a reply - we'll attach it to its parent
            orphanReplies.add(commentData);
          }
        }
        
        // Get replies for each top-level comment
        for (var comment in topLevelComments) {
          final replies = await CommentService.getReplies(comment['commentId']);
          comment['replies'] = replies;
          print('🔍 Comment ${comment['commentId']} (${comment['username']}) has ${replies.length} replies from getReplies');
        }
        
        // Try to match orphan replies to old comments more precisely
        // We need to track which replies have been matched to avoid duplicates
        final matchedReplyIds = <String>{};
        
        // Sort old comments by creation time (oldest first) to match replies in order
        final sortedOldComments = List<Map<String, dynamic>>.from(_currentProduct.comments);
        sortedOldComments.sort((a, b) {
          final aTime = a['createdAt'] ?? '';
          final bTime = b['createdAt'] ?? '';
          return aTime.toString().compareTo(bTime.toString());
        });
        
        final oldComments = sortedOldComments.map((oldComment) {
          final oldCommentId = oldComment['id'] ?? '';
          final oldUsername = oldComment['userName'] ?? 'Anonymous';
          final oldContent = oldComment['text'] ?? '';
          
          // Find replies that mention this old comment's username
          // Match to the FIRST comment from this user that matches
          // This ensures replies go to the correct comment when there are multiple from same user
          final matchingReplies = orphanReplies.where((reply) {
            if (matchedReplyIds.contains(reply['commentId'])) {
              return false; // Already matched to another comment
            }
            final content = reply['content'] ?? '';
            final contentStr = content.toString();
            // Check if reply is specifically for this comment
            // It should start with "Replying to [oldUsername]:"
            if (contentStr.startsWith('Replying to $oldUsername:')) {
              matchedReplyIds.add(reply['commentId']);
              return true;
            }
            return false;
          }).toList();
          
          return {
            'commentId': oldCommentId,
            'userId': oldComment['userId'] ?? '',
            'username': oldUsername,
            'profilePictureUrl': oldComment['userProfilePicture'] ?? '',
            'content': oldContent,
            'createdAt': oldComment['createdAt'] ?? DateTime.now().toIso8601String(),
            'replies': matchingReplies, // Attach matching replies
            'isOldComment': true,
          };
        }).toList();
        
        // Any remaining orphan replies that weren't matched should be shown as top-level comments
        final unmatchedReplies = orphanReplies.where((reply) => !matchedReplyIds.contains(reply['commentId'])).toList();
        if (unmatchedReplies.isNotEmpty) {
          print('⚠️ ${unmatchedReplies.length} replies could not be matched to any comment');
          // Add them as top-level comments
          topLevelComments.addAll(unmatchedReplies);
        }
        
        // Merge: new top-level comments first, then old comments with their replies
        allCommentsFromDB = [...topLevelComments, ...oldComments];
        
        print('🔍 Final comment count: ${allCommentsFromDB.length} (${topLevelComments.length} new + ${oldComments.length} old)');
        for (var comment in allCommentsFromDB) {
          final replies = comment['replies'] as List? ?? [];
          if (replies.isNotEmpty) {
            print('  - Comment ${comment['commentId']} has ${replies.length} replies');
          }
        }
      } catch (e) {
        print('❌ Error loading comments: $e');
        // Fallback to CommentService
        final newComments = await CommentService.getComments(widget.product.id);
        final oldComments = _currentProduct.comments.map((oldComment) {
          return {
            'commentId': oldComment['id'] ?? '',
            'userId': oldComment['userId'] ?? '',
            'username': oldComment['userName'] ?? 'Anonymous',
            'profilePictureUrl': oldComment['userProfilePicture'] ?? '',
            'content': oldComment['text'] ?? '',
            'createdAt': oldComment['createdAt'] ?? DateTime.now().toIso8601String(),
            'replies': <Map<String, dynamic>>[],
            'isOldComment': true,
          };
        }).toList();
        allCommentsFromDB = [...newComments, ...oldComments];
      }
      
      final allComments = allCommentsFromDB;
      
      if (mounted) {
        setState(() {
          _comments = allComments;
          _isLoadingComments = false;
        });
      }
    } catch (e) {
      print('❌ Error loading comments: $e');
      if (mounted) {
        setState(() {
          _isLoadingComments = false;
        });
      }
    }
  }

  Future<void> _addComment() async {
    if (_commentController.text.trim().isEmpty || widget.currentUserId == null || _isAddingComment) return;

    setState(() {
      _isAddingComment = true;
    });

    try {
      // Use CommentService for full reply support
      final success = await CommentService.addComment(
        productId: widget.product.id,
        content: _commentController.text.trim(),
      );

      if (success) {
        _commentController.clear();
        await _loadComments(); // Reload comments with replies
        // Refresh product to get updated comment count
        final updatedProduct = await ProductService.getProductById(_currentProduct.id);
        if (updatedProduct != null) {
          setState(() {
            _currentProduct = updatedProduct;
          });
          widget.onCommentAdded(updatedProduct);
        }
      }
    } catch (e) {
      print('❌ Error adding comment: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isAddingComment = false;
        });
      }
    }
  }

  Future<void> _addReply(String commentId, String parentUsername) async {
    final replyController = _replyControllers[commentId];
    if (replyController == null || replyController.text.trim().isEmpty || _isReplying[commentId] == true) return;

    setState(() {
      _isReplying[commentId] = true;
    });

    try {
      // Check if this is an old comment
      final comment = _comments.firstWhere(
        (c) => c['commentId'] == commentId,
        orElse: () => {},
      );
      
      final isOldComment = comment['isOldComment'] == true;
      
      // For old comments, we can't use their ID as parentCommentId (it doesn't exist in new system)
      // So we create a new top-level comment with a mention
      // For new comments, we can properly create a reply
      final replyContent = isOldComment 
          ? 'Replying to ${comment['username'] ?? 'user'}: ${replyController.text.trim()}'
          : replyController.text.trim();
      
      print('🔍 Adding reply - isOldComment: $isOldComment, commentId: $commentId');
      print('🔍 Reply content: $replyContent');
      
      final success = await CommentService.addComment(
        productId: widget.product.id,
        content: replyContent,
        parentCommentId: isOldComment ? null : commentId, // Don't use old comment ID as parent
      );
      
      print('🔍 Reply added successfully: $success');

      if (success) {
        replyController.clear();
        setState(() {
          _showReplyInput[commentId] = false;
          _showReplies[commentId] = true; // Ensure replies section is visible after adding reply
        });
        await _loadComments(); // Reload comments with new reply
        // Refresh product to get updated comment count
        final updatedProduct = await ProductService.getProductById(_currentProduct.id);
        if (updatedProduct != null) {
          setState(() {
            _currentProduct = updatedProduct;
          });
        }
        // Show success message
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Reply added successfully'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 2),
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to add reply'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      print('❌ Error adding reply: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isReplying[commentId] = false;
        });
      }
    }
  }

  void _showDeleteConfirmation(BuildContext context, String commentId, {bool isOldComment = false}) {
    bool isDeleting = false;
    
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1A0000),
              title: const Text('Delete Comment', style: TextStyle(color: Colors.white)),
              content: const Text('Are you sure you want to delete this comment?', style: TextStyle(color: Colors.white70)),
              actions: [
                TextButton(
                  onPressed: isDeleting ? null : () => Navigator.pop(dialogContext),
                  child: Text(
                    'Cancel',
                    style: TextStyle(
                      color: isDeleting ? Colors.white30 : Colors.white70,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: isDeleting ? null : () async {
                    setDialogState(() {
                      isDeleting = true;
                    });
                    Navigator.pop(dialogContext);
                    await _deleteComment(commentId, isOldComment: isOldComment);
                  },
                  child: isDeleting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            color: Colors.red,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text('Delete', style: TextStyle(color: Colors.red)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showCommentOptions(BuildContext context, String commentId, String currentText, {bool isOldComment = false, bool isProductOwner = false}) {
    print('🔍 _showCommentOptions called');
    print('  - commentId: $commentId');
    print('  - currentText: $currentText');
    print('  - isOldComment: $isOldComment');
    print('  - context: $context');
    
    try {
      // Try using a dialog instead of bottom sheet since we're already in a modal
      showDialog(
        context: context,
        barrierDismissible: true,
        builder: (BuildContext dialogContext) {
          print('🔍 Dialog builder called');
          return AlertDialog(
            backgroundColor: const Color(0xFF1A0000),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: const Text(
              'Comment Options',
              style: TextStyle(color: Colors.white, fontSize: 18),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.edit, color: Colors.blue, size: 24),
                  title: const Text('Edit', style: TextStyle(color: Colors.white, fontSize: 16)),
                  onTap: () {
                    print('🔍 Edit tapped');
                    Navigator.pop(dialogContext);
                    Future.delayed(const Duration(milliseconds: 100), () {
                      _editComment(commentId, currentText, isOldComment: isOldComment);
                    });
                  },
                ),
                const Divider(color: Colors.white24, height: 1),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.delete, color: Colors.red, size: 24),
                  title: const Text('Delete', style: TextStyle(color: Colors.red, fontSize: 16)),
                  onTap: () {
                    print('🔍 Delete tapped');
                    Navigator.pop(dialogContext);
                    Future.delayed(const Duration(milliseconds: 100), () {
                      _deleteComment(commentId, isOldComment: isOldComment);
                    });
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
              ),
            ],
          );
        },
      ).then((_) {
        print('🔍 Dialog closed');
      }).catchError((error) {
        print('❌ Error showing dialog: $error');
        // Fallback to bottom sheet if dialog fails
        _showBottomSheetFallback(context, commentId, currentText, isOldComment: isOldComment);
      });
    } catch (e, stackTrace) {
      print('❌ Exception in _showCommentOptions: $e');
      print('❌ Stack trace: $stackTrace');
      // Fallback to bottom sheet
      _showBottomSheetFallback(context, commentId, currentText, isOldComment: isOldComment);
    }
  }
  
  void _showBottomSheetFallback(BuildContext context, String commentId, String currentText, {bool isOldComment = false}) {
    try {
      showModalBottomSheet(
        context: context,
        backgroundColor: const Color(0xFF1A0000),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        isScrollControlled: false,
        enableDrag: true,
        isDismissible: true,
        useRootNavigator: false,
        builder: (BuildContext sheetContext) {
          print('🔍 Bottom sheet builder called');
          return Container(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.edit, color: Colors.blue, size: 24),
                  title: const Text('Edit', style: TextStyle(color: Colors.white, fontSize: 16)),
                  onTap: () {
                    print('🔍 Edit tapped');
                    Navigator.pop(sheetContext);
                    Future.delayed(const Duration(milliseconds: 100), () {
                      _editComment(commentId, currentText, isOldComment: isOldComment);
                    });
                  },
                ),
                const Divider(color: Colors.white24, height: 1),
                ListTile(
                  leading: const Icon(Icons.delete, color: Colors.red, size: 24),
                  title: const Text('Delete', style: TextStyle(color: Colors.red, fontSize: 16)),
                  onTap: () {
                    print('🔍 Delete tapped');
                    Navigator.pop(sheetContext);
                    Future.delayed(const Duration(milliseconds: 100), () {
                      _deleteComment(commentId, isOldComment: isOldComment);
                    });
                  },
                ),
                const SizedBox(height: 10),
              ],
            ),
          );
        },
      ).then((_) {
        print('🔍 Bottom sheet closed');
      }).catchError((error) {
        print('❌ Error showing bottom sheet: $error');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error showing menu: $error'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      });
    } catch (e, stackTrace) {
      print('❌ Exception in _showCommentOptions: $e');
      print('❌ Stack trace: $stackTrace');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _editComment(String commentId, String currentText, {bool isOldComment = false}) async {
    final textController = TextEditingController(text: currentText);
    
    final newText = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A0000),
        title: const Text('Edit Comment', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: textController,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Enter your comment',
            hintStyle: TextStyle(color: Colors.white54),
            filled: true,
            fillColor: Colors.white12,
            border: OutlineInputBorder(),
          ),
          autofocus: true,
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, textController.text),
            child: const Text('Save', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (newText != null && newText.trim().isNotEmpty && newText != currentText) {
      if (isOldComment) {
        // For old comments, use ProductService
        await ProductService.editComment(_currentProduct.id, commentId, newText);
        // Refresh the product data
        final updatedProduct = await ProductService.getProductById(_currentProduct.id);
        if (updatedProduct != null) {
          setState(() {
            _currentProduct = updatedProduct;
          });
          widget.onCommentAdded(updatedProduct);
        }
      } else {
        // For new comments, use CommentService
        final success = await CommentService.editComment(commentId, newText);
        if (success) {
          _loadComments();
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Failed to edit comment'),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      }
    }
  }

  Future<void> _deleteComment(String commentId, {bool isOldComment = false}) async {
    try {
      if (isOldComment) {
        // For old comments, use ProductService
        await ProductService.deleteComment(_currentProduct.id, commentId);
        // Refresh the product data
        final updatedProduct = await ProductService.getProductById(_currentProduct.id);
        if (updatedProduct != null && mounted) {
          setState(() {
            _currentProduct = updatedProduct;
          });
          widget.onCommentAdded(updatedProduct);
        }
      } else {
        // For new comments, use CommentService
        final success = await CommentService.deleteComment(commentId);
        if (success && mounted) {
          _loadComments();
        } else if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to delete comment'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      print('❌ Error deleting comment: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFF1A0000),
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Column(
            children: [
              // Handle bar
              Container(
                margin: const EdgeInsets.only(top: 8),
                height: 4,
                width: 40,
                decoration: BoxDecoration(
                  color: Colors.white30,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Header
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const Text(
                      'Comments',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              // Comments list
              Expanded(
                child: _isLoadingComments
                    ? const Center(
                        child: CircularProgressIndicator(color: Colors.white),
                      )
                    : _comments.isEmpty
                        ? const Center(
                            child: Text(
                              'No comments yet',
                              style: TextStyle(color: Colors.white54),
                            ),
                          )
                        : ListView.builder(
                            controller: scrollController,
                            padding: EdgeInsets.only(
                              left: 16,
                              right: 16,
                              bottom: MediaQuery.of(context).viewInsets.bottom > 0 ? 100 : 16,
                            ),
                            itemCount: _comments.length,
                            itemBuilder: (context, index) {
                              final comment = _comments[index];
                              final commentId = comment['commentId'] ?? '';
                              // Ensure replies is a proper list
                              final repliesRaw = comment['replies'];
                              final replies = repliesRaw is List 
                                  ? List<Map<String, dynamic>>.from(repliesRaw.map((r) => r is Map ? Map<String, dynamic>.from(r) : {}))
                                  : <Map<String, dynamic>>[];
                              // Compare user IDs (handle both string and null cases)
                              final commentUserId = comment['userId']?.toString() ?? '';
                              final currentUserIdStr = _currentUserId?.toString() ?? '';
                              final isCommentOwner = commentUserId.isNotEmpty && 
                                                    currentUserIdStr.isNotEmpty && 
                                                    commentUserId == currentUserIdStr;
                              final isProductOwner = _currentProduct.sellerId == currentUserIdStr;
                              
                              print('🔍 Comment owner check:');
                              print('  - commentUserId: "$commentUserId"');
                              print('  - currentUserId: "$currentUserIdStr"');
                              print('  - productSellerId: "${_currentProduct.sellerId}"');
                              print('  - isCommentOwner: $isCommentOwner');
                              print('  - isProductOwner: $isProductOwner');
                              
                              // Auto-show replies if they exist
                              if (replies.isNotEmpty) {
                                print('🔍 Comment $commentId (${comment['username']}): ${replies.length} replies');
                              }
                              
                              // Initialize reply controller if not exists
                              if (!_replyControllers.containsKey(commentId)) {
                                _replyControllers[commentId] = TextEditingController();
                                _showReplyInput[commentId] = false;
                                // Auto-show replies if they exist (only on first load)
                                _showReplies[commentId] = replies.isNotEmpty;
                                _isReplying[commentId] = false;
                              }
                              
                              return Dismissible(
                                key: Key('comment_$commentId'),
                                direction: isCommentOwner ? DismissDirection.endToStart : DismissDirection.none,
                                background: Container(
                                  alignment: Alignment.centerRight,
                                  padding: const EdgeInsets.only(right: 20),
                                  decoration: BoxDecoration(
                                    color: Colors.red.withOpacity(0.3),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Icon(Icons.delete, color: Colors.white, size: 30),
                                ),
                                onDismissed: isCommentOwner ? (direction) {
                                  _deleteComment(commentId, isOldComment: comment['isOldComment'] == true);
                                } : null,
                                child: GestureDetector(
                                  onLongPress: isCommentOwner ? () {
                                    HapticFeedback.mediumImpact();
                                    _showDeleteConfirmation(context, commentId, isOldComment: comment['isOldComment'] == true);
                                  } : null,
                                  behavior: HitTestBehavior.opaque,
                                  child: Container(
                                  margin: const EdgeInsets.only(bottom: 20),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          // Minimal profile picture - Tappable
                                          GestureDetector(
                                            onTap: () {
                                              final userId = comment['userId']?.toString();
                                              if (userId != null && userId.isNotEmpty) {
                                                Navigator.push(
                                                  context,
                                                  MaterialPageRoute(
                                                    builder: (context) => profile_screen.UserProfileViewScreen(
                                                      targetUserId: userId,
                                                      targetUsername: comment['username']?.toString(),
                                                    ),
                                                  ),
                                                );
                                              }
                                            },
                                            child: CircleAvatar(
                                              radius: 18,
                                              backgroundColor: Colors.transparent,
                                              backgroundImage: (comment['profilePictureUrl'] != null && 
                                                              comment['profilePictureUrl'].toString().isNotEmpty)
                                                  ? NetworkImage(comment['profilePictureUrl'])
                                                  : null,
                                              child: (comment['profilePictureUrl'] == null || 
                                                     comment['profilePictureUrl'].toString().isEmpty)
                                                  ? Text(
                                                      (comment['username'] ?? 'A')[0].toUpperCase(),
                                                      style: TextStyle(
                                                        color: Colors.white.withOpacity(0.6),
                                                        fontSize: 16,
                                                        fontWeight: FontWeight.w400,
                                                      ),
                                                    )
                                                  : null,
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          // Content section
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Row(
                                                  children: [
                                                    // Username - Tappable
                                                    GestureDetector(
                                                      onTap: () {
                                                        final userId = comment['userId']?.toString();
                                                        if (userId != null && userId.isNotEmpty) {
                                                          Navigator.push(
                                                            context,
                                                            MaterialPageRoute(
                                                              builder: (context) => profile_screen.UserProfileViewScreen(
                                                                targetUserId: userId,
                                                                targetUsername: comment['username']?.toString(),
                                                              ),
                                                            ),
                                                          );
                                                        }
                                                      },
                                                      child: Text(
                                                        comment['username'] ?? 'Anonymous',
                                                        style: TextStyle(
                                                          color: Colors.white.withOpacity(0.9),
                                                          fontWeight: FontWeight.w500,
                                                          fontSize: 14,
                                                        ),
                                                      ),
                                                    ),
                                                    const SizedBox(width: 8),
                                                    Text(
                                                      _formatCommentTime(comment['createdAt']),
                                                      style: TextStyle(
                                                        color: Colors.white.withOpacity(0.4),
                                                        fontSize: 12,
                                                        fontWeight: FontWeight.w400,
                                                      ),
                                                    ),
                                                    const Spacer(),
                                                    // Three-dot menu only for product owner
                                                    if (isProductOwner)
                                                      IconButton(
                                                        icon: Icon(Icons.more_vert, color: Colors.white.withOpacity(0.5), size: 18),
                                                        padding: EdgeInsets.zero,
                                                        constraints: const BoxConstraints(),
                                                        onPressed: () {
                                                          _showCommentOptions(context, commentId, comment['content'] ?? '', isOldComment: comment['isOldComment'] == true, isProductOwner: true);
                                                        },
                                                      ),
                                                  ],
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  comment['content'] ?? '',
                                                  style: TextStyle(
                                                    color: Colors.white.withOpacity(0.8),
                                                    fontSize: 14,
                                                    height: 1.5,
                                                  ),
                                                ),
                                                const SizedBox(height: 8),
                                                // Minimal action buttons
                                                Row(
                                                  children: [
                                                    TextButton(
                                                      onPressed: () {
                                                        if (!_replyControllers.containsKey(commentId)) {
                                                          _replyControllers[commentId] = TextEditingController();
                                                        }
                                                        final currentState = _showReplyInput[commentId] ?? false;
                                                        setState(() {
                                                          _showReplyInput[commentId] = !currentState;
                                                          _showReplies[commentId] = true;
                                                        });
                                                      },
                                                      style: TextButton.styleFrom(
                                                        padding: EdgeInsets.zero,
                                                        minimumSize: const Size(0, 0),
                                                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                                      ),
                                                      child: Text(
                                                        'Reply${replies.isNotEmpty ? ' (${replies.length})' : ''}',
                                                        style: TextStyle(
                                                          color: Colors.white.withOpacity(0.6),
                                                          fontSize: 12,
                                                          fontWeight: FontWeight.w400,
                                                        ),
                                                      ),
                                                    ),
                                                    // Show/Hide Replies toggle
                                                    if (replies.isNotEmpty) ...[
                                                      Text(
                                                        ' • ',
                                                        style: TextStyle(
                                                          color: Colors.white.withOpacity(0.3),
                                                          fontSize: 12,
                                                        ),
                                                      ),
                                                      TextButton(
                                                        onPressed: () {
                                                          setState(() {
                                                            _showReplies[commentId] = !(_showReplies[commentId] ?? true);
                                                          });
                                                        },
                                                        style: TextButton.styleFrom(
                                                          padding: EdgeInsets.zero,
                                                          minimumSize: const Size(0, 0),
                                                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                                        ),
                                                        child: Text(
                                                          _showReplies[commentId] == true ? 'Hide' : 'Show ${replies.length}',
                                                          style: TextStyle(
                                                            color: Colors.white.withOpacity(0.6),
                                                            fontSize: 12,
                                                            fontWeight: FontWeight.w400,
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    
                                    // Minimal Reply Input
                                    if ((_showReplyInput[commentId] ?? false) && _replyControllers.containsKey(commentId)) ...[
                                      const SizedBox(height: 12),
                                      Padding(
                                        padding: const EdgeInsets.only(left: 30),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'Replying to ${comment['username'] ?? 'user'}',
                                              style: TextStyle(
                                                color: Colors.white.withOpacity(0.5),
                                                fontSize: 11,
                                                fontWeight: FontWeight.w400,
                                              ),
                                            ),
                                            const SizedBox(height: 8),
                                            TextField(
                                              controller: _replyControllers[commentId],
                                              style: TextStyle(
                                                color: Colors.white.withOpacity(0.9),
                                                fontSize: 13,
                                              ),
                                              decoration: InputDecoration(
                                                hintText: 'Write a reply...',
                                                hintStyle: TextStyle(
                                                  color: Colors.white.withOpacity(0.3),
                                                ),
                                                border: UnderlineInputBorder(
                                                  borderSide: BorderSide(
                                                    color: Colors.white.withOpacity(0.2),
                                                  ),
                                                ),
                                                enabledBorder: UnderlineInputBorder(
                                                  borderSide: BorderSide(
                                                    color: Colors.white.withOpacity(0.2),
                                                  ),
                                                ),
                                                focusedBorder: UnderlineInputBorder(
                                                  borderSide: BorderSide(
                                                    color: Colors.white.withOpacity(0.4),
                                                  ),
                                                ),
                                                contentPadding: const EdgeInsets.symmetric(horizontal: 0, vertical: 8),
                                                isDense: true,
                                              ),
                                              maxLines: 3,
                                              minLines: 1,
                                            ),
                                            const SizedBox(height: 8),
                                            Row(
                                              mainAxisAlignment: MainAxisAlignment.end,
                                              children: [
                                                TextButton(
                                                  onPressed: () {
                                                    setState(() {
                                                      _showReplyInput[commentId] = false;
                                                      _replyControllers[commentId]?.clear();
                                                    });
                                                  },
                                                  style: TextButton.styleFrom(
                                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                                    minimumSize: const Size(0, 0),
                                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                                  ),
                                                  child: Text(
                                                    'Cancel',
                                                    style: TextStyle(
                                                      color: Colors.white.withOpacity(0.5),
                                                      fontSize: 12,
                                                      fontWeight: FontWeight.w400,
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                TextButton(
                                                  onPressed: _isReplying[commentId] == true 
                                                      ? null 
                                                      : () => _addReply(commentId, comment['username'] ?? 'user'),
                                                  style: TextButton.styleFrom(
                                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                                    minimumSize: const Size(0, 0),
                                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                                  ),
                                                  child: _isReplying[commentId] == true
                                                      ? SizedBox(
                                                          width: 14,
                                                          height: 14,
                                                          child: CircularProgressIndicator(
                                                            color: Colors.white.withOpacity(0.6),
                                                            strokeWidth: 2,
                                                          ),
                                                        )
                                                      : Text(
                                                          'Reply',
                                                          style: TextStyle(
                                                            color: Colors.white.withOpacity(0.8),
                                                            fontSize: 12,
                                                            fontWeight: FontWeight.w500,
                                                          ),
                                                        ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                    
                                    // Minimal Replies List
                                    if (replies.isNotEmpty && (_showReplies[commentId] ?? true)) ...[
                                      const SizedBox(height: 12),
                                      Padding(
                                        padding: const EdgeInsets.only(left: 30),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: replies.map((reply) {
                                            if (reply.isEmpty || reply['username'] == null) {
                                              return const SizedBox.shrink();
                                            }
                                            return _buildReplyWidget(reply, commentId);
                                          }).toList(),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          );
                            },
                          ),
              ),
              // Minimal Add comment section with keyboard padding
              Container(
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  top: 12,
                  bottom: 12 + keyboardHeight,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.02),
                  border: Border(
                    top: BorderSide(
                      color: Colors.white.withOpacity(0.1),
                      width: 0.5,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _commentController,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.9),
                          fontSize: 14,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Add a comment...',
                          hintStyle: TextStyle(
                            color: Colors.white.withOpacity(0.3),
                          ),
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 0, vertical: 8),
                          isDense: true,
                        ),
                        maxLines: null,
                        onSubmitted: (_) => _addComment(),
                        onTap: () {
                          // Scroll to bottom when text field is tapped
                          Future.delayed(const Duration(milliseconds: 300), () {
                            if (scrollController.hasClients) {
                              scrollController.animateTo(
                                scrollController.position.maxScrollExtent,
                                duration: const Duration(milliseconds: 200),
                                curve: Curves.easeOut,
                              );
                            }
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: _isAddingComment ? null : _addComment,
                      icon: _isAddingComment
                          ? SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                color: Colors.white.withOpacity(0.6),
                                strokeWidth: 2,
                              ),
                            )
                          : Icon(
                              Icons.send_rounded,
                              color: Colors.white.withOpacity(0.7),
                              size: 20,
                            ),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _formatCommentTime(dynamic timestamp) {
    if (timestamp == null) return 'Unknown';
    
    try {
      DateTime date;
      if (timestamp is Timestamp) {
        date = timestamp.toDate();
      } else if (timestamp is String) {
        date = DateTime.parse(timestamp);
      } else {
        return 'Unknown';
      }
      
      final now = DateTime.now();
      final difference = now.difference(date);
      
      if (difference.inDays > 0) {
        return '${difference.inDays}d ago';
      } else if (difference.inHours > 0) {
        return '${difference.inHours}h ago';
      } else if (difference.inMinutes > 0) {
        return '${difference.inMinutes}m ago';
      } else {
        return 'Just now';
      }
    } catch (e) {
      return 'Unknown';
    }
  }

  Widget _buildReplyWidget(Map<String, dynamic> reply, String parentCommentId) {
    // Check if current user owns this reply
    final replyUserId = reply['userId']?.toString() ?? '';
    final currentUserIdStr = _currentUserId?.toString() ?? '';
    final isReplyOwner = replyUserId.isNotEmpty && 
                        currentUserIdStr.isNotEmpty && 
                        replyUserId == currentUserIdStr;
    
    // Clean up reply content - remove "Replying to [username]: " prefix if present
    String replyContent = reply['content'] ?? '';
    if (replyContent.toString().startsWith('Replying to ')) {
      final colonIndex = replyContent.indexOf(': ');
      if (colonIndex > 0) {
        replyContent = replyContent.substring(colonIndex + 2);
      }
    }
    
    return GestureDetector(
      onLongPress: isReplyOwner ? () {
        HapticFeedback.mediumImpact();
        _showDeleteConfirmation(context, reply['commentId'] ?? '', isOldComment: false);
      } : null,
      behavior: HitTestBehavior.opaque,
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Minimal profile picture - Tappable
            GestureDetector(
              onTap: () {
                final userId = reply['userId']?.toString();
                if (userId != null && userId.isNotEmpty) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => profile_screen.UserProfileViewScreen(
                        targetUserId: userId,
                        targetUsername: reply['username']?.toString(),
                      ),
                    ),
                  );
                }
              },
              child: CircleAvatar(
                radius: 14,
                backgroundColor: Colors.transparent,
                backgroundImage: (reply['profilePictureUrl'] != null && 
                                reply['profilePictureUrl'].toString().isNotEmpty)
                    ? NetworkImage(reply['profilePictureUrl'])
                    : null,
                child: (reply['profilePictureUrl'] == null || 
                       reply['profilePictureUrl'].toString().isEmpty)
                    ? Text(
                        (reply['username'] ?? 'A')[0].toUpperCase(),
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.5),
                          fontSize: 14,
                          fontWeight: FontWeight.w400,
                        ),
                      )
                    : null,
              ),
            ),
            const SizedBox(width: 10),
            // Reply content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      // Username - Tappable
                      GestureDetector(
                        onTap: () {
                          final userId = reply['userId']?.toString();
                          if (userId != null && userId.isNotEmpty) {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => profile_screen.UserProfileViewScreen(
                                  targetUserId: userId,
                                  targetUsername: reply['username']?.toString(),
                                ),
                              ),
                            );
                          }
                        },
                        child: Text(
                          reply['username'] ?? 'Anonymous',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.9),
                            fontWeight: FontWeight.w500,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _formatCommentTime(reply['createdAt']),
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.4),
                          fontSize: 11,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    replyContent,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.8),
                      fontSize: 13,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

}

class _VideoPlayerDialog extends StatefulWidget {
  final String videoUrl;
  final String productTitle;

  const _VideoPlayerDialog({
    required this.videoUrl,
    required this.productTitle,
  });

  @override
  State<_VideoPlayerDialog> createState() => _VideoPlayerDialogState();
}

class _VideoPlayerDialogState extends State<_VideoPlayerDialog> {
  late VideoPlayerController _controller;
  bool _isInitialized = false;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _initializeVideo();
  }

  Future<void> _initializeVideo() async {
    try {
      _controller = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl));
      await _controller.initialize();
      
      _controller.addListener(() {
        if (mounted) {
          setState(() {});
        }
      });
      
      setState(() {
        _isInitialized = true;
      });
    } catch (e) {
      setState(() {
        _hasError = true;
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
    return Dialog(
      backgroundColor: Colors.black,
      child: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.productTitle,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, color: Colors.white),
                  ),
                ],
              ),
            ),
            // Video player
            Expanded(
              child: _hasError
                  ? const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.error, color: Colors.red, size: 48),
                          SizedBox(height: 16),
                          Text(
                            'Error loading video',
                            style: TextStyle(color: Colors.white),
                          ),
                        ],
                      ),
                    )
                  : !_isInitialized
                      ? const Center(
                          child: CircularProgressIndicator(color: Colors.red),
                        )
                      : GestureDetector(
                          onTap: () {
                            if (_controller.value.isPlaying) {
                              _controller.pause();
                            } else {
                              _controller.play();
                            }
                            setState(() {});
                          },
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              AspectRatio(
                                aspectRatio: _controller.value.aspectRatio,
                                child: VideoPlayer(_controller),
                              ),
                              // Play/Pause overlay
                              if (!_controller.value.isPlaying)
                                Center(
                                  child: Container(
                                    padding: const EdgeInsets.all(24),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withOpacity(0.7),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.play_arrow,
                                      color: Colors.white,
                                      size: 48,
                                    ),
                                  ),
                                ),
                              // Progress bar
                              Positioned(
                                bottom: 16,
                                left: 16,
                                right: 16,
                                child: Column(
                                  children: [
                                    // Progress bar
                                    Container(
                                      height: 3,
                                      decoration: BoxDecoration(
                                        color: Colors.white.withOpacity(0.3),
                                        borderRadius: BorderRadius.circular(2),
                                      ),
                                      child: LinearProgressIndicator(
                                        value: _controller.value.duration.inMilliseconds > 0
                                            ? _controller.value.position.inMilliseconds / 
                                              _controller.value.duration.inMilliseconds
                                            : 0.0,
                                        backgroundColor: Colors.transparent,
                                        valueColor: const AlwaysStoppedAnimation<Color>(Colors.red),
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    // Duration
                                    Text(
                                      '${_formatDuration(_controller.value.position)} / ${_formatDuration(_controller.value.duration)}',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
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

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    return "$twoDigitMinutes:$twoDigitSeconds";
  }
}
