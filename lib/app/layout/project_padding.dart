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

  /// A stage that fills its screen and does not scroll, so the inset is
  /// spent on breathing room rather than on clearing a navigation bar the
  /// content can no longer be dragged under.
  static const EdgeInsets stage = EdgeInsets.fromLTRB(
    ProjectSpacing.md,
    ProjectSpacing.lg,
    ProjectSpacing.md,
    ProjectSpacing.md,
  );
}
