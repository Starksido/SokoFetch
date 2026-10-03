import 'package:flutter/material.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';
import '../../config/app_theme.dart';
import '../../network/secure_client.dart';

class RateOrderScreen extends StatefulWidget {
  const RateOrderScreen({super.key});
  @override
  State<RateOrderScreen> createState() => _RateOrderScreenState();
}

class _RateOrderScreenState extends State<RateOrderScreen> {
  double _courierRating  = 5;
  double _merchantRating = 5;
  final _reviewCtrl = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _reviewCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final orderId =
        ModalRoute.of(context)!.settings.arguments as String;
    setState(() => _submitting = true);
    try {
      await SecureApiClient.instance.post('/orders/$orderId/rate', data: {
        'courier_rating':  _courierRating.round(),
        'merchant_rating': _merchantRating.round(),
        'review':          _reviewCtrl.text.trim().isEmpty
            ? null
            : _reviewCtrl.text.trim(),
      });
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/home');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Thanks for your feedback!')),
      );
    } catch (_) {
      setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Rate Your Experience')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Icon(Icons.star_rounded, size: 64, color: AppTheme.gold),
          const SizedBox(height: 12),
          const Text('How was your delivery?',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 20)),
          const SizedBox(height: 32),
          _RatingSection(
            title: 'Rate your rider',
            value: _courierRating,
            onChanged: (v) => setState(() => _courierRating = v),
          ),
          const SizedBox(height: 24),
          _RatingSection(
            title: 'Rate the restaurant / shop',
            value: _merchantRating,
            onChanged: (v) => setState(() => _merchantRating = v),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _reviewCtrl,
            maxLines: 3,
            decoration: InputDecoration(
              hintText: 'Leave a comment (optional)',
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 32),
          ElevatedButton(
            onPressed: _submitting ? null : _submit,
            style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(52)),
            child: _submitting
                ? const SizedBox(
                    width: 22, height: 22,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2.5))
                : const Text('Submit Rating'),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => Navigator.pushReplacementNamed(context, '/home'),
            child: const Text('Skip',
                style: TextStyle(color: AppTheme.mgray)),
          ),
        ],
      ),
    );
  }
}

class _RatingSection extends StatelessWidget {
  final String title;
  final double value;
  final ValueChanged<double> onChanged;
  const _RatingSection(
      {required this.title,
      required this.value,
      required this.onChanged});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16)),
        child: Column(children: [
          Text(title,
              style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          RatingBar.builder(
            initialRating: value,
            minRating: 1,
            allowHalfRating: false,
            itemCount: 5,
            itemSize: 40,
            itemBuilder: (_, __) =>
                const Icon(Icons.star_rounded, color: AppTheme.gold),
            onRatingUpdate: onChanged,
          ),
        ]),
      );
}
