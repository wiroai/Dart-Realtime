import 'package:flutter/material.dart';
import 'package:wiro_realtime/app/theme/app_theme.dart';
import 'package:wiro_realtime/core/auth/wiro_credentials.dart';
import 'package:wiro_realtime/features/realtime_home/view/realtime_home_view.dart';

class WiroRealtimeApp extends StatelessWidget {
  const WiroRealtimeApp({required this.credentials, super.key});

  final WiroCredentials credentials;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Wiro Realtime',
      theme: AppTheme.light,
      themeMode: ThemeMode.light,
      home: RealtimeHomeView(credentials: credentials),
    );
  }
}
