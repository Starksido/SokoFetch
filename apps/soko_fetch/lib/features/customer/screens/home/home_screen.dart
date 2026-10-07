import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/ui/ui.dart';
import '../../models/models.dart';
import '../../providers/providers.dart';
import '../../widgets/address_sheet.dart';
import '../../widgets/categories.dart';
import '../../widgets/shop_card.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key, this.onSearch});

  /// Opens the Browse tab (search).
  final VoidCallback? onSearch;

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  String? _category;
  bool _openNow = false;
  bool _topRated = false;

  List<Merchant> _filtered(List<Merchant> all) {
    var list = all.where((m) => !_openNow || m.isOpen).toList();
    if (_topRated) {
      list = list.where((m) => m.rating >= 4.5).toList()
        ..sort((a, b) => b.rating.compareTo(a.rating));
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final shops = ref.watch(merchantsProvider(_category));
    final width = MediaQuery.sizeOf(context).width;
    final columns = switch (Breakpoint.fromWidth(width)) {
      Breakpoint.compact => 1,
      Breakpoint.medium => 2,
      Breakpoint.expanded => 3,
    };
    final filtering = _category != null || _openNow || _topRated;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(merchantsProvider(_category));
            ref.invalidate(addressesProvider);
          },
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              const SliverToBoxAdapter(child: _DeliverTo()),
              SliverToBoxAdapter(child: _SearchPill(onTap: widget.onSearch)),
              SliverToBoxAdapter(
                child: _CategoryRail(
                  selected: _category,
                  onSelected: (v) => setState(() => _category = v),
                ),
              ),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 40,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: SfSpace.md),
                    children: [
                      FilterChip(
                        label: const Text('Open now'),
                        selected: _openNow,
                        onSelected: (v) => setState(() => _openNow = v),
                      ),
                      const SizedBox(width: SfSpace.xs),
                      FilterChip(
                        label: const Text('Top rated'),
                        avatar: Icon(Icons.star_rounded,
                            size: 16,
                            color: _topRated ? Colors.white : SfColors.rating),
                        selected: _topRated,
                        onSelected: (v) => setState(() => _topRated = v),
                      ),
                    ],
                  ),
                ),
              ),
              ...shops.when(
                loading: () => [
                  SliverPadding(
                    padding: const EdgeInsets.all(SfSpace.md),
                    sliver: SliverList.separated(
                      itemCount: 3,
                      separatorBuilder: (_, __) =>
                          const SizedBox(height: SfSpace.lg),
                      itemBuilder: (_, __) => const ShopCardSkeleton(),
                    ),
                  ),
                ],
                error: (e, _) => [
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: ErrorState(
                      message: 'Check your connection and try again.',
                      onRetry: () => ref.invalidate(merchantsProvider(_category)),
                    ),
                  ),
                ],
                data: (all) {
                  final list = _filtered(all);
                  if (list.isEmpty) {
                    return [
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: EmptyState(
                          icon: Icons.storefront_outlined,
                          title: 'No shops here yet',
                          message: filtering
                              ? 'Try another category or clear the filters.'
                              : 'New shops are joining. Check back soon.',
                          actionLabel: filtering ? 'Clear filters' : null,
                          onAction: () => setState(() {
                            _category = null;
                            _openNow = false;
                            _topRated = false;
                          }),
                        ),
                      ),
                    ];
                  }
                  final popular = !filtering && list.length > 2
                      ? ([...list.where((m) => m.isOpen)]
                            ..sort((a, b) => b.rating.compareTo(a.rating)))
                          .take(6)
                          .toList()
                      : <Merchant>[];
                  return [
                    if (popular.isNotEmpty) ...[
                      const SliverToBoxAdapter(
                          child: SectionHeader('Popular near you')),
                      SliverToBoxAdapter(
                        child: SizedBox(
                          height: 250,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(
                                horizontal: SfSpace.md),
                            itemCount: popular.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(width: SfSpace.sm),
                            itemBuilder: (_, i) => SizedBox(
                              width: 280,
                              child: ShopCard(
                                  shop: popular[i], imageHeight: 150),
                            ),
                          ),
                        ),
                      ),
                    ],
                    SliverToBoxAdapter(
                      child: SectionHeader(_category == null
                          ? 'All shops'
                          : categoryOf(_category!).label),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(
                          SfSpace.md, 0, SfSpace.md, SfSpace.xl),
                      sliver: SliverGrid(
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: columns,
                          crossAxisSpacing: SfSpace.md,
                          mainAxisSpacing: SfSpace.lg,
                          mainAxisExtent: 268,
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (_, i) => ShopCard(shop: list[i], imageHeight: 180),
                          childCount: list.length,
                        ),
                      ),
                    ),
                  ];
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Deliver to · Home ▾" with the selected saved address.
class _DeliverTo extends ConsumerWidget {
  const _DeliverTo();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final address = ref.watch(selectedAddressProvider);
    final loading = ref.watch(addressesProvider).isLoading;
    return InkWell(
      onTap: () => showAddressSheet(context),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            SfSpace.md, SfSpace.sm, SfSpace.md, SfSpace.sm),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Deliver to', style: text.bodySmall),
              const SizedBox(height: 2),
              Row(children: [
                Flexible(
                  child: Text(
                    loading
                        ? '…'
                        : address == null
                            ? 'Add a delivery address'
                            : '${address.label} · ${address.addressLine}',
                    style: text.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const Icon(Icons.keyboard_arrow_down_rounded),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _SearchPill extends StatelessWidget {
  const _SearchPill({this.onTap});
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(
            SfSpace.md, SfSpace.xs, SfSpace.md, SfSpace.md),
        child: Material(
          color: SfColors.surface2,
          shape: const StadiumBorder(),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: SfSpace.md, vertical: 14),
              child: Row(children: [
                const Icon(Icons.search_rounded),
                const SizedBox(width: SfSpace.sm),
                Text('Search shops and food',
                    style: Theme.of(context)
                        .textTheme
                        .bodyLarge!
                        .copyWith(color: SfColors.inkMuted)),
              ]),
            ),
          ),
        ),
      );
}

class _CategoryRail extends StatelessWidget {
  const _CategoryRail({required this.selected, required this.onSelected});

  final String? selected;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    Widget tile(String? value, String label, IconData icon) {
      final isSelected = value == selected;
      return Semantics(
        selected: isSelected,
        button: true,
        child: InkWell(
          borderRadius: SfRadius.mdAll,
          onTap: () => onSelected(isSelected ? null : value),
          child: SizedBox(
            width: 72,
            child: Column(children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: isSelected ? SfColors.ink : SfColors.surface2,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon,
                    color: isSelected ? Colors.white : SfColors.ink, size: 26),
              ),
              const SizedBox(height: SfSpace.xs),
              Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.labelSmall!.copyWith(
                      fontWeight:
                          isSelected ? FontWeight.w700 : FontWeight.w500)),
            ]),
          ),
        ),
      );
    }

    return SizedBox(
      height: 96,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: SfSpace.xs),
        children: [
          tile(null, 'All', Icons.apps_rounded),
          for (final c in kShopCategories) tile(c.value, c.label, c.icon),
        ],
      ),
    );
  }
}
