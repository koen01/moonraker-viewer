import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const _kRed = Color(0xFFEF4444);

// ── E-Stop button ────────────────────────────────────────────────────────────

class EStopButton extends StatefulWidget {
  final int holdDurationMs;
  final VoidCallback onArmed;

  const EStopButton({
    super.key,
    required this.holdDurationMs,
    required this.onArmed,
  });

  @override
  State<EStopButton> createState() => _EStopButtonState();
}

class _EStopButtonState extends State<EStopButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  bool _holding = false;
  bool _fired = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: widget.holdDurationMs),
    )..addStatusListener(_onStatus);
  }

  @override
  void didUpdateWidget(EStopButton old) {
    super.didUpdateWidget(old);
    if (old.holdDurationMs != widget.holdDurationMs) {
      _ctrl.duration = Duration(milliseconds: widget.holdDurationMs);
    }
  }

  void _onStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && _holding && !_fired) {
      _fired = true;
      setState(() => _holding = false);
      _ctrl.reverse();
      HapticFeedback.mediumImpact();
      widget.onArmed();
    }
  }

  void _cancel() {
    if (!_holding) return;
    setState(() {
      _holding = false;
      _fired = false;
    });
    _ctrl.reverse();
  }

  @override
  void dispose() {
    _ctrl.removeStatusListener(_onStatus);
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) {
        setState(() {
          _holding = true;
          _fired = false;
        });
        _ctrl.forward(from: 0);
      },
      onPointerUp: (_) => _cancel(),
      onPointerCancel: (_) => _cancel(),
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, __) => _buildButton(_ctrl.value),
      ),
    );
  }

  Widget _buildButton(double t) {
    final bg = Color.lerp(const Color(0xC7140808), const Color(0xF2EF4444), t)!;
    final fg = Color.lerp(_kRed, Colors.white, t)!;

    return Transform.scale(
      scale: 1.0 - 0.06 * t,
      child: SizedBox(
        width: 56,
        height: 56,
        child: Stack(
          alignment: Alignment.center,
          children: [
            CustomPaint(size: const Size(56, 56), painter: _RingPainter(t)),
            ClipOval(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: bg,
                    border: Border.all(
                      color: _kRed.withValues(alpha: 0.55),
                      width: 1,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    'STOP',
                    style: TextStyle(
                      color: fg,
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.72,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double t;
  const _RingPainter(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2 - 1;

    canvas.drawCircle(
      c, r,
      Paint()
        ..color = const Color(0x2EEF4444)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    if (t > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: r),
        -math.pi / 2,
        2 * math.pi * t,
        false,
        Paint()
          ..color = _kRed
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.t != t;
}

// ── Confirmation dialog ───────────────────────────────────────────────────────

class EStopConfirmDialog extends StatelessWidget {
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  const EStopConfirmDialog({
    super.key,
    required this.onConfirm,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onCancel,
      behavior: HitTestBehavior.opaque,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
        child: Container(
          color: const Color(0xB8000000),
          child: Center(
            child: GestureDetector(
              onTap: () {},
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 40),
                padding: const EdgeInsets.fromLTRB(22, 24, 22, 18),
                decoration: BoxDecoration(
                  color: const Color(0xFF161514),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0x4DEF4444), width: 1),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: const BoxDecoration(
                        color: Color(0x24EF4444),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.warning_amber_rounded,
                        color: _kRed,
                        size: 22,
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Emergency stop?',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'This halts the printer immediately. Heaters off, motors disabled. The current print will be lost.',
                      style: TextStyle(
                        color: Color(0x8CFFFFFF),
                        fontSize: 13,
                        height: 1.5,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _kRed,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 13),
                        ),
                        onPressed: onConfirm,
                        child: const Text(
                          'Stop Printer',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: TextButton(
                        onPressed: onCancel,
                        child: const Text(
                          'Cancel',
                          style: TextStyle(
                            color: Color(0x99FFFFFF),
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Post-confirm toast ────────────────────────────────────────────────────────

void showEStopToast(BuildContext context, {String? error}) {
  final overlay = Overlay.of(context);
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => Material(
      type: MaterialType.transparency,
      child: _EStopToast(error: error, onDone: entry.remove),
    ),
  );
  overlay.insert(entry);
}

class _EStopToast extends StatefulWidget {
  final String? error;
  final VoidCallback onDone;
  const _EStopToast({this.error, required this.onDone});

  @override
  State<_EStopToast> createState() => _EStopToastState();
}

class _EStopToastState extends State<_EStopToast>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _opacity = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _ctrl.forward();
    Future.delayed(const Duration(milliseconds: 2400), () {
      if (mounted) _ctrl.reverse().then((_) => widget.onDone());
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isError = widget.error != null;
    return Positioned(
      top: 80,
      left: 0,
      right: 0,
      child: FadeTransition(
        opacity: _opacity,
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: isError ? Colors.black87 : const Color(0xF2EF4444),
              borderRadius: BorderRadius.circular(24),
              border: isError
                  ? Border.all(color: const Color(0x4DEF4444), width: 1)
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!isError) ...[
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                ] else ...[
                  const Icon(Icons.error_outline, color: _kRed, size: 16),
                  const SizedBox(width: 8),
                ],
                Text(
                  isError ? widget.error! : 'PRINTER STOPPED',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
