import 'package:flutter/material.dart';
import 'package:wiro_realtime/app/extensions/theme_extension.dart';
import 'package:wiro_realtime/app/layout/project_spacing.dart';

/// A labelled figure in the session summary.
class ConversationMetricTile extends StatelessWidget {
  const ConversationMetricTile({
    required this.label,
    required this.value,
    super.key,
  });

  final String label;
  final Widget value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: context.textTheme.labelSmall),
        const SizedBox(height: ProjectSpacing.xs + 2),
        value,
      ],
    );
  }
}
