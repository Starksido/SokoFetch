import 'package:flutter/material.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';

import '../../../../core/api_client.dart';
import '../../../../core/errors.dart';
import '../../../../core/ui/ui.dart';

class RateOrderScreen extends StatefulWidget {
  const RateOrderScreen({super.key});
  @override
  State<RateOrderScreen> createState() => _RateOrderScreenState();
}

class _RateOrderScreenState extends State<RateOrderScreen> {
  double _courierRating = 5;
  double _merchantRating = 5;
  final _reviewCtrl = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _reviewCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final orderId = ModalRoute.of(context)!.settings.arguments as String;
    setState(() { _submitting = true; _error = null; });
    try {
      await ApiClient.instance.post('/orders/$orderId/rate', data: {
        'courier_rating': _courierRating.round(),
        'merchant_rating': _merchantRating.round(),
        'review': _reviewCtrl.text.trim().isEmpty ? null : _reviewCtrl.text.trim(),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Thanks for your feedback!')));
      Navigator.pushNamedAndRemoveUntil(context, '/customer', (_) => false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _submitting = false;
          _error = errorMessage(e, "Couldn't send your rating.");
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.pushNamedAndRemoveUntil(context, '/customer', (_) => false),
            child: const Text('Skip'),
          ),
        ],
      ),
      bottomNavigationBar: BottomCtaBar(
          label: 'Send rating', loading: _submitting, onPressed: _submit),
      body: MaxWidth(
        maxWidth: 520,
        child: ListView(
          padding: const EdgeInsets.all(SfSpace.lg),
          children: [
            Text('How did it go?', style: text.headlineMedium),
            const SizedBox(height: SfSpace.xs),
            Text('Your rating helps riders and shops do better.',
                style: text.bodyLarge!.copyWith(color: SfColors.inkMuted)),
            const SizedBox(height: SfSpace.xl),
            _RatingRow(
              title: 'Your rider',
              value: _courierRating,
              onChanged: (v) => setState(() => _courierRating = v),
            ),
            const SizedBox(height: SfSpace.lg),
            _RatingRow(
              title: 'The shop',
              value: _merchantRating,
              onChanged: (v) => setState(() => _merchantRating = v),
            ),
            const SizedBox(height: SfSpace.xl),
            TextField(
              controller: _reviewCtrl,
              maxLines: 3,
              maxLength: 500,
              textCapitalization: TextCapitalization.sentences,
              decoration:
                  const InputDecoration(hintText: 'Anything to add? (optional)'),
            ),
            if (_error != null) InlineMessage(_error!),
          ],
        ),
      ),
    );
  }
}

class _RatingRow extends StatelessWidget {
  const _RatingRow(
      {required this.title, required this.value, required this.onChanged});

  final String title;
  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: SfSpace.xs),
          RatingBar.builder(
            initialRating: value,
            minRating: 1,
            allowHalfRating: false,
            itemCount: 5,
            itemSize: 44,
            itemPadding: const EdgeInsets.only(right: SfSpace.xxs),
            unratedColor: SfColors.surface3,
            itemBuilder: (_, __) =>
                const Icon(Icons.star_rounded, color: SfColors.rating),
            onRatingUpdate: onChanged,
          ),
        ],
      );
}
