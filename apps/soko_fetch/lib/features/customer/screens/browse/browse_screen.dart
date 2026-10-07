import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/ui/ui.dart';
import '../../models/models.dart';
import '../../providers/providers.dart';
import '../../widgets/categories.dart';
import '../../widgets/shop_card.dart';

/// Search shops by name, category or area; browse by category.
class BrowseScreen extends ConsumerStatefulWidget {
  const BrowseScreen({super.key});

  @override
  ConsumerState<BrowseScreen> createState() => BrowseScreenState();
}

class BrowseScreenState extends ConsumerState<BrowseScreen> {
  final _query = TextEditingController();
  final _focus = FocusNode();
  String? _category;

  /// Called when the Home search pill opens this tab.
  void focusSearch() => _focus.requestFocus();

  @override
  void dispose() {
    _query.dispose();
    _focus.dispose();
    super.dispose();
  }

  List<Merchant> _matches(List<Merchant> all) {
    final q = _query.text.trim().toLowerCase();
    return all.where((m) {
      if (_category != null && m.category != _category) return false;
      if (q.isEmpty) return true;
      return m.shopName.toLowerCase().contains(q) ||
          categoryOf(m.category).label.toLowerCase().contains(q) ||
          m.address.toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final shops = ref.watch(merchantsProvider(null));
    final searching = _query.text.trim().isNotEmpty || _category != null;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
                SfSpace.md, SfSpace.md, SfSpace.md, SfSpace.xs),
            child: TextField(
              controller: _query,
              focusNode: _focus,
              textInputAction: TextInputAction.search,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Search shops and food',
                prefixIcon: const Icon(Icons.search_rounded),
                border: const OutlineInputBorder(
                    borderRadius: SfRadius.pillAll, borderSide: BorderSide.none),
                enabledBorder: const OutlineInputBorder(
                    borderRadius: SfRadius.pillAll, borderSide: BorderSide.none),
                focusedBorder: const OutlineInputBorder(
                    borderRadius: SfRadius.pillAll,
                    borderSide: BorderSide(color: SfColors.ink, width: 2)),
                suffixIcon: searching
                    ? IconButton(
                        tooltip: 'Clear',
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => setState(() {
                          _query.clear();
                          _category = null;
                        }),
                      )
                    : null,
              ),
            ),
          ),
          if (_category != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: SfSpace.md),
              child: Align(
                alignment: Alignment.centerLeft,
                child: InputChip(
                  label: Text(categoryOf(_category!).label),
                  onDeleted: () => setState(() => _category = null),
                ),
              ),
            ),
          Expanded(
            child: !searching
                ? _CategoryGrid(
                    onSelected: (c) => setState(() => _category = c))
                : shops.when(
                    loading: () => const LoadingList(),
                    error: (e, _) => ErrorState(
                        onRetry: () => ref.invalidate(merchantsProvider(null))),
                    data: (all) {
                      final list = _matches(all);
                      if (list.isEmpty) {
                        return const EmptyState(
                          icon: Icons.search_off_rounded,
                          title: 'No matches',
                          message: 'Try a shop name, a category or an area.',
                        );
                      }
                      return ListView.builder(
                        padding: const EdgeInsets.only(bottom: SfSpace.xl),
                        itemCount: list.length + 1,
                        itemBuilder: (_, i) => i == 0
                            ? Padding(
                                padding: const EdgeInsets.fromLTRB(SfSpace.md,
                                    SfSpace.sm, SfSpace.md, SfSpace.xs),
                                child: Text(
                                    '${list.length} shop${list.length == 1 ? '' : 's'}',
                                    style: text.bodyMedium),
                              )
                            : ShopRow(shop: list[i - 1]),
                      );
                    },
                  ),
          ),
        ]),
      ),
    );
  }
}

class _CategoryGrid extends StatelessWidget {
  const _CategoryGrid({required this.onSelected});
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final width = MediaQuery.sizeOf(context).width;
    return ListView(
      padding: const EdgeInsets.all(SfSpace.md),
      children: [
        Text('Browse categories', style: text.titleLarge),
        const SizedBox(height: SfSpace.md),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: width >= 600 ? 4 : 2,
          mainAxisSpacing: SfSpace.sm,
          crossAxisSpacing: SfSpace.sm,
          childAspectRatio: 1.6,
          children: [
            for (final c in kShopCategories)
              Material(
                color: SfColors.surface2,
                borderRadius: SfRadius.mdAll,
                child: InkWell(
                  borderRadius: SfRadius.mdAll,
                  onTap: () => onSelected(c.value),
                  child: Padding(
                    padding: const EdgeInsets.all(SfSpace.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Icon(c.icon, size: 28),
                        Text(c.label, style: text.titleSmall),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
