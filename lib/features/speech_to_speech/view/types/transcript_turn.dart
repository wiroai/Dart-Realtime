import 'package:equatable/equatable.dart';

enum TranscriptSpeaker { you, assistant }

/// One attributed line in the conversation feed.
final class TranscriptTurn extends Equatable {
  const TranscriptTurn({required this.speaker, required this.text});

  final TranscriptSpeaker speaker;
  final String text;

  /// Builds the feed from the two latest lines the session reports.
  ///
  /// The session keeps only the most recent line per speaker, so this is
  /// derived rather than accumulated. Swapping in a real turn history
  /// means replacing this call, not the widgets that consume it.
  static List<TranscriptTurn> fromLatest({
    required String user,
    required String assistant,
  }) {
    return [
      if (user.trim().isNotEmpty)
        TranscriptTurn(speaker: TranscriptSpeaker.you, text: user),
      if (assistant.trim().isNotEmpty)
        TranscriptTurn(speaker: TranscriptSpeaker.assistant, text: assistant),
    ];
  }

  @override
  List<Object?> get props => [speaker, text];
}
