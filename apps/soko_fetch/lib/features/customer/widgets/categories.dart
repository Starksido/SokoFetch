import 'package:flutter/material.dart';

/// Shop categories. Values must match MerchantCategory on the backend.
class ShopCategory {
  const ShopCategory(this.value, this.label, this.icon);
  final String value;
  final String label;
  final IconData icon;
}

const kShopCategories = [
  ShopCategory('restaurant', 'Restaurants', Icons.restaurant_rounded),
  ShopCategory('fast_food', 'Fast food', Icons.fastfood_rounded),
  ShopCategory('grocery', 'Groceries', Icons.local_grocery_store_rounded),
  ShopCategory('bakery', 'Bakery', Icons.bakery_dining_rounded),
  ShopCategory('beverages', 'Drinks', Icons.local_cafe_rounded),
  ShopCategory('pharmacy', 'Pharmacy', Icons.local_pharmacy_rounded),
  ShopCategory('general', 'Shops', Icons.storefront_rounded),
];

ShopCategory categoryOf(String value) => kShopCategories.firstWhere(
      (c) => c.value == value,
      orElse: () => ShopCategory(value, _titleCase(value), Icons.storefront_rounded),
    );

String _titleCase(String raw) => raw
    .replaceAll('_', ' ')
    .split(' ')
    .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1))
    .join(' ');

/// "Vegetables", "Main dishes"... from a menu category value.
String menuCategoryLabel(String raw) => raw.isEmpty ? 'Menu' : _titleCase(raw);
