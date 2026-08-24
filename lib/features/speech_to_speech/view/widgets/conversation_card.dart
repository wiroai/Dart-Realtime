import 'package:flutter/material.dart';
import 'package:wiro_realtime/app/extensions/theme_extension.dart';
import 'package:wiro_realtime/app/layout/project_padding.dart';
import 'package:wiro_realtime/app/layout/project_radius.dart';

/// The one container shape this screen uses.
///
/// Follows the wiro.ai card treatment: a white surface on the warm page
/// background, a hairline border, and no shadow.
class ConversationCard extends StatelessWidget {
  const ConversationCard({
    required this.child,
    this.padding = ProjectPadding.card,
    this.background,
    this.borderColor,
    super.key,
  });

  final Widget child;
  final EdgeInsets padding;
  final Color? background;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: background ?? colorScheme.surfaceContainerLowest,
        border: Border.all(color: borderColor ?? colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(ProjectRadius.panel),
      ),
      child: child,
    );
  }
}
