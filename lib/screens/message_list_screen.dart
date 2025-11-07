import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'conversation_screen.dart';
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

  Future<void> _showStartConversationDialog() async {
    final TextEditingController emailController = TextEditingController();
    
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF2C0000),
          title: const Text(
            'Start Conversation',
            style: TextStyle(color: Colors.white),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Enter the email of the user you want to chat with:',
                style: TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: emailController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'user@example.com',
                  hintStyle: const TextStyle(color: Colors.white54),
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.1),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: Colors.white24),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: Colors.white24),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Colors.red),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
            ),
            ElevatedButton(
              onPressed: () async {
                final email = emailController.text.trim();
                if (email.isNotEmpty) {
                  Navigator.pop(context);
                  await _startConversationWithUser(email);
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: const Text('Start Chat'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _startConversationWithUser(String email) async {
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

      // Find user by email
      final usersSnapshot = await FirebaseFirestore.instanceFor(
        app: Firebase.app(),
        databaseId: 'marketsafe',
      ).collection('users')
          .where('email', isEqualTo: email)
          .limit(1)
          .get();

      if (usersSnapshot.docs.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('User not found with this email'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      final otherUserId = usersSnapshot.docs.first.id;
      
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
                    icon: const Icon(Icons.person_add, color: Colors.white),
                    onPressed: _showStartConversationDialog,
                    tooltip: 'Start Conversation',
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

                            return ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              onTap: () async {
                                // Mark messages as read when opening conversation
                                await MessageService.markMessagesAsRead(
                                  conversation['conversationId'],
                                  _currentUserId!,
                                );

                                // Go to conversation
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => ConversationScreen(
                                      conversationId: conversation['conversationId'],
                                      otherUser: otherUser,
                                      currentUserId: _currentUserId!,
                                    ),
                                  ),
                                );

                                // Refresh conversations after returning
                                _loadConversations();
                              },
                              leading: CircleAvatar(
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
                              title: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      otherUser['name'] ?? 'Unknown User',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: unreadCount > 0 ? FontWeight.bold : FontWeight.normal,
                                      ),
                                    ),
                                  ),
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
