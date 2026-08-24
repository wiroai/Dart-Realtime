import 'package:flutter/foundation.dart';

@immutable
final class WiroRunResult {
  const WiroRunResult({
    required this.taskId,
    required this.taskToken,
  });

  final String taskId;
  final String taskToken;
}
