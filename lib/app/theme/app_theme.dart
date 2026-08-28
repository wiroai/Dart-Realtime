import 'package:flutter/material.dart';
import 'package:wiro_realtime/app/layout/project_radius.dart';
import 'package:wiro_realtime/app/theme/app_color_scheme.dart';
import 'package:wiro_realtime/app/theme/app_colors.dart';
import 'package:wiro_realtime/app/theme/app_text_styles.dart';

abstract final class AppTheme {
  static ThemeData get light {
    final baseTheme = ThemeData(
      colorScheme: AppColorScheme.light,
      scaffoldBackgroundColor: AppColors.background,
      useMaterial3: true,
    );

    return baseTheme.copyWith(
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.ink,
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: const CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: AppColors.border),
          borderRadius: BorderRadius.all(
            Radius.circular(ProjectRadius.control),
          ),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.border,
        thickness: 1,
        space: 1,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return AppColors.backgroundStone;
            }
            if (states.contains(WidgetState.hovered)) {
              return AppColors.inkHover;
            }
            return AppColors.ink;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return AppColors.inkDisabled;
            }
            return AppColors.onDark;
          }),
          elevation: const WidgetStatePropertyAll(0),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          ),
          shape: const WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.all(
                Radius.circular(ProjectRadius.button),
              ),
            ),
          ),
        ),
      ),
      outlinedButtonTheme: const OutlinedButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStatePropertyAll(AppColors.ink),
          padding: WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          ),
          side: WidgetStatePropertyAll(
            BorderSide(color: AppColors.borderStrong),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.all(
                Radius.circular(ProjectRadius.button),
              ),
            ),
          ),
        ),
      ),
      textButtonTheme: const TextButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStatePropertyAll(AppColors.greenText),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.all(
                Radius.circular(ProjectRadius.button),
              ),
            ),
          ),
        ),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        labelStyle: TextStyle(color: AppColors.inkMuted),
        floatingLabelStyle: TextStyle(color: AppColors.greenText),
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(color: AppColors.borderMedium),
          borderRadius: BorderRadius.all(
            Radius.circular(ProjectRadius.control),
          ),
        ),
        disabledBorder: OutlineInputBorder(
          borderSide: BorderSide(color: AppColors.border),
          borderRadius: BorderRadius.all(
            Radius.circular(ProjectRadius.control),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: BorderSide(color: AppColors.green, width: 1.5),
          borderRadius: BorderRadius.all(
            Radius.circular(ProjectRadius.control),
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderSide: BorderSide(color: AppColors.danger),
          borderRadius: BorderRadius.all(
            Radius.circular(ProjectRadius.control),
          ),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderSide: BorderSide(color: AppColors.danger, width: 1.5),
          borderRadius: BorderRadius.all(
            Radius.circular(ProjectRadius.control),
          ),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.surface,
        indicatorColor: AppColors.greenContainer,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        // No pill in the wiro radius scale, so the indicator is a rounded
        // rectangle like every other container on the site.
        indicatorShape: const RoundedRectangleBorder(
          side: BorderSide(color: AppColors.greenBorder),
          borderRadius: BorderRadius.all(
            Radius.circular(ProjectRadius.card),
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(
              color: AppColors.greenText,
              size: 22,
            );
          }
          return const IconThemeData(
            color: AppColors.inkMuted,
            size: 22,
          );
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const TextStyle(
              color: AppColors.greenText,
              fontSize: 12,
              letterSpacing: 0.1,
              fontWeight: FontWeight.w600,
            );
          }
          return const TextStyle(
            color: AppColors.inkMuted,
            fontSize: 12,
            letterSpacing: 0.1,
            fontWeight: FontWeight.w500,
          );
        }),
      ),
      chipTheme: baseTheme.chipTheme.copyWith(
        backgroundColor: AppColors.backgroundWarm,
        selectedColor: AppColors.greenContainer,
        checkmarkColor: AppColors.greenText,
        side: const BorderSide(color: AppColors.borderMedium),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(
            Radius.circular(ProjectRadius.chip),
          ),
        ),
      ),
      // Only slots the wiro type scale has an opinion about are replaced
      // outright. `bodyMedium` keeps its Material size because unstyled
      // `Text` across the other two features resolves to it.
      textTheme: baseTheme.textTheme.copyWith(
        headlineSmall: AppTextStyles.pageTitle.copyWith(
          color: AppColors.ink,
        ),
        titleLarge: baseTheme.textTheme.titleLarge?.copyWith(
          color: AppColors.ink,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.3,
        ),
        titleMedium: baseTheme.textTheme.titleMedium?.copyWith(
          color: AppColors.ink,
          fontWeight: FontWeight.w600,
        ),
        titleSmall: AppTextStyles.title.copyWith(color: AppColors.ink),
        bodyLarge: AppTextStyles.pageSubtitle.copyWith(
          color: AppColors.inkSecondary,
        ),
        bodyMedium: baseTheme.textTheme.bodyMedium?.copyWith(
          color: AppColors.inkSecondary,
        ),
        bodySmall: AppTextStyles.caption.copyWith(
          color: AppColors.inkMuted,
        ),
        labelSmall: AppTextStyles.eyebrow.copyWith(
          color: AppColors.inkMuted,
        ),
        labelMedium: AppTextStyles.buttonSmall.copyWith(
          color: AppColors.inkSecondary,
        ),
      ),
    );
  }
}
