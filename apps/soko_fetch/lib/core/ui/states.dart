import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import '../design/tokens.dart';
import 'buttons.dart';

/// Nothing to show (no orders, no shops...).
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title,
      this.message, this.actionLabel, this.onAction});

  final IconData icon;
  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(SfSpace.xl),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 72,
            height: 72,
            decoration: const BoxDecoration(
                color: SfColors.surface2, shape: BoxShape.circle),
            child: Icon(icon, size: 32, color: SfColors.ink),
          ),
          const SizedBox(height: SfSpace.md),
          Text(title, style: text.titleMedium, textAlign: TextAlign.center),
          if (message != null) ...[
            const SizedBox(height: SfSpace.xs),
            Text(message!, style: text.bodyMedium, textAlign: TextAlign.center),
          ],
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: SfSpace.lg),
            SfButton.secondary(
                label: actionLabel!, onPressed: onAction, expand: false),
          ],
        ]),
      ),
    );
  }
}

/// A failed load with a way to try again.
class ErrorState extends StatelessWidget {
  const ErrorState(
      {super.key, this.message = 'Something went wrong.', required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => EmptyState(
        icon: Icons.wifi_off_rounded,
        title: "Couldn't load this",
        message: message,
        actionLabel: 'Try again',
        onAction: onRetry,
      );
}

/// An inline warning/error under a form field or above a button.
class InlineMessage extends StatelessWidget {
  const InlineMessage(this.message, {super.key, this.isError = true});

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final fg = isError ? SfColors.danger : SfColors.inkMuted;
    return Container(
      padding: const EdgeInsets.all(SfSpace.sm),
      decoration: BoxDecoration(
        color: isError ? SfColors.dangerSoft : SfColors.surface2,
        borderRadius: SfRadius.mdAll,
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(isError ? Icons.error_outline_rounded : Icons.info_outline_rounded,
            color: fg, size: 20),
        const SizedBox(width: SfSpace.xs),
        Expanded(
          child: Text(message,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium!
                  .copyWith(color: fg)),
        ),
      ]),
    );
  }
}

/// Small centred spinner.
class SfLoader extends StatelessWidget {
  const SfLoader({super.key});

  @override
  Widget build(BuildContext context) => const Center(
        child: SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(strokeWidth: 3)),
      );
}

/// A grey block that shimmers while content loads.
class Skeleton extends StatelessWidget {
  const Skeleton({super.key, this.width, this.height = 16,
      this.radius = SfRadius.sm});

  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) => Shimmer.fromColors(
        baseColor: SfColors.surface2,
        highlightColor: SfColors.surface,
        child: Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: SfColors.surface3,
            borderRadius: BorderRadius.circular(radius),
          ),
        ),
      );
}

/// Placeholder rows: a square thumbnail and two lines of text.
class LoadingList extends StatelessWidget {
  const LoadingList({super.key, this.count = 5});

  final int count;

  @override
  Widget build(BuildContext context) => ListView.separated(
        physics: const NeverScrollableScrollPhysics(),
        shrinkWrap: true,
        padding: const EdgeInsets.all(SfSpace.md),
        itemCount: count,
        separatorBuilder: (_, __) => const SizedBox(height: SfSpace.md),
        itemBuilder: (_, __) => const Row(children: [
          Skeleton(width: 56, height: 56, radius: SfRadius.sm),
          SizedBox(width: SfSpace.sm),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Skeleton(width: 160),
              SizedBox(height: SfSpace.xs),
              Skeleton(width: 100, height: 12),
            ]),
          ),
        ]),
      );
}
