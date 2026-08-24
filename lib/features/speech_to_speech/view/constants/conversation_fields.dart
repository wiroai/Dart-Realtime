import 'package:wiro_realtime/core/models/model_definition.dart';

/// Splits the model's first-pass fields into the one the screen shows and
/// the rest.
///
/// The voice is the only parameter a person choosing a conversation
/// partner cares about; the other eight are engineering knobs and live
/// behind the settings control. Both halves are derived from the same
/// constant here so the two callers cannot drift apart and show a field
/// twice or lose one entirely.
abstract final class ConversationFields {
  static const String voiceId = 'voice';

  static ModelFieldDefinition? voice(ModelDefinition model) {
    for (final field in model.firstPassFields) {
      if (field.id == voiceId) {
        return field;
      }
    }
    return null;
  }

  static List<ModelFieldDefinition> advanced(ModelDefinition model) {
    return model.firstPassFields.where((field) => field.id != voiceId).toList();
  }
}
