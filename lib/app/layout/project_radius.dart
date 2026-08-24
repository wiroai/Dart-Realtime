/// Corner radii from the wiro.ai `--wiro-radius` scale, which steps in
/// 2px increments from a 4px base and stops at 14px.
///
/// The site has no fully rounded containers, so there is no pill value.
abstract final class ProjectRadius {
  static const double small = 2;
  static const double button = 4;
  static const double chip = 6;
  static const double control = 8;
  static const double card = 10;
  static const double panel = 12;
  static const double sheet = 14;
}
