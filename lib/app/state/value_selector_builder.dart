import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Rebuilds only when the part of a state object this widget reads
/// actually changes.
///
/// `ValueListenableBuilder` rebuilds on every notification, so a field
/// that ticks every second — an elapsed timer, say — would redraw
/// everything else on the screen with it. [selector] narrows the
/// notification down to one value, compared with `==`.
///
/// [Selected] must have value equality for this to help; primitives,
/// records, and `Equatable` types all qualify.
class ValueSelectorBuilder<Source, Selected> extends StatefulWidget {
  const ValueSelectorBuilder({
    required this.valueListenable,
    required this.selector,
    required this.builder,
    super.key,
  });

  final ValueListenable<Source> valueListenable;
  final Selected Function(Source source) selector;
  final Widget Function(BuildContext context, Selected value) builder;

  @override
  State<ValueSelectorBuilder<Source, Selected>> createState() =>
      _ValueSelectorBuilderState<Source, Selected>();
}

class _ValueSelectorBuilderState<Source, Selected>
    extends State<ValueSelectorBuilder<Source, Selected>> {
  late Selected _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.selector(widget.valueListenable.value);
    widget.valueListenable.addListener(_handleChange);
  }

  @override
  void didUpdateWidget(ValueSelectorBuilder<Source, Selected> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.valueListenable != widget.valueListenable) {
      oldWidget.valueListenable.removeListener(_handleChange);
      widget.valueListenable.addListener(_handleChange);
    }
    _selected = widget.selector(widget.valueListenable.value);
  }

  @override
  void dispose() {
    widget.valueListenable.removeListener(_handleChange);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _selected);

  void _handleChange() {
    final next = widget.selector(widget.valueListenable.value);
    if (next == _selected) {
      return;
    }
    setState(() => _selected = next);
  }
}
