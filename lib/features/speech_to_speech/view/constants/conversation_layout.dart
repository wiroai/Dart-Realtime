/// The one measurement the conversation stages share.
abstract final class ConversationLayout {
  /// Height reserved above the orb, as a share of the space the stage was
  /// actually given.
  ///
  /// Reserving the same band in every stage is what lets the orb keep one
  /// position from the first tap to the last word: the note appearing
  /// underneath grows downwards instead of pushing the orb up.
  ///
  /// It is a share of the stage rather than of the screen because the
  /// screen does not scroll. A fraction of the whole screen ignores what
  /// the app bar and the navigation bar have already taken, which on the
  /// smallest phone leaves the band, the orb and the connect line fighting
  /// over a few pixels they do not have.
  static double bandAbove(double stageHeight) => stageHeight * 0.3;
}
