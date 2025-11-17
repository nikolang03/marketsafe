import 'dart:io';
import 'package:flutter/material.dart';

class ImageSwiper extends StatefulWidget {
  final List<String> imageUrls;
  final double height;
  final bool showDots;
  final bool showCounter;
  final Function(int index)? onImageTap;
  final bool enableCropping;
  final Function(int index, File croppedFile)? onImageCropped;

  const ImageSwiper({
    super.key,
    required this.imageUrls,
    this.height = 200,
    this.showDots = true,
    this.showCounter = true,
    this.onImageTap,
    this.enableCropping = false,
    this.onImageCropped,
  });

  @override
  State<ImageSwiper> createState() => _ImageSwiperState();
}

class _ImageSwiperState extends State<ImageSwiper> {
  late PageController _pageController;
  int _currentIndex = 0;
  late List<TransformationController> _transformationControllers;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _transformationControllers = List.generate(
      widget.imageUrls.length,
      (index) => TransformationController(),
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    for (var controller in _transformationControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  Widget _buildImage(String imageUrl) {
    print('🖼️ ImageSwiper: Building image - $imageUrl');
    
    // Check if it's a local file path or network URL
    // SECURITY: Reject HTTP URLs for production (only allow HTTPS)
    if (imageUrl.startsWith('https://')) {
      print('🌐 Loading network image: $imageUrl');
      // Network image - show full size for cropping
      return Image.network(
        imageUrl,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          print('❌ Network image error: $error');
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
          return Center(
            child: CircularProgressIndicator(
              value: loadingProgress.expectedTotalBytes != null
                  ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                  : null,
              color: Colors.white,
            ),
          );
        },
      );
    } else {
      print('📁 Loading local file: $imageUrl');
      final file = File(imageUrl);
      print('📁 File exists: ${file.existsSync()}');
      print('📁 File path: ${file.path}');
      
      // Local file - show full size for cropping
      return Image.file(
        file,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          print('❌ Local image error: $error');
          print('❌ File path that failed: $imageUrl');
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

  @override
  Widget build(BuildContext context) {
    final containerSize = widget.height; // Use the height parameter as the container size
    
    print('🖼️ ImageSwiper build: ${widget.imageUrls.length} images');
    for (int i = 0; i < widget.imageUrls.length; i++) {
      print('📁 ImageSwiper image $i: ${widget.imageUrls[i]}');
    }
    
    if (widget.imageUrls.isEmpty) {
      return Container(
        height: containerSize,
        width: containerSize, // Square container
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
      height: containerSize + (widget.imageUrls.length > 1 ? 32 : 0), // Add space for dots/counter
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Image swiper - Square preview
          Center(
            child: SizedBox(
              width: containerSize, // Square container
              height: containerSize,
              child: PageView.builder(
                controller: _pageController,
                onPageChanged: (index) {
                  setState(() {
                    _currentIndex = index;
                  });
                },
                itemCount: widget.imageUrls.length,
                itemBuilder: (context, index) {
                  return Container(
                    width: containerSize, // Square container
                    height: containerSize,
                    decoration: const BoxDecoration(
                      borderRadius: BorderRadius.all(Radius.circular(8)),
                    ),
                    child: widget.imageUrls[index].isEmpty
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
                              child: _buildImage(widget.imageUrls[index]),
                            ),
                          ),
                  );
                },
              ),
            ),
          ),
          
          // Dots indicator and counter
          if (widget.imageUrls.length > 1) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Dots indicator
                if (widget.showDots) ...[
                  ...List.generate(
                    widget.imageUrls.length,
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
                      '${_currentIndex + 1}/${widget.imageUrls.length}',
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