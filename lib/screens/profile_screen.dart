import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:ui';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import 'simple_profile_photo_screen.dart';
import '../models/product_model.dart';
import '../services/product_service.dart';
import 'product_preview_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Map<String, dynamic>? userData;
  bool isLoading = true;
  String? error;
  String? profileImagePath;
  String? profilePhotoUrl;
  List<Product> userProducts = [];
  bool isLoadingProducts = false;

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _loadUserProducts();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reload data when screen comes into focus to show updated profile photo
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshUserData();
      _loadUserProducts();
    });
  }

  Future<void> _loadUserData() async {
    try {
      // Get the current user ID from SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString('signup_user_id') ?? 
                    prefs.getString('current_user_id') ?? '';
      
      print('🔍 Profile Screen Debug:');
      print('  - signup_user_id: ${prefs.getString('signup_user_id')}');
      print('  - current_user_id: ${prefs.getString('current_user_id')}');
      print('  - profile_image_path: ${prefs.getString('profile_image_path')}');
      print('  - Final userId: $userId');
      
      // Debug: Print all SharedPreferences keys
      final keys = prefs.getKeys();
      print('🔍 All SharedPreferences keys: $keys');
      
      if (userId.isEmpty) {
        setState(() {
          error = 'No user logged in';
          isLoading = false;
        });
        return;
      }

      // Get user data from Firestore
      final userDoc = await FirebaseFirestore.instanceFor(
        app: Firebase.app(),
        databaseId: 'marketsafe',
      ).collection('users').doc(userId).get();

      if (userDoc.exists) {
        setState(() {
          userData = userDoc.data();
          // Get profile photo URL from Firebase Storage (priority)
          profilePhotoUrl = userData?['profilePictureUrl'] ?? prefs.getString('profile_photo_url');
          // Fallback to local file path if Firebase URL is not available
          profileImagePath = prefs.getString('profile_image_path') ?? 
                           userData?['profileImagePath'];
          print('✅ Profile photo URL loaded: $profilePhotoUrl');
          print('✅ Profile image path loaded: $profileImagePath');
          print('✅ User data profileImagePath: ${userData?['profileImagePath']}');
          if (profileImagePath != null) {
            print('📸 File exists check: ${File(profileImagePath!).existsSync()}');
          }
          isLoading = false;
        });
      } else {
        setState(() {
          error = 'User data not found';
          isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        error = 'Error loading user data: $e';
        isLoading = false;
      });
    }
  }

  Future<void> _refreshUserData() async {
    try {
      // Get the current user ID from SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString('signup_user_id') ?? 
                    prefs.getString('current_user_id') ?? '';
      
      if (userId.isEmpty) return;

      print('🔄 Refreshing profile data for user: $userId');

      // Get updated user data from Firestore
      final userDoc = await FirebaseFirestore.instanceFor(
        app: Firebase.app(),
        databaseId: 'marketsafe',
      ).collection('users').doc(userId).get();

      if (userDoc.exists) {
        setState(() {
          userData = userDoc.data();
          // Get updated profile photo URL from Firebase Storage or SharedPreferences
          profilePhotoUrl = userData?['profilePictureUrl'] ?? prefs.getString('profile_photo_url');
          // Also check for updated local file path
          profileImagePath = prefs.getString('profile_image_path') ?? 
                           userData?['profileImagePath'];
          print('🔄 Refreshed profile photo URL: $profilePhotoUrl');
          print('🔄 Refreshed profile image path: $profileImagePath');
        });
      }
    } catch (e) {
      print('❌ Error refreshing user data: $e');
    }
  }

  Future<void> _loadUserProducts() async {
    try {
      setState(() {
        isLoadingProducts = true;
      });

      // Get the current user ID from SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString('signup_user_id') ?? 
                    prefs.getString('current_user_id') ?? '';
      
      if (userId.isEmpty) {
        setState(() {
          isLoadingProducts = false;
        });
        return;
      }

      print('🔍 Loading products for user: $userId');
      
      // Fetch user's products
      final allProducts = await ProductService.getUserProducts(userId);
      
      // Filter products: only show approved products in profile
      final filteredProducts = allProducts.where((product) {
        return product.moderationStatus == 'approved';
      }).toList();
      
      setState(() {
        userProducts = filteredProducts;
        isLoadingProducts = false;
      });
      
      print('✅ Loaded ${filteredProducts.length} approved products for user (${allProducts.length} total)');
    } catch (e) {
      print('❌ Error loading user products: $e');
      setState(() {
        isLoadingProducts = false;
      });
    }
  }


  Future<void> _logout() async {
    try {
      // Show confirmation dialog
      final shouldLogout = await showDialog<bool>(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            backgroundColor: Colors.grey[900],
            title: const Text(
              'Logout',
              style: TextStyle(color: Colors.white),
            ),
            content: const Text(
              'Are you sure you want to logout?',
              style: TextStyle(color: Colors.white),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text(
                  'Cancel',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text(
                  'Logout',
                  style: TextStyle(color: Colors.red),
                ),
              ),
            ],
          );
        },
      );

      if (shouldLogout == true) {
        // Clear SharedPreferences
        final prefs = await SharedPreferences.getInstance();
        await prefs.clear();
        print('✅ SharedPreferences cleared');

        // Sign out from Firebase Auth
        await FirebaseAuth.instance.signOut();
        print('✅ Firebase Auth sign out completed');

        // Navigate to welcome screen (you may need to adjust this based on your app structure)
        if (mounted) {
          Navigator.pushNamedAndRemoveUntil(
            context,
            '/welcome', // Adjust this route name based on your app
            (route) => false,
          );
        }
      }
    } catch (e) {
      print('❌ Error during logout: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Logout failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }


  Future<void> _navigateToSecureProfilePhotoUpload() async {
    try {
      // Get current user ID
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString('current_user_id') ?? prefs.getString('signup_user_id');
      
      if (userId == null) {
        _showErrorDialog('Error', 'No user logged in');
        return;
      }

      // Navigate to simple profile photo upload screen
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => const SimpleProfilePhotoScreen(),
        ),
      );
    } catch (e) {
      _showErrorDialog('Error', 'Failed to navigate to profile photo upload: $e');
    }
  }


  void _showProfilePreview() {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.grey[900],
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header with delete button
              Container(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Profile Picture',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    IconButton(
                      onPressed: () {
                        Navigator.pop(context);
                        _removeProfilePicture();
                      },
                      icon: const Icon(
                        Icons.delete_forever,
                        color: Colors.red,
                        size: 28,
                      ),
                      tooltip: 'Delete Profile Picture',
                    ),
                  ],
                ),
              ),
              // Profile image
              Container(
                padding: const EdgeInsets.all(20),
                child: _buildProfileImage(),
              ),
              // User info
              if (userData != null) ...[
                Text(
                  userData!['firstName'] != null && userData!['lastName'] != null
                      ? '${userData!['firstName']} ${userData!['lastName']}'
                      : userData!['username'] ?? 'User',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  userData!['email'] ?? '',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.7),
                    fontSize: 14,
                  ),
                ),
              ],
              const SizedBox(height: 20),
              // Close button
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text(
                  'Close',
                  style: TextStyle(
                    color: Colors.blue,
                    fontSize: 16,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _removeProfilePicture() async {
    try {
      // Show confirmation dialog
      final shouldRemove = await showDialog<bool>(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            backgroundColor: Colors.grey[900],
            title: const Text(
              'Remove Profile Picture',
              style: TextStyle(color: Colors.white),
            ),
            content: const Text(
              'Are you sure you want to remove your profile picture?',
              style: TextStyle(color: Colors.white70),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text(
                  'Cancel',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text(
                  'Remove',
                  style: TextStyle(color: Colors.red),
                ),
              ),
            ],
          );
        },
      );

      if (shouldRemove == true) {
        // Show loading indicator
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const Center(
            child: CircularProgressIndicator(color: Colors.white),
          ),
        );

        // Get current user ID
        final prefs = await SharedPreferences.getInstance();
        final userId = prefs.getString('current_user_id') ?? prefs.getString('signup_user_id');
        
        if (userId != null) {
          // Remove profile picture from Firestore
          await FirebaseFirestore.instanceFor(
            app: Firebase.app(),
            databaseId: 'marketsafe',
          ).collection('users').doc(userId).update({
            'profilePictureUrl': FieldValue.delete(),
            'profilePhotoUpdatedAt': FieldValue.serverTimestamp(),
          });
        }

        // Clear from SharedPreferences
        await prefs.remove('profile_photo_url');
        await prefs.remove('profile_image_path');
        await prefs.remove('profile_image_url');

        // Refresh user data
        await _refreshUserData();
        
        // Close loading dialog
        if (mounted) {
          Navigator.pop(context);
          
          // Show success message
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Profile picture removed successfully!'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      // Close loading dialog
      if (mounted) {
        Navigator.pop(context);
        
        // Show error message
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to remove profile picture: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showErrorDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: Text(
          title,
          style: const TextStyle(color: Colors.white),
        ),
        content: Text(
          message,
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'OK',
              style: TextStyle(color: Colors.blue),
            ),
          ),
        ],
      ),
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
          child: SafeArea(
            child: Column(
              children: [
                // Top bar (transparent like message screen)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const SizedBox(), // Spacer for centering
                      const SizedBox(), // Spacer for balance
                    ],
                  ),
                ),
                // Profile content
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _refreshUserData,
                    color: Colors.red,
                    child: isLoading
                        ? const SingleChildScrollView(
                            physics: AlwaysScrollableScrollPhysics(),
                            child: SizedBox(
                              height: 600,
                              child: Center(
                                child: CircularProgressIndicator(color: Colors.white),
                              ),
                            ),
                          )
                        : error != null
                            ? SingleChildScrollView(
                                physics: const AlwaysScrollableScrollPhysics(),
                                child: SizedBox(
                                  height: MediaQuery.of(context).size.height - 200,
                                  child: Center(
                                    child: Text(
                                      error!,
                                      style: const TextStyle(color: Colors.white),
                                    ),
                                  ),
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
                                      _buildStatItem(userProducts.length.toString(), "posts"),
                                      const SizedBox(width: 30),
                                      _buildStatItem("0", "followers"),
                                      const SizedBox(width: 30),
                                      _buildStatItem("0", "following"),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 20),
                            // Action Buttons
                            Row(
                              children: [
                                Expanded(
                                  child: _buildActionButton("Edit profile"),
                                ),
                                const SizedBox(width: 10),
                                // Logout Button
                                GestureDetector(
                                  onTap: _logout,
                                  child: Container(
                                    height: 40,
                                    width: 40,
                                    decoration: BoxDecoration(
                                      border: Border.all(color: Colors.white, width: 1),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Icon(
                                      Icons.logout,
                                      color: Colors.white,
                                      size: 20,
                                    ),
                                  ),
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
                                          width: 20,
                                          height: 2,
                                          color: Colors.white,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            // Content Grid
                            Padding(
                              padding: const EdgeInsets.all(20),
                              child: isLoadingProducts
                                  ? const Center(
                                      child: CircularProgressIndicator(color: Colors.white),
                                    )
                                  : userProducts.isEmpty
                                      ? Center(
                                          child: Column(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              Icon(
                                                Icons.add_photo_alternate_outlined,
                                                color: Colors.grey[600],
                                                size: 64,
                                              ),
                                              const SizedBox(height: 16),
                                              Text(
                                                'No products yet',
                                                style: TextStyle(
                                                  color: Colors.grey[600],
                                                  fontSize: 18,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                              const SizedBox(height: 8),
                                              Text(
                                                'Start selling by posting your first product!',
                                                style: TextStyle(
                                                  color: Colors.grey[500],
                                                  fontSize: 14,
                                                ),
                                                textAlign: TextAlign.center,
                                              ),
                                            ],
                                          ),
                                        )
                                      : GridView.builder(
                                          shrinkWrap: true,
                                          physics: const NeverScrollableScrollPhysics(),
                                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                            crossAxisCount: 3,
                                            crossAxisSpacing: 2,
                                            mainAxisSpacing: 2,
                                          ),
                                          itemCount: userProducts.length,
                                          itemBuilder: (context, index) {
                                            final product = userProducts[index];
                                            return _buildProductGridItem(product);
                                          },
                                        ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                            ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _getDisplayName() {
    if (userData == null) return "NAME";
    
    // Try to get full name first, then fallback to individual fields
    final fullName = userData!['fullName'] ?? '';
    if (fullName.isNotEmpty) return fullName.toUpperCase();
    
    final firstName = userData!['firstName'] ?? '';
    final lastName = userData!['lastName'] ?? '';
    if (firstName.isNotEmpty || lastName.isNotEmpty) {
      return '${firstName.toUpperCase()} ${lastName.toUpperCase()}'.trim();
    }
    
    final username = userData!['username'] ?? '';
    if (username.isNotEmpty) return username.toUpperCase();
    
    return "NAME";
  }

  String _getUsername() {
    if (userData == null) return "@username";
    
    final username = userData!['username'] ?? '';
    if (username.isNotEmpty) return '@${username.toLowerCase()}';
    
    return "@username";
  }

  Widget _buildStatItem(String number, String label) {
    return Column(
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
  }

  Widget _buildActionButton(String text) {
    return GestureDetector(
      onTap: text == "Edit profile" ? _showEditProfileDialog : null,
      child: Container(
        height: 40,
        decoration: BoxDecoration(
          border: Border.all(color: Colors.white, width: 1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: Text(
            text,
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

  Future<void> _showEditProfileDialog() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString('current_user_id') ?? prefs.getString('signup_user_id');
    
    if (userId == null) {
      _showErrorDialog('Error', 'No user logged in');
      return;
    }

    // Get current user data
    final firestore = FirebaseFirestore.instanceFor(
      app: Firebase.app(),
      databaseId: 'marketsafe',
    );
    
    final userDoc = await firestore.collection('users').doc(userId).get();
    if (!userDoc.exists) {
      _showErrorDialog('Error', 'User data not found');
      return;
    }

    final currentData = userDoc.data()!;
    
    // Initialize controllers with current values
    final firstNameController = TextEditingController(
      text: currentData['firstName'] ?? '',
    );
    final lastNameController = TextEditingController(
      text: currentData['lastName'] ?? '',
    );
    final usernameController = TextEditingController(
      text: currentData['username'] ?? '',
    );
    String? selectedGender = currentData['gender']?.toString();

    await showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.5),
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
          child: Dialog(
            backgroundColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Container(
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
              borderRadius: BorderRadius.all(Radius.circular(16)),
            ),
            padding: const EdgeInsets.all(24),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Edit Profile',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  
                  // First Name field
                  _buildEditField(
                    label: 'First Name',
                    controller: firstNameController,
                  ),
                  const SizedBox(height: 16),
                  
                  // Last Name field
                  _buildEditField(
                    label: 'Last Name',
                    controller: lastNameController,
                  ),
                  const SizedBox(height: 16),
                  
                  // Username field
                  _buildEditField(
                    label: 'Username',
                    controller: usernameController,
                  ),
                  const SizedBox(height: 16),
                  
                  // Gender field
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.grey[900],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey[800]!),
                    ),
                    child: DropdownButtonFormField<String>(
                      value: selectedGender,
                      decoration: InputDecoration(
                        labelText: 'Gender',
                        labelStyle: const TextStyle(color: Colors.grey),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                        border: InputBorder.none,
                      ),
                      dropdownColor: Colors.grey[900],
                      style: const TextStyle(color: Colors.white),
                      items: ['Male', 'Female', 'Other']
                          .map((gender) => DropdownMenuItem(
                                value: gender,
                                child: Text(gender, style: const TextStyle(color: Colors.white)),
                              ))
                          .toList(),
                      onChanged: (value) {
                        setDialogState(() {
                          selectedGender = value;
                        });
                      },
                    ),
                  ),
                  const SizedBox(height: 24),
                  
                  // Save button
                  ElevatedButton(
                    onPressed: () async {
                      await _saveProfileChanges(
                        userId: userId,
                        firstName: firstNameController.text.trim(),
                        lastName: lastNameController.text.trim(),
                        username: usernameController.text.trim(),
                        gender: selectedGender,
                      );
                      if (context.mounted) {
                        Navigator.pop(context);
                        _refreshUserData();
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Save',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  
                  // Cancel button
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                ],
              ),
            ),
          ),
          ),
        ),
      ),
    );
  }

  Widget _buildEditField({
    required String label,
    required TextEditingController controller,
    int maxLines = 1,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[800]!),
      ),
      child: TextField(
        controller: controller,
        style: const TextStyle(color: Colors.white),
        maxLines: maxLines,
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Colors.grey),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
        ),
      ),
    );
  }

  Future<void> _saveProfileChanges({
    required String userId,
    required String firstName,
    required String lastName,
    required String username,
    String? gender,
  }) async {
    try {
      setState(() {
        isLoading = true;
      });

      final firestore = FirebaseFirestore.instanceFor(
        app: Firebase.app(),
        databaseId: 'marketsafe',
      );

      // Update user data
      await firestore.collection('users').doc(userId).update({
        'firstName': firstName,
        'lastName': lastName,
        'fullName': '$firstName $lastName'.trim(),
        'username': username.trim(),
        if (gender != null) 'gender': gender,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profile updated successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      print('❌ Error updating profile: $e');
      if (mounted) {
        _showErrorDialog('Error', 'Failed to update profile: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  Widget _buildProfileImage() {
    Widget imageWidget;
    
    // Priority 1: Firebase Storage URL
    if (profilePhotoUrl != null && profilePhotoUrl!.isNotEmpty) {
      imageWidget = ClipOval(
        child: Image.network(
          profilePhotoUrl!,
          width: 100,
          height: 100,
          fit: BoxFit.cover,
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) return child;
            return Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: Colors.grey[800],
                shape: BoxShape.circle,
              ),
              child: const Center(
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              ),
            );
          },
          errorBuilder: (context, error, stackTrace) {
            print('❌ Error loading profile photo from Firebase: $error');
            // Fallback to local file if Firebase URL fails
            return _buildLocalProfileImage();
          },
        ),
      );
    } else {
      // Priority 2: Local file path
      imageWidget = _buildLocalProfileImage();
    }
    
    // Profile image with edit button overlay
    return Stack(
      children: [
        // Main profile image with click to preview
        GestureDetector(
          onTap: _showProfilePreview,
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withOpacity(0.3),
                width: 2,
              ),
            ),
            child: imageWidget,
          ),
        ),
        // Edit button positioned at bottom right
        Positioned(
          bottom: 0,
          right: 0,
          child: GestureDetector(
            onTap: _navigateToSecureProfilePhotoUpload,
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: Colors.red,
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white,
                  width: 2,
                ),
              ),
              child: const Icon(
                Icons.edit,
                color: Colors.white,
                size: 18,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLocalProfileImage() {
    if (profileImagePath != null && File(profileImagePath!).existsSync()) {
      return ClipOval(
        child: Image.file(
          File(profileImagePath!),
          width: 100,
          height: 100,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            print('❌ Error loading local profile image: $error');
            return Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: Colors.grey[800],
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.person,
                color: Colors.white,
                size: 50,
              ),
            );
          },
        ),
      );
    }
    
    // Default: Show person icon
    return Container(
      width: 100,
      height: 100,
      decoration: BoxDecoration(
        color: Colors.grey[800],
        shape: BoxShape.circle,
      ),
      child: const Icon(
        Icons.person,
        color: Colors.white,
        size: 50,
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

  Widget _buildProductGridItem(Product product) {
    return GestureDetector(
      onTap: () {
        // Navigate to product preview screen
        final productMap = {
          'id': product.id,
          'title': product.title,
          'price': product.price.toString(),
          'description': product.description,
          'details': product.description,
          'date': _formatProductDate(product.createdAt),
          'userId': product.sellerId,
          'sellerName': product.sellerName,
          'imageUrls': product.imageUrls,
          'videoUrl': product.videoUrl,
          'videoThumbnailUrl': product.videoThumbnailUrl,
          'mediaType': product.mediaType,
        };
        
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ProductPreviewScreen(
              product: productMap,
              currentUserId: userData?['id'] ?? '',
            ),
          ),
        );
      },
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: Colors.grey[700]!,
            width: 0.5,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Product image
              if (product.imageUrls.isNotEmpty)
                Image.network(
                  product.imageUrls.first,
                  fit: BoxFit.cover,
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    return Container(
                      color: Colors.grey[800],
                      child: const Center(
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      ),
                    );
                  },
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      color: Colors.grey[800],
                      child: const Icon(
                        Icons.image_not_supported,
                        color: Colors.grey,
                        size: 32,
                      ),
                    );
                  },
                )
              else
                Container(
                  color: Colors.grey[800],
                  child: const Icon(
                    Icons.image_not_supported,
                    color: Colors.grey,
                    size: 32,
                  ),
                ),
              // Status indicator
              if (product.status != 'active')
                Positioned(
                  top: 4,
                  right: 4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: product.status == 'sold' ? Colors.green : Colors.orange,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      product.status.toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              // Price overlay
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withOpacity(0.7),
                      ],
                    ),
                  ),
                  child: Text(
                    '₱${product.price.toStringAsFixed(0)}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}