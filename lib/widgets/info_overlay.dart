import 'package:flutter/material.dart';
import '../models/printer_state.dart';

class InfoOverlay extends StatelessWidget {
  final PrinterState state;
  final bool connected;
  final String? thumbnailUrl;
  final VoidCallback onSettings;

  const InfoOverlay({
    super.key,
    required this.state,
    required this.connected,
    required this.onSettings,
    this.thumbnailUrl,
  });

  Color _stateColor() {
    switch (state.state.toLowerCase()) {
      case 'printing':
        return Colors.greenAccent;
      case 'paused':
        return Colors.orangeAccent;
      case 'error':
      case 'cancelled':
        return Colors.redAccent;
      case 'complete':
        return Colors.lightBlueAccent;
      default:
        return Colors.grey;
    }
  }

  bool get _isActive =>
      state.state == 'printing' || state.state == 'paused';

  @override
  Widget build(BuildContext context) {
    final pct = (state.progress * 100).toStringAsFixed(1);
    final eta = state.etaWallClock;
    final speedPct = (state.speedFactor * 100).round();
    final flowPct = (state.extrudeFactor * 100).round();

    return SafeArea(
      child: Stack(
        children: [
          // ── Top bar ──────────────────────────────────────────────
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.black87, Colors.transparent],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _Thumbnail(url: thumbnailUrl),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Status dot + state + filename + ETA
                        Row(
                          children: [
                            Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: connected
                                    ? _stateColor()
                                    : Colors.grey,
                                boxShadow: connected
                                    ? [
                                        BoxShadow(
                                          color: _stateColor()
                                              .withValues(alpha: 0.6),
                                          blurRadius: 6,
                                        )
                                      ]
                                    : null,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              state.state.toUpperCase(),
                              style: TextStyle(
                                color: _stateColor(),
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                                letterSpacing: 0.8,
                              ),
                            ),
                            if (state.filename != null) ...[
                              const SizedBox(width: 8),
                              const Text('•',
                                  style: TextStyle(
                                      color: Colors.white38, fontSize: 12)),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  state.filename!,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ] else
                              const Spacer(),
                            if (eta.isNotEmpty) ...[
                              const SizedBox(width: 8),
                              const Text('•',
                                  style: TextStyle(
                                      color: Colors.white38, fontSize: 12)),
                              const SizedBox(width: 8),
                              Text(
                                'ETA: $eta',
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ],
                        ),
                        // Speed + Flow (only when active)
                        if (_isActive && state.speed > 0) ...[
                          const SizedBox(height: 3),
                          Text(
                            'Speed: ${state.speed.round()} mm/s  •  Flow: $flowPct%  •  Speed override: $speedPct%',
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  _FocusableIconButton(
                    icon: Icons.settings,
                    onPressed: onSettings,
                    tooltip: 'Settings',
                  ),
                ],
              ),
            ),
          ),

          // ── Bottom bar ───────────────────────────────────────────
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 24, 12, 12),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.transparent, Colors.black87],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _hotendChip(),
                      _bedChip(),
                      if (state.currentLayer != null &&
                          state.totalLayer != null)
                        _chip(
                          Icons.layers,
                          'Layer',
                          '${state.currentLayer} / ${state.totalLayer}',
                        ),
                      _chip(Icons.timer_outlined, 'Elapsed',
                          state.formatElapsed),
                      _chip(Icons.hourglass_bottom, 'Remaining',
                          state.formatRemaining),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: state.progress.clamp(0.0, 1.0),
                            minHeight: 8,
                            backgroundColor: Colors.white24,
                            valueColor:
                                AlwaysStoppedAnimation(_stateColor()),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        '$pct%',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _hotendChip() {
    final heating = state.extruderPower > 0.01;
    final icon = Icons.local_fire_department;
    final value =
        '${state.extruderTemp.toStringAsFixed(0)}° / ${state.extruderTarget.toStringAsFixed(0)}°C';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          heating
              ? ShaderMask(
                  shaderCallback: (bounds) => const LinearGradient(
                    colors: [Colors.orange, Colors.deepOrange],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ).createShader(bounds),
                  child: Icon(icon,
                      color: Colors.white,
                      size: 16,
                      shadows: const [
                        Shadow(
                            color: Colors.orangeAccent,
                            blurRadius: 8)
                      ]),
                )
              : Icon(icon, color: Colors.white38, size: 16),
          const SizedBox(width: 6),
          const Text('Hotend',
              style: TextStyle(color: Colors.white60, fontSize: 11)),
          const SizedBox(width: 6),
          Text(value,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _bedChip() {
    return _chip(
      Icons.bed,
      'Bed',
      '${state.bedTemp.toStringAsFixed(0)}° / ${state.bedTarget.toStringAsFixed(0)}°C',
    );
  }

  Widget _chip(IconData icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white70, size: 16),
          const SizedBox(width: 6),
          Text(label,
              style: const TextStyle(color: Colors.white60, fontSize: 11)),
          const SizedBox(width: 6),
          Text(value,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _Thumbnail extends StatelessWidget {
  final String? url;
  const _Thumbnail({this.url});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        width: 56,
        height: 56,
        child: url != null
            ? Image.network(
                url!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _placeholder(),
              )
            : _placeholder(),
      ),
    );
  }

  Widget _placeholder() => Container(
        color: Colors.white10,
        child: const Icon(Icons.print, color: Colors.white30, size: 28),
      );
}

class _FocusableIconButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final String tooltip;
  const _FocusableIconButton(
      {required this.icon, required this.onPressed, required this.tooltip});

  @override
  State<_FocusableIconButton> createState() => _FocusableIconButtonState();
}

class _FocusableIconButtonState extends State<_FocusableIconButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      onFocusChange: (f) => setState(() => _focused = f),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: _focused ? Colors.white24 : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: _focused ? Colors.white54 : Colors.transparent,
            width: 2,
          ),
        ),
        child: IconButton(
          icon: Icon(widget.icon,
              color: _focused ? Colors.white : Colors.white70),
          onPressed: widget.onPressed,
          tooltip: widget.tooltip,
        ),
      ),
    );
  }
}
