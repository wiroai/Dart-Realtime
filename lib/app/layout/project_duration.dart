abstract final class ProjectDuration {
  /// The wiro.ai `--wiro-transition` value, used for colour and opacity
  /// changes on interactive surfaces.
  static const Duration transition = Duration(milliseconds: 140);

  static const Duration stageSwap = Duration(milliseconds: 240);

  static const Duration pulse = Duration(milliseconds: 1600);

  /// Slower than [pulse]: the idle orb is inviting a tap, not reporting
  /// activity, and an invitation that hurries reads as an alarm.
  static const Duration invite = Duration(milliseconds: 2600);
}
