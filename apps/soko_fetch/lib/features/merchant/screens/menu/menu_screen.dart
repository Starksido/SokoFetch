import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/api_client.dart';
import '../../../../core/errors.dart';
import '../../../../core/ui/ui.dart';
import '../../models/models.dart';
import '../../providers/providers.dart';

class MenuScreen extends ConsumerWidget {
  const MenuScreen({super.key});

  Future<void> _openEditor(BuildContext context, WidgetRef ref, [MenuItem? item]) async {
    await Navigator.push(context,
        MaterialPageRoute(builder: (_) => AddEditItemScreen(item: item)));
    ref.invalidate(menuProvider);
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, MenuItem item) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete this item?'),
        content: Text('"${item.name}" will be removed from your menu.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Keep')),
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              style: TextButton.styleFrom(foregroundColor: SfColors.danger),
              child: const Text('Delete')),
        ],
      ),
    );
    if (confirm == true) {
      await ApiClient.instance.delete('/merchant/menu/${item.id}');
      ref.invalidate(menuProvider);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final menuAsync = ref.watch(menuProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Menu'),
        actions: [
          TextButton.icon(
            onPressed: () => _openEditor(context, ref),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Add item'),
          ),
          const SizedBox(width: SfSpace.xs),
        ],
      ),
      body: menuAsync.when(
        loading: () => const LoadingList(),
        error: (e, _) => ErrorState(onRetry: () => ref.invalidate(menuProvider)),
        data: (items) {
          if (items.isEmpty) {
            return EmptyState(
              icon: Icons.menu_book_outlined,
              title: 'Your menu is empty',
              message: 'Add what you sell so customers can order it.',
              actionLabel: 'Add your first item',
              onAction: () => _openEditor(context, ref),
            );
          }
          final grouped = <String, List<MenuItem>>{};
          for (final item in items) {
            grouped.putIfAbsent(item.category, () => []).add(item);
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(menuProvider),
            child: LayoutBuilder(builder: (context, c) {
              final columns = c.maxWidth >= 840 ? 2 : 1;
              final tileWidth =
                  (c.maxWidth - SfSpace.md * 2 - SfSpace.sm * (columns - 1)) / columns;
              return ListView(
                padding: const EdgeInsets.only(bottom: SfSpace.xl),
                children: [
                  for (final entry in grouped.entries) ...[
                    SectionHeader(entry.key),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: SfSpace.md),
                      child: Wrap(
                        spacing: SfSpace.sm,
                        runSpacing: SfSpace.sm,
                        children: [
                          for (final item in entry.value)
                            SizedBox(
                              width: tileWidth,
                              child: _MenuItemTile(
                                item: item,
                                onToggle: (val) async {
                                  await ApiClient.instance.put(
                                      '/merchant/menu/${item.id}/availability?is_available=$val');
                                  ref.invalidate(menuProvider);
                                },
                                onEdit: () => _openEditor(context, ref, item),
                                onDelete: () => _delete(context, ref, item),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                  Padding(
                    padding: const EdgeInsets.all(SfSpace.md),
                    child: Text('${items.length} items · '
                        '${items.where((i) => !i.isAvailable).length} sold out',
                        style: text.bodySmall),
                  ),
                ],
              );
            }),
          );
        },
      ),
    );
  }
}

class _MenuItemTile extends StatelessWidget {
  const _MenuItemTile({required this.item, required this.onToggle,
      required this.onEdit, required this.onDelete});

  final MenuItem item;
  final ValueChanged<bool> onToggle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Card(
      child: InkWell(
        borderRadius: SfRadius.mdAll,
        onTap: onEdit,
        child: Padding(
          padding: const EdgeInsets.all(SfSpace.sm),
          child: Row(children: [
            Opacity(
              opacity: item.isAvailable ? 1 : 0.5,
              child: SfNetworkImage(
                url: item.photoUrl,
                width: 64,
                height: 64,
                radius: SfRadius.sm,
                fallbackIcon: Icons.shopping_basket_outlined,
              ),
            ),
            const SizedBox(width: SfSpace.sm),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(item.name,
                    style: text.titleSmall,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(formatKes(item.effectivePrice), style: text.bodyMedium),
                if (!item.isAvailable) ...[
                  const SizedBox(height: SfSpace.xxs),
                  const StatusPill('Sold out', tone: PillTone.danger),
                ],
              ]),
            ),
            Switch(value: item.isAvailable, onChanged: onToggle),
            PopupMenuButton<String>(
              tooltip: 'More',
              onSelected: (v) => v == 'edit' ? onEdit() : onDelete(),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'edit', child: Text('Edit')),
                PopupMenuItem(
                    value: 'delete',
                    child: Text('Delete', style: TextStyle(color: SfColors.danger))),
              ],
            ),
          ]),
        ),
      ),
    );
  }
}

// ── Add / edit item ──────────────────────────────────────────────────────────
class AddEditItemScreen extends StatefulWidget {
  final MenuItem? item;
  const AddEditItemScreen({super.key, this.item});

  @override
  State<AddEditItemScreen> createState() => _AddEditItemScreenState();
}

class _AddEditItemScreenState extends State<AddEditItemScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.item?.name);
  late final _desc = TextEditingController(text: widget.item?.description);
  late final _cat = TextEditingController(text: widget.item?.category);
  late final _price =
      TextEditingController(text: widget.item?.price.toStringAsFixed(0));
  late final _prep =
      TextEditingController(text: (widget.item?.prepMinutes ?? 15).toString());
  late bool _isAvailable = widget.item?.isAvailable ?? true;
  bool _saving = false;
  String? _error;

  bool get isEdit => widget.item != null;

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _saving = true; _error = null; });

    final data = {
      'name': _name.text.trim(),
      'description': _desc.text.trim().isEmpty ? null : _desc.text.trim(),
      'category': _cat.text.trim(),
      'price': double.parse(_price.text.trim()),
      'prep_minutes': int.tryParse(_prep.text.trim()) ?? 15,
      'is_available': _isAvailable,
    };

    try {
      if (isEdit) {
        await ApiClient.instance.put('/merchant/menu/${widget.item!.id}', data: data);
      } else {
        await ApiClient.instance.post('/merchant/menu', data: data);
      }
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e, "Couldn't save the item."));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    _cat.dispose();
    _price.dispose();
    _prep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: Text(isEdit ? 'Edit item' : 'New item')),
      bottomNavigationBar: Column(mainAxisSize: MainAxisSize.min, children: [
        if (_error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(SfSpace.md, SfSpace.xs, SfSpace.md, 0),
            child: InlineMessage(_error!),
          ),
        BottomCtaBar(
            label: isEdit ? 'Save changes' : 'Add to menu',
            loading: _saving,
            onPressed: _save),
      ]),
      body: Form(
        key: _formKey,
        child: MaxWidth(
          maxWidth: 560,
          child: ListView(
            padding: const EdgeInsets.all(SfSpace.md),
            children: [
              TextFormField(
                controller: _name,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Name'),
                validator: (v) => v!.trim().isEmpty ? 'Enter a name' : null,
              ),
              const SizedBox(height: SfSpace.sm),
              TextFormField(
                controller: _desc,
                maxLines: 3,
                minLines: 2,
                textCapitalization: TextCapitalization.sentences,
                decoration:
                    const InputDecoration(labelText: 'Description (optional)'),
              ),
              const SizedBox(height: SfSpace.sm),
              TextFormField(
                controller: _cat,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                    labelText: 'Menu section', hintText: 'e.g. Mains, Drinks, Vegetables'),
                validator: (v) => v!.trim().isEmpty ? 'Enter a section' : null,
              ),
              const SizedBox(height: SfSpace.sm),
              Row(children: [
                Expanded(
                  child: TextFormField(
                    controller: _price,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: 'Price', prefixText: 'KES '),
                    validator: (v) => double.tryParse(v!.trim()) == null
                        ? 'Enter a price'
                        : null,
                  ),
                ),
                const SizedBox(width: SfSpace.sm),
                Expanded(
                  child: TextFormField(
                    controller: _prep,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: 'Prep time', suffixText: 'min'),
                  ),
                ),
              ]),
              const SizedBox(height: SfSpace.xs),
              SwitchListTile(
                value: _isAvailable,
                onChanged: (v) => setState(() => _isAvailable = v),
                title: Text('Available to order', style: text.titleSmall),
                subtitle: Text('Turn off when it runs out', style: text.bodySmall),
                contentPadding: EdgeInsets.zero,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
