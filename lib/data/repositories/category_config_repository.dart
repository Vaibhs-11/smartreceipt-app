import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:receiptnest/core/utils/app_logger.dart';
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
        AppLogger.log('Using fallback categories');
        return _fallbackCategories;
      }

      final data = snapshot.data();
      if (data == null) {
        AppLogger.log('Using fallback categories');
        return _fallbackCategories;
      }

      final config = CategoryConfig.fromFirestore(data);
      return config.categories.isNotEmpty
          ? config.categories
          : _fallbackCategories;
    } catch (error) {
      AppLogger.error('Failed to load category config: $error');
      return _fallbackCategories;
    }
  }
}
