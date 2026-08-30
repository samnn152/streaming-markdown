// Modified by animated_streaming_markdown for Flutter 3.10 through current.
// Upstream's RenderConstrainedLayoutBuilder implementation crosses a breaking
// Flutter API boundary at 3.32. This version delegates layout to Flutter's
// public LayoutBuilder and forwards the built child's baseline dynamically.

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

class LayoutBuilderPreserveBaseline extends StatelessWidget {
  /// Creates a widget that defers its building until layout.
  ///
  /// The [builder] argument must not be null.
  const LayoutBuilderPreserveBaseline({
    super.key,
    required LayoutWidgetBuilder builder,
  }) : _builder = builder;

  final LayoutWidgetBuilder _builder;

  @override
  Widget build(BuildContext context) {
    return _BaselineThroughLayoutBuilder(
      child: LayoutBuilder(builder: _builder),
    );
  }
}

class _BaselineThroughLayoutBuilder extends SingleChildRenderObjectWidget {
  const _BaselineThroughLayoutBuilder({required super.child});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderBaselineThroughLayoutBuilder();
}

class _RenderBaselineThroughLayoutBuilder extends RenderProxyBox {
  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) {
    final RenderBox? layoutBuilder = child;
    if (layoutBuilder == null) {
      return null;
    }
    final Object? builtChild = (layoutBuilder as dynamic).child;
    if (builtChild is RenderBox) {
      return builtChild.getDistanceToActualBaseline(baseline);
    }
    return layoutBuilder.getDistanceToActualBaseline(baseline);
  }
}
