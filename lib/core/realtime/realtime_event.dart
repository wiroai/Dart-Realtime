import 'dart:typed_data';

import 'package:equatable/equatable.dart';

enum RealtimeEventType {
  queue('task_queue'),
  accepted('task_accept'),
  preprocessStarted('task_preprocess_start'),
  preprocessEnded('task_preprocess_end'),
  assigned('task_assign'),
  started('task_start'),
  outputFull('task_output_full'),
  ended('task_end'),
  postprocessStarted('task_postprocess_start'),
  postprocessEnded('task_postprocess_end'),
  streamReady('task_stream_ready'),
  streamEnded('task_stream_end'),
  cost('task_cost');

  const RealtimeEventType(this.wireName);

  final String wireName;

  static RealtimeEventType? fromWireName(String wireName) {
    for (final value in values) {
      if (value.wireName == wireName) {
        return value;
      }
    }
    return null;
  }
}

sealed class RealtimeEvent extends Equatable {
  const RealtimeEvent();

  String get wireType;
}

final class RealtimeStatusEvent extends RealtimeEvent {
  const RealtimeStatusEvent(this.type);

  final RealtimeEventType type;

  @override
  String get wireType => type.wireName;

  @override
  List<Object?> get props => [type];
}

final class RealtimeOutputEvent extends RealtimeEvent {
  const RealtimeOutputEvent(this.message);

  final String message;

  @override
  String get wireType => 'task_output';

  @override
  List<Object?> get props => [message];
}

final class RealtimeErrorEvent extends RealtimeEvent {
  const RealtimeErrorEvent(this.wireType);

  @override
  final String wireType;

  @override
  List<Object?> get props => [wireType];
}

final class RealtimeCancelEvent extends RealtimeEvent {
  const RealtimeCancelEvent();

  @override
  String get wireType => 'task_cancel';

  @override
  List<Object?> get props => const [];
}

final class RealtimeBinaryEvent extends RealtimeEvent {
  const RealtimeBinaryEvent(this.bytes);

  final Uint8List bytes;

  @override
  String get wireType => 'binary';

  @override
  List<Object?> get props => [bytes];
}

final class RealtimeUnknownEvent extends RealtimeEvent {
  const RealtimeUnknownEvent(this.wireType);

  @override
  final String wireType;

  @override
  List<Object?> get props => [wireType];
}

final class RealtimeMalformedEvent extends RealtimeEvent {
  const RealtimeMalformedEvent();

  @override
  String get wireType => 'malformed';

  @override
  List<Object?> get props => const [];
}
