import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'offer_dialog.dart';
import '../services/media_download_service.dart';

class ProductPreviewScreen extends StatefulWidget {
  final Map<String, dynamic> product;
  final String currentUserId;

  const ProductPreviewScreen({
    Key? key,
    required this.product,
    required this.currentUserId,
  }) : super(key: key);

  @override
  _ProductPreviewScreenState createState() => _ProductPreviewScreenState();
}

class _ProductPreviewScreenState extends State<ProductPreviewScreen> {
  List<VideoPlayerController> _videoControllers = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadMediaFiles();
    
    // Set status bar style to match the gradient
    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: Color(0xFF8B0000), // Dark red to match gradient
        statusBarIconBrightness: Brightness.light, // White icons
        statusBarBrightness: Brightness.dark, // For iOS
        systemNavigationBarColor: Colors.black, // Black navigation bar
        systemNavigationBarIconBrightness: Brightness.light, // White icons
      ),
    );
  }

  Future<void> _loadMediaFiles() async {
    setState(() {
      _isLoading = true;
    });

    // Simulate loading delay
    await Future.delayed(Duration(milliseconds: 500));
    
    setState(() {
      _isLoading = false;
    });
  }

  @override
  void dispose() {
    for (var controller in _videoControllers) {
      controller.dispose();
    }
    
    // Restore default status bar style
    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        systemNavigationBarColor: Colors.white,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
    );
    
    super.dispose();
  }

  void _showOfferDialog() {
    print('🔍 ProductPreviewScreen: Showing offer dialog');
    print('  - Received currentUserId: ${widget.currentUserId}');
    
    showDialog(
      context: context,
      builder: (context) => OfferDialog(
        product: widget.product,
        currentUserId: widget.currentUserId,
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 100,
          child: Text(
            label,
            style: TextStyle(
              color: Colors.white70,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
            ),
          ),
        ),
      ],
    );
  }

  String _formatTimePosted() {
    // For now, return a sample time. In a real app, you'd get this from the product data
    final now = DateTime.now();
    return '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF8B0000), // Dark red at top
              Colors.black,      // Black at bottom
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
            // Custom AppBar
            Container(
              height: 60,
              color: Color(0xFF8B0000),
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                  Expanded(
                    child: Text(
                      'Collection',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  // Spacer to balance the layout (notification icon removed)
                  const SizedBox(width: 48),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Media placeholder
                    Container(
                      height: 300,
                      width: double.infinity,
                      margin: EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: _isLoading
                          ? Center(child: CircularProgressIndicator())
                          : _buildMediaDisplay(),
                    ),

                    // Product information
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Title and Make Offer button in a row
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              // Title
                              Expanded(
                                child: Text(
                                  widget.product['title'] ?? 'TITLE',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              // Make Offer button - only show for buyers (not sellers)
                              if (widget.product['userId'] != widget.currentUserId)
                                ElevatedButton(
                                  onPressed: _showOfferDialog,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Color(0xFF8B0000), // Dark red background
                                    side: BorderSide(color: Colors.white, width: 1),
                                    padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    elevation: 4,
                                  ),
                                  child: Text(
                                    'MAKE OFFER',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          SizedBox(height: 16),

                          // Details section
                          Container(
                            width: double.infinity,
                            padding: EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'DETAILS',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                SizedBox(height: 12),
                                
                                // Price detail
                                _buildDetailRow('Price:', '${widget.product['price'] ?? '500'} PHP'),
                                SizedBox(height: 8),
                                
                                // Date posted detail
                                _buildDetailRow('Date Posted:', widget.product['date'] ?? 'July 12 2025'),
                                SizedBox(height: 8),
                                
                                // Time posted detail (using current time as example)
                                _buildDetailRow('Time Posted:', _formatTimePosted()),
                                SizedBox(height: 8),
                                
                                // Description detail
                                _buildDetailRow('Description:', widget.product['description'] ?? 'No description available'),
                              ],
                            ),
                          ),
                          SizedBox(height: 32),
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
      ),
    );
  }


  Widget _buildMediaDisplay() {
    final imageUrls = widget.product['imageUrls'] as List<dynamic>? ?? [];
    final videoUrl = widget.product['videoUrl'] as String?;
    final videoThumbnailUrl = widget.product['videoThumbnailUrl'] as String?;
    final mediaType = widget.product['mediaType'] as String?;

    // If it's a video product, show video thumbnail
    if (mediaType == 'video' && videoThumbnailUrl != null && videoThumbnailUrl.isNotEmpty) {
      return GestureDetector(
        onLongPress: () {
          if (videoUrl != null && videoUrl.isNotEmpty) {
            MediaDownloadService.showDownloadDialog(
              context: context,
              mediaUrl: videoUrl,
              productTitle: widget.product['title'] ?? 'Product',
              isVideo: true,
              productId: widget.product['id'] ?? widget.product['productId'],
            );
          }
        },
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  videoThumbnailUrl,
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
                  onTap: () => _showVideoPlayer(videoUrl!),
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
              // Download button
              Positioned(
                bottom: 8,
                right: 8,
                child: GestureDetector(
                  onTap: () {
                    print('📥 Download button tapped for video: $videoUrl');
                    if (videoUrl != null && videoUrl.isNotEmpty) {
                      MediaDownloadService.showDownloadDialog(
                        context: context,
                        mediaUrl: videoUrl,
                        productTitle: widget.product['title'] ?? 'Product',
                        isVideo: true,
                        productId: widget.product['id'] ?? widget.product['productId'],
                      );
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.9),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.download,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    
    // For image products, show images
    if (imageUrls.isNotEmpty) {
      return PageView.builder(
        itemCount: imageUrls.length,
        itemBuilder: (context, index) {
          final imageUrl = imageUrls[index] as String;
          return GestureDetector(
            onLongPress: () {
              MediaDownloadService.showDownloadDialog(
                context: context,
                mediaUrl: imageUrl,
                productTitle: widget.product['title'] ?? 'Product',
                isVideo: false,
                productId: widget.product['id'] ?? widget.product['productId'],
              );
            },
            child: Stack(
              fit: StackFit.expand,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    imageUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        color: Colors.grey[800],
                        child: const Center(
                          child: Icon(Icons.image_not_supported, color: Colors.grey, size: 50),
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
                // Download button
                Positioned(
                  bottom: 8,
                  right: 8,
                  child: GestureDetector(
                    onTap: () {
                      print('📥 Download button tapped for image: $imageUrl');
                      MediaDownloadService.showDownloadDialog(
                        context: context,
                        mediaUrl: imageUrl,
                        productTitle: widget.product['title'] ?? 'Product',
                        isVideo: false,
                        productId: widget.product['id'] ?? widget.product['productId'],
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.9),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.download,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      );
    }
    
    // No media available
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.image, size: 50, color: Colors.grey[600]),
          SizedBox(height: 8),
          Text(
            'No media available',
            style: TextStyle(color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  void _showVideoPlayer(String videoUrl) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => _VideoPlayerDialog(
        videoUrl: videoUrl,
        productTitle: widget.product['title'] ?? 'Product Video',
        productId: widget.product['id'] ?? widget.product['productId'],
      ),
    );
  }
}

class _VideoPlayerDialog extends StatefulWidget {
  final String videoUrl;
  final String productTitle;
  final String? productId;

  const _VideoPlayerDialog({
    required this.videoUrl,
    required this.productTitle,
    this.productId,
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
                    onPressed: () {
                      MediaDownloadService.showDownloadDialog(
                        context: context,
                        mediaUrl: widget.videoUrl,
                        productTitle: widget.productTitle,
                        isVideo: true,
                        productId: widget.productId,
                      );
                    },
                    icon: const Icon(Icons.download, color: Colors.white),
                    tooltip: 'Download video',
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
                          onLongPress: () {
                            MediaDownloadService.showDownloadDialog(
                              context: context,
                              mediaUrl: widget.videoUrl,
                              productTitle: widget.productTitle,
                              isVideo: true,
                            );
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
                              // Download hint
                              Positioned(
                                bottom: 16,
                                left: 16,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withOpacity(0.6),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.download, color: Colors.white, size: 14),
                                      SizedBox(width: 4),
                                      Text(
                                        'Long press to download',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 10,
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
          ],
        ),
      ),
    );
  }
}