import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shimmer/shimmer.dart';

import '../../../../core/theme.dart';
import '../../models/models.dart';
import '../../providers/providers.dart';
import '../cart/cart_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  String? _selectedCategory;
  final _categories = const [
    _CategorySpec(null, 'All', Icons.grid_view_rounded, AppTheme.primaryFixed),
    _CategorySpec('restaurant', 'Restaurants', Icons.restaurant_rounded,
        AppTheme.primaryContainer),
    _CategorySpec('pharmacy', 'Pharmacy', Icons.medical_services_rounded,
        AppTheme.secondaryContainer),
    _CategorySpec(
        'fast_food', 'Fast Food', Icons.fastfood_rounded, Color(0xFFD0E5FC)),
    _CategorySpec('grocery', 'Mama Mboga', Icons.storefront_rounded,
        AppTheme.surfaceHigh),
    _CategorySpec(
        'beverages', 'More', Icons.more_horiz_rounded, AppTheme.surfaceHigh),
  ];

  @override
  Widget build(BuildContext context) {
    final merchants = ref.watch(merchantsProvider(_selectedCategory));
    final cartItems = ref.watch(cartProvider);

    return Scaffold(
      backgroundColor: AppTheme.lgray,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: AppTheme.accent,
          onRefresh: () async =>
              ref.invalidate(merchantsProvider(_selectedCategory)),
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: _TopBar(
                  cartCount:
                      cartItems.fold(0, (sum, item) => sum + item.quantity),
                  onCart: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const CartScreen()),
                  ),
                  onProfile: () => Navigator.pushNamed(context, '/customer/profile'),
                ),
              ),
              const SliverToBoxAdapter(child: _SearchBox()),
              SliverToBoxAdapter(
                child: _CategoryRail(
                  categories: _categories,
                  selected: _selectedCategory,
                  onSelected: (value) =>
                      setState(() => _selectedCategory = value),
                ),
              ),
              const SliverToBoxAdapter(child: _PromoBanner()),
              SliverToBoxAdapter(
                child: _SectionTitle(
                  title: _selectedCategory == null
                      ? 'Fastest Delivery Near You'
                      : 'Open Near You',
                  action: 'See all',
                ),
              ),
              merchants.when(
                loading: () => SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (_, __) => const _ShimmerCard(),
                    childCount: 4,
                  ),
                ),
                error: (_, __) => SliverToBoxAdapter(
                  child: _StatePanel(
                    icon: Icons.wifi_off_rounded,
                    title: 'Unable to load merchants',
                    body: 'Check your connection and try again.',
                    actionLabel: 'Retry',
                    onAction: () =>
                        ref.invalidate(merchantsProvider(_selectedCategory)),
                  ),
                ),
                data: (list) => list.isEmpty
                    ? const SliverToBoxAdapter(
                        child: _StatePanel(
                          icon: Icons.storefront_rounded,
                          title: 'No shops in this category',
                          body: 'Try another category or check again later.',
                        ),
                      )
                    : SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        sliver: SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (_, i) => _MerchantCard(merchant: list[i]),
                            childCount: list.length,
                          ),
                        ),
                      ),
              ),
              const SliverToBoxAdapter(child: _EssentialsGrid()),
              const SliverToBoxAdapter(child: SizedBox(height: 104)),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.pushNamed(context, '/customer/orders'),
        backgroundColor: AppTheme.accent,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: const Icon(Icons.receipt_long_rounded),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  final int cartCount;
  final VoidCallback onCart;
  final VoidCallback onProfile;

  const _TopBar({
    required this.cartCount,
    required this.onCart,
    required this.onProfile,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 10),
      child: Row(
        children: [
          const Icon(Icons.location_on_rounded, color: AppTheme.accent),
          const SizedBox(width: 6),
          const Expanded(
            child: Text(
              'Westlands, Nairobi',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style:
                  TextStyle(fontWeight: FontWeight.w700, color: AppTheme.brand),
            ),
          ),
          const Text(
            'Soko Fetch',
            style: TextStyle(
              color: AppTheme.accent,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          const Spacer(),
          Stack(
            clipBehavior: Clip.none,
            children: [
              IconButton(
                tooltip: 'Cart',
                onPressed: onCart,
                icon: const Icon(Icons.shopping_bag_outlined,
                    color: AppTheme.accent),
              ),
              if (cartCount > 0)
                Positioned(
                  right: 7,
                  top: 7,
                  child: Container(
                    height: 18,
                    width: 18,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      color: AppTheme.teal,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '$cartCount',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          IconButton(
            tooltip: 'Profile',
            onPressed: onProfile,
            icon:
                const Icon(Icons.person_outline_rounded, color: AppTheme.mgray),
          ),
        ],
      ),
    );
  }
}

class _SearchBox extends StatelessWidget {
  const _SearchBox();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      child: TextField(
        readOnly: true,
        onTap: () {},
        decoration: const InputDecoration(
          hintText: 'Search for food, medicine, or essentials',
          prefixIcon: Icon(Icons.search_rounded, color: AppTheme.mgray),
          suffixIcon: Icon(Icons.mic_rounded, color: AppTheme.accent),
        ),
      ),
    );
  }
}

class _CategoryRail extends StatelessWidget {
  final List<_CategorySpec> categories;
  final String? selected;
  final ValueChanged<String?> onSelected;

  const _CategoryRail({
    required this.categories,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle(title: 'Categories'),
        SizedBox(
          height: 100,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            scrollDirection: Axis.horizontal,
            itemCount: categories.length,
            separatorBuilder: (_, __) => const SizedBox(width: 14),
            itemBuilder: (_, i) {
              final category = categories[i];
              final isSelected = category.value == selected;
              return GestureDetector(
                onTap: () => onSelected(category.value),
                child: SizedBox(
                  width: 76,
                  child: Column(
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        height: 64,
                        width: 64,
                        decoration: BoxDecoration(
                          color: category.color,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: isSelected ? AppTheme.accent : Colors.white,
                            width: isSelected ? 2 : 1,
                          ),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x12000000),
                              blurRadius: 10,
                              offset: Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Icon(
                          category.icon,
                          color: isSelected ? AppTheme.accent : AppTheme.brand,
                          size: 30,
                        ),
                      ),
                      const SizedBox(height: 7),
                      Text(
                        category.label,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.brand,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _PromoBanner extends StatelessWidget {
  const _PromoBanner();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      child: Container(
        height: 160,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: const LinearGradient(
            colors: [AppTheme.accent, AppTheme.primaryContainer],
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x24000000),
              blurRadius: 18,
              offset: Offset(0, 10),
            ),
          ],
        ),
        child: Stack(
          children: [
            Positioned(
              right: -18,
              bottom: -24,
              child: Icon(
                Icons.delivery_dining_rounded,
                size: 150,
                color: Colors.white.withValues(alpha: 0.18),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Text(
                      'Limited Offer',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'First Fetch Free',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const SizedBox(
                    width: 230,
                    child: Text(
                      'Get your first 3 deliveries with zero service fee. Karibu Soko!',
                      style: TextStyle(color: Colors.white, height: 1.3),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MerchantCard extends StatelessWidget {
  final Merchant merchant;

  const _MerchantCard({required this.merchant});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: merchant.isOpen
            ? () => Navigator.pushNamed(context, '/customer/shop',
                arguments: merchant.id)
            : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 176,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  merchant.bannerUrl != null
                      ? CachedNetworkImage(
                          imageUrl: merchant.bannerUrl!,
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) =>
                              _PlaceholderBanner(merchant.category),
                        )
                      : _PlaceholderBanner(merchant.category),
                  Positioned(
                    top: 12,
                    right: 12,
                    child: _GlassPill(
                      icon: Icons.star_rounded,
                      label: merchant.rating.toStringAsFixed(1),
                      iconColor: AppTheme.gold,
                    ),
                  ),
                  Positioned(
                    left: 12,
                    bottom: 12,
                    child: _SolidPill(
                      icon: merchant.avgPrepMinutes <= 15
                          ? Icons.bolt_rounded
                          : Icons.schedule_rounded,
                      label: '${merchant.avgPrepMinutes} min',
                    ),
                  ),
                  if (!merchant.isOpen)
                    Container(
                      color: Colors.black.withValues(alpha: 0.52),
                      alignment: Alignment.center,
                      child: const Text(
                        'CLOSED',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 3,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          merchant.shopName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.brand,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${_labelCategory(merchant.category)} - ${merchant.address}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: AppTheme.mgray, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  if (merchant.minOrderAmount > 0) ...[
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        const Text(
                          'Min. order',
                          style: TextStyle(color: AppTheme.mgray, fontSize: 11),
                        ),
                        Text(
                          'KES ${merchant.minOrderAmount.toStringAsFixed(0)}',
                          style: const TextStyle(
                            color: AppTheme.accent,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _labelCategory(String category) {
    return category
        .replaceAll('_', ' ')
        .split(' ')
        .map((word) =>
            word.isEmpty ? word : word[0].toUpperCase() + word.substring(1))
        .join(' ');
  }
}

class _EssentialsGrid extends StatelessWidget {
  const _EssentialsGrid();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Daily Essentials',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 220,
            child: Row(
              children: [
                Expanded(
                  child: _EssentialTile(
                    title: 'Fresh Fruits',
                    subtitle: 'From local farms',
                    icon: Icons.eco_rounded,
                    color: AppTheme.secondaryContainer,
                    tall: true,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    children: const [
                      Expanded(
                        child: _EssentialTile(
                          title: 'Milk & Dairy',
                          icon: Icons.egg_alt_rounded,
                          color: Color(0xFFD0E5FC),
                        ),
                      ),
                      SizedBox(height: 12),
                      Expanded(
                        child: _EssentialTile(
                          title: 'Household',
                          icon: Icons.sanitizer_rounded,
                          color: AppTheme.primaryFixed,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EssentialTile extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData icon;
  final Color color;
  final bool tall;

  const _EssentialTile({
    required this.title,
    this.subtitle,
    required this.icon,
    required this.color,
    this.tall = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -10,
            bottom: -10,
            child: Icon(icon,
                size: tall ? 82 : 42, color: AppTheme.brand.withValues(alpha: 0.16)),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: tall
                ? MainAxisAlignment.spaceBetween
                : MainAxisAlignment.center,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: AppTheme.brand,
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      subtitle!,
                      style:
                          const TextStyle(color: AppTheme.mgray, fontSize: 12),
                    ),
                  ],
                ],
              ),
              if (tall)
                Align(
                  alignment: Alignment.bottomRight,
                  child: Container(
                    width: 42,
                    height: 42,
                    decoration: const BoxDecoration(
                      color: AppTheme.teal,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.arrow_forward_rounded,
                        color: Colors.white),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final String? action;

  const _SectionTitle({required this.title, this.action});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
          ),
          if (action != null)
            Text(
              action!,
              style: const TextStyle(
                color: AppTheme.accent,
                fontWeight: FontWeight.w700,
              ),
            ),
        ],
      ),
    );
  }
}

class _GlassPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color iconColor;

  const _GlassPill({
    required this.icon,
    required this.label,
    required this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: iconColor),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

class _SolidPill extends StatelessWidget {
  final IconData icon;
  final String label;

  const _SolidPill({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: AppTheme.accent,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Colors.white),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _PlaceholderBanner extends StatelessWidget {
  final String category;

  const _PlaceholderBanner(this.category);

  IconData get _icon {
    switch (category) {
      case 'restaurant':
        return Icons.restaurant_rounded;
      case 'grocery':
        return Icons.storefront_rounded;
      case 'pharmacy':
        return Icons.medical_services_rounded;
      case 'bakery':
        return Icons.bakery_dining_rounded;
      case 'fast_food':
        return Icons.fastfood_rounded;
      default:
        return Icons.store_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppTheme.primaryFixed,
      child: Icon(_icon, size: 68, color: AppTheme.accent.withValues(alpha: 0.38)),
    );
  }
}

class _StatePanel extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _StatePanel({
    required this.icon,
    required this.title,
    required this.body,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Icon(icon, size: 56, color: AppTheme.mgray),
          const SizedBox(height: 12),
          Text(title,
              style:
                  const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 4),
          Text(body,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppTheme.mgray)),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 16),
            ElevatedButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    );
  }
}

class _ShimmerCard extends StatelessWidget {
  const _ShimmerCard();

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: Colors.grey.shade200,
      highlightColor: Colors.grey.shade100,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        height: 250,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    );
  }
}

class _CategorySpec {
  final String? value;
  final String label;
  final IconData icon;
  final Color color;

  const _CategorySpec(this.value, this.label, this.icon, this.color);
}
