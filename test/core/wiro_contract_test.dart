import 'package:flutter_test/flutter_test.dart';
import 'package:wiro_realtime/core/audio/audio_constants.dart';
import 'package:wiro_realtime/core/config/wiro_endpoints.dart';
import 'package:wiro_realtime/core/models/wiro_model_catalog.dart';

void main() {
  test('exposes official REST and WebSocket endpoints', () {
    expect(WiroEndpoints.restBaseUrl, 'https://api.wiro.ai/v1');
    expect(WiroEndpoints.webSocketUrl, 'wss://socket.wiro.ai/v1');
    expect(
      WiroEndpoints.runPath(owner: 'openai', model: 'gpt-realtime-mini'),
      '/Run/openai/gpt-realtime-mini',
    );
  });

  test('uses 24 kHz mono Int16 20 ms chunks', () {
    expect(AudioConstants.sampleRateHz, 24000);
    expect(AudioConstants.channelCount, 1);
    expect(AudioConstants.pcmBytesPerChunk, 960);
  });

  test('catalog field ids match the 2026-08-21 MCP schemas', () {
    expect(
      WiroModelCatalog.gptRealtimeMini.modelSlug,
      'openai/gpt-realtime-mini',
    );
    expect(
      WiroModelCatalog.gptRealtimeMini.firstPassFields.map((f) => f.id),
      [
        'voice',
        'system_instructions',
        'transcription_model',
        'input_audio_format',
        'output_audio_format',
        'input_audio_rate',
        'output_audio_rate',
        'turn_detection_threshold',
        'turn_detection_silence_ms',
      ],
    );
    expect(
      WiroModelCatalog.voxtralMiniRealtime.firstPassFields.single.id,
      'transcriptionDelay',
    );
    expect(
      WiroModelCatalog.voxtralMiniRealtime.firstPassFields.single.defaultValue,
      'balanced',
    );
    expect(
      WiroModelCatalog.mossTtsRealtime.firstPassFields.map((f) => f.id),
      ['text'],
    );
    expect(
      WiroModelCatalog.voxcpm2.firstPassFields.map((f) => f.id),
      ['prompt', 'cfgValue', 'inferenceSteps'],
    );
    expect(
      WiroModelCatalog.voxcpm2.fields
          .firstWhere((field) => field.id == 'cfgValue')
          .defaultValue,
      '2.0',
    );
  });
}
