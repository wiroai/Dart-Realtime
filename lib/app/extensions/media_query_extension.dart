import 'package:flutter/widgets.dart';

extension MediaQueryContextX on BuildContext {
  Size get mediaSize => MediaQuery.sizeOf(this);

  double get height => mediaSize.height;

  double get width => mediaSize.width;

  double dynamicHeight(double fraction) => height * fraction;

  double dynamicWidth(double fraction) => width * fraction;
}
