import 'package:flutter/widgets.dart';
import 'package:wiro_realtime/app/layout/project_spacing.dart';

abstract final class ProjectPadding {
  static const EdgeInsets page = EdgeInsets.symmetric(
    horizontal: ProjectSpacing.md,
    vertical: ProjectSpacing.sm,
  );

  static const EdgeInsets card = EdgeInsets.all(ProjectSpacing.md);

  static const EdgeInsets controlBar = EdgeInsets.symmetric(
    horizontal: ProjectSpacing.md,
    vertical: ProjectSpacing.sm,
  );

  static const EdgeInsets sheet = EdgeInsets.fromLTRB(
    ProjectSpacing.md,
    ProjectSpacing.md,
    ProjectSpacing.md,
    ProjectSpacing.lg,
  );

  /// A full-height scrollable stage. The generous bottom inset keeps the
  /// last control clear of the navigation bar and of the floating in-call
  /// bar that sits above it.
  static const EdgeInsets stage = EdgeInsets.fromLTRB(
    ProjectSpacing.md,
    ProjectSpacing.lg,
    ProjectSpacing.md,
    ProjectSpacing.xxxl,
  );
}
