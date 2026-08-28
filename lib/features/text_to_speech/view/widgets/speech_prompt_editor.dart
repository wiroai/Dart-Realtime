import 'package:flutter/material.dart';
import 'package:wiro_realtime/app/extensions/theme_extension.dart';
import 'package:wiro_realtime/app/layout/project_padding.dart';
import 'package:wiro_realtime/app/theme/app_text_styles.dart';
import 'package:wiro_realtime/features/text_to_speech/view/constants/speech_copy.dart';

/// The text to speak, framed in a card.
///
/// The editor fills whatever space the controls leave it and scrolls
/// inside itself, so the play button never moves no matter how long the
/// text grows. The character count sits small in the top corner and only
/// once there is something to count.
class SpeechPromptEditor extends StatefulWidget {
  const SpeechPromptEditor({
    required this.promptNotifier,
    required this.enabled,
    super.key,
  });

  final ValueNotifier<String> promptNotifier;
  final bool enabled;

  @override
  State<SpeechPromptEditor> createState() => _SpeechPromptEditorState();
}

class _SpeechPromptEditorState extends State<SpeechPromptEditor> {
  late final TextEditingController _controller;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.promptNotifier.value,
    );
    widget.promptNotifier.addListener(_syncFromNotifier);
  }

  /// Flipping read-only under a focused field leaves its keyboard
  /// connection dangling, and the platform asserts when the next
  /// connection shows over it. Play is usually tapped with the keyboard
  /// still up, so the focus is released on every editability change.
  @override
  void didUpdateWidget(SpeechPromptEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled != widget.enabled) {
      _focusNode.unfocus();
    }
  }

  @override
  void dispose() {
    widget.promptNotifier.removeListener(_syncFromNotifier);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _syncFromNotifier() {
    if (_controller.text == widget.promptNotifier.value) {
      return;
    }
    _controller.text = widget.promptNotifier.value;
  }

  @override
  Widget build(BuildContext context) {
    final textStyle = context.textTheme.bodyLarge
        ?.merge(AppTextStyles.reading)
        .copyWith(color: context.colorScheme.onSurface);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 24,
          child: ValueListenableBuilder<String>(
            valueListenable: widget.promptNotifier,
            builder: (context, value, _) {
              if (value.isEmpty) {
                return const SizedBox.shrink();
              }
              return Align(
                alignment: Alignment.centerRight,
                child: Text(
                  SpeechCopy.characterCount(value.length),
                  key: const ValueKey<String>('tts-character-count'),
                  style: context.textTheme.bodySmall,
                ),
              );
            },
          ),
        ),
        Expanded(
          child: Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: ProjectPadding.card,
              child: TextField(
                key: const ValueKey<String>('tts-prompt'),
                controller: _controller,
                focusNode: _focusNode,
                // Read-only rather than disabled: a disabled field also
                // stops scrolling inside itself, and this field is the
                // only thing on the page that scrolls, so long text could
                // not be followed while it is being spoken.
                readOnly: !widget.enabled,
                expands: true,
                maxLines: null,
                textAlignVertical: TextAlignVertical.top,
                style: textStyle,
                decoration: InputDecoration(
                  hintText: SpeechCopy.promptHint,
                  hintStyle: textStyle?.copyWith(
                    color: context.colorScheme.onSurfaceVariant,
                  ),
                  filled: false,
                  isCollapsed: true,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                ),
                onChanged: (value) => widget.promptNotifier.value = value,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
