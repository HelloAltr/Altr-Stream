import 'package:flutter/material.dart';

/// Renders text truncated in the middle on a single line, adhering to macOS-style path truncation.
class MiddleTruncatedPathText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final TextAlign textAlign;

  const MiddleTruncatedPathText(
    this.text, {
    super.key,
    this.style,
    this.textAlign = TextAlign.end,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveStyle = style ?? DefaultTextStyle.of(context).style;
    final textScaler = MediaQuery.textScalerOf(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        if (maxWidth <= 0 || maxWidth == double.infinity) {
          return Text(
            text,
            style: effectiveStyle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          );
        }

        // 1. Measure if the full path fits on a single line
        final painter = TextPainter(
          text: TextSpan(text: text, style: effectiveStyle),
          textDirection: TextDirection.ltr,
          textScaler: textScaler,
          maxLines: 1,
        )..layout();

        if (painter.width <= maxWidth) {
          return Text(
            text,
            style: effectiveStyle,
            maxLines: 1,
            textAlign: textAlign,
          );
        }

        // 2. Perform segment-based middle truncation (macOS style: preserving root & leaf directories)
        final bool isWindows = text.contains('\\') && !text.contains('/');
        final String separator = isWindows ? '\\' : '/';
        final bool hasLeading = text.startsWith(separator);
        final bool hasTrailing = text.endsWith(separator);

        final List<String> segments = text
            .split(separator)
            .where((s) => s.isNotEmpty)
            .toList();

        String bestCandidate = '';

        if (segments.length > 2) {
          int leftCount = 1;
          int rightCount = 1;

          while (leftCount + rightCount < segments.length) {
            bool advanced = false;

            // Try adding left segment if balanced or fewer segments
            if (leftCount <= rightCount && leftCount + rightCount + 1 <= segments.length) {
              final String nextLeft = (hasLeading ? separator : '') + segments.sublist(0, leftCount + 1).join(separator);
              final String currentRight = segments.sublist(segments.length - rightCount).join(separator) + (hasTrailing ? separator : '');
              final String testCandidate = '$nextLeft$separator...$separator$currentRight';

              painter.text = TextSpan(text: testCandidate, style: effectiveStyle);
              painter.layout();

              if (painter.width <= maxWidth) {
                leftCount++;
                advanced = true;
              }
            }

            // Try adding right segment
            if (rightCount < leftCount && leftCount + rightCount + 1 <= segments.length) {
              final String currentLeft = (hasLeading ? separator : '') + segments.sublist(0, leftCount).join(separator);
              final String nextRight = segments.sublist(segments.length - (rightCount + 1)).join(separator) + (hasTrailing ? separator : '');
              final String testCandidate = '$currentLeft$separator...$separator$nextRight';

              painter.text = TextSpan(text: testCandidate, style: effectiveStyle);
              painter.layout();

              if (painter.width <= maxWidth) {
                rightCount++;
                advanced = true;
              }
            }

            if (!advanced) break;
          }

          final String finalLeft = (hasLeading ? separator : '') + segments.sublist(0, leftCount).join(separator);
          final String finalRight = segments.sublist(segments.length - rightCount).join(separator) + (hasTrailing ? separator : '');
          final String candidate = '$finalLeft$separator...$separator$finalRight';

          painter.text = TextSpan(text: candidate, style: effectiveStyle);
          painter.layout();

          if (painter.width <= maxWidth) {
            bestCandidate = candidate;
          }
        }

        // 3. Fallback to character-level middle truncation if segment level still exceeds maxWidth
        if (bestCandidate.isEmpty) {
          int low = 4;
          int high = text.length - 1;
          bestCandidate = '...';

          while (low <= high) {
            final mid = (low + high) ~/ 2;
            final startLen = (mid / 2).ceil();
            final endLen = (mid / 2).floor();

            String cleanStart = text.substring(0, startLen);
            String cleanEnd = text.substring(text.length - endLen);

            if (cleanStart.endsWith(separator)) cleanStart = cleanStart.substring(0, cleanStart.length - 1);
            if (cleanEnd.startsWith(separator)) cleanEnd = cleanEnd.substring(1);

            final candidate = '$cleanStart$separator...$separator$cleanEnd';

            painter.text = TextSpan(text: candidate, style: effectiveStyle);
            painter.layout();

            if (painter.width <= maxWidth) {
              bestCandidate = candidate;
              low = mid + 1;
            } else {
              high = mid - 1;
            }
          }
        }

        return Tooltip(
          message: text,
          waitDuration: const Duration(milliseconds: 400),
          child: Text(
            bestCandidate,
            style: effectiveStyle,
            maxLines: 1,
            textAlign: textAlign,
          ),
        );
      },
    );
  }
}
