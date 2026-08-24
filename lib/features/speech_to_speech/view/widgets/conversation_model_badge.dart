import 'package:flutter/material.dart';
import 'package:wiro_realtime/app/extensions/theme_extension.dart';
import 'package:wiro_realtime/app/layout/project_radius.dart';
import 'package:wiro_realtime/app/layout/project_spacing.dart';
import 'package:wiro_realtime/app/theme/app_text_styles.dart';
import 'package:wiro_realtime/core/models/model_definition.dart';

/// Names the model in the words its provider uses, not by request slug.
///
/// It shares one row with the voice control, so it carries the name alone
/// and lets it ellipsize; the owner and the slug live in the advanced
/// sheet, where someone is actually looking for them.
class ConversationModelBadge extends StatelessWidget {
  const ConversationModelBadge({required this.model, super.key});

  final ModelDefinition model;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return Container(
      key: ValueKey<String>('model-${model.modelSlug}'),
      padding: const EdgeInsets.symmetric(
        horizontal: ProjectSpacing.sm,
        vertical: ProjectSpacing.xs + 1,
      ),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        border: Border.all(color: colorScheme.outline),
        borderRadius: BorderRadius.circular(ProjectRadius.chip),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.graphic_eq_rounded,
            size: 14,
            color: colorScheme.primary,
          ),
          const SizedBox(width: ProjectSpacing.xs + 2),
          Flexible(
            child: Text(
              model.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.buttonSmall.copyWith(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
