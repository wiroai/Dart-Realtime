import 'package:flutter/widgets.dart';
import 'package:wiro_realtime/app/extensions/media_query_extension.dart';

/// The one measurement the conversation stages share.
abstract final class ConversationLayout {
  /// Height reserved above the orb.
  ///
  /// Setup leaves this band quiet because its metadata now belongs to the
  /// app bar; live fills it from the top with the status line and the
  /// transcript. Reserving the same band in both is what lets the orb keep
  /// one position from the first tap to the last word.
  ///
  /// The fraction is what is left once the app bar, the orb and the bottom
  /// navigation have taken their share. It places the orb at the visual
  /// center of the usable area between the app bar and bottom navigation.
  static double contentBand(BuildContext context) {
    return context.dynamicHeight(0.24);
  }
}
