import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:receiptnest/domain/entities/category_config.dart';

class CategoryConfigRepository {
  CategoryConfigRepository({FirebaseFirestore? firestoreInstance})
      : _firestore = firestoreInstance ?? FirebaseFirestore.instance;

  static const List<String> _fallbackCategories = <String>[
    "Groceries",
    "Dining & Takeaway",
    "Transport",
    "Travel & Accommodation",
    "Clothing & Accessories",
    "Electronics & Gadgets",
    "Home & Household",
    "Health & Medical",
    "Personal Care & Beauty",
    "Subscriptions",
    "Utilities",
    "Insurance",
    "Education",
    "Professional Services",
    "Entertainment",
    "Gifts & Donations",
    "Other",
  ];

  final FirebaseFirestore _firestore;

  DocumentReference<Map<String, dynamic>> _configDoc() {
    return _firestore.collection('config').doc('categories');
  }

  Future<List<String>> getCategories() async {
    try {
      final snapshot = await _configDoc().get();
      if (!snapshot.exists) {
        debugPrint('Category config document missing; using fallback categories.');
        return _fallbackCategories;
      }

      final data = snapshot.data();
      if (data == null) {
        debugPrint('Category config document is null; using fallback categories.');
        return _fallbackCategories;
      }

      final config = CategoryConfig.fromFirestore(data);
      return config.categories.isNotEmpty ? config.categories : _fallbackCategories;
    } catch (error) {
      debugPrint('Failed to load category config: $error');
      return _fallbackCategories;
    }
  }
}
