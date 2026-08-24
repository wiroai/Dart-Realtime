import 'package:wiro_realtime/app/state/base_view_model.dart';
import 'package:wiro_realtime/app/state/view_status.dart';
import 'package:wiro_realtime/features/realtime_home/view_model/state/realtime_home_state.dart';

final class RealtimeHomeViewModel extends BaseViewModel<RealtimeHomeState> {
  RealtimeHomeViewModel() : super(const RealtimeHomeState());

  void selectDestination(int index) {
    if (index < 0 || index >= RealtimeDestination.values.length) {
      return;
    }
    emit(
      state.copyWith(
        status: ViewStatus.success,
        destination: RealtimeDestination.values[index],
      ),
    );
  }
}
