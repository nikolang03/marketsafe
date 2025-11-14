import 'package:flutter/material.dart';
import '../../services/product_service.dart';
import '../../models/product_model.dart';
import '../../widgets/product_card.dart';

class VehiclesScreen extends StatefulWidget {
  const VehiclesScreen({super.key});

  @override
  State<VehiclesScreen> createState() => _VehiclesScreenState();
}

class _VehiclesScreenState extends State<VehiclesScreen> {
  List<Product> _products = [];
  bool _isLoading = true;
  String? _error;

  // For price filter
  double minPrice = 0;
  double maxPrice = 100000; // High but manageable for slider (₱100,000)
  double selectedMin = 0;
  double selectedMax = 100000; // High default maximum

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  Future<void> _loadProducts() async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });

      final products = await ProductService.getProductsByCategory('Vehicle');
      
      setState(() {
        _products = products;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  void _showFilterDialog() {
    final TextEditingController minController = TextEditingController(text: selectedMin == minPrice ? '' : selectedMin.toInt().toString());
    final TextEditingController maxController = TextEditingController(text: selectedMax == maxPrice ? '' : selectedMax.toInt().toString());
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A0000),
        title: const Text(
          "Filter by Price",
          style: TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              "Enter price range:",
              style: TextStyle(color: Colors.white70, fontSize: 16),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Minimum Price (₱)",
                        style: TextStyle(color: Colors.white, fontSize: 14),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: minController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: "0",
                          hintStyle: TextStyle(color: Colors.white54),
                          filled: true,
                          fillColor: Colors.white10,
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
                            borderSide: BorderSide(color: Colors.red),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Maximum Price (₱)",
                        style: TextStyle(color: Colors.white, fontSize: 14),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: maxController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: "100000",
                          hintStyle: TextStyle(color: Colors.white54),
                          filled: true,
                          fillColor: Colors.white10,
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
                            borderSide: BorderSide(color: Colors.red),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              setState(() {
                selectedMin = minPrice;
                selectedMax = maxPrice;
              });
              Navigator.pop(context);
            },
            child: const Text("Reset", style: TextStyle(color: Colors.white70)),
          ),
          TextButton(
            onPressed: () {
              // Parse values, defaulting to min/max if empty or invalid
              double? minValue = minController.text.trim().isEmpty 
                  ? null 
                  : double.tryParse(minController.text.trim());
              double? maxValue = maxController.text.trim().isEmpty 
                  ? null 
                  : double.tryParse(maxController.text.trim());
              
              // Validate and set values
              final newMin = minValue ?? minPrice;
              final newMax = maxValue ?? maxPrice;
              
              // Ensure min <= max
              if (newMin > newMax) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text("Minimum price must be less than or equal to maximum price"),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }
              
              setState(() {
                selectedMin = newMin.clamp(minPrice, maxPrice);
                selectedMax = newMax.clamp(minPrice, maxPrice);
              });
              
              print('✅ Filter applied: ₱${selectedMin.toInt()} - ₱${selectedMax.toInt()}');
              Navigator.pop(context);
            },
            child: const Text("Apply", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF2E0000),
      appBar: AppBar(
        backgroundColor: const Color(0xFF2E0000),
        elevation: 0,
        title: const Text(
          "VEHICLES",
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 20,
            letterSpacing: 1.2,
          ),
        ),
        centerTitle: true,
        leading: Padding(
          padding: const EdgeInsets.all(8.0),
          child: GestureDetector(
            onTap: () {
              Navigator.pop(context);
            },
            child: Image.asset("assets/logo.png"),
          ),
        ),
        actions: [
          IconButton(
            color: Colors.white,
            icon: const Icon(Icons.filter_list),
            onPressed: _showFilterDialog,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadProducts,
        color: Colors.red,
        child: _isLoading
            ? const SingleChildScrollView(
                physics: AlwaysScrollableScrollPhysics(),
                child: SizedBox(
                  height: 600,
                  child: Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  ),
                ),
              )
            : _error != null
                ? SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    child: SizedBox(
                      height: MediaQuery.of(context).size.height - 200,
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.error, color: Colors.red, size: 50),
                            const SizedBox(height: 16),
                            const Text(
                              'Error loading products',
                              style: TextStyle(color: Colors.white, fontSize: 18),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _error!,
                              style: const TextStyle(color: Colors.white70),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton(
                              onPressed: _loadProducts,
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                : _products.isEmpty
                    ? SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        child: SizedBox(
                          height: MediaQuery.of(context).size.height - 200,
                          child: const Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.inventory_2_outlined, color: Colors.white70, size: 50),
                                SizedBox(height: 16),
                                Text(
                                  'No vehicles found',
                                  style: TextStyle(color: Colors.white70, fontSize: 18),
                                ),
                                SizedBox(height: 8),
                                Text(
                                  'Be the first to post a vehicle!',
                                  style: TextStyle(color: Colors.white54),
                                ),
                              ],
                            ),
                          ),
                        ),
                      )
                    : ListView.builder(
                        itemCount: _products.length,
                        itemBuilder: (context, index) {
                          final product = _products[index];
                          return ProductCard(
                            product: product,
                            onRefresh: _loadProducts,
                            selectedMin: selectedMin,
                            selectedMax: selectedMax,
                          );
                        },
                      ),
      ),
    );
  }
}