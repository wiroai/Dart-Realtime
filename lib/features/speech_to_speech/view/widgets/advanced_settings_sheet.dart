import 'package:flutter/material.dart';
import 'package:wiro_realtime/app/extensions/media_query_extension.dart';
import 'package:wiro_realtime/app/extensions/theme_extension.dart';
import 'package:wiro_realtime/app/layout/project_padding.dart';
import 'package:wiro_realtime/app/layout/project_radius.dart';
import 'package:wiro_realtime/app/layout/project_spacing.dart';
import 'package:wiro_realtime/app/widgets/model_parameter_form.dart';
import 'package:wiro_realtime/core/models/model_definition.dart';
import 'package:wiro_realtime/core/models/model_parameter_values.dart';
import 'package:wiro_realtime/features/speech_to_speech/view/constants/conversation_copy.dart';

/// Where the engineering parameters live.
///
/// Nothing the model accepts is removed from the example; sample rates,
/// audio formats, and turn-detection thresholds simply stop competing
/// with the one control most people came for.
Future<void> showAdvancedSettingsSheet(
  BuildContext context, {
  required List<ModelFieldDefinition> fields,
  required ModelParameterValues values,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: context.colorScheme.surfaceContainerLow,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(ProjectRadius.sheet),
      ),
    ),
    builder: (context) => AdvancedSettingsSheet(
      fields: fields,
      values: values,
    ),
  );
}

class AdvancedSettingsSheet extends StatelessWidget {
  const AdvancedSettingsSheet({
    required this.fields,
    required this.values,
    super.key,
  });

  final List<ModelFieldDefinition> fields;
  final ModelParameterValues values;

  @override
  Widget build(BuildContext context) {
    final textTheme = context.textTheme;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: context.dynamicHeight(0.82)),
        child: SingleChildScrollView(
          padding: ProjectPadding.sheet,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                ConversationCopy.advancedTitle,
                style: textTheme.titleSmall,
              ),
              const SizedBox(height: ProjectSpacing.xs),
              Text(
                ConversationCopy.advancedSubtitle,
                style: textTheme.bodySmall,
              ),
              const SizedBox(height: ProjectSpacing.lg),
              ModelParameterForm(
                fields: fields,
                values: values,
                enabled: true,
              ),
              const SizedBox(height: ProjectSpacing.sm),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text(ConversationCopy.advancedDone),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
