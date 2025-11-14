import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'conversation_screen.dart';
import 'user_profile_view_screen.dart' as profile_screen;
import '../services/message_service.dart';

class MessageListScreen extends StatefulWidget {
  const MessageListScreen({super.key});

  @override
  State<MessageListScreen> createState() => _MessageListScreenState();
}

class _MessageListScreenState extends State<MessageListScreen> {
  List<Map<String, dynamic>> _conversations = [];
  bool _isLoading = true;
  String? _currentUserId;
  String? _navigatingToConversationId; // Track which conversation is being opened

  @override
  void initState() {
    super.initState();
    _loadConversations();
  }

  Future<void> _loadConversations() async {
    try {
      _currentUserId = await MessageService.getCurrentUserId();
      if (_currentUserId == null) {
        print('❌ No current user ID found');
        setState(() {
          _isLoading = false;
        });
        return;
      }

      print('💬 Loading conversations for user: $_currentUserId');
      final conversations = await MessageService.getConversations(_currentUserId!);
      
      setState(() {
        _conversations = conversations;
        _isLoading = false;
      });
    } catch (e) {
      print('❌ Error loading conversations: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  String _formatTimestamp(dynamic timestamp) {
    if (timestamp == null) return '';
    
    DateTime dateTime;
    if (timestamp is Timestamp) {
      dateTime = timestamp.toDate();
    } else if (timestamp is DateTime) {
      dateTime = timestamp;
    } else {
      return '';
    }

    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays > 0) {
      return '${difference.inDays}d ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m ago';
    } else {
      return 'Just now';
    }
  }

  Future<void> _showSearchDialog() async {
    final TextEditingController searchController = TextEditingController();
    List<Map<String, dynamic>> searchResults = [];
    bool isSearching = false;
    
    await showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            // Debounce search
            void performSearch(String query) async {
              if (query.trim().isEmpty) {
                setDialogState(() {
                  searchResults = [];
                  isSearching = false;
                });
                return;
              }

              setDialogState(() {
                isSearching = true;
              });

              final results = await MessageService.searchUsers(
                query,
                _currentUserId ?? '',
              );

              if (mounted) {
                setDialogState(() {
                  searchResults = results;
                  isSearching = false;
                });
              }
            }

            return Dialog(
              backgroundColor: const Color(0xFF2C0000),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Container(
                width: MediaQuery.of(context).size.width * 0.9,
                height: MediaQuery.of(context).size.height * 0.7,
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    // Title and close button
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Search Users',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white),
                          onPressed: () => Navigator.pop(dialogContext),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // Search field
                    TextField(
                      controller: searchController,
                      autofocus: true,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Search by name or username...',
                        hintStyle: const TextStyle(color: Colors.white54),
                        prefixIcon: const Icon(Icons.search, color: Colors.white54),
                        filled: true,
                        fillColor: Colors.white.withOpacity(0.1),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.white24),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.white24),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Colors.red),
                        ),
                      ),
                      onChanged: (value) {
                        performSearch(value);
                      },
                    ),
                    const SizedBox(height: 16),
                    // Results list
                    Expanded(
                      child: isSearching
                          ? const Center(
                              child: CircularProgressIndicator(
                                color: Colors.red,
                              ),
                            )
                          : searchController.text.trim().isEmpty
                              ? Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.search,
                                        size: 64,
                                        color: Colors.white.withOpacity(0.3),
                                      ),
                                      const SizedBox(height: 16),
                                      Text(
                                        'Start typing to search users',
                                        style: TextStyle(
                                          color: Colors.white.withOpacity(0.5),
                                          fontSize: 16,
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              : searchResults.isEmpty
                                  ? Center(
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            Icons.person_off,
                                            size: 64,
                                            color: Colors.white.withOpacity(0.3),
                                          ),
                                          const SizedBox(height: 16),
                                          Text(
                                            'No users found',
                                            style: TextStyle(
                                              color: Colors.white.withOpacity(0.5),
                                              fontSize: 16,
                                            ),
                                          ),
                                        ],
                                      ),
                                    )
                                  : ListView.builder(
                                      itemCount: searchResults.length,
                                      itemBuilder: (context, index) {
                                        final user = searchResults[index];
                                        return ListTile(
                                          contentPadding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 4,
                                          ),
                                          leading: CircleAvatar(
                                            radius: 24,
                                            backgroundColor: Colors.grey,
                                            backgroundImage: user['profilePictureUrl'] != null &&
                                                    user['profilePictureUrl'].toString().isNotEmpty
                                                ? NetworkImage(user['profilePictureUrl'].toString())
                                                : null,
                                            child: user['profilePictureUrl'] == null ||
                                                    user['profilePictureUrl'].toString().isEmpty
                                                ? Text(
                                                    (user['name']?.toString().substring(0, 1).toUpperCase() ?? 'U'),
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                      fontWeight: FontWeight.bold,
                                                    ),
                                                  )
                                                : null,
                                          ),
                                          title: Text(
                                            user['name']?.toString() ?? 'Unknown User',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                          subtitle: user['username'] != null &&
                                                  user['username'].toString().isNotEmpty &&
                                                  user['username'] != user['name']
                                              ? Text(
                                                  '@${user['username']}',
                                                  style: TextStyle(
                                                    color: Colors.white.withOpacity(0.7),
                                                    fontSize: 12,
                                                  ),
                                                )
                                              : null,
                                          trailing: const Icon(
                                            Icons.arrow_forward_ios,
                                            color: Colors.white54,
                                            size: 16,
                                          ),
                                          onTap: () async {
                                            Navigator.pop(dialogContext);
                                            await _startConversationWithUserId(user['id'].toString());
                                          },
                                        );
                                      },
                                    ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _startConversationWithUserId(String otherUserId) async {
    try {
      if (_currentUserId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please log in to start a conversation'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      if (otherUserId == _currentUserId) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('You cannot start a conversation with yourself'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      // Create or get conversation
      final conversationId = await MessageService.getOrCreateConversation(
        _currentUserId!,
        otherUserId,
      );

      // Get other user data
      final otherUserData = await MessageService.getUserData(otherUserId);

      // Navigate to conversation
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ConversationScreen(
            conversationId: conversationId,
            otherUser: otherUserData,
            currentUserId: _currentUserId!,
          ),
        ),
      );

      // Refresh conversations
      _loadConversations();
    } catch (e) {
      print('❌ Error starting conversation: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error starting conversation: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
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
            // Top bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const SizedBox(width: 24), // Spacer to balance the layout
                  const Text(
                    "Messages",
                    style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                    icon: const Icon(Icons.search, color: Colors.white),
                    onPressed: _showSearchDialog,
                    tooltip: 'Search Users',
                  ),
                ],
              ),
            ),

            // Conversations list
            Expanded(
              child: RefreshIndicator(
                onRefresh: _loadConversations,
                color: Colors.red,
                child: _isLoading
                    ? const SingleChildScrollView(
                        physics: AlwaysScrollableScrollPhysics(),
                        child: SizedBox(
                          height: 600,
                          child: Center(
                            child: CircularProgressIndicator(
                              color: Colors.red,
                            ),
                          ),
                        ),
                      )
                    : _conversations.isEmpty
                        ? SingleChildScrollView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            child: SizedBox(
                              height: MediaQuery.of(context).size.height - 200,
                              child: Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.chat_bubble_outline,
                                      size: 64,
                                      color: Colors.white.withOpacity(0.5),
                                    ),
                                    const SizedBox(height: 16),
                                    Text(
                                      'No conversations yet',
                                      style: TextStyle(
                                        color: Colors.white.withOpacity(0.7),
                                        fontSize: 18,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Start a conversation with other users',
                                      style: TextStyle(
                                        color: Colors.white.withOpacity(0.5),
                                        fontSize: 14,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          )
                        : ListView.builder(
                          itemCount: _conversations.length,
                          itemBuilder: (context, index) {
                            final conversation = _conversations[index];
                            final otherUser = conversation['otherUser'] as Map<String, dynamic>;
                            final unreadCount = conversation['unreadCount'] as int;
                            final lastMessage = conversation['lastMessage'] as String;
                            final lastMessageAt = conversation['lastMessageAt'];

                            final conversationId = conversation['conversationId'] as String;
                            final isNavigating = _navigatingToConversationId == conversationId;
                            
                            return ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              enabled: !isNavigating,
                              onTap: isNavigating ? null : () async {
                                // Prevent multiple taps
                                if (_navigatingToConversationId != null) return;
                                
                                setState(() {
                                  _navigatingToConversationId = conversationId;
                                });

                                try {
                                  // Mark messages as read when opening conversation
                                  await MessageService.markMessagesAsRead(
                                    conversationId,
                                    _currentUserId!,
                                  );

                                  // Go to conversation
                                  await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => ConversationScreen(
                                        conversationId: conversationId,
                                        otherUser: otherUser,
                                        currentUserId: _currentUserId!,
                                      ),
                                    ),
                                  );

                                  // Refresh conversations after returning
                                  _loadConversations();
                                } finally {
                                  // Reset navigation flag
                                  if (mounted) {
                                    setState(() {
                                      _navigatingToConversationId = null;
                                    });
                                  }
                                }
                              },
                              leading: GestureDetector(
                                behavior: HitTestBehavior.deferToChild,
                                onTap: () {
                                  final otherUserId = otherUser['id']?.toString();
                                  if (otherUserId != null && otherUserId.isNotEmpty) {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => profile_screen.UserProfileViewScreen(
                                          targetUserId: otherUserId,
                                          targetUsername: otherUser['name']?.toString(),
                                        ),
                                      ),
                                    );
                                  }
                                },
                                child: CircleAvatar(
                                  radius: 22,
                                  backgroundColor: Colors.grey,
                                  backgroundImage: otherUser['profilePictureUrl'] != null && 
                                      otherUser['profilePictureUrl'].isNotEmpty
                                      ? NetworkImage(otherUser['profilePictureUrl'])
                                      : null,
                                  child: otherUser['profilePictureUrl'] == null || 
                                      otherUser['profilePictureUrl'].isEmpty
                                      ? Text(
                                          otherUser['name']?.substring(0, 1).toUpperCase() ?? 'U',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        )
                                      : null,
                                ),
                              ),
                              title: Row(
                                children: [
                                  GestureDetector(
                                    behavior: HitTestBehavior.deferToChild,
                                    onTap: () {
                                      final otherUserId = otherUser['id']?.toString();
                                      if (otherUserId != null && otherUserId.isNotEmpty) {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (context) => profile_screen.UserProfileViewScreen(
                                              targetUserId: otherUserId,
                                              targetUsername: otherUser['name']?.toString(),
                                            ),
                                          ),
                                        );
                                      }
                                    },
                                    child: Text(
                                      otherUser['name'] ?? 'Unknown User',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: unreadCount > 0 ? FontWeight.bold : FontWeight.normal,
                                      ),
                                    ),
                                  ),
                                  const Spacer(),
                                  if (unreadCount > 0)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Colors.red,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        unreadCount > 99 ? '99+' : unreadCount.toString(),
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              subtitle: Text(
                                lastMessage.isNotEmpty ? lastMessage : 'No messages yet',
                                style: TextStyle(
                                  color: unreadCount > 0 ? Colors.white : Colors.grey.shade400,
                                  fontWeight: unreadCount > 0 ? FontWeight.w500 : FontWeight.normal,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: Text(
                                _formatTimestamp(lastMessageAt),
                                style: const TextStyle(color: Colors.white70, fontSize: 12),
                              ),
                            );
                          },
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
}
