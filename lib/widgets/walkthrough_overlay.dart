import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class _Step {
  final IconData icon;
  final String title;
  final String body;
  const _Step(this.icon, this.title, this.body);
}

const _steps = [
  _Step(
    Icons.print,
    'Welcome to Moonraker Viewer',
    'Your 3D printer\'s live camera feed and print status — always at a glance.',
  ),
  _Step(
    Icons.videocam,
    'Live Camera Feed',
    'Your printer\'s feed fills the screen in real time. Pinch to zoom up to 6×, or double-tap to reset.',
  ),
  _Step(
    Icons.layers,
    'Print Status Overlay',
    'Tap anywhere to show or hide the overlay. It displays temperatures, progress, speed, ETA, and more.',
  ),
  _Step(
    Icons.settings,
    'Settings & More',
    'Tap the gear icon to configure your printer, enable split-screen for a second printer, or toggle the Klipper console.',
  ),
];

class WalkthroughOverlay extends StatefulWidget {
  final VoidCallback onDone;

  const WalkthroughOverlay({super.key, required this.onDone});

  @override
  State<WalkthroughOverlay> createState() => _WalkthroughOverlayState();
}

class _WalkthroughOverlayState extends State<WalkthroughOverlay> {
  int _step = 0;

  void _next() {
    if (_step < _steps.length - 1) {
      setState(() => _step++);
    } else {
      widget.onDone();
    }
  }

  void _prev() {
    if (_step > 0) setState(() => _step--);
  }

  KeyEventResult _handleKey(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.gameButtonA ||
        key == LogicalKeyboardKey.space) {
      _next();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      _prev();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape || key == LogicalKeyboardKey.goBack) {
      widget.onDone();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final step = _steps[_step];
    final isLast = _step == _steps.length - 1;

    return Focus(
      autofocus: true,
      onKeyEvent: _handleKey,
      child: Container(
        color: Colors.black.withValues(alpha: 0.85),
        child: SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(),
              Icon(step.icon, size: 64, color: Colors.white),
              const SizedBox(height: 24),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 48),
                child: Text(
                  step.title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 64),
                child: Text(
                  step.body,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 15,
                    height: 1.5,
                  ),
                ),
              ),
              const Spacer(),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(_steps.length, (i) {
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: i == _step ? 20 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: i == _step ? Colors.white : Colors.white38,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TextButton(
                    onPressed: widget.onDone,
                    child: const Text(
                      'Skip',
                      style: TextStyle(color: Colors.white54, fontSize: 14),
                    ),
                  ),
                  const SizedBox(width: 24),
                  ElevatedButton(
                    onPressed: _next,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 32, vertical: 12),
                    ),
                    child: Text(
                      isLast ? 'Get started' : 'Next',
                      style: const TextStyle(fontSize: 15),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}
