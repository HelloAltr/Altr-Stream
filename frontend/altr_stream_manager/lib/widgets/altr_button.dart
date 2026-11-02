import 'package:flutter/material.dart';

/// Standard Altr Button widget with themed hover, pressed, and elevation states.
class AltrButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;
  final Icon? icon;
  final bool? isOutsideContainer;
  final Color? backgroundColor;
  final Color? foregroundColor;

  final bool isDestructive;

  const AltrButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.isOutsideContainer,
    this.isDestructive = false,
    this.backgroundColor,
    this.foregroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final brightness = View.of(context).platformDispatcher.platformBrightness;

    final defaultBg = brightness == Brightness.light
        ? isOutsideContainer == true
            ? colorScheme.surfaceContainerHigh
            : colorScheme.surfaceContainerLowest
        : isOutsideContainer == true
            ? colorScheme.surfaceContainerHigh
            : colorScheme.surfaceContainer;

    final effectiveBg = isDestructive
        ? colorScheme.error
        : (backgroundColor ?? defaultBg);

    final effectiveFg = isDestructive
        ? colorScheme.onError
        : (foregroundColor ?? colorScheme.onSurface);

    return FilledButton.icon(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: effectiveBg,
        foregroundColor: effectiveFg,
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
