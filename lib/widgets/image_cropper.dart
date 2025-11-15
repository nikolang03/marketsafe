
import 'dart:io';
import 'package:flutter/material.dart';

class ImageCropper extends StatefulWidget {
  final File imageFile;
  final double cropAspectRatio;
  final VoidCallback? onCropComplete;
  final Function(File)? onCropSave;

  const ImageCropper({
    super.key,
    required this.imageFile,
    this.cropAspectRatio = 1.0,
    this.onCropComplete,
    this.onCropSave,
  });

  @override
  State<ImageCropper> createState() => _ImageCropperState();
}

class _ImageCropperState extends State<ImageCropper> {
  late TransformationController _transformationController;
  double _scale = 1.0;

  @override
  void initState() {
    super.initState();
    _transformationController = TransformationController();
  }

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }

  void _onInteractionStart(ScaleStartDetails details) {
    // Interaction started
  }

  void _onInteractionUpdate(ScaleUpdateDetails details) {
    setState(() {
      _scale = (_scale * details.scale).clamp(0.5, 5.0);
    });
  }

  void _onInteractionEnd(ScaleEndDetails details) {
    // Interaction ended
  }

  void _resetCrop() {
    setState(() {
      _scale = 1.0;
    });
    _transformationController.value = Matrix4.identity();
  }

  void _applyCrop() async {
    try {
      // For now, we'll just save the original image
      // In a real implementation, you'd apply the crop transformation
      if (widget.onCropSave != null) {
        widget.onCropSave!(widget.imageFile);
      }
      
      if (widget.onCropComplete != null) {
        widget.onCropComplete!();
      }
    } catch (e) {
      print('❌ Error applying crop: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Crop Image',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: _resetCrop,
            child: const Text(
              'Reset',
              style: TextStyle(color: Colors.white),
            ),
          ),
          TextButton(
            onPressed: _applyCrop,
            child: const Text(
              'Done',
              style: TextStyle(
                color: Colors.blue,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
      body: Center(
        child: Container(
          width: double.infinity,
          height: MediaQuery.of(context).size.width / widget.cropAspectRatio,
          decoration: BoxDecoration(
            border: Border.all(color: Colors.white, width: 2),
            borderRadius: BorderRadius.circular(8),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: InteractiveViewer(
              transformationController: _transformationController,
              minScale: 0.5,
              maxScale: 5.0,
              onInteractionStart: _onInteractionStart,
              onInteractionUpdate: _onInteractionUpdate,
              onInteractionEnd: _onInteractionEnd,
              child: Image.file(
                widget.imageFile,
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
              ),
            ),
          ),
        ),
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(16),
        color: Colors.black,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Instructions
            const Text(
              'Pinch to zoom • Drag to move',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 8),
            // Aspect ratio info
            Text(
              'Aspect Ratio: ${widget.cropAspectRatio.toStringAsFixed(1)}:1',
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}





