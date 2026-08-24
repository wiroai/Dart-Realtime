import 'package:flutter/foundation.dart';
import 'package:wiro_realtime/core/models/model_definition.dart';

final class ModelParameterValues {
  ModelParameterValues(List<ModelFieldDefinition> fields) {
    for (final field in fields) {
      if (!field.includeInFirstPass) {
        continue;
      }
      _definitions[field.id] = field;
      notifiers[field.id] = ValueNotifier(field.defaultValue ?? '');
    }
  }

  final Map<String, ModelFieldDefinition> _definitions = {};
  final Map<String, ValueNotifier<String>> notifiers = {};

  ValueNotifier<String> require(String id) {
    final notifier = notifiers[id];
    if (notifier == null) {
      throw StateError('Missing parameter notifier for $id');
    }
    return notifier;
  }

  Map<String, String> snapshot() {
    return {
      for (final entry in notifiers.entries)
        if (entry.value.value.trim().isNotEmpty) entry.key: entry.value.value,
    };
  }

  Map<String, Object?> requestSnapshot() {
    return {
      for (final entry in snapshot().entries)
        entry.key: _requestValue(
          definition: _definitions[entry.key]!,
          value: entry.value,
        ),
    };
  }

  void dispose() {
    for (final notifier in notifiers.values) {
      notifier.dispose();
    }
  }

  Object _requestValue({
    required ModelFieldDefinition definition,
    required String value,
  }) {
    return switch (definition.kind) {
      ModelFieldKind.number => int.tryParse(value) ?? value,
      ModelFieldKind.float => double.tryParse(value) ?? value,
      ModelFieldKind.text ||
      ModelFieldKind.textarea ||
      ModelFieldKind.select => value,
    };
  }
}
