import 'package:flutter/material.dart';

class CategoryIconHelper {
  static const Set<String> _foodKeywords = {
    'food', 'foodie', 'hotel', 'soru', 'lunch', 'dinner', 'breakfast',
    'restaurant', 'swiggy', 'zomato', 'eat', 'meal', 'snack'
  };
  static const Set<String> _shoppingKeywords = {
    'shop', 'shopping', 'cart', 'buy', 'mall', 'clothes', 'amazon',
    'flipkart', 'myntra', 'grocery', 'groceries'
  };
  static const Set<String> _fuelKeywords = {
    'petrol', 'diesel', 'fuel', 'gas', 'cng', 'pump'
  };
  static const Set<String> _transportKeywords = {
    'travel', 'bus', 'car', 'train', 'flight', 'taxi', 'cab', 'uber',
    'ola', 'rapido', 'auto', 'metro', 'transport'
  };

  static IconData getIconForCategory(String categoryName) {
    final normalized = categoryName.toLowerCase().trim();

    for (var word in _foodKeywords) {
      if (normalized.contains(word)) return Icons.restaurant;
    }
    for (var word in _shoppingKeywords) {
      if (normalized.contains(word)) return Icons.shopping_cart;
    }
    for (var word in _fuelKeywords) {
      if (normalized.contains(word)) return Icons.local_gas_station;
    }
    for (var word in _transportKeywords) {
      if (normalized.contains(word)) return Icons.directions_bus;
    }

    return Icons.edit;
  }
}
