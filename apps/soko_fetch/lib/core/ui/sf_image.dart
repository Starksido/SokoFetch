import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../design/tokens.dart';
import 'states.dart';

/// A network photo with a shimmer while loading and a generated fallback
/// (soft tinted background with an icon or initials) when there is no photo.
class SfNetworkImage extends StatelessWidget {
  const SfNetworkImage({
    super.key,
    required this.url,
    this.width,
    this.height,
    this.radius = SfRadius.md,
    this.fallbackIcon = Icons.storefront_outlined,
    this.fallbackLabel,
    this.fit = BoxFit.cover,
  });

  final String? url;
  final double? width;
  final double? height;
  final double radius;
  final IconData fallbackIcon;

  /// Used for initials and to pick a stable tint (e.g. the shop name).
  final String? fallbackLabel;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final fallback = ImageFallback(
        icon: fallbackIcon, label: fallbackLabel, width: width, height: height);
    final hasUrl = url != null && url!.isNotEmpty;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: width,
        height: height,
        child: hasUrl
            ? CachedNetworkImage(
                imageUrl: url!,
                fit: fit,
                placeholder: (_, __) =>
                    Skeleton(width: width, height: height ?? 120, radius: 0),
                errorWidget: (_, __, ___) => fallback,
              )
            : fallback,
      ),
    );
  }
}

class ImageFallback extends StatelessWidget {
  const ImageFallback(
      {super.key, required this.icon, this.label, this.width, this.height});

  final IconData icon;
  final String? label;
  final double? width;
  final double? height;

  static const _tints = [
    (SfColors.accentSoft, SfColors.accentStrong),
    (SfColors.successSoft, SfColors.success),
    (SfColors.warningSoft, SfColors.warning),
    (SfColors.surface2, SfColors.inkMuted),
  ];

  static String initials(String text) {
    final words = text
        .replaceAll(RegExp(r'[^A-Za-z0-9 ]'), ' ')
        .split(' ')
        .where((w) => w.isNotEmpty)
        .toList();
    if (words.isEmpty) return '';
    return (words.first[0] + (words.length > 1 ? words[1][0] : ''))
        .toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final seed = (label ?? '').codeUnits.fold<int>(0, (a, b) => a + b);
    final (bg, fg) = _tints[seed % _tints.length];
    final text = label == null ? '' : initials(label!);
    return LayoutBuilder(builder: (context, c) {
      final side = [
        c.maxWidth.isFinite ? c.maxWidth : 96.0,
        c.maxHeight.isFinite ? c.maxHeight : 96.0,
      ].reduce((a, b) => a < b ? a : b);
      return Container(
        width: width,
        height: height,
        color: bg,
        alignment: Alignment.center,
        child: side < 72 || text.isEmpty
            ? Icon(icon, color: fg, size: (side * 0.42).clamp(16, 48))
            : Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(icon, color: fg, size: (side * 0.22).clamp(20, 40)),
                const SizedBox(height: SfSpace.xxs),
                Text(text,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium!
                        .copyWith(color: fg)),
              ]),
      );
    });
  }
}

/// Round avatar with initials (riders, customers, shops without a logo).
class InitialsAvatar extends StatelessWidget {
  const InitialsAvatar({super.key, required this.name, this.size = 48});

  final String name;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration:
            const BoxDecoration(color: SfColors.surface2, shape: BoxShape.circle),
        child: Text(
          ImageFallback.initials(name).isEmpty ? '?' : ImageFallback.initials(name),
          style: Theme.of(context)
              .textTheme
              .titleSmall!
              .copyWith(fontSize: size * 0.36),
        ),
      );
}
