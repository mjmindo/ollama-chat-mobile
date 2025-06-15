import 'package:flutter/material.dart';

class TypingIndicator extends StatefulWidget {
  const TypingIndicator({super.key});

  @override
  State<TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<TypingIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 0.0),
      child: Row(
        children: [
          const Padding(
              padding: EdgeInsets.only(right: 8.0, top: 4.0),
              child: CircleAvatar(
                  backgroundImage: AssetImage('assets/icon.png'),
                  backgroundColor: Colors.transparent)),
          Container(
            margin: const EdgeInsets.symmetric(vertical: 4.0),
            padding:
                const EdgeInsets.symmetric(vertical: 10.0, horizontal: 14.0),
            decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(16.0)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(3, (index) {
                return FadeTransition(
                  opacity: Tween(begin: 0.3, end: 1.0).animate(CurvedAnimation(
                      parent: _controller,
                      curve: Interval(index * 0.2, (index * 0.2) + 0.6,
                          curve: Curves.easeInOut))),
                  child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                          color: theme.colorScheme.onSurface,
                          shape: BoxShape.circle)),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}