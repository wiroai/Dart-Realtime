import 'package:flutter/material.dart';
import 'package:wiro_realtime/app/extensions/theme_extension.dart';
import 'package:wiro_realtime/app/layout/project_radius.dart';
import 'package:wiro_realtime/app/layout/project_spacing.dart';
import 'package:wiro_realtime/app/theme/app_colors.dart';
import 'package:wiro_realtime/app/theme/app_text_styles.dart';
import 'package:wiro_realtime/core/models/model_definition.dart';

/// The one setting worth showing before a conversation starts.
///
/// Thirteen voices as chips filled the screen with words. What is left is
/// a pill naming only the current choice: no field label, because a
/// speech-bubble icon next to a voice name needs no caption.
class VoiceSelector extends StatelessWidget {
  const VoiceSelector({
    required this.field,
    required this.valueListenable,
    required this.enabled,
    this.loading = false,
    this.onSelected,
    super.key,
  });

  final ModelFieldDefinition field;
  final ValueNotifier<String> valueListenable;
  final bool enabled;
  final bool loading;
  final ValueChanged<String>? onSelected;

  static String displayName(String value) {
    if (value.isEmpty) {
      return value;
    }
    return value[0].toUpperCase() + value.substring(1);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final interactive = enabled && !loading;
    return ValueListenableBuilder<String>(
      valueListenable: valueListenable,
      builder: (context, selected, _) {
        return Semantics(
          button: true,
          label: '${field.label}: ${displayName(selected)}',
          child: PopupMenuButton<String>(
            key: const ValueKey<String>('field-voice'),
            enabled: interactive,
            initialValue: selected,
            position: PopupMenuPosition.under,
            tooltip: field.label,
            color: colorScheme.surfaceContainerLowest,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(ProjectRadius.control),
              side: BorderSide(color: colorScheme.outline),
            ),
            onSelected: (value) {
              if (value == selected) {
                return;
              }
              if (onSelected != null) {
                onSelected!(value);
                return;
              }
              valueListenable.value = value;
            },
            itemBuilder: (context) => [
              for (final option in field.options)
                PopupMenuItem<String>(
                  key: ValueKey<String>('voice-${option.value}'),
                  value: option.value,
                  child: Row(
                    children: [
                      Text(
                        displayName(option.value),
                        style: AppTextStyles.row.copyWith(
                          color: colorScheme.onSurface,
                          fontWeight: option.value == selected
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                      ),
                      const Spacer(),
                      if (option.value == selected)
                        Icon(
                          Icons.check_rounded,
                          size: 18,
                          color: colorScheme.primary,
                        ),
                    ],
                  ),
                ),
            ],
            child: Container(
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
                    Icons.record_voice_over_outlined,
                    size: 14,
                    color: interactive
                        ? colorScheme.onSurfaceVariant
                        : AppColors.inkDisabled,
                  ),
                  const SizedBox(width: ProjectSpacing.xs + 2),
                  Text(
                    displayName(selected),
                    style: AppTextStyles.buttonSmall.copyWith(
                      color: interactive
                          ? colorScheme.onSurface
                          : AppColors.inkDisabled,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (loading)
                    Padding(
                      padding: const EdgeInsets.only(
                        left: ProjectSpacing.xs,
                      ),
                      child: SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  else
                    Icon(
                      Icons.expand_more_rounded,
                      size: 16,
                      color: interactive
                          ? colorScheme.onSurfaceVariant
                          : AppColors.inkDisabled,
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
