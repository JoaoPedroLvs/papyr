import 'package:flutter/material.dart';

/// Bottom bar whose pill stretches toward the new item, then shrinks behind it.
class SnakeBar extends StatefulWidget {
  const SnakeBar({super.key, required this.index, required this.onTap, required this.items});

  final int index;
  final ValueChanged<int> onTap;
  final List<(IconData, String)> items;

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
    _c.forward(from: 0);
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
      color: scheme.surfaceContainer,
      child: Padding(
        padding: EdgeInsets.fromLTRB(12, 8, 12, 8 + MediaQuery.viewPaddingOf(context).bottom),
        child: SizedBox(
          height: 48,
          child: LayoutBuilder(builder: (context, box) {
            final w = box.maxWidth / widget.items.length;
            return Stack(children: [
              AnimatedBuilder(
                animation: _c,
                builder: (_, _) {
                  final (l, r) = _edges();
                  return Positioned(
                    left: l * w + 4,
                    width: (r - l) * w - 8,
                    top: 0,
                    bottom: 0,
                    child: DecoratedBox(
                      decoration: BoxDecoration(color: scheme.secondaryContainer, borderRadius: BorderRadius.circular(24)),
                    ),
                  );
                },
              ),
              Row(children: [
                for (final (i, (icon, label)) in widget.items.indexed)
                  Expanded(
                    child: Semantics(
                      button: true,
                      selected: i == widget.index,
                      label: label,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(24),
                        onTap: () => widget.onTap(i),
                        child: ExcludeSemantics(
                          child: IconTheme.merge(
                            data: IconThemeData(color: i == widget.index ? scheme.onSecondaryContainer : scheme.onSurfaceVariant),
                            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                              Icon(icon),
                              if (i == widget.index) ...[
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Text(label,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context).textTheme.labelLarge?.copyWith(color: scheme.onSecondaryContainer)),
                                ),
                              ],
                            ]),
                          ),
                        ),
                      ),
                    ),
                  ),
              ]),
            ]);
          }),
        ),
      ),
    );
  }
}
