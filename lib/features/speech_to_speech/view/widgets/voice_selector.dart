import 'package:flutter/material.dart';
import 'package:wiro_realtime/app/extensions/media_query_extension.dart';
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
/// speech-bubble icon next to a voice name needs no caption. Tapping the
/// pill opens a sheet whose options are built lazily, so only the rows on
/// screen ever exist.
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

  Future<void> _openOptions(BuildContext context, String selected) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: context.colorScheme.surfaceContainerLow,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(ProjectRadius.sheet),
        ),
      ),
      builder: (sheetContext) => _VoiceOptionsSheet(
        field: field,
        selected: selected,
        onSelected: (value) {
          Navigator.of(sheetContext).pop();
          if (value == selected) {
            return;
          }
          if (onSelected != null) {
            onSelected!(value);
            return;
          }
          valueListenable.value = value;
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final interactive = enabled && !loading;
    return ValueListenableBuilder<String>(
      valueListenable: valueListenable,
      builder: (context, selected, _) {
        return Semantics(
          button: true,
          label: '${field.label}: ${displayName(selected)}',
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              key: const ValueKey<String>('field-voice'),
              borderRadius: BorderRadius.circular(ProjectRadius.chip),
              onTap: interactive ? () => _openOptions(context, selected) : null,
              child: _VoicePill(
                selected: selected,
                interactive: interactive,
                loading: loading,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The collapsed control: the current voice's name inside a bordered pill.
class _VoicePill extends StatelessWidget {
  const _VoicePill({
    required this.selected,
    required this.interactive,
    required this.loading,
  });

  final String selected;
  final bool interactive;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return Container(
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
            VoiceSelector.displayName(selected),
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
    );
  }
}

/// Voice options in a lazily built list: only visible rows are created.
class _VoiceOptionsSheet extends StatelessWidget {
  const _VoiceOptionsSheet({
    required this.field,
    required this.selected,
    required this.onSelected,
  });

  final ModelFieldDefinition field;
  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: context.dynamicHeight(0.6),
        ),
        child: CustomScrollView(
          shrinkWrap: true,
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                ProjectSpacing.md,
                0,
                ProjectSpacing.md,
                ProjectSpacing.sm,
              ),
              sliver: SliverToBoxAdapter(
                child: Text(
                  field.label,
                  style: context.textTheme.titleSmall,
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                ProjectSpacing.sm,
                0,
                ProjectSpacing.sm,
                ProjectSpacing.md,
              ),
              sliver: SliverList.builder(
                itemCount: field.options.length,
                itemBuilder: (context, index) {
                  final option = field.options[index];
                  return _VoiceOptionTile(
                    value: option.value,
                    isSelected: option.value == selected,
                    onTap: () => onSelected(option.value),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One selectable voice row; the current choice carries a check mark.
class _VoiceOptionTile extends StatelessWidget {
  const _VoiceOptionTile({
    required this.value,
    required this.isSelected,
    required this.onTap,
  });

  final String value;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return InkWell(
      key: ValueKey<String>('voice-$value'),
      borderRadius: BorderRadius.circular(ProjectRadius.control),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: ProjectSpacing.sm,
          vertical: ProjectSpacing.sm,
        ),
        child: Row(
          children: [
            Text(
              VoiceSelector.displayName(value),
              style: AppTextStyles.row.copyWith(
                color: colorScheme.onSurface,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
            const Spacer(),
            if (isSelected)
              Icon(
                Icons.check_rounded,
                size: 18,
                color: colorScheme.primary,
              ),
          ],
        ),
      ),
    );
  }
}
