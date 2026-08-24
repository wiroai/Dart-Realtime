import 'package:flutter/material.dart';
import 'package:wiro_realtime/app/layout/project_padding.dart';

class ProtocolEventPanel extends StatelessWidget {
  const ProtocolEventPanel({
    required this.expanded,
    required this.events,
    required this.onToggle,
    super.key,
  });

  final bool expanded;
  final List<String> events;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextButton(
          key: const ValueKey<String>('protocol-toggle'),
          onPressed: onToggle,
          child: Text(
            expanded ? 'Hide protocol events' : 'Show protocol events',
          ),
        ),
        if (expanded && events.isEmpty)
          const Padding(
            padding: ProjectPadding.page,
            child: Text('No protocol events yet.'),
          )
        else if (expanded)
          SizedBox(
            height: 160,
            child: CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: ProjectPadding.page,
                  sliver: SliverList.builder(
                    itemCount: events.length,
                    itemBuilder: (context, index) {
                      return Text(events[index]);
                    },
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
