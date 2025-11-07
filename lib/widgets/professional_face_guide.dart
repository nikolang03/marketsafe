
import 'package:flutter/material.dart';

class ProfessionalFaceGuide extends StatefulWidget {
  final Map<String, dynamic>? positionData;
  final bool isVisible;
  final double screenWidth;
  final double screenHeight;
  final bool isAuthenticating;
  final VoidCallback? onStartScanning;
  final VoidCallback? onStopScanning;

  const ProfessionalFaceGuide({
    Key? key,
    this.positionData,
    required this.isVisible,
    required this.screenWidth,
    required this.screenHeight,
    this.isAuthenticating = false,
    this.onStartScanning,
    this.onStopScanning,
  }) : super(key: key);

  @override
  State<ProfessionalFaceGuide> createState() => _ProfessionalFaceGuideState();
}

class _ProfessionalFaceGuideState extends State<ProfessionalFaceGuide>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late AnimationController _scanController;
  late Animation<double> _pulseAnimation;
  late Animation<double> _scanAnimation;
  
  int _currentStep = 0;
  bool _isScanning = false;
  
  final List<Map<String, dynamic>> _scanningSteps = [
    {
      'title': 'Position Your Face',
      'description': 'Center your face within the oval frame',
      'icon': Icons.face,
      'color': Colors.blue,
    },
    {
      'title': 'Check Distance',
      'description': 'Keep your face 12-18 inches from the camera',
      'icon': Icons.straighten,
      'color': Colors.green,
    },
    {
      'title': 'Look Straight',
      'description': 'Keep your head straight and look at the camera',
      'icon': Icons.visibility,
      'color': Colors.orange,
    },
    {
      'title': 'Check Lighting',
      'description': 'Ensure good, even lighting on your face',
      'icon': Icons.wb_sunny,
      'color': Colors.yellow,
    },
  ];

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    );
    _scanController = AnimationController(
      duration: const Duration(seconds: 3),
      vsync: this,
    );
    
    _pulseAnimation = Tween<double>(
      begin: 0.8,
      end: 1.2,
    ).animate(CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    ));
    
    _scanAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _scanController,
      curve: Curves.easeInOut,
    ));
    
    _pulseController.repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _scanController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isVisible) return const SizedBox.shrink();

    return Stack(
      children: [
        // Clean elliptical camera frame
        _buildEllipticalFrame(),
        
        // Scanning progress overlay
        if (widget.isAuthenticating) _buildScanningOverlay(),
        
        // Compact status indicator
        _buildCompactStatusIndicator(),
      ],
    );
  }

  Widget _buildEllipticalFrame() {
    return Center(
      child: Container(
        width: 300,
        height: 400,
        decoration: BoxDecoration(
          shape: BoxShape.rectangle,
          borderRadius: BorderRadius.circular(150),
          border: Border.all(
            color: _getFrameColor(),
            width: 3,
          ),
          boxShadow: [
            BoxShadow(
              color: _getFrameColor().withOpacity(0.2),
              blurRadius: 15,
              spreadRadius: 2,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(150),
          child: Stack(
            children: [
              // Face detection overlay
              if (widget.positionData != null)
                _buildFaceDetectionOverlay(),
              
              // Clean scanning indicator
              if (_isScanning)
                _buildCleanScanningIndicator(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFaceDetectionOverlay() {
    final positionData = widget.positionData!;
    final faceCenter = positionData['faceCenter'] as Map<String, dynamic>;
    final isGoodPosition = positionData['score'] >= 75;
    
    return Positioned(
      left: (faceCenter['x'] as double) - 50,
      top: (faceCenter['y'] as double) - 50,
      child: AnimatedBuilder(
        animation: _pulseAnimation,
        builder: (context, child) {
          return Transform.scale(
            scale: _pulseAnimation.value,
            child: Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isGoodPosition ? Colors.green : Colors.orange,
                  width: 2,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildCleanScanningIndicator() {
    return AnimatedBuilder(
      animation: _scanAnimation,
      builder: (context, child) {
        return Center(
          child: Container(
            width: 200,
            height: 200,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.green.withOpacity(0.8),
                width: 2,
              ),
            ),
            child: Stack(
              children: [
                // Rotating scanning line
                Center(
                  child: Transform.rotate(
                    angle: _scanAnimation.value * 2 * 3.14159,
                    child: Container(
                      width: 2,
                      height: 100,
                      decoration: BoxDecoration(
                        color: Colors.green,
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                  ),
                ),
                // Center dot
                Center(
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: Colors.green,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCompactStatusIndicator() {
    if (widget.positionData == null) return const SizedBox.shrink();
    
    final positionData = widget.positionData!;
    final status = positionData['status'] as String;
    final score = positionData['score'] as int;
    final lighting = positionData['lighting'] as Map<String, dynamic>?;
    
    return Positioned(
      top: 20,
      left: 20,
      right: 20,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.7),
          borderRadius: BorderRadius.circular(25),
          border: Border.all(
            color: _getStatusColor(status),
            width: 2,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Status indicator
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: _getStatusColor(status),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '$status ($score%)',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
            
            // Lighting indicator
            if (lighting != null) ...[
              const SizedBox(width: 16),
              Icon(
                _getLightingIcon(lighting['lightingStatus']),
                color: _getLightingColor(lighting['lightingStatus']),
                size: 16,
              ),
              const SizedBox(width: 4),
              Text(
                '${lighting['lightingStatus']}',
                style: TextStyle(
                  color: _getLightingColor(lighting['lightingStatus']),
                  fontSize: 12,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }


  Widget _buildInstructions() {
    final currentStep = _scanningSteps[_currentStep];
    
    return Column(
      children: [
        Text(
          currentStep['title'],
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          currentStep['description'],
          style: TextStyle(
            color: Colors.white.withOpacity(0.8),
            fontSize: 14,
          ),
          textAlign: TextAlign.center,
        ),
        
        // Additional guidance based on position data
        if (widget.positionData != null)
          _buildDetailedGuidance(),
      ],
    );
  }

  Widget _buildDetailedGuidance() {
    final positionData = widget.positionData!;
    final instructions = positionData['instructions'] as List<String>;
    
    if (instructions.isEmpty) return const SizedBox.shrink();
    
    return Column(
      children: [
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.orange.withOpacity(0.2),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: Colors.orange.withOpacity(0.5),
              width: 1,
            ),
          ),
          child: Column(
            children: instructions.take(3).map((instruction) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    color: Colors.orange,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      instruction,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            )).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildStatusIndicator() {
    if (widget.positionData == null) return const SizedBox.shrink();
    
    final positionData = widget.positionData!;
    final status = positionData['status'] as String;
    final score = positionData['score'] as int;
    final lighting = positionData['lighting'] as Map<String, dynamic>?;
    
    return Positioned(
      bottom: 120,
      left: 20,
      right: 20,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.8),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _getStatusColor(status),
            width: 2,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Overall status
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: _getStatusColor(status),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Status: $status ($score%)',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            
            // Lighting status
            if (lighting != null) ...[
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    _getLightingIcon(lighting['lightingStatus']),
                    color: _getLightingColor(lighting['lightingStatus']),
                    size: 16,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Lighting: ${lighting['lightingStatus']} (${lighting['lightingScore']}%)',
                    style: TextStyle(
                      color: _getLightingColor(lighting['lightingStatus']),
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildScanningOverlay() {
    return Container(
      width: widget.screenWidth,
      height: widget.screenHeight,
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.3),
        borderRadius: BorderRadius.circular(175),
      ),
      child: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
              color: Colors.green,
              strokeWidth: 4,
            ),
            SizedBox(height: 16),
            Text(
              'Authenticating...',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons() {
    return Positioned(
      bottom: 40,
      left: 20,
      right: 20,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // Start/Stop scanning button
          ElevatedButton.icon(
            onPressed: _isScanning ? _stopScanning : _startScanning,
            icon: Icon(_isScanning ? Icons.stop : Icons.play_arrow),
            label: Text(_isScanning ? 'Stop Scanning' : 'Start Scanning'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _isScanning ? Colors.red : Colors.green,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(25),
              ),
            ),
          ),
          
          // Next step button
          if (_currentStep < _scanningSteps.length - 1)
            ElevatedButton.icon(
              onPressed: _nextStep,
              icon: const Icon(Icons.arrow_forward),
              label: const Text('Next'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(25),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _startScanning() {
    setState(() {
      _isScanning = true;
    });
    _scanController.repeat();
    widget.onStartScanning?.call();
  }

  void _stopScanning() {
    setState(() {
      _isScanning = false;
    });
    _scanController.stop();
    widget.onStopScanning?.call();
  }

  void _nextStep() {
    if (_currentStep < _scanningSteps.length - 1) {
      setState(() {
        _currentStep++;
      });
    }
  }

  Color _getFrameColor() {
    if (widget.positionData == null) return Colors.grey;
    final score = widget.positionData!['score'] as int;
    if (score >= 90) return Colors.green;
    if (score >= 75) return Colors.lightGreen;
    if (score >= 50) return Colors.orange;
    return Colors.red;
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'PERFECT':
        return Colors.green;
      case 'GOOD':
        return Colors.lightGreen;
      case 'FAIR':
        return Colors.orange;
      case 'POOR':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  IconData _getLightingIcon(String status) {
    switch (status) {
      case 'EXCELLENT':
        return Icons.wb_sunny;
      case 'GOOD':
        return Icons.wb_sunny_outlined;
      case 'FAIR':
        return Icons.wb_cloudy;
      case 'POOR':
        return Icons.wb_cloudy_outlined;
      default:
        return Icons.lightbulb_outline;
    }
  }

  Color _getLightingColor(String status) {
    switch (status) {
      case 'EXCELLENT':
        return Colors.yellow;
      case 'GOOD':
        return Colors.lightGreen;
      case 'FAIR':
        return Colors.orange;
      case 'POOR':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }
}

class ScanningLinesPainter extends CustomPainter {
  final double progress;
  
  ScanningLinesPainter(this.progress);
  
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.green.withOpacity(0.6)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;
    
    // Draw scanning lines
    final centerX = size.width / 2;
    final centerY = size.height / 2;
    final radius = size.width / 2;
    
    // Horizontal scanning line
    final scanY = centerY + (progress - 0.5) * size.height;
    canvas.drawLine(
      Offset(centerX - radius * 0.8, scanY),
      Offset(centerX + radius * 0.8, scanY),
      paint,
    );
    
    // Vertical scanning line
    final scanX = centerX + (progress - 0.5) * size.width;
    canvas.drawLine(
      Offset(scanX, centerY - radius * 0.8),
      Offset(scanX, centerY + radius * 0.8),
      paint,
    );
  }
  
  @override
  bool shouldRepaint(ScanningLinesPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
