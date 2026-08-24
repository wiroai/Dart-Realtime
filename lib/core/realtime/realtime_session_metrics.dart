import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:wiro_realtime/core/realtime/realtime_event.dart';

@immutable
final class RealtimeSessionMetrics {
  const RealtimeSessionMetrics({
    required this.framesProcessed,
    required this.binaryFrames,
    required this.malformedFrames,
    required this.maximumProcessingMicros,
    required this.p95ProcessingMicros,
  });

  const RealtimeSessionMetrics.empty()
    : framesProcessed = 0,
      binaryFrames = 0,
      malformedFrames = 0,
      maximumProcessingMicros = 0,
      p95ProcessingMicros = 0;

  final int framesProcessed;
  final int binaryFrames;
  final int malformedFrames;
  final int maximumProcessingMicros;
  final int p95ProcessingMicros;
}

final class RealtimeSessionMetricsCollector {
  static const int _maximumSamples = 256;

  final Queue<int> _processingSamples = Queue<int>();
  int _framesProcessed = 0;
  int _binaryFrames = 0;
  int _malformedFrames = 0;
  int _maximumProcessingMicros = 0;

  RealtimeSessionMetrics get snapshot {
    final sortedSamples = _processingSamples.toList()..sort();
    final p95Index = sortedSamples.isEmpty
        ? 0
        : ((sortedSamples.length - 1) * 0.95).ceil();
    return RealtimeSessionMetrics(
      framesProcessed: _framesProcessed,
      binaryFrames: _binaryFrames,
      malformedFrames: _malformedFrames,
      maximumProcessingMicros: _maximumProcessingMicros,
      p95ProcessingMicros: sortedSamples.isEmpty ? 0 : sortedSamples[p95Index],
    );
  }

  void record(RealtimeEvent event, int processingMicros) {
    _framesProcessed++;
    if (event is RealtimeBinaryEvent) {
      _binaryFrames++;
    } else if (event is RealtimeMalformedEvent) {
      _malformedFrames++;
    }
    if (processingMicros > _maximumProcessingMicros) {
      _maximumProcessingMicros = processingMicros;
    }
    _processingSamples.addLast(processingMicros);
    if (_processingSamples.length > _maximumSamples) {
      _processingSamples.removeFirst();
    }
  }
}
