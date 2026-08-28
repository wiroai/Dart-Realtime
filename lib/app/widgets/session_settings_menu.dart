import 'package:flutter/material.dart';

/// One entry in a [SessionSettingsMenu].
typedef SessionMenuOption = ({String value, String label});

/// The one setting a tool screen parks in its app bar.
///
/// A checked popup behind the tune icon: the transcriber's accuracy
/// trade, the player's voice model. The value is sent once when the
/// task starts, so callers lock the menu while a session runs.
class SessionSettingsMenu extends StatelessWidget {
  const SessionSettingsMenu({
    required this.tooltip,
    required this.enabled,
    required this.selectedValue,
    required this.options,
    required this.onSelected,
    this.menuKey,
    super.key,
  });

  final String tooltip;
  final bool enabled;
  final String selectedValue;
  final List<SessionMenuOption> options;
  final ValueChanged<String> onSelected;
  final Key? menuKey;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      key: menuKey,
      tooltip: tooltip,
      enabled: enabled,
      icon: const Icon(Icons.tune_rounded),
      onSelected: onSelected,
      itemBuilder: (context) => [
        for (final option in options)
          CheckedPopupMenuItem<String>(
            value: option.value,
            checked: option.value == selectedValue,
            child: Text(option.label),
          ),
      ],
    );
  }
}
