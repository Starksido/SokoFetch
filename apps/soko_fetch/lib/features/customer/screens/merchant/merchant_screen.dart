import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/ui/ui.dart';
import '../../models/models.dart';
import '../../providers/providers.dart';
import '../../widgets/categories.dart';

/// A shop's page: photo header, details, sticky menu categories, menu rows.
class MerchantScreen extends ConsumerWidget {
  const MerchantScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final merchantId = ModalRoute.of(context)!.settings.arguments as String;
    final shop = ref.watch(merchantDetailProvider(merchantId));
    return shop.when(
      loading: () => Scaffold(appBar: AppBar(), body: const LoadingList()),
      error: (e, _) => Scaffold(
        appBar: AppBar(),
        body: ErrorState(
            onRetry: () => ref.invalidate(merchantDetailProvider(merchantId))),
      ),
      data: (m) => _ShopView(shop: m),
    );
  }
}

class _ShopView extends ConsumerStatefulWidget {
  const _ShopView({required this.shop});
  final Merchant shop;

  @override
  ConsumerState<_ShopView> createState() => _ShopViewState();
}

class _ShopViewState extends ConsumerState<_ShopView> {
  static const _heroHeight = 220.0;
  static const _barHeight = 52.0;

  final _scroll = ScrollController();
  late final Map<String, List<MenuItem>> _sections;
  late final Map<String, GlobalKey> _keys;
  String? _active;
  bool _collapsed = false;

  @override
  void initState() {
    super.initState();
    _sections = {};
    for (final item in widget.shop.menuItems) {
      _sections.putIfAbsent(item.category, () => []).add(item);
    }
    _keys = {for (final c in _sections.keys) c: GlobalKey()};
    _active = _sections.keys.isEmpty ? null : _sections.keys.first;
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  double get _pinnedTop =>
      MediaQuery.paddingOf(context).top + kToolbarHeight + _barHeight;

  void _onScroll() {
    final collapsed = _scroll.offset > _heroHeight - kToolbarHeight - 8;
    String? active = _active;
    for (final entry in _keys.entries) {
      final box = entry.value.currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.attached) continue;
      if (box.localToGlobal(Offset.zero).dy <= _pinnedTop + SfSpace.lg) {
        active = entry.key;
      }
    }
    if (collapsed != _collapsed || active != _active) {
      setState(() {
        _collapsed = collapsed;
        _active = active;
      });
    }
  }

  void _jumpTo(String category) {
    final box = _keys[category]?.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final target = _scroll.offset + box.localToGlobal(Offset.zero).dy - _pinnedTop;
    _scroll.animateTo(target.clamp(0, _scroll.position.maxScrollExtent),
        duration: const Duration(milliseconds: 350), curve: Curves.easeOutCubic);
  }

  /// Adding from this shop when the cart holds another shop's items.
  Future<bool> _confirmNewCart() async {
    final cart = ref.read(cartProvider.notifier);
    if (!cart.belongsToOtherShop(widget.shop.id)) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Start a new cart?'),
        content: Text(
            'Your cart has items from another shop. Adding this will clear them '
            'and start a cart from ${widget.shop.shopName}.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Keep my cart')),
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Start new cart')),
        ],
      ),
    );
    return ok ?? false;
  }

  Future<void> _setQty(MenuItem item, int qty) async {
    if (qty > 0 && !await _confirmNewCart()) return;
    ref.read(cartProvider.notifier).setQuantity(item, widget.shop.id, qty);
  }

  void _openItem(MenuItem item) => showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => _ItemSheet(
          item: item,
          canOrder: widget.shop.isOpen && item.isAvailable,
          initialQty: ref.read(cartProvider.notifier).quantityOf(item.id),
          onConfirm: (qty) => _setQty(item, qty),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final shop = widget.shop;
    final text = Theme.of(context).textTheme;
    ref.watch(cartProvider); // Rebuild steppers and the cart bar
    final cart = ref.read(cartProvider.notifier);
    final inThisShop = cart.merchantId == shop.id;
    final category = categoryOf(shop.category);

    return Scaffold(
      bottomNavigationBar: inThisShop && cart.totalItems > 0
          ? BottomCtaBar(
              label: 'View cart',
              count: cart.totalItems,
              amount: cart.subtotal,
              onPressed: () => Navigator.pushNamed(context, '/customer/cart'),
            )
          : null,
      body: CustomScrollView(
        controller: _scroll,
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: _heroHeight,
            leading: Padding(
              padding: const EdgeInsets.all(SfSpace.xs),
              child: SfCircleButton(
                icon: Icons.arrow_back_rounded,
                tooltip: 'Back',
                onPressed: () => Navigator.maybePop(context),
              ),
            ),
            title: AnimatedOpacity(
              opacity: _collapsed ? 1 : 0,
              duration: const Duration(milliseconds: 150),
              child: Text(shop.shopName, overflow: TextOverflow.ellipsis),
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: SfNetworkImage(
                url: shop.bannerUrl,
                radius: 0,
                fallbackIcon: category.icon,
                fallbackLabel: shop.shopName,
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                  SfSpace.md, SfSpace.md, SfSpace.md, SfSpace.xs),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(shop.shopName, style: text.headlineMedium),
                const SizedBox(height: SfSpace.xs),
                Wrap(
                  spacing: SfSpace.xs,
                  runSpacing: SfSpace.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    RatingBadge(rating: shop.rating, count: shop.ratingCount),
                    StatusPill(shop.isOpen ? 'Open' : 'Closed',
                        tone: shop.isOpen ? PillTone.success : PillTone.neutral),
                    StatusPill('${shop.avgPrepMinutes} min prep',
                        icon: Icons.schedule_rounded),
                    if (shop.minOrderAmount > 0)
                      StatusPill('Min. ${formatKes(shop.minOrderAmount)}'),
                  ],
                ),
                const SizedBox(height: SfSpace.sm),
                Row(children: [
                  const Icon(Icons.place_outlined,
                      size: 18, color: SfColors.inkMuted),
                  const SizedBox(width: SfSpace.xxs),
                  Expanded(
                    child: Text(shop.address,
                        style: text.bodyMedium,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                  ),
                ]),
                if (!shop.isOpen) ...[
                  const SizedBox(height: SfSpace.sm),
                  const InlineMessage(
                    "This shop is closed right now. You can look at the menu "
                    'and order once it opens.',
                    isError: false,
                  ),
                ],
              ]),
            ),
          ),
          if (_sections.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(
                icon: Icons.menu_book_outlined,
                title: 'No menu yet',
                message: "This shop hasn't added any items.",
              ),
            )
          else ...[
            SliverPersistentHeader(
              pinned: true,
              delegate: _CategoryBar(
                height: _barHeight,
                categories: _sections.keys.toList(),
                active: _active,
                onTap: _jumpTo,
              ),
            ),
            // One box so every section exists (and can be scrolled to)
            SliverToBoxAdapter(
              child: Column(children: [
                for (final entry in _sections.entries) ...[
                  Padding(
                    key: _keys[entry.key],
                    padding: const EdgeInsets.fromLTRB(
                        SfSpace.md, SfSpace.lg, SfSpace.md, SfSpace.xs),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(menuCategoryLabel(entry.key),
                          style: text.titleLarge),
                    ),
                  ),
                  for (final item in entry.value) ...[
                    _MenuRow(
                      item: item,
                      quantity: inThisShop ? cart.quantityOf(item.id) : 0,
                      canOrder: shop.isOpen && item.isAvailable,
                      onTap: () => _openItem(item),
                      onQuantity: (q) => _setQty(item, q),
                    ),
                    const Divider(indent: SfSpace.md, endIndent: SfSpace.md),
                  ],
                ],
                const SizedBox(height: SfSpace.xxl),
              ]),
            ),
          ],
        ],
      ),
    );
  }
}

class _CategoryBar extends SliverPersistentHeaderDelegate {
  _CategoryBar({required this.height, required this.categories,
      required this.active, required this.onTap});

  final double height;
  final List<String> categories;
  final String? active;
  final ValueChanged<String> onTap;

  @override
  double get minExtent => height;
  @override
  double get maxExtent => height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: SfColors.surface,
      alignment: Alignment.centerLeft,
      child: Column(children: [
        Expanded(
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(
                horizontal: SfSpace.md, vertical: SfSpace.xs),
            itemCount: categories.length,
            separatorBuilder: (_, __) => const SizedBox(width: SfSpace.xs),
            itemBuilder: (_, i) {
              final c = categories[i];
              return ChoiceChip(
                label: Text(menuCategoryLabel(c)),
                selected: c == active,
                onSelected: (_) => onTap(c),
              );
            },
          ),
        ),
        const Divider(),
      ]),
    );
  }

  @override
  bool shouldRebuild(_CategoryBar old) =>
      old.active != active || old.categories != categories;
}

/// Text on the left, square photo on the right with a + / stepper.
class _MenuRow extends StatelessWidget {
  const _MenuRow({required this.item, required this.quantity,
      required this.canOrder, required this.onTap, required this.onQuantity});

  final MenuItem item;
  final int quantity;
  final bool canOrder;
  final VoidCallback onTap;
  final ValueChanged<int> onQuantity;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final discounted = item.effectivePrice < item.price;
    final stepper = canOrder
        ? QtyStepper(
            quantity: quantity, onChanged: onQuantity, onSurface: item.photoUrl != null)
        : null;
    return InkWell(
      onTap: onTap,
      child: Opacity(
        opacity: item.isAvailable ? 1 : 0.5,
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: SfSpace.md, vertical: SfSpace.sm),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(item.name, style: text.titleSmall),
                const SizedBox(height: SfSpace.xxs),
                Row(children: [
                  Text(formatKes(item.effectivePrice),
                      style: text.bodyLarge!.copyWith(
                          color: discounted ? SfColors.accentStrong : SfColors.ink,
                          fontWeight: FontWeight.w500)),
                  if (discounted) ...[
                    const SizedBox(width: SfSpace.xs),
                    Text(formatKes(item.price),
                        style: text.bodyMedium!.copyWith(
                            decoration: TextDecoration.lineThrough)),
                  ],
                ]),
                if (item.description != null && item.description!.isNotEmpty) ...[
                  const SizedBox(height: SfSpace.xxs),
                  Text(item.description!,
                      style: text.bodyMedium,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                ],
                if (!item.isAvailable) ...[
                  const SizedBox(height: SfSpace.xs),
                  const StatusPill('Sold out'),
                ],
              ]),
            ),
            const SizedBox(width: SfSpace.md),
            if (item.photoUrl != null)
              SizedBox(
                width: 96,
                height: 96,
                child: Stack(children: [
                  SfNetworkImage(
                    url: item.photoUrl,
                    width: 96,
                    height: 96,
                    radius: SfRadius.md,
                    fallbackIcon: Icons.shopping_basket_outlined,
                  ),
                  if (stepper != null)
                    Positioned(right: 4, bottom: 4, child: stepper),
                ]),
              )
            else if (stepper != null)
              stepper,
          ]),
        ),
      ),
    );
  }
}

/// Item details with a quantity picker.
class _ItemSheet extends StatefulWidget {
  const _ItemSheet({required this.item, required this.canOrder,
      required this.initialQty, required this.onConfirm});

  final MenuItem item;
  final bool canOrder;
  final int initialQty;
  final ValueChanged<int> onConfirm;

  @override
  State<_ItemSheet> createState() => _ItemSheetState();
}

class _ItemSheetState extends State<_ItemSheet> {
  late int _qty = widget.initialQty > 0 ? widget.initialQty : 1;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final item = widget.item;
    final updating = widget.initialQty > 0;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(SfSpace.md, 0, SfSpace.md, SfSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (item.photoUrl != null) ...[
            AspectRatio(
              aspectRatio: 16 / 10,
              child: SfNetworkImage(
                  url: item.photoUrl, fallbackIcon: Icons.shopping_basket_outlined),
            ),
            const SizedBox(height: SfSpace.md),
          ],
          Text(item.name, style: text.headlineSmall),
          const SizedBox(height: SfSpace.xxs),
          Text(formatKes(item.effectivePrice), style: text.titleMedium),
          if (item.description != null && item.description!.isNotEmpty) ...[
            const SizedBox(height: SfSpace.sm),
            Text(item.description!, style: text.bodyLarge),
          ],
          const SizedBox(height: SfSpace.lg),
          if (!widget.canOrder)
            InlineMessage(
              item.isAvailable
                  ? "The shop is closed, so this can't be ordered right now."
                  : 'Sold out for now.',
              isError: false,
            )
          else ...[
            Center(
              child: QtyStepper(
                quantity: _qty,
                onChanged: (q) => setState(() => _qty = q),
              ),
            ),
            const SizedBox(height: SfSpace.lg),
            SfButton.primary(
              label: _qty == 0
                  ? 'Remove from cart'
                  : '${updating ? 'Update' : 'Add'} $_qty · ${formatKes(item.effectivePrice * _qty)}',
              onPressed: _qty == 0 && !updating
                  ? null
                  : () {
                      widget.onConfirm(_qty);
                      Navigator.pop(context);
                    },
            ),
          ],
        ],
      ),
    );
  }
}
