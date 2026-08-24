import 'package:flutter/material.dart';
import 'package:wiro_realtime/features/realtime_home/view/widgets/model_parameter_form.dart';

mixin ModelTextValueFieldMixin on State<ModelTextValueField> {
  late final TextEditingController textController;

  @override
  void initState() {
    super.initState();
    textController = TextEditingController(text: widget.valueListenable.value);
    widget.valueListenable.addListener(_syncFromNotifier);
  }

  set inputValue(String value) {
    widget.valueListenable.value = value;
  }

  void _syncFromNotifier() {
    if (textController.text == widget.valueListenable.value) {
      return;
    }
    textController.text = widget.valueListenable.value;
  }

  @override
  void dispose() {
    widget.valueListenable.removeListener(_syncFromNotifier);
    textController.dispose();
    super.dispose();
  }
}
