import 'package:flutter/material.dart';

class SkeletonBox extends StatefulWidget {
  final double height;
  final double? width;
  final BorderRadius borderRadius;

  const SkeletonBox({
    Key? key,
    required this.height,
    this.width,
    this.borderRadius = const BorderRadius.all(Radius.circular(8)),
  }) : super(key: key);

  @override
  State<SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<SkeletonBox> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Container(
          height: widget.height,
          width: widget.width ?? double.infinity,
          decoration: BoxDecoration(
            borderRadius: widget.borderRadius,
            gradient: LinearGradient(
              begin: Alignment(-1.0 - _controller.value * 2, 0),
              end: Alignment(1.0 - _controller.value * 2, 0),
              colors: [
                Colors.grey.shade200,
                Colors.grey.shade100,
                Colors.grey.shade200,
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Skeleton placeholder that mirrors ProgressScreen's content.
class ProgressScreenSkeleton extends StatelessWidget {
  const ProgressScreenSkeleton({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        SkeletonBox(height: 110, borderRadius: BorderRadius.circular(18)),
        const SizedBox(height: 24),
        SkeletonBox(height: 18, width: 120, borderRadius: BorderRadius.circular(4)),
        const SizedBox(height: 14),
        ...List.generate(10, (i) => Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonBox(height: 14, width: 100, borderRadius: BorderRadius.circular(4)),
              const SizedBox(height: 8),
              SkeletonBox(height: 8, borderRadius: BorderRadius.circular(10)),
            ],
          ),
        )),
      ],
    );
  }
}

/// Skeleton placeholder that mirrors HistoryScreen's grouped session list.
class HistoryScreenSkeleton extends StatelessWidget {
  const HistoryScreenSkeleton({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SkeletonBox(height: 12, width: 60, borderRadius: BorderRadius.circular(4)),
        const SizedBox(height: 12),
        ...List.generate(3, (i) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: SkeletonBox(height: 62, borderRadius: BorderRadius.circular(12)),
        )),
        const SizedBox(height: 16),
        SkeletonBox(height: 12, width: 80, borderRadius: BorderRadius.circular(4)),
        const SizedBox(height: 12),
        ...List.generate(2, (i) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: SkeletonBox(height: 62, borderRadius: BorderRadius.circular(12)),
        )),
      ],
    );
  }
}

/// Skeleton placeholder for PracticeDashboardScreen's below-the-fold widgets
/// (week tracker + sign-of-day/streak cards) while their data loads.
class WeekTrackerSkeleton extends StatelessWidget {
  const WeekTrackerSkeleton({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(7, (i) => Padding(
        padding: const EdgeInsets.only(right: 10),
        child: SkeletonBox(height: 64, width: 50, borderRadius: BorderRadius.circular(14)),
      )),
    );
  }
}

/// Skeleton placeholder that mirrors SelectCollectionScreen's category list.
class SelectCollectionScreenSkeleton extends StatelessWidget {
  const SelectCollectionScreenSkeleton({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      itemCount: 8,
      separatorBuilder: (_, __) => const SizedBox(height: 16),
      itemBuilder: (context, index) => SkeletonBox(height: 76, borderRadius: BorderRadius.circular(18)),
    );
  }
}