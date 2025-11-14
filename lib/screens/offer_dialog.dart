import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/message_service.dart';

class OfferDialog extends StatefulWidget {
  final Map<String, dynamic> product;
  final String currentUserId;

  const OfferDialog({
    Key? key,
    required this.product,
    required this.currentUserId,
  }) : super(key: key);

  @override
  _OfferDialogState createState() => _OfferDialogState();
}

class _OfferDialogState extends State<OfferDialog> {
  final TextEditingController _offerController = TextEditingController();
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    // Set initial offer to be slightly less than asking price
    final askingPrice = int.tryParse(widget.product['price']?.toString().replaceAll(' PHP', '').replaceAll(',', '') ?? '500') ?? 500;
    _offerController.text = (askingPrice * 0.8).round().toString();
  }

  @override
  void dispose() {
    _offerController.dispose();
    super.dispose();
  }

  Future<void> _submitOffer() async {
    if (_offerController.text.isEmpty) {
      _showErrorSnackBar('Please enter an offer amount');
      return;
    }

    final offerAmount = int.tryParse(_offerController.text);
    if (offerAmount == null || offerAmount <= 0) {
      _showErrorSnackBar('Please enter a valid offer amount');
      return;
    }

    // Prevent sellers from making offers on their own products
    final sellerId = widget.product['userId'];
    if (widget.currentUserId == sellerId) {
      _showErrorSnackBar('You cannot make an offer on your own product');
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      // Get seller information
      final productTitle = widget.product['title'] ?? 'Unknown Product';
      
      print('🔍 Offer Debug Info:');
      print('  - Current User ID: ${widget.currentUserId}');
      print('  - Seller ID: $sellerId');
      print('  - Product Title: $productTitle');
      print('  - Offer Amount: $offerAmount');
      
      if (sellerId == null || sellerId.isEmpty) {
        throw Exception('Seller ID is null or empty');
      }
      
      if (widget.currentUserId.isEmpty) {
        print('🔍 OfferDialog: Current user ID is empty, trying to get it directly...');
        // Try to get user ID directly from SharedPreferences
        final prefs = await SharedPreferences.getInstance();
        final directUserId = prefs.getString('current_user_id') ?? 
                           prefs.getString('signup_user_id');
        
        print('🔍 OfferDialog: Direct user ID fetch result: $directUserId');
        
        if (directUserId == null || directUserId.isEmpty) {
          throw Exception('Current User ID is empty. Please log in again.');
        }
        
        // Use the directly fetched user ID
        final conversationId = await MessageService.getOrCreateConversation(
          directUserId,
          sellerId,
        );

        // Send offer message
        final offerMessage = 'You got an offer for "$productTitle" - PHP $offerAmount';
        print('💬 Sending message: $offerMessage');
        
        await MessageService.sendMessage(
          conversationId: conversationId,
          senderId: directUserId,
          text: offerMessage,
        );
        print('✅ Message sent successfully!');

        // Show success message
        if (mounted) {
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Offer sent successfully!'),
              backgroundColor: Colors.green,
            ),
          );
        }
        return;
      }
      
      // Create conversation with seller
      print('📞 Creating conversation...');
      final conversationId = await MessageService.getOrCreateConversation(
        widget.currentUserId,
        sellerId,
      );
      print('  - Conversation ID: $conversationId');

      // Send offer message
      final offerMessage = 'You got an offer for "$productTitle" - PHP $offerAmount';
      print('💬 Sending message: $offerMessage');
      
      await MessageService.sendMessage(
        conversationId: conversationId,
        senderId: widget.currentUserId,
        text: offerMessage,
      );
      print('✅ Message sent successfully!');

      // Show success message
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Offer sent successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      print('Error sending offer: $e');
      if (mounted) {
        _showErrorSnackBar('Failed to send offer. Please try again.');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final askingPrice = widget.product['price'] ?? '500 PHP';
    final sellerName = widget.product['sellerName'] ?? 'Full name';

    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Container(
        padding: EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Color(0xFFF5F5DC), // Light beige background
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey[400]!, width: 1),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Seller info header
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Color(0xFFF5F5DC),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey[300]!, width: 1),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.person,
                    color: Colors.grey[700],
                    size: 20,
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '$sellerName is selling this for $askingPrice',
                      style: TextStyle(
                        color: Colors.grey[700],
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 20),

            // Offer input section
            Text(
              'You are offering:',
              style: TextStyle(
                color: Colors.grey[700],
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            SizedBox(height: 8),

            // Offer amount input
            TextFormField(
              controller: _offerController,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
              ],
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.grey[800],
              ),
              decoration: InputDecoration(
                prefixText: 'PHP ',
                prefixStyle: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[800],
                ),
                border: UnderlineInputBorder(
                  borderSide: BorderSide(color: Colors.grey[400]!),
                ),
                focusedBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: Colors.grey[600]!, width: 2),
                ),
                contentPadding: EdgeInsets.symmetric(vertical: 8),
              ),
            ),
            SizedBox(height: 24),

            // Confirm button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isSubmitting ? null : _submitOffer,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Color(0xFFF5F5DC),
                  side: BorderSide(color: Color(0xFF8B0000), width: 2),
                  padding: EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: _isSubmitting
                    ? SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF8B0000)),
                        ),
                      )
                    : Text(
                        'CONFIRM',
                        style: TextStyle(
                          color: Color(0xFF8B0000),
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
