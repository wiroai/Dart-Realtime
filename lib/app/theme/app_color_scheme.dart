import 'package:flutter/material.dart';
import 'package:wiro_realtime/app/theme/app_colors.dart';

abstract final class AppColorScheme {
  static const ColorScheme light = ColorScheme.light(
    primary: AppColors.green,
    onPrimary: AppColors.onDark,
    primaryContainer: AppColors.greenContainer,
    onPrimaryContainer: AppColors.greenText,
    secondary: AppColors.inkSecondary,
    onSecondary: AppColors.onDark,
    tertiary: AppColors.blue,
    error: AppColors.danger,
    onError: AppColors.onDark,
    errorContainer: AppColors.dangerContainer,
    onErrorContainer: AppColors.dangerText,
    onSurface: AppColors.ink,
    onSurfaceVariant: AppColors.inkMuted,
    outline: AppColors.borderMedium,
    outlineVariant: AppColors.border,
    surfaceContainerLowest: AppColors.surface,
    surfaceContainerLow: AppColors.background,
    surfaceContainer: AppColors.backgroundWarm,
    surfaceContainerHigh: AppColors.backgroundStone,
    surfaceContainerHighest: AppColors.backgroundStone,
  );
}
