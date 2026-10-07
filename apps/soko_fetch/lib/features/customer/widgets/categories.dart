import 'package:flutter/material.dart';

import '../../../core/ui/ui.dart';

/// Shop categories. Values must match MerchantCategory on the backend.
class ShopCategory {
  const ShopCategory(this.value, this.label, this.icon, [this.image]);
  final String value;
  final String label;
  final IconData icon;

  /// Bundled photo (assets/categories, credits in CREDITS.md there).
  final String? image;
}

const _photos = 'assets/categories';

/// Photo for the "All" tile.
const kAllCategoriesImage = '$_photos/all.jpg';

const kShopCategories = [
  ShopCategory('restaurant', 'Restaurants', Icons.restaurant_rounded,
      '$_photos/restaurant.jpg'),
  ShopCategory('fast_food', 'Fast food', Icons.fastfood_rounded,
      '$_photos/fast_food.jpg'),
  ShopCategory('grocery', 'Groceries', Icons.local_grocery_store_rounded,
      '$_photos/grocery.jpg'),
  ShopCategory('bakery', 'Bakery', Icons.bakery_dining_rounded,
      '$_photos/bakery.jpg'),
  ShopCategory('beverages', 'Drinks', Icons.local_cafe_rounded,
      '$_photos/beverages.jpg'),
  ShopCategory('pharmacy', 'Pharmacy', Icons.local_pharmacy_rounded,
      '$_photos/pharmacy.jpg'),
  ShopCategory('general', 'Shops', Icons.storefront_rounded,
      '$_photos/general.jpg'),
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

/// Round category photo; the icon on a cream disc if the photo is missing.
class CategoryPhoto extends StatelessWidget {
  const CategoryPhoto({super.key, required this.image, required this.icon});

  final String? image;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final fallback = DecoratedBox(
      decoration:
          const BoxDecoration(color: SfColors.surface2, shape: BoxShape.circle),
      child: Center(child: Icon(icon, color: SfColors.accentStrong, size: 26)),
    );
    if (image == null) return fallback;
    return ClipOval(
      child: Image.asset(
        image!,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        cacheWidth: 192, // 64 px at 3x; keeps memory small
        errorBuilder: (_, __, ___) => fallback,
      ),
    );
  }
}
