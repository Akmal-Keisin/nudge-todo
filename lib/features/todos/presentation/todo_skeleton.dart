import 'package:flutter/material.dart';

/// Placeholder rows shown while the list loads for the first time. Sized like
/// the real rows so the list does not jump when the data arrives.
class TodoSkeleton extends StatefulWidget {
  const TodoSkeleton({this.rows = 6, super.key});

  final int rows;

  @override
  State<TodoSkeleton> createState() => _TodoSkeletonState();
}

class _TodoSkeletonState extends State<TodoSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.surfaceContainerHighest;
    final opacity = Tween<double>(begin: 0.35, end: 0.75).animate(_controller);

    return ListView.builder(
      padding: const EdgeInsets.only(top: 8, bottom: 16),
      itemCount: widget.rows,
      itemBuilder: (context, index) => Card(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
          child: Row(
            children: [
              _Block(color: color, opacity: opacity, width: 20, height: 20),
              const SizedBox(width: 16),
              Expanded(
                child: _Block(
                  color: color,
                  opacity: opacity,
                  width: double.infinity,
                  height: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Block extends StatelessWidget {
  const _Block({
    required this.color,
    required this.opacity,
    required this.width,
    required this.height,
  });

  final Color color;
  final Animation<double> opacity;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: opacity,
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(4),
        ),
      ),
    );
  }
}
