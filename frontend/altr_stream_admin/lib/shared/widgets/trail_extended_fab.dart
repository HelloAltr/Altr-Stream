import 'package:flutter/material.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:hugeicons/hugeicons.dart';

/// A Material 3 Expressive extended FAB with the icon positioned on the trailing (right) side of the label.
class M3ETrailExtendedFab extends StatelessWidget {
  final String label;
  final dynamic icon;
  final VoidCallback? onPressed;
  final M3EFabColor color;
  final bool extended;

  const M3ETrailExtendedFab({
    super.key,
    required this.label,
    required this.icon,
    this.onPressed,
    this.color = M3EFabColor.primary,
    this.extended = true,
  });

  bool get _enabled => onPressed != null;

  @override
  Widget build(BuildContext context) {
    final theme = M3ETheme.of(context);
    final materialTheme = Theme.of(context);
    final colorScheme = materialTheme.colorScheme;
    final fabTheme = theme.fabTheme;
    final extendedTheme = fabTheme.extended;
    final metrics = fabTheme.resolve(
      size: M3EFabSize.medium,
      color: color,
      scheme: theme.colorScheme,
    );
    final borderRadius = M3EShapes.resolve(extendedTheme.cornerRadius);
    final border = RoundedRectangleBorder(borderRadius: borderRadius);

    final fg = metrics.foreground.a > 0
        ? metrics.foreground
        : colorScheme.onPrimaryContainer;
    final bg = metrics.background.a > 0
        ? metrics.background
        : colorScheme.primaryContainer;

    Widget buildIcon() {
      if (icon is Widget) {
        return icon as Widget;
      }
      if (icon is List<List<dynamic>>) {
        return HugeIcon(
          icon: icon as List<List<dynamic>>,
          color: fg,
          size: extendedTheme.iconSize,
        );
      }
      return const SizedBox.shrink();
    }

    return M3EComponentTheme(
      builder: (context) => M3ETappable(
        onTap: onPressed,
        enabled: _enabled,
        semanticLabel: label,
        pressedScale: extendedTheme.pressedScale,
        materialInk: true,
        builder: (context, state) {
          final resolvedElevation = state.hovered
              ? extendedTheme.elevation(hovered: true)
              : extendedTheme.elevation(hovered: false);

          final content = Padding(
            padding: EdgeInsets.symmetric(
              horizontal: extended
                  ? extendedTheme.extendedHorizontalPadding
                  : extendedTheme.collapsedHorizontalPadding,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                AnimatedSize(
                  duration: M3EMotion.medium2,
                  curve: M3EMotion.emphasized,
                  child: extended
                      ? Padding(
                          padding: EdgeInsets.only(right: extendedTheme.iconLabelGap),
                          child: Text(
                            label,
                            style: extendedTheme
                                .labelStyle(
                                  theme.typeScale,
                                  fg,
                                )
                                .copyWith(
                                  color: fg,
                                  fontWeight: FontWeight.w600,
                                ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
                IconTheme.merge(
                  data: IconThemeData(color: fg, size: extendedTheme.iconSize),
                  child: buildIcon(),
                ),
              ],
            ),
          );

          final surface = AnimatedContainer(
            duration: M3EMotion.medium2,
            curve: M3EMotion.emphasized,
            height: extendedTheme.height,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: borderRadius,
              boxShadow: M3EElevation.shadows(
                resolvedElevation,
                shadowColor: colorScheme.shadow,
              ),
            ),
            child: M3EStateLayerOverlay(
              state: state,
              color: fg,
              shape: border,
              alignment: Alignment.center,
              child: content,
            ),
          );

          return M3EFocusRing(
            focused: state.focused,
            radius: borderRadius,
            child: surface,
          );
        },
      ),
    );
  }
}
