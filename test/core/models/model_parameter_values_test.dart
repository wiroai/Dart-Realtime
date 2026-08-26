import 'package:flutter_test/flutter_test.dart';
import 'package:wiro_realtime/core/models/model_parameter_values.dart';
import 'package:wiro_realtime/core/models/wiro_model_catalog.dart';

void main() {
  test('converts numeric model fields for JSON requests', () {
    final parameters = ModelParameterValues(
      WiroModelCatalog.voxcpm2.firstPassFields,
    );
    addTearDown(parameters.dispose);

    final snapshot = parameters.requestSnapshot();

    expect(snapshot['cfgValue'], 2.0);
    expect(snapshot['inferenceSteps'], 10);
  });

  test('uses noise-resistant conversation defaults', () {
    final parameters = ModelParameterValues(
      WiroModelCatalog.gptRealtimeMini.firstPassFields,
    );
    addTearDown(parameters.dispose);

    final snapshot = parameters.requestSnapshot();

    expect(snapshot['turn_detection_threshold'], 0.75);
    expect(snapshot['turn_detection_silence_ms'], 700);
  });

  test('overrides replace catalog defaults and ignore unknown ids', () {
    final parameters = ModelParameterValues(
      WiroModelCatalog.gptRealtimeMini.firstPassFields,
      overrides: const {
        'voice': 'cedar',
        'system_instructions': 'You answer support questions.',
        'not_a_field': 'ignored',
      },
    );
    addTearDown(parameters.dispose);

    final snapshot = parameters.requestSnapshot();

    expect(snapshot['voice'], 'cedar');
    expect(snapshot['system_instructions'], 'You answer support questions.');
    expect(snapshot.containsKey('not_a_field'), isFalse);
    expect(snapshot['turn_detection_threshold'], 0.75);
  });
}
