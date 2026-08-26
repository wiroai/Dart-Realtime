import 'package:flutter/material.dart';

/// The title bar a destination owns.
///
/// The shell used to hold one shared bar naming the product, which meant
/// no screen could put anything in it and every screen repeated its own
/// name in the body. Each destination now carries its own bar, so the
/// conversation can hang its settings control where a settings control
/// belongs and the body can start with content.
///
/// Deliberately the small variant. A large collapsing title looked the
/// part but spent a sixth of the screen restating a word already printed
/// on the tab below it, and pushed the orb off the bottom of the page.
class RealtimeSliverAppBar extends StatelessWidget {
  const RealtimeSliverAppBar({
    required this.title,
    this.actions,
    this.bottom,
    super.key,
  });

  final String title;
  final List<Widget>? actions;
  final PreferredSizeWidget? bottom;

  @override
  Widget build(BuildContext context) {
    return SliverAppBar(
      pinned: true,
      automaticallyImplyLeading: false,
      title: Text(title),
      actions: actions,
      bottom: bottom,
    );
  }
}
