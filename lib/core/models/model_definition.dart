enum RealtimeDirection {
  speechToSpeech,
  speechToText,
  textToSpeech,
}

enum ModelFieldKind {
  text,
  textarea,
  select,
  number,
  float,
}

final class ModelFieldOption {
  const ModelFieldOption({required this.value});

  final String value;
}

final class ModelFieldDefinition {
  const ModelFieldDefinition({
    required this.id,
    required this.label,
    required this.kind,
    required this.isRequired,
    required this.includeInFirstPass,
    this.options = const [],
    this.defaultValue,
  });

  final String id;
  final String label;
  final ModelFieldKind kind;
  final bool isRequired;
  final bool includeInFirstPass;
  final List<ModelFieldOption> options;
  final String? defaultValue;
}

final class ModelDefinition {
  const ModelDefinition({
    required this.owner,
    required this.slug,
    required this.displayName,
    required this.direction,
    required this.fields,
  });

  final String owner;
  final String slug;
  final String displayName;
  final RealtimeDirection direction;
  final List<ModelFieldDefinition> fields;

  String get modelSlug => '$owner/$slug';

  List<ModelFieldDefinition> get firstPassFields {
    return fields.where((field) => field.includeInFirstPass).toList();
  }
}
