import 'package:flutter/material.dart';

/// An [IconButton] sized for use in an [AppBar]'s actions row.
///
/// Plain [IconButton]s are inflated to Material's 48x48 minimum tap
/// target, which reads as a lot of empty space once more than one or two
/// sit next to each other in an app bar. This trims that down to 36x36
/// while keeping every app bar's action row sized consistently across the
/// app.
class AppBarActionIconButton extends StatelessWidget {
  const AppBarActionIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    required this.tooltip,
  });

  final Widget icon;
  final VoidCallback? onPressed;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: icon,
      onPressed: onPressed,
      tooltip: tooltip,
      padding: const EdgeInsets.all(6),
      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
    );
  }
}
