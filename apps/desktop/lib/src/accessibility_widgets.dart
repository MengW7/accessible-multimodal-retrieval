import 'package:flutter/material.dart';

/// A semantic boundary prevents adjacent explanatory text from becoming part of
/// an editable control's accessible name. It introduces no extra tab stop.
class AccessibleControl extends StatefulWidget {
  const AccessibleControl({super.key, required this.child});
  final Widget child;
  @override
  State<AccessibleControl> createState() => _AccessibleControlState();
}

class _AccessibleControlState extends State<AccessibleControl> {
  bool focused = false;
  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    explicitChildNodes: true,
    child: Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (value) {
        if (!mounted) return;
        setState(() => focused = value);
        if (value) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              Scrollable.ensureVisible(
                context,
                alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
              );
            }
          });
        }
      },
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            width: 3,
            color: focused
                ? Theme.of(context).colorScheme.primary
                : Colors.transparent,
          ),
        ),
        child: widget.child,
      ),
    ),
  );
}

Widget accessibleHeading(
  BuildContext context,
  String text, {
  TextStyle? style,
}) => Semantics(
  header: true,
  child: Text(text, style: style ?? Theme.of(context).textTheme.titleLarge),
);

/// A stable semantic-only region lives outside the scrolling viewport. The
/// matching visual status is excluded from semantics to avoid double reading.
class LiveStatus extends StatelessWidget {
  const LiveStatus({super.key, required this.message});
  final String message;
  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    liveRegion: true,
    label: message,
    child: const SizedBox(width: 1, height: 1),
  );
}
