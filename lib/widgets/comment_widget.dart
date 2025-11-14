import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/comment_service.dart';
import '../screens/user_profile_view_screen.dart';

class CommentWidget extends StatefulWidget {
  final Map<String, dynamic> comment;
  final String productId;
  final VoidCallback? onReply;

  const CommentWidget({
    super.key,
    required this.comment,
    required this.productId,
    this.onReply,
  });

  @override
  State<CommentWidget> createState() => _CommentWidgetState();
}

class _CommentWidgetState extends State<CommentWidget> {
  bool _isLiked = false;
  bool _isLikeLoading = false;
  bool _isReplyLoading = false;
  bool _showReplies = false;
  bool _showReplyInput = false;
  String? _replyingToUserId; // Track which user we're replying to
  String? _replyingToUsername; // Track which username we're replying to
  String? _replyingToCommentId; // Track which comment/reply ID we're replying to
  List<Map<String, dynamic>> _replies = [];
  final TextEditingController _replyController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _checkLikeStatus();
    _loadReplies();
  }

  @override
  void dispose() {
    _replyController.dispose();
    super.dispose();
  }

  Future<void> _checkLikeStatus() async {
    try {
      final isLiked = await CommentService.isCommentLiked(widget.comment['commentId']);
      if (mounted) {
        setState(() {
          _isLiked = isLiked;
        });
      }
    } catch (e) {
      print('❌ Error checking like status: $e');
    }
  }

  Future<void> _loadReplies() async {
    try {
      final replies = await CommentService.getReplies(widget.comment['commentId']);
      if (mounted) {
        setState(() {
          _replies = replies;
        });
      }
    } catch (e) {
      print('❌ Error loading replies: $e');
    }
  }

  Future<void> _toggleLike() async {
    if (_isLikeLoading) return;

    setState(() {
      _isLikeLoading = true;
    });

    try {
      final success = await CommentService.likeComment(widget.comment['commentId']);
      if (success && mounted) {
        setState(() {
          _isLiked = !_isLiked;
        });
      }
    } catch (e) {
      print('❌ Error toggling like: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLikeLoading = false;
        });
      }
    }
  }

  Future<void> _addReply() async {
    if (_replyController.text.trim().isEmpty || _isReplyLoading) return;

    setState(() {
      _isReplyLoading = true;
    });

    try {
      // Use the stored comment ID if replying to a specific reply
      // Otherwise, use the main comment's ID
      final parentId = _replyingToCommentId ?? widget.comment['commentId'];
      
      final success = await CommentService.addComment(
        productId: widget.productId,
        content: _replyController.text.trim(),
        parentCommentId: parentId,
      );

      if (success) {
        _replyController.clear();
        // Ensure replies are shown after adding a reply
        setState(() {
          _showReplyInput = false;
          _showReplies = true; // Ensure replies section is visible
          _replyingToUserId = null;
          _replyingToUsername = null;
          _replyingToCommentId = null;
        });
        // Reload replies to get the newly added reply
        await _loadReplies();
        if (widget.onReply != null) {
          widget.onReply!();
        }
        _showSuccessSnackBar('Reply added successfully');
      } else {
        _showErrorSnackBar('Failed to add reply');
      }
    } catch (e) {
      print('❌ Error adding reply: $e');
      _showErrorSnackBar('An error occurred');
    } finally {
      if (mounted) {
        setState(() {
          _isReplyLoading = false;
        });
      }
    }
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _navigateToUserProfile() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => UserProfileViewScreen(
          targetUserId: widget.comment['userId'],
          targetUsername: widget.comment['username'],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[800]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Comment Header
          Row(
            children: [
              // Profile Picture
              GestureDetector(
                onTap: _navigateToUserProfile,
                child: CircleAvatar(
                  radius: 20,
                  backgroundColor: Colors.grey[800],
                  backgroundImage: widget.comment['profilePictureUrl'] != null
                      ? NetworkImage(widget.comment['profilePictureUrl'])
                      : null,
                  child: widget.comment['profilePictureUrl'] == null
                      ? const Icon(Icons.person, size: 20, color: Colors.white)
                      : null,
                ),
              ),
              
              const SizedBox(width: 12),
              
              // Username and Time
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GestureDetector(
                      onTap: _navigateToUserProfile,
                      child: Text(
                        widget.comment['username'] ?? 'Unknown User',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    Text(
                      _formatTime(widget.comment['createdAt']),
                      style: const TextStyle(
                        color: Colors.grey,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              
              // More options
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, color: Colors.grey),
                onSelected: (value) {
                  if (value == 'delete') {
                    _showDeleteDialog();
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'delete',
                    child: Text('Delete', style: TextStyle(color: Colors.red)),
                  ),
                ],
              ),
            ],
          ),
          
          const SizedBox(height: 12),
          
          // Comment Content
          Text(
            widget.comment['content'] ?? '',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
            ),
          ),
          
          const SizedBox(height: 12),
          
          // Comment Actions
          Row(
            children: [
              // Like Button
              GestureDetector(
                onTap: _toggleLike,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      _isLikeLoading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                color: Colors.red,
                                strokeWidth: 2,
                              ),
                            )
                          : Icon(
                              _isLiked ? Icons.favorite : Icons.favorite_border,
                              color: _isLiked ? Colors.red : Colors.grey,
                              size: 20,
                            ),
                      const SizedBox(width: 4),
                      Text(
                        '${widget.comment['likes'] ?? 0}',
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              
              const SizedBox(width: 12),
              
              // Reply Button - Always visible for all users
              GestureDetector(
                onTap: () {
                  setState(() {
                    _showReplies = true;
                    _showReplyInput = true;
                    _replyingToUserId = widget.comment['userId'];
                    _replyingToUsername = widget.comment['username'];
                    _replyingToCommentId = widget.comment['commentId'];
                  });
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.grey.withOpacity(0.3),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.reply,
                        color: Colors.red,
                        size: 18,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Reply${_replies.isNotEmpty ? ' (${_replies.length})' : ''}',
                        style: const TextStyle(
                          color: Colors.red,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              
              // Show/Hide Replies Toggle
              if (_replies.isNotEmpty) ...[
                const SizedBox(width: 12),
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _showReplies = !_showReplies;
                      if (!_showReplies) {
                        _showReplyInput = false;
                        _replyingToUserId = null;
                        _replyingToUsername = null;
                        _replyingToCommentId = null;
                      }
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _showReplies ? Icons.expand_less : Icons.expand_more,
                          color: Colors.grey,
                          size: 18,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _showReplies ? 'Hide' : 'Show Replies',
                          style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
          
          // Reply Input
          if (_showReplyInput) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[800],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.withOpacity(0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Show who you're replying to
                  if (_replyingToUsername != null) ...[
                    Row(
                      children: [
                        const Icon(Icons.reply, color: Colors.red, size: 16),
                        const SizedBox(width: 4),
                        Text(
                          'Replying to ${_replyingToUsername}',
                          style: const TextStyle(
                            color: Colors.red,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],
                  TextField(
                    controller: _replyController,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      hintText: 'Write a reply...',
                      hintStyle: TextStyle(color: Colors.grey),
                      border: InputBorder.none,
                    ),
                    maxLines: 3,
                    minLines: 1,
                    autofocus: true,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () {
                          setState(() {
                            _showReplyInput = false;
                            _replyingToUserId = null;
                            _replyingToUsername = null;
                            _replyingToCommentId = null;
                          });
                          _replyController.clear();
                        },
                        child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: _isReplyLoading ? null : _addReply,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        ),
                        child: _isReplyLoading
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Reply', style: TextStyle(color: Colors.white)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
          
          // Replies List
          if (_showReplies && _replies.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.only(left: 16),
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(color: Colors.grey[700]!, width: 2),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.reply, color: Colors.grey, size: 16),
                      const SizedBox(width: 4),
                      Text(
                        '${_replies.length} ${_replies.length == 1 ? 'reply' : 'replies'}',
                        style: const TextStyle(
                          color: Colors.grey,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ..._replies.map((reply) => _buildReplyWidget(reply)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildReplyWidget(Map<String, dynamic> reply) {
    final isReplyingToThis = _replyingToUserId == reply['userId'] && 
                             _replyingToUsername == reply['username'] &&
                             _showReplyInput;
    
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isReplyingToThis ? Colors.grey[750] : Colors.grey[800],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isReplyingToThis ? Colors.red.withOpacity(0.5) : Colors.grey[700]!,
          width: isReplyingToThis ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => UserProfileViewScreen(
                        targetUserId: reply['userId'],
                        targetUsername: reply['username'],
                      ),
                    ),
                  );
                },
                child: CircleAvatar(
                  radius: 16,
                  backgroundColor: Colors.grey[700],
                  backgroundImage: reply['profilePictureUrl'] != null
                      ? NetworkImage(reply['profilePictureUrl'])
                      : null,
                  child: reply['profilePictureUrl'] == null
                      ? const Icon(Icons.person, size: 16, color: Colors.white)
                      : null,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => UserProfileViewScreen(
                              targetUserId: reply['userId'],
                              targetUsername: reply['username'],
                            ),
                          ),
                        );
                      },
                      child: Text(
                        reply['username'] ?? 'Unknown User',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    Text(
                      _formatTime(reply['createdAt']),
                      style: const TextStyle(
                        color: Colors.grey,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
              // Reply to this reply button - Always visible for all users
              GestureDetector(
                onTap: () {
                  setState(() {
                    _showReplies = true;
                    _showReplyInput = true;
                    _replyingToUserId = reply['userId'];
                    _replyingToUsername = reply['username'];
                    _replyingToCommentId = reply['commentId'];
                    // Pre-fill with @username for better UX
                    _replyController.text = '@${reply['username']} ';
                  });
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.red.withOpacity(0.3),
                      width: 1,
                    ),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.reply,
                        color: Colors.red,
                        size: 14,
                      ),
                      SizedBox(width: 2),
                      Text(
                        'Reply',
                        style: TextStyle(
                          color: Colors.red,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            reply['content'] ?? '',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(dynamic timestamp) {
    if (timestamp == null) return 'Unknown';
    
    try {
      DateTime date;
      if (timestamp is Timestamp) {
        date = timestamp.toDate();
      } else {
        date = DateTime.parse(timestamp.toString());
      }
      
      final now = DateTime.now();
      final difference = now.difference(date);
      
      if (difference.inDays > 0) {
        return '${difference.inDays}d ago';
      } else if (difference.inHours > 0) {
        return '${difference.inHours}h ago';
      } else if (difference.inMinutes > 0) {
        return '${difference.inMinutes}m ago';
      } else {
        return 'Just now';
      }
    } catch (e) {
      return 'Unknown';
    }
  }

  void _showDeleteDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text('Delete Comment', style: TextStyle(color: Colors.white)),
        content: const Text(
          'Are you sure you want to delete this comment?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              final success = await CommentService.deleteComment(widget.comment['commentId']);
              if (success) {
                _showSuccessSnackBar('Comment deleted successfully');
                if (widget.onReply != null) {
                  widget.onReply!();
                }
              } else {
                _showErrorSnackBar('Failed to delete comment');
              }
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
