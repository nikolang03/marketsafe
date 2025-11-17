import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class UnifiedMediaSwiper extends StatefulWidget {
  final List<String> mediaUrls;
  final double height;
  final bool showDots;
  final bool showCounter;
  final Function(int index)? onMediaTap;
  final bool enableCropping;
  final Function(int index, File croppedFile)? onMediaCropped;

  const UnifiedMediaSwiper({
    super.key,
    required this.mediaUrls,
    this.height = 200,
    this.showDots = true,
    this.showCounter = true,
    this.onMediaTap,
    this.enableCropping = false,
    this.onMediaCropped,
  });

  @override
  State<UnifiedMediaSwiper> createState() => _UnifiedMediaSwiperState();
}

class _UnifiedMediaSwiperState extends State<UnifiedMediaSwiper> {
  late PageController _pageController;
  int _currentIndex = 0;
  late List<TransformationController> _transformationControllers;
  
  // Cache for video controllers
  final Map<String, VideoPlayerController> _videoControllers = {};

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _transformationControllers = List.generate(
      widget.mediaUrls.length,
      (index) => TransformationController(),
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    for (var controller in _transformationControllers) {
      try {
        controller.dispose();
      } catch (e) {
        // Ignore disposal errors
      }
    }
    // Dispose all video controllers safely
    for (var controller in _videoControllers.values) {
      try {
        controller.dispose();
      } catch (e) {
        // Ignore disposal errors
      }
    }
    _videoControllers.clear();
    super.dispose();
  }

  // Check if media is video
  bool _isVideoFile(String url) {
    // Remove query parameters and get the actual file extension
    final urlWithoutQuery = url.split('?').first;
    final extension = urlWithoutQuery.toLowerCase().split('.').last;
    return ['mp4', 'mov', 'avi', 'mkv', 'webm'].contains(extension);
  }

  // Get or create video controller
  Future<VideoPlayerController?> _getOrCreateVideoController(String url) async {
    if (_videoControllers.containsKey(url)) {
      final controller = _videoControllers[url]!;
      if (controller.value.isInitialized) {
        return controller;
      } else {
        try {
          controller.dispose();
        } catch (e) {
          // Ignore disposal errors
        }
        _videoControllers.remove(url);
      }
    }
    
    // Limit number of cached controllers to prevent memory issues
    if (_videoControllers.length >= 3) {
      // Dispose oldest controller
      final oldestKey = _videoControllers.keys.first;
      try {
        _videoControllers[oldestKey]?.dispose();
      } catch (e) {
        // Ignore disposal errors
      }
      _videoControllers.remove(oldestKey);
    }
    
    try {
      // SECURITY: Only allow HTTPS for network videos (reject HTTP)
      if (!url.startsWith('https://') && url.startsWith('http://')) {
        throw Exception('SECURITY ERROR: HTTP video URLs are not allowed. Use HTTPS only.');
      }
      final controller = VideoPlayerController.networkUrl(Uri.parse(url));
      await controller.initialize();
      
      controller.addListener(() {
        if (mounted) {
          setState(() {});
        }
      });
      
      _videoControllers[url] = controller;
      return controller;
    } catch (e) {
      // Return null on error to show error state
      return null;
    }
  }

  Widget _buildImage(String imageUrl) {
    // Check if it's a local file path or network URL
    // SECURITY: Reject HTTP URLs for production (only allow HTTPS)
    if (imageUrl.startsWith('https://')) {
      return Image.network(
        imageUrl,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return const Center(
            child: Icon(
              Icons.image,
              color: Colors.white54,
              size: 50,
            ),
          );
        },
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return const Center(
            child: CircularProgressIndicator(
              color: Colors.white,
            ),
          );
        },
      );
    } else {
      final file = File(imageUrl);
      return Image.file(
        file,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return const Center(
            child: Icon(
              Icons.image,
              color: Colors.white54,
              size: 50,
            ),
          );
        },
      );
    }
  }

  Widget _buildVideo(String videoUrl) {
    return FutureBuilder<VideoPlayerController?>(
      future: _getOrCreateVideoController(videoUrl),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Container(
            color: Colors.black,
            child: const Center(
              child: CircularProgressIndicator(color: Colors.red),
            ),
          );
        }
        
        if (snapshot.hasError || snapshot.data == null) {
          return Container(
            color: Colors.black,
            child: const Center(
              child: Icon(Icons.error, color: Colors.red, size: 48),
            ),
          );
        }
        
        try {
          final controller = snapshot.data!;
          if (!controller.value.isInitialized) {
            return Container(
              color: Colors.black,
              child: const Center(
                child: CircularProgressIndicator(color: Colors.red),
              ),
            );
          }
          return _buildVideoPlayerWithControls(controller);
        } catch (e) {
          return Container(
            color: Colors.black,
            child: const Center(
              child: Icon(Icons.error, color: Colors.red, size: 48),
            ),
          );
        }
      },
    );
  }

  // Build video player with controls
  Widget _buildVideoPlayerWithControls(VideoPlayerController controller) {
    return GestureDetector(
      onTap: () {
        if (!mounted || !controller.value.isInitialized) return;
        
        setState(() {
          try {
            if (controller.value.isPlaying) {
              controller.pause();
            } else {
              controller.play();
            }
          } catch (e) {
            print('Error controlling video: $e');
          }
        });
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Video player
          AspectRatio(
            aspectRatio: controller.value.isInitialized ? controller.value.aspectRatio : 16/9,
            child: controller.value.isInitialized 
                ? VideoPlayer(controller)
                : Container(
                    color: Colors.black,
                    child: const Center(
                      child: CircularProgressIndicator(color: Colors.red),
                    ),
                  ),
          ),
          
          // Play/Pause overlay - only show when paused or just started
          if (controller.value.isInitialized && !controller.value.isPlaying)
            Center(
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.7),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.5),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.play_arrow,
                  color: Colors.white,
                  size: 48,
                ),
              ),
            ),
          
          // Video duration and progress - only show when paused or on hover
          if (controller.value.isInitialized && !controller.value.isPlaying)
            Positioned(
              bottom: 16,
              left: 16,
              right: 16,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Progress bar
                  Container(
                    height: 3,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                    child: LinearProgressIndicator(
                      value: controller.value.duration.inMilliseconds > 0
                          ? controller.value.position.inMilliseconds / 
                            controller.value.duration.inMilliseconds
                          : 0.0,
                      backgroundColor: Colors.transparent,
                      valueColor: const AlwaysStoppedAnimation<Color>(Colors.red),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Duration text
                  Text(
                    '${_formatDuration(controller.value.position)} / ${_formatDuration(controller.value.duration)}',
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
    );
  }

  // Format duration helper
  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    return "$twoDigitMinutes:$twoDigitSeconds";
  }

  @override
  Widget build(BuildContext context) {
    final containerSize = widget.height;
    
    if (widget.mediaUrls.isEmpty) {
      return Container(
        height: containerSize,
        width: containerSize,
        decoration: const BoxDecoration(
          borderRadius: BorderRadius.all(Radius.circular(8)),
        ),
        child: const Center(
          child: Icon(
            Icons.image,
            color: Colors.white54,
            size: 50,
          ),
        ),
      );
    }

    return SizedBox(
      height: containerSize + (widget.mediaUrls.length > 1 ? 32 : 0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Media swiper
          Center(
            child: SizedBox(
              width: containerSize,
              height: containerSize,
              child: PageView.builder(
                controller: _pageController,
                onPageChanged: (index) {
                  setState(() {
                    _currentIndex = index;
                  });
                },
                itemCount: widget.mediaUrls.length,
                itemBuilder: (context, index) {
                  final mediaUrl = widget.mediaUrls[index];
                  
                  return Container(
                    width: containerSize,
                    height: containerSize,
                    decoration: const BoxDecoration(
                      borderRadius: BorderRadius.all(Radius.circular(8)),
                    ),
                    child: mediaUrl.isEmpty
                        ? const Center(
                            child: Icon(
                              Icons.image,
                              color: Colors.white54,
                              size: 50,
                            ),
                          )
                        : ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: SizedBox(
                              width: containerSize,
                              height: containerSize,
                              child: _isVideoFile(mediaUrl)
                                  ? _buildVideo(mediaUrl)
                                  : _buildImage(mediaUrl),
                            ),
                          ),
                  );
                },
              ),
            ),
          ),
          
          // Dots indicator and counter
          if (widget.mediaUrls.length > 1) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Dots indicator
                if (widget.showDots) ...[
                  ...List.generate(
                    widget.mediaUrls.length,
                    (index) => Container(
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _currentIndex == index
                            ? Colors.white
                            : Colors.white.withOpacity(0.4),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                ],
                
                // Counter
                if (widget.showCounter)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.6),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${_currentIndex + 1}/${widget.mediaUrls.length}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
