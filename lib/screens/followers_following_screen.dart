import 'package:flutter/material.dart';
import '../services/follow_service.dart';
import 'user_profile_view_screen.dart' as profile_screen;

class FollowersFollowingScreen extends StatefulWidget {
  final String userId;
  final String username;
  final bool isFollowers; // true for followers, false for following

  const FollowersFollowingScreen({
    super.key,
    required this.userId,
    required this.username,
    required this.isFollowers,
  });

  @override
  State<FollowersFollowingScreen> createState() => _FollowersFollowingScreenState();
}

class _FollowersFollowingScreenState extends State<FollowersFollowingScreen> {
  List<Map<String, dynamic>> _users = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });

      List<Map<String, dynamic>> users;
      if (widget.isFollowers) {
        users = await FollowService.getFollowers(widget.userId);
      } else {
        users = await FollowService.getFollowing(widget.userId);
      }

      setState(() {
        _users = users;
        _isLoading = false;
      });
    } catch (e) {
      print('❌ Error loading ${widget.isFollowers ? "followers" : "following"}: $e');
      setState(() {
        _error = 'Error loading ${widget.isFollowers ? "followers" : "following"}';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF2B0000),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          widget.isFollowers ? 'Followers' : 'Following',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(
                color: Colors.red,
              ),
            )
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.error_outline,
                        size: 64,
                        color: Colors.white.withOpacity(0.5),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _error!,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.7),
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadUsers,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                        ),
                        child: const Text(
                          'Retry',
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                )
              : _users.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            widget.isFollowers ? Icons.people_outline : Icons.person_outline,
                            size: 64,
                            color: Colors.white.withOpacity(0.5),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            widget.isFollowers
                                ? 'No followers yet'
                                : 'Not following anyone',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.7),
                              fontSize: 18,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: _users.length,
                      itemBuilder: (context, index) {
                        final user = _users[index];
                        final userId = user['userId']?.toString() ?? '';
                        final username = user['username']?.toString() ?? 'Unknown User';
                        final fullName = user['fullName']?.toString() ?? username;
                        final profilePictureUrl = user['profilePictureUrl']?.toString() ?? '';

                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          leading: CircleAvatar(
                            radius: 24,
                            backgroundColor: Colors.grey[800],
                            backgroundImage: profilePictureUrl.isNotEmpty
                                ? NetworkImage(profilePictureUrl)
                                : null,
                            child: profilePictureUrl.isEmpty
                                ? Text(
                                    fullName.isNotEmpty
                                        ? fullName[0].toUpperCase()
                                        : 'U',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  )
                                : null,
                          ),
                          title: Text(
                            fullName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          subtitle: username != fullName
                              ? Text(
                                  '@$username',
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.6),
                                    fontSize: 13,
                                  ),
                                )
                              : null,
                          onTap: () {
                            if (userId.isNotEmpty) {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => profile_screen.UserProfileViewScreen(
                                    targetUserId: userId,
                                    targetUsername: username,
                                  ),
                                ),
                              );
                            }
                          },
                        );
                      },
                    ),
    );
  }
}









