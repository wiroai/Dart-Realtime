import 'package:flutter/widgets.dart';
import 'package:wiro_realtime/app/layout/project_spacing.dart';

abstract final class ProjectPadding {
  static const EdgeInsets page = EdgeInsets.symmetric(
    horizontal: ProjectSpacing.md,
    vertical: ProjectSpacing.sm,
  );
}
