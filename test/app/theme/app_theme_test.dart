import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wiro_realtime/app/theme/app_colors.dart';
import 'package:wiro_realtime/app/theme/app_theme.dart';

void main() {
  test('configures the application color scheme', () {
    final theme = AppTheme.light;

    expect(theme.scaffoldBackgroundColor, AppColors.background);
    expect(theme.colorScheme.primary, AppColors.green);
    expect(theme.colorScheme.surface, AppColors.surface);
    expect(theme.colorScheme.onSurface, AppColors.ink);
    expect(theme.brightness, Brightness.light);
  });
}
