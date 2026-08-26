import 'package:wiro_realtime/core/models/model_definition.dart';

/// Model parameter table from Wiro MCP `get_model_schema` on 2026-08-21.
///
/// `openbmb/voxcpm2` defaults for `cfgValue` and `inferenceSteps` come from
/// the live model page; MCP schema listed the fields without defaults.
abstract final class WiroModelCatalog {
  static const ModelDefinition gptRealtimeMini = ModelDefinition(
    owner: 'openai',
    slug: 'gpt-realtime-mini',
    displayName: 'GPT Realtime Mini',
    direction: RealtimeDirection.speechToSpeech,
    fields: [
      ModelFieldDefinition(
        id: 'voice',
        label: 'Voice',
        kind: ModelFieldKind.select,
        isRequired: true,
        includeInFirstPass: true,
        defaultValue: 'marin',
        options: [
          ModelFieldOption(value: 'marin'),
          ModelFieldOption(value: 'cedar'),
          ModelFieldOption(value: 'alloy'),
          ModelFieldOption(value: 'ash'),
          ModelFieldOption(value: 'ballad'),
          ModelFieldOption(value: 'coral'),
          ModelFieldOption(value: 'echo'),
          ModelFieldOption(value: 'fable'),
          ModelFieldOption(value: 'nova'),
          ModelFieldOption(value: 'onyx'),
          ModelFieldOption(value: 'sage'),
          ModelFieldOption(value: 'shimmer'),
          ModelFieldOption(value: 'verse'),
        ],
      ),
      // What the assistant is told lives in ConversationConfig, since it is
      // an application's choice rather than something the schema fixes.
      ModelFieldDefinition(
        id: 'system_instructions',
        label: 'System instructions',
        kind: ModelFieldKind.textarea,
        isRequired: true,
        includeInFirstPass: true,
      ),
      ModelFieldDefinition(
        id: 'transcription_model',
        label: 'Transcription model',
        kind: ModelFieldKind.select,
        isRequired: false,
        includeInFirstPass: true,
        defaultValue: 'gpt-4o-mini-transcribe',
        options: [
          ModelFieldOption(value: 'gpt-4o-mini-transcribe'),
          ModelFieldOption(value: 'gpt-4o-transcribe'),
          ModelFieldOption(value: 'whisper-1'),
        ],
      ),
      ModelFieldDefinition(
        id: 'input_audio_format',
        label: 'Input audio format',
        kind: ModelFieldKind.select,
        isRequired: false,
        includeInFirstPass: true,
        defaultValue: 'audio/pcm',
        options: [
          ModelFieldOption(value: 'audio/pcm'),
          ModelFieldOption(value: 'audio/pcmu'),
          ModelFieldOption(value: 'audio/pcma'),
        ],
      ),
      ModelFieldDefinition(
        id: 'output_audio_format',
        label: 'Output audio format',
        kind: ModelFieldKind.select,
        isRequired: false,
        includeInFirstPass: true,
        defaultValue: 'audio/pcm',
        options: [
          ModelFieldOption(value: 'audio/pcm'),
          ModelFieldOption(value: 'audio/pcmu'),
          ModelFieldOption(value: 'audio/pcma'),
        ],
      ),
      ModelFieldDefinition(
        id: 'input_audio_rate',
        label: 'Input audio rate',
        kind: ModelFieldKind.select,
        isRequired: false,
        includeInFirstPass: true,
        defaultValue: '24000',
        options: [
          ModelFieldOption(value: '24000'),
          ModelFieldOption(value: '8000'),
        ],
      ),
      ModelFieldDefinition(
        id: 'output_audio_rate',
        label: 'Output audio rate',
        kind: ModelFieldKind.select,
        isRequired: false,
        includeInFirstPass: true,
        defaultValue: '24000',
        options: [
          ModelFieldOption(value: '24000'),
          ModelFieldOption(value: '8000'),
        ],
      ),
      ModelFieldDefinition(
        id: 'turn_detection_threshold',
        label: 'Turn detection threshold',
        kind: ModelFieldKind.float,
        isRequired: false,
        includeInFirstPass: true,
        defaultValue: '0.75',
      ),
      ModelFieldDefinition(
        id: 'turn_detection_silence_ms',
        label: 'Silence duration (ms)',
        kind: ModelFieldKind.number,
        isRequired: false,
        includeInFirstPass: true,
        defaultValue: '700',
      ),
    ],
  );

  static const ModelDefinition voxtralMiniRealtime = ModelDefinition(
    owner: 'mistralai',
    slug: 'voxtral-mini-4b-realtime-2602',
    displayName: 'Voxtral Mini Realtime',
    direction: RealtimeDirection.speechToText,
    fields: [
      ModelFieldDefinition(
        id: 'transcriptionDelay',
        label: 'Transcription delay',
        kind: ModelFieldKind.select,
        isRequired: false,
        includeInFirstPass: true,
        defaultValue: 'balanced',
        options: [
          ModelFieldOption(value: 'fastest'),
          ModelFieldOption(value: 'fast'),
          ModelFieldOption(value: 'balanced'),
          ModelFieldOption(value: 'accurate'),
        ],
      ),
    ],
  );

  static const ModelDefinition mossTtsRealtime = ModelDefinition(
    owner: 'openmoss',
    slug: 'moss-tts-realtime',
    displayName: 'MOSS TTS Realtime',
    direction: RealtimeDirection.textToSpeech,
    fields: [
      ModelFieldDefinition(
        id: 'text',
        label: 'Text',
        kind: ModelFieldKind.textarea,
        isRequired: false,
        includeInFirstPass: true,
      ),
      ModelFieldDefinition(
        id: 'inputAudio',
        label: 'Reference audio',
        kind: ModelFieldKind.text,
        isRequired: false,
        includeInFirstPass: false,
      ),
      ModelFieldDefinition(
        id: 'temperature',
        label: 'Temperature',
        kind: ModelFieldKind.float,
        isRequired: false,
        includeInFirstPass: false,
      ),
      ModelFieldDefinition(
        id: 'topP',
        label: 'Top P',
        kind: ModelFieldKind.float,
        isRequired: false,
        includeInFirstPass: false,
      ),
      ModelFieldDefinition(
        id: 'topK',
        label: 'Top K',
        kind: ModelFieldKind.number,
        isRequired: false,
        includeInFirstPass: false,
      ),
      ModelFieldDefinition(
        id: 'repetitionPenalty',
        label: 'Repetition penalty',
        kind: ModelFieldKind.float,
        isRequired: false,
        includeInFirstPass: false,
      ),
      ModelFieldDefinition(
        id: 'repetitionWindow',
        label: 'Repetition window',
        kind: ModelFieldKind.number,
        isRequired: false,
        includeInFirstPass: false,
      ),
      ModelFieldDefinition(
        id: 'maxLength',
        label: 'Max length',
        kind: ModelFieldKind.number,
        isRequired: false,
        includeInFirstPass: false,
      ),
    ],
  );

  static const ModelDefinition voxcpm2 = ModelDefinition(
    owner: 'openbmb',
    slug: 'voxcpm2',
    displayName: 'VoxCPM2',
    direction: RealtimeDirection.textToSpeech,
    fields: [
      ModelFieldDefinition(
        id: 'prompt',
        label: 'Prompt',
        kind: ModelFieldKind.textarea,
        isRequired: false,
        includeInFirstPass: true,
      ),
      ModelFieldDefinition(
        id: 'inputAudio',
        label: 'Reference audio',
        kind: ModelFieldKind.text,
        isRequired: false,
        includeInFirstPass: false,
      ),
      ModelFieldDefinition(
        id: 'inputAudio2',
        label: 'Prompt audio',
        kind: ModelFieldKind.text,
        isRequired: false,
        includeInFirstPass: false,
      ),
      ModelFieldDefinition(
        id: 'promptAudioText',
        label: 'Prompt audio text',
        kind: ModelFieldKind.textarea,
        isRequired: false,
        includeInFirstPass: false,
      ),
      ModelFieldDefinition(
        id: 'cfgValue',
        label: 'CFG value',
        kind: ModelFieldKind.float,
        isRequired: true,
        includeInFirstPass: true,
        defaultValue: '2.0',
      ),
      ModelFieldDefinition(
        id: 'inferenceSteps',
        label: 'Inference steps',
        kind: ModelFieldKind.number,
        isRequired: false,
        includeInFirstPass: true,
        defaultValue: '10',
      ),
    ],
  );

  static const List<ModelDefinition> all = [
    gptRealtimeMini,
    voxtralMiniRealtime,
    mossTtsRealtime,
    voxcpm2,
  ];
}
