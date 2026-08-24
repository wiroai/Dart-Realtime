import 'package:flutter/widgets.dart';
import 'package:wiro_realtime/app/app.dart';
import 'package:wiro_realtime/app/config/wiro_environment.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final credentials = WiroEnvironment.fromDartDefines();
  runApp(WiroRealtimeApp(credentials: credentials));
}
