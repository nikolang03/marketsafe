import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../services/watermarking_service.dart';

class WatermarkPreviewScreen extends StatefulWidget {
  final String imagePath;
  final String username;
  final String userId;
  final Function(String) onWatermarkApplied;

  const WatermarkPreviewScreen({
    Key? key,
    required this.imagePath,
    required this.username,
    required this.userId,
    required this.onWatermarkApplied,
  }) : super(key: key);

  @override
  State<WatermarkPreviewScreen> createState() => _WatermarkPreviewScreenState();
}

class _WatermarkPreviewScreenState extends State<WatermarkPreviewScreen> {
  // Watermark properties - positioning and sizing
  double _positionX = 0.5; // 0.0 to 1.0 (center by default)
  double _positionY = 0.5; // 0.0 to 1.0 (center by default)
  double _size = 0.8; // 0.1 to 2.0 (80% by default)
  double _opacity = 0.9; // 0.1 to 1.0 (90% by default)

  // Image data
  Uint8List? _originalImageBytes;
  Uint8List? _previewImageBytes;
  bool _isLoading = true;

  // UI state
  bool _isDragging = false;
  GlobalKey _imageKey = GlobalKey();
  Size? _imageDisplaySize;

  @override
  void initState() {
    super.initState();
    print('🎨 WatermarkPreviewScreen initialized');
    print('📸 Image path: ${widget.imagePath}');
    print('👤 Username: ${widget.username}');
    print('🆔 User ID: ${widget.userId}');
    print('🔍 This screen should show for both camera and gallery photos');
    _loadImage();
  }

  Future<void> _loadImage() async {
    try {
      print('📸 Loading image from: ${widget.imagePath}');
      final file = File(widget.imagePath);
      _originalImageBytes = await file.readAsBytes();
      print('📸 Image loaded successfully: ${_originalImageBytes!.length} bytes');
      await _generatePreview();
      print('📸 Preview generated successfully');
      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      print('❌ Error loading image: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _generatePreview() async {
    if (_originalImageBytes == null) {
      print('❌ Cannot generate preview: original image bytes are null');
      return;
    }

    try {
      print('🎨 Generating watermark preview...');
      print('🎨 Position: (${_positionX}, ${_positionY})');
      print('🎨 Text: @${widget.username}');
      print('📏 Original image size: ${_originalImageBytes!.length} bytes');
      print('🔍 This should work for both camera and gallery photos');
      
      _previewImageBytes = await WatermarkingService.applyUsernameWatermark(
        imageBytes: _originalImageBytes!,
        username: widget.username,
      );
      
      print('✅ Preview generated successfully: ${_previewImageBytes!.length} bytes');
      print('🔍 Watermark should now be visible in the preview');
      setState(() {});
    } catch (e) {
      print('❌ Error generating preview: $e');
      print('❌ Stack trace: ${StackTrace.current}');
    }
  }

  void _updateWatermarkPosition(Offset localPosition, Size containerSize) {
    if (_imageDisplaySize == null || _imageDisplaySize!.isEmpty) return;

    setState(() {
      _positionX = (localPosition.dx / containerSize.width).clamp(0.0, 1.0);
      _positionY = (localPosition.dy / containerSize.height).clamp(0.0, 1.0);
    });
    _generatePreview();
  }

  void _setPresetPosition(double x, double y) {
    setState(() {
      _positionX = x;
      _positionY = y;
    });
    _generatePreview();
  }

  Future<void> _applyWatermark() async {
    try {
      print('🎯 Applying watermark with custom settings:');
      print('  - Position: (${_positionX.toStringAsFixed(2)}, ${_positionY.toStringAsFixed(2)})');
      print('  - Size: ${(_size * 100).round()}%');
      print('  - Opacity: ${(_opacity * 100).round()}%');
      
      final watermarkedBytes = await WatermarkingService.applyUsernameWatermark(
        imageBytes: _originalImageBytes!,
        username: widget.username,
      );

      final tempFile = File('${widget.imagePath}_watermarked.jpg');
      await tempFile.writeAsBytes(watermarkedBytes);

      widget.onWatermarkApplied(tempFile.path);
      Navigator.pop(context);
    } catch (e) {
      print('Error applying watermark: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error applying watermark: $e'),
          backgroundColor: const Color(0xFF5C0000),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.black, Color(0xFF2B0000)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Compact Header
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                    ),
                    const Expanded(
                      child: Text(
                        'Position Watermark',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF5C0000),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: TextButton(
                        onPressed: _applyWatermark,
                        child: const Text(
                          'APPLY',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Image Preview
              Expanded(
                child: Container(
                  decoration: const BoxDecoration(
                    color: Colors.black,
                  ),
                  child: _isLoading
                      ? const Center(
                          child: CircularProgressIndicator(
                            color: Color(0xFF5C0000),
                          ),
                        )
                      : LayoutBuilder(
                          builder: (context, constraints) {
                            return Stack(
                              children: [
                                GestureDetector(
                                  key: _imageKey,
                                  onPanStart: (details) {
                                    setState(() {
                                      _isDragging = true;
                                    });
                                  },
                                  onPanUpdate: (details) {
                                    if (_isDragging) {
                                      final RenderBox? renderBox =
                                          _imageKey.currentContext?.findRenderObject() as RenderBox?;
                                      if (renderBox != null) {
                                        final localPosition = renderBox.globalToLocal(details.globalPosition);
                                        _updateWatermarkPosition(localPosition, renderBox.size);
                                      }
                                    }
                                  },
                                  onPanEnd: (details) {
                                    setState(() {
                                      _isDragging = false;
                                    });
                                  },
                                  child: Image.memory(
                                    _previewImageBytes!,
                                    fit: BoxFit.contain,
                                    width: double.infinity,
                                    height: double.infinity,
                                    frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
                                      if (frame != null && _imageDisplaySize == null) {
                                        WidgetsBinding.instance.addPostFrameCallback((_) {
                                          final RenderBox? renderBox =
                                              _imageKey.currentContext?.findRenderObject() as RenderBox?;
                                          if (renderBox != null) {
                                            setState(() {
                                              _imageDisplaySize = renderBox.size;
                                            });
                                          }
                                        });
                                      }
                                      return child;
                                    },
                                  ),
                                ),
                                // Grid overlay when dragging
                                if (_isDragging)
                                  Positioned.fill(
                                    child: CustomPaint(
                                      painter: GridPainter(),
                                    ),
                                  ),
                              ],
                            );
                          },
                        ),
                ),
              ),

              // Compact Controls Panel
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A0000).withOpacity(0.8),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF5C0000), width: 1),
                ),
                child: Column(
                  children: [
                    // Quick Position Presets
                    const Text(
                      'QUICK POSITION',
                      style: TextStyle(
                        color: Color(0xFF5C0000),
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _buildPresetButton('TL', () => _setPresetPosition(0.1, 0.1)),
                        _buildPresetButton('TR', () => _setPresetPosition(0.9, 0.1)),
                        _buildPresetButton('CENTER', () => _setPresetPosition(0.5, 0.5)),
                        _buildPresetButton('BL', () => _setPresetPosition(0.1, 0.9)),
                        _buildPresetButton('BR', () => _setPresetPosition(0.9, 0.9)),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Position Coordinates
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2B0000).withOpacity(0.5),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF5C0000), width: 1),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _buildCoordinateDisplay('X', (_positionX * 100).round()),
                          Container(
                            width: 1,
                            height: 30,
                            color: const Color(0xFF5C0000),
                          ),
                          _buildCoordinateDisplay('Y', (_positionY * 100).round()),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Size and Opacity Controls
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2B0000).withOpacity(0.5),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF5C0000), width: 1),
                      ),
                      child: Column(
                        children: [
                          // Size Control
                          Row(
                            children: [
                              const Icon(Icons.zoom_in, color: Color(0xFF5C0000), size: 20),
                              const SizedBox(width: 12),
                              const Text(
                                'Size:',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Slider(
                                  value: _size,
                                  min: 0.1,
                                  max: 2.0,
                                  divisions: 19,
                                  activeColor: const Color(0xFF5C0000),
                                  inactiveColor: const Color(0xFF5C0000).withOpacity(0.3),
                                  onChanged: (value) {
                                    setState(() {
                                      _size = value;
                                    });
                                    _generatePreview();
                                  },
                                ),
                              ),
                              Container(
                                width: 50,
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF5C0000).withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  '${(_size * 100).round()}%',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          
                          // Opacity Control
                          Row(
                            children: [
                              const Icon(Icons.opacity, color: Color(0xFF5C0000), size: 20),
                              const SizedBox(width: 12),
                              const Text(
                                'Opacity:',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Slider(
                                  value: _opacity,
                                  min: 0.1,
                                  max: 1.0,
                                  divisions: 9,
                                  activeColor: const Color(0xFF5C0000),
                                  inactiveColor: const Color(0xFF5C0000).withOpacity(0.3),
                                  onChanged: (value) {
                                    setState(() {
                                      _opacity = value;
                                    });
                                    _generatePreview();
                                  },
                                ),
                              ),
                              Container(
                                width: 50,
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF5C0000).withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  '${(_opacity * 100).round()}%',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Instructions
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF5C0000).withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF5C0000), width: 1),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.info_outline, color: Color(0xFF5C0000), size: 16),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Drag to position • Use presets for quick placement • Adjust size and opacity with sliders',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPresetButton(String label, VoidCallback onTap) {
    final isSelected = (label == 'TL' && _positionX == 0.1 && _positionY == 0.1) ||
                      (label == 'TR' && _positionX == 0.9 && _positionY == 0.1) ||
                      (label == 'CENTER' && _positionX == 0.5 && _positionY == 0.5) ||
                      (label == 'BL' && _positionX == 0.1 && _positionY == 0.9) ||
                      (label == 'BR' && _positionX == 0.9 && _positionY == 0.9);
    
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF5C0000) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? const Color(0xFF5C0000) : Colors.white30,
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.white70,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildCoordinateDisplay(String axis, int value) {
    return Column(
      children: [
        Text(
          axis,
          style: const TextStyle(
            color: Color(0xFF5C0000),
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '$value%',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}

class GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF5C0000).withOpacity(0.3)
      ..strokeWidth = 1.0;

    // Draw vertical lines
    for (int i = 0; i <= 10; i++) {
      final x = (size.width / 10) * i;
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        paint,
      );
    }

    // Draw horizontal lines
    for (int i = 0; i <= 10; i++) {
      final y = (size.height / 10) * i;
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        paint,
      );
    }

    // Draw center lines
    final centerPaint = Paint()
      ..color = const Color(0xFF5C0000).withOpacity(0.6)
      ..strokeWidth = 2.0;

    canvas.drawLine(
      Offset(size.width / 2, 0),
      Offset(size.width / 2, size.height),
      centerPaint,
    );
    canvas.drawLine(
      Offset(0, size.height / 2),
      Offset(size.width, size.height / 2),
      centerPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
