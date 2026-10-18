import 'package:flutter/material.dart';
import 'package:papyr/widgets/papyr_mark.dart';

/// Icon-only bottom bar whose pill stretches toward the new item, then shrinks behind it.
/// A null item is an empty column, under the [ScanButton]; [index] always points at a non-null one.
class SnakeBar extends StatefulWidget {
  const SnakeBar({super.key, required this.index, required this.onTap, required this.items});

  final int index;
  final ValueChanged<int> onTap;
  final List<(IconData, String)?> items;

  @override
  State<SnakeBar> createState() => _SnakeBarState();
}

class _SnakeBarState extends State<SnakeBar> with SingleTickerProviderStateMixin {
  static const _front = Interval(0.0, 0.7, curve: Curves.easeOutCubic);
  static const _back = Interval(0.3, 1.0, curve: Curves.easeOutCubic);

  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 400), value: 1);
  late int _to = widget.index;
  late var _from = (_to.toDouble(), _to + 1.0); // pill edges, in slots, when the animation started
  var _right = true;

  (double, double) _edges() {
    final t = _c.value;
    final (l, r) = _from;
    final tl = (_right ? _back : _front).transform(t), tr = (_right ? _front : _back).transform(t);
    return (l + (_to - l) * tl, r + (_to + 1 - r) * tr);
  }

  @override
  void didUpdateWidget(SnakeBar old) {
    super.didUpdateWidget(old);
    if (widget.index == _to) return;
    _from = _edges();
    _right = widget.index > _to;
    _to = widget.index;
    if (MediaQuery.disableAnimationsOf(context)) {
      _c.value = 1;
    } else {
      _c.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      shape: Border(top: BorderSide(color: scheme.outlineVariant)), // paint only: the row keeps its full 64
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewPaddingOf(context).bottom),
        child: SizedBox(
          height: 64,
          child: LayoutBuilder(builder: (context, box) {
            final w = box.maxWidth / widget.items.length, inset = (w - 64) / 2;
            return Stack(fit: StackFit.expand, children: [
              AnimatedBuilder(
                animation: _c,
                builder: (_, _) {
                  final (l, r) = _edges();
                  return Positioned(
                    key: const ValueKey('pill'),
                    left: l * w + inset,
                    width: (r - l) * w - 2 * inset,
                    top: 10,
                    height: 44,
                    child: DecoratedBox(
                      decoration: BoxDecoration(color: scheme.surfaceContainerHigh, borderRadius: BorderRadius.circular(22)),
                    ),
                  );
                },
              ),
              Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                for (final (i, item) in widget.items.indexed)
                  if (item case (final icon, final label))
                    Expanded(
                      child: Semantics(
                        button: true,
                        selected: i == widget.index,
                        label: label,
                        child: Tooltip(
                          message: label,
                          excludeFromSemantics: true, // the label above already names it
                          child: InkWell(
                            onTap: () => widget.onTap(i),
                            child: Center(
                              child: Icon(icon, size: 24, color: i == widget.index ? scheme.primary : scheme.outline),
                            ),
                          ),
                        ),
                      ),
                    )
                  else
                    const Spacer(),
              ]),
            ]);
          }),
        ),
      ),
    );
  }
}

/// The raised Escanear button, for the Scaffold's FAB slot: there its top, above the bar, still takes taps.
class ScanButton extends StatelessWidget {
  const ScanButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = scheme.brightness == Brightness.dark;
    final r = BorderRadius.circular(21);
    return Semantics(
      button: true,
      label: 'Escanear',
      child: Tooltip(
        message: 'Escanear',
        excludeFromSemantics: true,
        child: DecoratedBox(
          decoration: BoxDecoration(borderRadius: r, boxShadow: [
            BoxShadow(
              color: dark ? const Color(0x66000000) : const Color(0x4D102E50),
              offset: const Offset(0, 8),
              blurRadius: 18,
            ),
          ]),
          child: Material(
            color: scheme.primaryContainer,
            borderRadius: r,
            child: InkWell(
              onTap: onPressed,
              borderRadius: r,
              child: SizedBox.square(
                dimension: 62,
                child: Center(child: PapyrMark.scan(width: 29, brackets: scheme.onPrimaryContainer)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ScanButtonLocation extends FloatingActionButtonLocation {
  const _ScanButtonLocation();

  @override
  Offset getOffset(ScaffoldPrelayoutGeometry g) =>
      Offset((g.scaffoldSize.width - g.floatingActionButtonSize.width) / 2, g.contentBottom - 22);
}

/// Centred, with the button's top 22 dp above the bar's top edge.
const FloatingActionButtonLocation scanButtonLocation = _ScanButtonLocation();
