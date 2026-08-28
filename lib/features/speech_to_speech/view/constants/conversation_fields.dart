import 'package:wiro_realtime/core/models/model_definition.dart';

/// Finds the one first-pass field the screen shows.
///
/// The voice is the only parameter a person choosing a conversation
/// partner cares about; the rest of the model's knobs are an
/// application's decision and are fixed in `ConversationConfig` rather
/// than surfaced to the person talking.
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
}
