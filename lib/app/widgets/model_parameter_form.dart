import 'package:flutter/material.dart';
import 'package:wiro_realtime/app/widgets/mixin/model_text_value_field_mixin.dart';
import 'package:wiro_realtime/core/models/model_definition.dart';
import 'package:wiro_realtime/core/models/model_parameter_values.dart';

class ModelParameterForm extends StatelessWidget {
  const ModelParameterForm({
    required this.fields,
    required this.values,
    required this.enabled,
    super.key,
  });

  final List<ModelFieldDefinition> fields;
  final ModelParameterValues values;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final field in fields)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: ModelParameterField(
              field: field,
              valueListenable: values.require(field.id),
              enabled: enabled,
            ),
          ),
      ],
    );
  }
}

class ModelParameterField extends StatelessWidget {
  const ModelParameterField({
    required this.field,
    required this.valueListenable,
    required this.enabled,
    super.key,
  });

  final ModelFieldDefinition field;
  final ValueNotifier<String> valueListenable;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    if (field.kind == ModelFieldKind.select) {
      return ModelSelectField(
        field: field,
        valueListenable: valueListenable,
        enabled: enabled,
      );
    }
    return ModelTextValueField(
      field: field,
      valueListenable: valueListenable,
      enabled: enabled,
    );
  }
}

class ModelSelectField extends StatelessWidget {
  const ModelSelectField({
    required this.field,
    required this.valueListenable,
    required this.enabled,
    super.key,
  });

  final ModelFieldDefinition field;
  final ValueNotifier<String> valueListenable;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: valueListenable,
      builder: (context, value, _) {
        final items = field.options
            .map(
              (option) => DropdownMenuItem<String>(
                value: option.value,
                child: Text(option.value),
              ),
            )
            .toList();
        final selected = field.options.any((option) => option.value == value)
            ? value
            : null;
        return DropdownButtonFormField<String>(
          key: ValueKey<String>('field-${field.id}'),
          initialValue: selected,
          items: items,
          onChanged: enabled
              ? (next) {
                  if (next != null) {
                    valueListenable.value = next;
                  }
                }
              : null,
          decoration: InputDecoration(labelText: field.label),
        );
      },
    );
  }
}

class ModelTextValueField extends StatefulWidget {
  const ModelTextValueField({
    required this.field,
    required this.valueListenable,
    required this.enabled,
    super.key,
  });

  final ModelFieldDefinition field;
  final ValueNotifier<String> valueListenable;
  final bool enabled;

  @override
  State<ModelTextValueField> createState() => _ModelTextValueFieldState();
}

class _ModelTextValueFieldState extends State<ModelTextValueField>
    with ModelTextValueFieldMixin {
  @override
  Widget build(BuildContext context) {
    final isMultiline = widget.field.kind == ModelFieldKind.textarea;
    return TextField(
      key: ValueKey<String>('field-${widget.field.id}'),
      controller: textController,
      enabled: widget.enabled,
      maxLines: isMultiline ? 4 : 1,
      keyboardType:
          widget.field.kind == ModelFieldKind.number ||
              widget.field.kind == ModelFieldKind.float
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
      onChanged: (value) => inputValue = value,
      decoration: InputDecoration(labelText: widget.field.label),
    );
  }
}
