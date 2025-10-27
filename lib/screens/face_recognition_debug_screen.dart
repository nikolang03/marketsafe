import 'package:flutter/material.dart';
import '../services/face_recognition_test_service.dart';

class FaceRecognitionDebugScreen extends StatefulWidget {
  const FaceRecognitionDebugScreen({super.key});

  @override
  State<FaceRecognitionDebugScreen> createState() => _FaceRecognitionDebugScreenState();
}

class _FaceRecognitionDebugScreenState extends State<FaceRecognitionDebugScreen> {
  bool _isLoading = false;
  Map<String, dynamic> _testResults = {};
  Map<String, dynamic> _recognitionStats = {};

  @override
  void initState() {
    super.initState();
    _runTests();
  }

  Future<void> _runTests() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final testResults = await FaceRecognitionTestService.testFaceEmbeddings();
      final recognitionStats = await FaceRecognitionTestService.getRecognitionStats();
      
      setState(() {
        _testResults = testResults;
        _recognitionStats = recognitionStats;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error running tests: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Face Recognition Debug'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Face Recognition Debug Information',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            
            if (_isLoading)
              const Center(child: CircularProgressIndicator())
            else ...[
              // Test Results Card
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Database Test Results',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 10),
                      if (_testResults.isNotEmpty) ...[
                        Text('Face Embeddings: ${_testResults['faceEmbeddingsCount'] ?? 0}'),
                        Text('Completed Users: ${_testResults['completedUsersCount'] ?? 0}'),
                        Text('Biometric Users: ${_testResults['biometricUsersCount'] ?? 0}'),
                        Text('Total Documents: ${_testResults['totalDocuments'] ?? 0}'),
                        
                        const SizedBox(height: 10),
                        const Text('Face Embeddings:', style: TextStyle(fontWeight: FontWeight.bold)),
                        ...(_testResults['faceEmbeddings'] as List<dynamic>? ?? []).map((embedding) => 
                          Text('  - User: ${embedding['userId']}, Size: ${embedding['embeddingSize']}D, Active: ${embedding['isActive']}')),
                        
                        const SizedBox(height: 10),
                        const Text('Completed Users:', style: TextStyle(fontWeight: FontWeight.bold)),
                        ...(_testResults['completedUsers'] as List<dynamic>? ?? []).map((user) => 
                          Text('  - User: ${user['userId']}, Status: ${user['verificationStatus']}, Completed: ${user['signupCompleted']}')),
                        
                        const SizedBox(height: 10),
                        const Text('Biometric Users:', style: TextStyle(fontWeight: FontWeight.bold)),
                        ...(_testResults['biometricUsers'] as List<dynamic>? ?? []).map((user) => 
                          Text('  - User: ${user['userId']}, Signature Size: ${user['biometricSignatureSize']}D, Type: ${user['biometricType']}')),
                      ] else
                        const Text('No test results available'),
                    ],
                  ),
                ),
              ),
              
              const SizedBox(height: 20),
              
              // Recognition Stats Card
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Recognition Statistics',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 10),
                      if (_recognitionStats.isNotEmpty) ...[
                        Text('Total Attempts: ${_recognitionStats['totalAttempts'] ?? 0}'),
                        Text('Success Count: ${_recognitionStats['successCount'] ?? 0}'),
                        Text('Failure Count: ${_recognitionStats['failureCount'] ?? 0}'),
                        Text('Success Rate: ${(_recognitionStats['successRate'] ?? 0.0).toStringAsFixed(2)}'),
                        Text('Average Similarity: ${(_recognitionStats['averageSimilarity'] ?? 0.0).toStringAsFixed(4)}'),
                      ] else
                        const Text('No recognition statistics available'),
                    ],
                  ),
                ),
              ),
              
              const SizedBox(height: 20),
              
              // Refresh Button
              Center(
                child: ElevatedButton.icon(
                  onPressed: _runTests,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Refresh Tests'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
