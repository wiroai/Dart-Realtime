import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wiro_realtime/app/extensions/theme_extension.dart';
import 'package:wiro_realtime/app/layout/project_spacing.dart';
import 'package:wiro_realtime/app/state/value_selector_builder.dart';
import 'package:wiro_realtime/app/theme/app_text_styles.dart';
import 'package:wiro_realtime/core/realtime/realtime_session_state.dart';
import 'package:wiro_realtime/features/speech_to_text/view/constants/transcription_copy.dart';
import 'package:wiro_realtime/features/speech_to_text/view_model/speech_to_text_view_model.dart';
import 'package:wiro_realtime/features/speech_to_text/view_model/state/speech_to_text_state.dart';

/// The words themselves, owning the screen the way a page of a book does.
///
/// No card, no border: recorder apps draw the transcript as the content
/// of the screen, not as a field on a form. The text is selectable, set
/// large enough to read at arm's length, and while the model is still
/// speaking the view follows its own bottom edge so the newest words
/// stay in sight. The two things worth doing with the text — copying it
/// and clearing it — sit as icons in its top corner, next to what they
/// act on.
class TranscriptPanel extends StatefulWidget {
  const TranscriptPanel({required this.viewModel, super.key});

  final SpeechToTextViewModel viewModel;

  @override
  State<TranscriptPanel> createState() => _TranscriptPanelState();
}

class _TranscriptPanelState extends State<TranscriptPanel> {
  final ScrollController _scrollController = ScrollController();
  String _lastTranscript = '';

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _followNewWords(String transcript) {
    if (transcript == _lastTranscript) {
      return;
    }
    _lastTranscript = transcript;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) {
        return;
      }
      _scrollController.jumpTo(
        _scrollController.position.maxScrollExtent,
      );
    });
  }

  Future<void> _copyTranscript(String transcript) async {
    await Clipboard.setData(ClipboardData(text: transcript));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text(TranscriptionCopy.copiedToast),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return ValueSelectorBuilder<SpeechToTextState, _PanelSelection>(
      valueListenable: widget.viewModel,
      selector: (state) => (
        transcript: state.transcript,
        idle: state.sessionState.isIdleLike,
      ),
      builder: (context, selection) {
        _followNewWords(selection.transcript);
        if (selection.transcript.isEmpty) {
          return const _EmptyTranscript();
        }
        final iconColor = context.colorScheme.onSurfaceVariant;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  key: const ValueKey<String>('copy-transcript'),
                  tooltip: TranscriptionCopy.copyAction,
                  iconSize: 18,
                  color: iconColor,
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _copyTranscript(selection.transcript),
                  icon: const Icon(Icons.copy_rounded),
                ),
                IconButton(
                  key: const ValueKey<String>('clear-transcript'),
                  tooltip: TranscriptionCopy.clearAction,
                  iconSize: 18,
                  color: iconColor,
                  visualDensity: VisualDensity.compact,
                  onPressed: selection.idle
                      ? widget.viewModel.clearTranscript
                      : null,
                  icon: const Icon(Icons.delete_outline_rounded),
                ),
              ],
            ),
            Expanded(
              child: SingleChildScrollView(
                controller: _scrollController,
                padding: const EdgeInsets.only(
                  bottom: ProjectSpacing.md,
                ),
                child: SelectableText(
                  selection.transcript,
                  key: const ValueKey<String>('transcript-text'),
                  style: context.textTheme.bodyLarge?.merge(
                    AppTextStyles.reading,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _EmptyTranscript extends StatelessWidget {
  const _EmptyTranscript();

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.graphic_eq_rounded,
            size: 36,
            color: colorScheme.outline,
          ),
          const SizedBox(height: ProjectSpacing.md),
          Text(
            TranscriptionCopy.emptyTranscript,
            textAlign: TextAlign.center,
            style: context.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

typedef _PanelSelection = ({String transcript, bool idle});
