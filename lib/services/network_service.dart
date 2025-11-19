import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import '../widgets/loading_screen.dart';

class NetworkService {
  static Timer? _connectionTimer;
  static bool _isConnected = true;
  static bool _isCheckingConnection = false;
  static final List<VoidCallback> _connectionListeners = [];
  static final List<VoidCallback> _disconnectionListeners = [];
  static BuildContext? _globalContext;
  static OverlayEntry? _loadingOverlay;
  static OverlayEntry? _statusBanner;
  static OverlayEntry? _fullScreenLoadingOverlay;
  
  // Network stability tracking
  static int _consecutiveFailures = 0;
  static const int _unstableThreshold = 2; // Consider unstable after 2 failures
  static const int _disconnectedThreshold = 3; // Consider disconnected after 3 failures

  // Check internet connectivity
  static Future<bool> checkConnectivity() async {
    try {
      final result = await InternetAddress.lookup('google.com');
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  // Set global context for showing overlays
  static void setGlobalContext(BuildContext context) {
    _globalContext = context;
  }

  // Adaptive monitoring: check more frequently when disconnected, less when connected
  static Duration _getMonitoringInterval() {
    if (!_isConnected) {
      return const Duration(seconds: 2); // Check every 2s when disconnected
    }
    return const Duration(seconds: 5); // Check every 5s when connected
  }

  // Start monitoring network connectivity with adaptive frequency
  static void startMonitoring() {
    _connectionTimer?.cancel();
    
    // Declare checkConnection function first
    void checkConnection() async {
      // Skip if already checking
      if (_isCheckingConnection) {
        _connectionTimer = Timer(_getMonitoringInterval(), checkConnection);
        return;
      }
      
      _isCheckingConnection = true;
      final isConnected = await checkConnectivity();
      _isCheckingConnection = false;
      
      // Track consecutive failures for stability detection
      if (!isConnected) {
        _consecutiveFailures++;
      } else {
        _consecutiveFailures = 0;
      }
      
      // Determine network state
      final wasConnected = _isConnected;
      final isUnstable = _consecutiveFailures >= _unstableThreshold && _consecutiveFailures < _disconnectedThreshold;
      final isDisconnected = _consecutiveFailures >= _disconnectedThreshold;
      
      // Update connection state
      if (isConnected && _consecutiveFailures == 0) {
        _isConnected = true;
      } else if (isDisconnected) {
        _isConnected = false;
      }
      
      // Handle state changes
      if (wasConnected != _isConnected || isUnstable) {
        if (_isConnected && !isUnstable) {
          // Connection restored
          _hideFullScreenLoadingOverlay();
          _hideNetworkStatusBanner();
          _notifyConnectionRestored();
        } else if (isDisconnected) {
          // Fully disconnected - show full screen loading
          _showFullScreenLoadingOverlay();
          _showNetworkStatusBanner();
          _notifyConnectionLost();
        } else if (isUnstable) {
          // Network unstable - show loading overlay
          _showFullScreenLoadingOverlay();
          _showNetworkStatusBanner();
        }
      } else if (!_isConnected || isUnstable) {
        // Still disconnected or unstable - keep showing overlays
        if (isDisconnected) {
          _showFullScreenLoadingOverlay();
        }
        _showNetworkStatusBanner();
      }
      
      // Schedule next check with adaptive interval
      _connectionTimer = Timer(_getMonitoringInterval(), checkConnection);
    }
    
    // Start first check
    checkConnection();
  }
  

  // Stop monitoring network connectivity
  static void stopMonitoring() {
    _connectionTimer?.cancel();
    _connectionTimer = null;
  }

  // Add connection listener
  static void addConnectionListener(VoidCallback listener) {
    _connectionListeners.add(listener);
  }

  // Remove connection listener
  static void removeConnectionListener(VoidCallback listener) {
    _connectionListeners.remove(listener);
  }

  // Add disconnection listener
  static void addDisconnectionListener(VoidCallback listener) {
    _disconnectionListeners.add(listener);
  }

  // Remove disconnection listener
  static void removeDisconnectionListener(VoidCallback listener) {
    _disconnectionListeners.remove(listener);
  }

  // Notify connection restored
  static void _notifyConnectionRestored() {
    for (var listener in _connectionListeners) {
      listener();
    }
  }

  // Notify connection lost
  static void _notifyConnectionLost() {
    for (var listener in _disconnectionListeners) {
      listener();
    }
  }

  // Execute with network retry
  static Future<T> executeWithRetry<T>(
    Future<T> Function() operation, {
    int maxRetries = 3,
    Duration retryDelay = const Duration(seconds: 2),
    String? loadingMessage,
    BuildContext? context,
    bool showNetworkErrors = true,
  }) async {
    int attempts = 0;
    String? lastError;
    
    while (attempts < maxRetries) {
      try {
        // Check connectivity before attempting
        final isConnected = await checkConnectivity();
        if (!isConnected) {
          lastError = 'No internet connection';
          
          // Show network status banner if not already shown
          if (!_isConnected) {
            _showNetworkStatusBanner();
          }
          
          // Show loading with network checking message
          if (context != null && loadingMessage != null) {
            _showLoadingOverlay(context, "Checking network connection...");
            // Wait a bit and check again
            await Future.delayed(const Duration(seconds: 1));
            final retryCheck = await checkConnectivity();
            _hideLoadingOverlay(context);
            
            if (!retryCheck) {
              if (showNetworkErrors) {
                showNetworkErrorDialog(
                  context,
                  lastError,
                  onRetry: () {
                    executeWithRetry(
                      operation,
                      maxRetries: maxRetries,
                      retryDelay: retryDelay,
                      loadingMessage: loadingMessage,
                      context: context,
                      showNetworkErrors: showNetworkErrors,
                    );
                  },
                );
              }
              throw Exception(lastError);
            }
          } else {
            throw Exception(lastError);
          }
        }
        
        // Show loading if context provided
        if (context != null && loadingMessage != null) {
          _showLoadingOverlay(context, loadingMessage);
        }
        
        // Execute operation with timeout
        final result = await operation().timeout(
          const Duration(seconds: 30),
          onTimeout: () {
            throw Exception('Request timeout - network may be unstable');
          },
        );
        
        // Hide loading if shown
        if (context != null && loadingMessage != null) {
          _hideLoadingOverlay(context);
        }
        
        return result;
      } catch (e) {
        attempts++;
        lastError = e.toString();
        
        print('🚨🚨🚨 NetworkService.executeWithRetry: Attempt $attempts/$maxRetries FAILED');
        print('🚨 Error: $lastError');
        print('🚨 Error type: ${e.runtimeType}');
        
        // Hide loading if shown
        if (context != null && loadingMessage != null) {
          _hideLoadingOverlay(context);
        }
        
        // Check if it's a network error
        final isNetworkError = lastError.contains('network') ||
            lastError.contains('connection') ||
            lastError.contains('timeout') ||
            lastError.contains('internet');
        
        if (isNetworkError && !_isConnected) {
          // Network is disconnected, show banner
          _showNetworkStatusBanner();
        }
        
        if (attempts >= maxRetries) {
          print('❌❌❌ NetworkService.executeWithRetry: ALL RETRIES EXHAUSTED!');
          print('❌ Final error: $lastError');
          if (showNetworkErrors && context != null && isNetworkError) {
            showNetworkErrorDialog(
              context,
              lastError,
              onRetry: () {
                executeWithRetry(
                  operation,
                  maxRetries: maxRetries,
                  retryDelay: retryDelay,
                  loadingMessage: loadingMessage,
                  context: context,
                  showNetworkErrors: showNetworkErrors,
                );
              },
            );
          }
          rethrow;
        }
        
        // Show retry message if context provided
        if (context != null && loadingMessage != null) {
          _showLoadingOverlay(
            context,
            "Network unstable. Retrying... (${attempts + 1}/$maxRetries)",
          );
        }
        
        // Wait before retry with exponential backoff
        await Future.delayed(Duration(
          milliseconds: retryDelay.inMilliseconds * (attempts + 1),
        ));
      }
    }
    
    throw Exception('Max retries exceeded: $lastError');
  }

  // Execute with network loading screen
  static Future<T> executeWithNetworkLoading<T>(
    BuildContext context,
    Future<T> Function() operation, {
    required String loadingMessage,
    int maxRetries = 3,
    Duration retryDelay = const Duration(seconds: 2),
  }) async {
    return executeWithRetry(
      operation,
      maxRetries: maxRetries,
      retryDelay: retryDelay,
      loadingMessage: loadingMessage,
      context: context,
    );
  }

  // Show network error dialog
  static void showNetworkErrorDialog(
    BuildContext context,
    String error, {
    VoidCallback? onRetry,
    VoidCallback? onCancel,
  }) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1a1a1a),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(
              Icons.wifi_off_rounded,
              color: Colors.red,
              size: 24,
            ),
            const SizedBox(width: 12),
            const Text(
              "Connection Error",
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Unable to connect to the server:",
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.withOpacity(0.3)),
              ),
              child: Text(
                error,
                style: const TextStyle(color: Colors.red, fontSize: 12),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              "Please check your internet connection and try again.",
              style: TextStyle(color: Colors.white60, fontSize: 12),
            ),
          ],
        ),
        actions: [
          if (onCancel != null)
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                onCancel();
              },
              child: const Text(
                "Cancel",
                style: TextStyle(color: Colors.white60),
              ),
            ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              if (onRetry != null) onRetry();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.refresh_rounded, color: Colors.white, size: 16),
                SizedBox(width: 8),
                Text(
                  "Retry",
                  style: TextStyle(color: Colors.white),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Show loading overlay
  static void _showLoadingOverlay(BuildContext context, String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => LoadingScreen(message: message),
    );
  }

  // Hide loading overlay
  static void _hideLoadingOverlay(BuildContext context) {
    Navigator.of(context).pop();
  }

  // Get current connection status
  static bool get isConnected => _isConnected;
  static bool get isCheckingConnection => _isCheckingConnection;

  // Hide network loading overlay (used when connection is restored)
  static void _hideNetworkLoadingOverlay() {
    if (_loadingOverlay != null) {
      try {
        _loadingOverlay!.remove();
      } catch (e) {
        // Ignore errors
      }
      _loadingOverlay = null;
    }
  }

  // Show full-screen loading overlay when network is lost or unstable
  static void _showFullScreenLoadingOverlay() {
    if (_globalContext == null || _fullScreenLoadingOverlay != null) return;
    
    try {
      final overlay = Overlay.of(_globalContext!);
      _fullScreenLoadingOverlay = OverlayEntry(
        builder: (context) => Material(
          color: Colors.black.withOpacity(0.85),
          child: const LoadingScreen(
            message: "No internet connection. Please check your network...",
            showProgress: true,
          ),
        ),
      );
      overlay.insert(_fullScreenLoadingOverlay!);
    } catch (e) {
      // Context might be invalid, ignore
      _fullScreenLoadingOverlay = null;
    }
  }

  // Hide full-screen loading overlay
  static void _hideFullScreenLoadingOverlay() {
    if (_fullScreenLoadingOverlay != null) {
      try {
        _fullScreenLoadingOverlay!.remove();
      } catch (e) {
        // Ignore errors
      }
      _fullScreenLoadingOverlay = null;
    }
  }

  // Show network status banner at top
  static void _showNetworkStatusBanner() {
    if (_globalContext == null || _statusBanner != null) return;
    
    try {
      final overlay = Overlay.of(_globalContext!);
      _statusBanner = OverlayEntry(
        builder: (context) => Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: Material(
            color: Colors.red.withOpacity(0.9),
            child: SafeArea(
              bottom: false,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    const Icon(
                      Icons.wifi_off_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _consecutiveFailures >= _disconnectedThreshold
                            ? "No internet connection. Checking..."
                            : "Network unstable. Checking...",
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      overlay.insert(_statusBanner!);
    } catch (e) {
      // Context might be invalid, ignore
      _statusBanner = null;
    }
  }

  // Hide network status banner
  static void _hideNetworkStatusBanner() {
    if (_statusBanner != null) {
      try {
        _statusBanner!.remove();
      } catch (e) {
        // Ignore errors
      }
      _statusBanner = null;
    }
  }

  // Check network with loading indicator
  static Future<bool> checkNetworkWithLoading(BuildContext context) async {
    // Show loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const LoadingScreen(
        message: "Checking network connection...",
      ),
    );

    try {
      final isConnected = await checkConnectivity();
      Navigator.of(context).pop(); // Hide loading
      
      if (!isConnected) {
        showNetworkErrorDialog(
          context,
          "No internet connection",
          onRetry: () => checkNetworkWithLoading(context),
        );
      }
      
      return isConnected;
    } catch (e) {
      Navigator.of(context).pop(); // Hide loading
      showNetworkErrorDialog(
        context,
        "Failed to check network: $e",
        onRetry: () => checkNetworkWithLoading(context),
      );
      return false;
    }
  }

  // Dispose resources
  static void dispose() {
    stopMonitoring();
    _hideNetworkLoadingOverlay();
    _hideFullScreenLoadingOverlay();
    _hideNetworkStatusBanner();
    _connectionListeners.clear();
    _disconnectionListeners.clear();
    _globalContext = null;
    _consecutiveFailures = 0;
  }
  
  // Get network status for UI
  static bool get isNetworkStable => _isConnected && _consecutiveFailures == 0;
  static bool get isNetworkUnstable => _consecutiveFailures >= _unstableThreshold && _consecutiveFailures < _disconnectedThreshold;
  static bool get isNetworkDisconnected => _consecutiveFailures >= _disconnectedThreshold;
  
  // Setup lifecycle observer to pause monitoring when app is backgrounded
  static void setupLifecycleObserver() {
    WidgetsBinding.instance.addObserver(_AppLifecycleObserver());
  }
  
  // Handle app lifecycle changes
  static void _handleAppLifecycleChange(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || 
        state == AppLifecycleState.inactive) {
      // Pause monitoring when app is backgrounded
      stopMonitoring();
    } else if (state == AppLifecycleState.resumed) {
      // Resume monitoring when app comes to foreground
      startMonitoring();
    }
  }
}

// App lifecycle observer for network monitoring
class _AppLifecycleObserver extends WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    NetworkService._handleAppLifecycleChange(state);
  }
}
