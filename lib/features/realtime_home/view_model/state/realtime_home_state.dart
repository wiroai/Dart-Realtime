import 'package:equatable/equatable.dart';
import 'package:wiro_realtime/app/state/view_status.dart';

enum RealtimeDestination {
  conversation,
  transcription,
  speech,
}

final class RealtimeHomeState extends Equatable {
  const RealtimeHomeState({
    this.status = ViewStatus.initial,
    this.destination = RealtimeDestination.conversation,
  });

  final ViewStatus status;
  final RealtimeDestination destination;

  int get selectedIndex => destination.index;

  RealtimeHomeState copyWith({
    ViewStatus? status,
    RealtimeDestination? destination,
  }) {
    return RealtimeHomeState(
      status: status ?? this.status,
      destination: destination ?? this.destination,
    );
  }

  @override
  List<Object> get props => [status, destination];
}
