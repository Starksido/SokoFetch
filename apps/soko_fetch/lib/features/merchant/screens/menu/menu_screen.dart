import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../../core/theme.dart';
import '../../models/models.dart';
import '../../../../core/api_client.dart';
import '../../providers/providers.dart';

class MenuScreen extends ConsumerWidget {
  const MenuScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final menuAsync = ref.watch(menuProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Menu Management'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () async {
              await Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const AddEditItemScreen()));
              ref.invalidate(menuProvider);
            },
          ),
        ],
      ),
      body: menuAsync.when(
        loading: () =>
            const Center(child: CircularProgressIndicator(color: AppTheme.accent)),
        error: (e, _) => Center(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Text('Failed to load menu'),
            const SizedBox(height: 12),
            ElevatedButton(
                onPressed: () => ref.invalidate(menuProvider),
                child: const Text('Retry')),
          ]),
        ),
        data: (items) {
          if (items.isEmpty) {
            return Center(
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.restaurant_menu_outlined,
                        size: 72, color: AppTheme.mgray),
                    const SizedBox(height: 16),
                    const Text('No menu items yet',
                        style: TextStyle(color: AppTheme.mgray, fontSize: 16)),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: () async {
                        await Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const AddEditItemScreen()));
                        ref.invalidate(menuProvider);
                      },
                      icon: const Icon(Icons.add),
                      label: const Text('Add First Item'),
                    ),
                  ]),
            );
          }

          // Group by category
          final Map<String, List<MenuItem>> grouped = {};
          for (final item in items) {
            grouped.putIfAbsent(item.category, () => []).add(item);
          }

          return RefreshIndicator(
            color: AppTheme.accent,
            onRefresh: () async => ref.invalidate(menuProvider),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                for (final entry in grouped.entries) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(entry.key,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: AppTheme.brand)),
                  ),
                  ...entry.value.map((item) => _MenuItemTile(
                        item: item,
                        onToggle: (val) async {
                          await ApiClient.instance.put(
                              '/merchant/menu/${item.id}/availability?is_available=$val');
                          ref.invalidate(menuProvider);
                        },
                        onEdit: () async {
                          await Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) =>
                                      AddEditItemScreen(item: item)));
                          ref.invalidate(menuProvider);
                        },
                        onDelete: () async {
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (_) => AlertDialog(
                              title: const Text('Delete Item'),
                              content: Text(
                                  'Delete "${item.name}"? This cannot be undone.'),
                              actions: [
                                TextButton(
                                    onPressed: () =>
                                        Navigator.pop(context, false),
                                    child: const Text('Cancel')),
                                TextButton(
                                    onPressed: () =>
                                        Navigator.pop(context, true),
                                    child: const Text('Delete',
                                        style: TextStyle(color: AppTheme.red))),
                              ],
                            ),
                          );
                          if (confirm == true) {
                            await ApiClient.instance
                                .delete('/merchant/menu/${item.id}');
                            ref.invalidate(menuProvider);
                          }
                        },
                      )),
                  const SizedBox(height: 8),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

// ── Menu item tile ─────────────────────────────────────────────────────────────
class _MenuItemTile extends StatelessWidget {
  final MenuItem item;
  final ValueChanged<bool> onToggle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _MenuItemTile({
    required this.item,
    required this.onToggle,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: item.photoUrl != null
              ? CachedNetworkImage(
                  imageUrl: item.photoUrl!,
                  width: 56, height: 56,
                  fit: BoxFit.cover,
                  errorWidget: (_, __, ___) => _thumb())
              : _thumb(),
        ),
        title: Text(item.name,
            style: TextStyle(
                fontWeight: FontWeight.w600,
                color: item.isAvailable ? AppTheme.brand : AppTheme.mgray)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('KES ${item.effectivePrice.toStringAsFixed(0)}',
                style: const TextStyle(
                    color: AppTheme.accent, fontWeight: FontWeight.w600)),
            if (!item.isAvailable)
              const Text('UNAVAILABLE',
                  style: TextStyle(
                      color: AppTheme.red, fontSize: 10,
                      fontWeight: FontWeight.bold)),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Switch(
              value: item.isAvailable,
              onChanged: onToggle,
              activeColor: AppTheme.accent,
            ),
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'edit') onEdit();
                if (v == 'delete') onDelete();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'edit', child: Text('Edit')),
                PopupMenuItem(
                    value: 'delete',
                    child: Text('Delete',
                        style: TextStyle(color: AppTheme.red))),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _thumb() => Container(
        width: 56, height: 56,
        decoration: BoxDecoration(
            color: AppTheme.lgray,
            borderRadius: BorderRadius.circular(8)),
        child: const Icon(Icons.fastfood_outlined,
            color: AppTheme.mgray, size: 28),
      );
}

// ══════════════════════════════════════════════════════════════════════════════
// Add / Edit item screen
// ══════════════════════════════════════════════════════════════════════════════
class AddEditItemScreen extends StatefulWidget {
  final MenuItem? item;
  const AddEditItemScreen({super.key, this.item});

  @override
  State<AddEditItemScreen> createState() => _AddEditItemScreenState();
}

class _AddEditItemScreenState extends State<AddEditItemScreen> {
  final _formKey     = GlobalKey<FormState>();
  late final _name   = TextEditingController(text: widget.item?.name);
  late final _desc   = TextEditingController(text: widget.item?.description);
  late final _cat    = TextEditingController(text: widget.item?.category);
  late final _price  = TextEditingController(
      text: widget.item?.price.toStringAsFixed(0));
  late final _prep   = TextEditingController(
      text: (widget.item?.prepMinutes ?? 15).toString());
  late bool _isAvailable = widget.item?.isAvailable ?? true;
  bool _saving       = false;

  bool get isEdit => widget.item != null;

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final data = {
      'name':         _name.text.trim(),
      'description':  _desc.text.trim().isEmpty ? null : _desc.text.trim(),
      'category':     _cat.text.trim(),
      'price':        double.parse(_price.text.trim()),
      'prep_minutes': int.parse(_prep.text.trim()),
      'is_available': _isAvailable,
    };

    try {
      if (isEdit) {
        await ApiClient.instance
            .put('/merchant/menu/${widget.item!.id}', data: data);
      } else {
        await ApiClient.instance.post('/merchant/menu', data: data);
      }
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _name.dispose(); _desc.dispose(); _cat.dispose();
    _price.dispose(); _prep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          title: Text(isEdit ? 'Edit Item' : 'Add Menu Item')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _field(_name, 'Item name *',
                validator: (v) =>
                    v!.isEmpty ? 'Required' : null),
            const SizedBox(height: 12),
            _field(_desc, 'Description (optional)', maxLines: 2),
            const SizedBox(height: 12),
            _field(_cat, 'Category * (e.g. Mains, Drinks, Sides)',
                validator: (v) => v!.isEmpty ? 'Required' : null),
            const SizedBox(height: 12),
            _field(_price, 'Price (KES) *',
                keyboardType: TextInputType.number,
                validator: (v) {
                  if (v!.isEmpty) return 'Required';
                  if (double.tryParse(v) == null) return 'Enter a valid price';
                  return null;
                }),
            const SizedBox(height: 12),
            _field(_prep, 'Prep time (minutes)',
                keyboardType: TextInputType.number),
            const SizedBox(height: 12),
            SwitchListTile(
              value: _isAvailable,
              onChanged: (v) => setState(() => _isAvailable = v),
              title: const Text('Available for ordering',
                  style: TextStyle(fontWeight: FontWeight.w500)),
              activeColor: AppTheme.accent,
              contentPadding: EdgeInsets.zero,
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: _saving ? null : _save,
              style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(52)),
              child: _saving
                  ? const SizedBox(width: 22, height: 22,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2.5))
                  : Text(isEdit ? 'Save Changes' : 'Add Item'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(TextEditingController ctrl, String label,
      {int maxLines = 1,
      TextInputType? keyboardType,
      String? Function(String?)? validator}) {
    return TextFormField(
      controller:   ctrl,
      maxLines:     maxLines,
      keyboardType: keyboardType,
      validator:    validator,
      decoration: InputDecoration(labelText: label),
    );
  }
}

