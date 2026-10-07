import 'package:flutter/material.dart';

/// "KES 1,250" for whole amounts, "KES 377.25" when there are cents.
String formatKes(num amount) {
  final negative = amount < 0;
  final cents = (amount.abs() * 100).round();
  final whole = cents ~/ 100;
  final fraction = cents % 100;

  final digits = whole.toString();
  final grouped = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) grouped.write(',');
    grouped.write(digits[i]);
  }
  final decimals = fraction == 0 ? '' : '.${fraction.toString().padLeft(2, '0')}';
  return '${negative ? '-' : ''}KES $grouped$decimals';
}

class PriceText extends StatelessWidget {
  const PriceText(this.amount, {super.key, this.style});

  final num amount;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => Text(
        formatKes(amount),
        style: style ?? Theme.of(context).textTheme.titleSmall,
        maxLines: 1,
      );
}
