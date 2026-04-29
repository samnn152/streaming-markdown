part of '../view.dart';

class _ScheduledRevealHost extends StatefulWidget {
  const _ScheduledRevealHost({
    required this.scheduledStart,
    required this.child,
  });

  final DateTime scheduledStart;
  final Widget child;

  @override
  State<_ScheduledRevealHost> createState() => _ScheduledRevealHostState();
}

class _ScheduledRevealHostState extends State<_ScheduledRevealHost> {
  bool _visible = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _configure();
  }

  @override
  void didUpdateWidget(covariant _ScheduledRevealHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scheduledStart != widget.scheduledStart) {
      _configure();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _configure() {
    _timer?.cancel();
    final DateTime now = DateTime.now();
    if (!now.isBefore(widget.scheduledStart)) {
      _visible = true;
      return;
    }
    _visible = false;
    _timer = Timer(widget.scheduledStart.difference(now), () {
      if (!mounted) {
        return;
      }
      setState(() {
        _visible = true;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible) {
      return const SizedBox.shrink();
    }
    return widget.child;
  }
}
