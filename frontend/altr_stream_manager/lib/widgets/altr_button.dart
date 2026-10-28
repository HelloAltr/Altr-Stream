import 'package:flutter/material.dart';

/// Standard Altr Button widget with themed hover, pressed, and elevation states.
class AltrButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;
  final Icon? icon;
  final bool? isOutsideContainer;

  const AltrButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.isOutsideContainer,
  });

  @override
  Widget build(BuildContext context) {
    final brightness = View.of(context).platformDispatcher.platformBrightness;

    return FilledButton.icon(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: brightness == Brightness.light
            ? isOutsideContainer == true
                ? Theme.of(context).colorScheme.surfaceContainerHigh
                : Theme.of(context).colorScheme.surfaceContainerLowest
            : isOutsideContainer == true
                ? Theme.of(context).colorScheme.surfaceContainerHigh
                : Theme.of(context).colorScheme.surfaceContainer,
        foregroundColor: Theme.of(context).colorScheme.onSurface,
        fixedSize: const Size.fromHeight(36),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.normal),
        elevation: 0,
      ),
      icon: icon,
      label: Text(label),
    );
  }
}
