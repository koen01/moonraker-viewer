import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../widgets/printer_pane.dart';
import '../widgets/walkthrough_overlay.dart';
import 'settings_screen.dart';

class ViewerScreen extends StatefulWidget {
  const ViewerScreen({super.key});

  @override
  State<ViewerScreen> createState() => _ViewerScreenState();
}

class _ViewerScreenState extends State<ViewerScreen> {
  // Printer 1
  String? _host;
  int _port = 7125;

  // Printer 2
  bool _secondPrinterEnabled = false;
  String? _host2;
  int _port2 = 7125;

  // UI state
  bool _showOverlay = true;
  bool _showConsole = false;
  bool _eStopEnabled = true;
  int _eStopHoldMs = 1500;
  bool _showWalkthrough = false;

  // Split/focus state: null = split (when 2 printers), else 0/1
  int? _focusedPane;
  int _highlightedPane = 0;

  final FocusNode _settingsFocusNode = FocusNode();
  final FocusNode _settingsFocusNode2 = FocusNode();

  bool get _splitMode =>
      _secondPrinterEnabled &&
      (_host2?.isNotEmpty ?? false) &&
      _focusedPane == null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadSettings());
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final host = prefs.getString('moonraker_host');
    final port = prefs.getInt('moonraker_port') ?? 7125;
    final keepScreenOn = prefs.getBool('keep_screen_on') ?? true;
    await WakelockPlus.toggle(enable: keepScreenOn);
    setState(() {
      _host = host;
      _port = port;
      _showConsole = prefs.getBool('show_console') ?? false;
      _secondPrinterEnabled = prefs.getBool('second_printer_enabled') ?? false;
      _host2 = prefs.getString('moonraker_host_2');
      _port2 = prefs.getInt('moonraker_port_2') ?? 7125;
      _eStopEnabled = prefs.getBool('estop_enabled') ?? true;
      _eStopHoldMs = prefs.getInt('estop_hold_ms') ?? 1500;
      final onboardingSeen = prefs.getBool('onboarding_seen') ?? false;
      _showWalkthrough = !onboardingSeen;
    });
  }

  Future<void> _dismissWalkthrough() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_seen', true);
    if (!mounted) return;
    setState(() => _showWalkthrough = false);
    if (_host == null || _host!.isEmpty) {
      _openSettings();
    }
  }

  Future<void> _openSettings() async {
    if (!mounted) return;
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const SettingsScreen()),
    );
    if (saved == true) {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _host = prefs.getString('moonraker_host');
        _port = prefs.getInt('moonraker_port') ?? 7125;
        _showConsole = prefs.getBool('show_console') ?? false;
        _secondPrinterEnabled = prefs.getBool('second_printer_enabled') ?? false;
        _host2 = prefs.getString('moonraker_host_2');
        _port2 = prefs.getInt('moonraker_port_2') ?? 7125;
        _eStopEnabled = prefs.getBool('estop_enabled') ?? true;
        _eStopHoldMs = prefs.getInt('estop_hold_ms') ?? 1500;
        // Reset focus to split when settings change
        _focusedPane = null;
        _showOverlay = true;
      });
    }
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;

    // Return to split view from a focused pane (Escape / Back)
    if (_focusedPane != null &&
        (key == LogicalKeyboardKey.escape ||
            key == LogicalKeyboardKey.goBack)) {
      setState(() {
        _focusedPane = null;
        _showOverlay = true;
      });
      return KeyEventResult.handled;
    }

    if (_splitMode) {
      if (key == LogicalKeyboardKey.arrowLeft) {
        setState(() => _highlightedPane = 0);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowRight) {
        setState(() => _highlightedPane = 1);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.select ||
          key == LogicalKeyboardKey.enter ||
          key == LogicalKeyboardKey.gameButtonA) {
        setState(() {
          _focusedPane = _highlightedPane;
          _showOverlay = true;
        });
        return KeyEventResult.handled;
      }
    } else {
      if (key == LogicalKeyboardKey.select ||
          key == LogicalKeyboardKey.enter ||
          key == LogicalKeyboardKey.gameButtonA) {
        if (!_showOverlay) setState(() => _showOverlay = true);
        (_focusedPane == 1 ? _settingsFocusNode2 : _settingsFocusNode)
            .requestFocus();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  @override
  void dispose() {
    _settingsFocusNode.dispose();
    _settingsFocusNode2.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final host = _host;

    return PopScope(
      canPop: _focusedPane == null && !_showOverlay,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_focusedPane != null) {
          setState(() {
            _focusedPane = null;
            _showOverlay = true;
          });
        } else {
          setState(() => _showOverlay = false);
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            Focus(
              autofocus: !_showWalkthrough,
              onKeyEvent: _handleKeyEvent,
              child: host == null || host.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'Tap the gear icon to configure your printer.',
                          style:
                              TextStyle(color: Colors.white70, fontSize: 16),
                        ),
                      ),
                    )
                  : _splitMode
                      ? _buildSplitView(host)
                      : _buildSingleView(host),
            ),
            if (_showWalkthrough)
              Positioned.fill(
                child: WalkthroughOverlay(onDone: _dismissWalkthrough),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSingleView(String host) {
    final isSecond = _focusedPane == 1;
    final activeHost = isSecond ? (_host2 ?? host) : host;
    final activePort = isSecond ? _port2 : _port;
    final focusNode = isSecond ? _settingsFocusNode2 : _settingsFocusNode;

    return PrinterPane(
      key: ValueKey('pane_${_focusedPane ?? 0}'),
      host: activeHost,
      port: activePort,
      compact: false,
      showOverlay: _showOverlay,
      showConsole: _showConsole,
      eStopEnabled: _eStopEnabled,
      eStopHoldMs: _eStopHoldMs,
      onSettings: _openSettings,
      settingsFocusNode: focusNode,
      onToggleOverlay: () => setState(() => _showOverlay = !_showOverlay),
      onBackToSplit: _focusedPane != null
          ? () => setState(() {
                _focusedPane = null;
                _showOverlay = true;
              })
          : null,
    );
  }

  Widget _buildSplitView(String host) {
    final host2 = _host2 ?? '';
    return Row(
      children: [
        Expanded(child: _buildPaneWrapper(0, host, _port, _settingsFocusNode)),
        Container(width: 1, color: Colors.white12),
        Expanded(child: _buildPaneWrapper(1, host2, _port2, _settingsFocusNode2)),
      ],
    );
  }

  Widget _buildPaneWrapper(
      int index, String host, int port, FocusNode focusNode) {
    return PrinterPane(
      key: ValueKey('split_$index'),
      host: host,
      port: port,
      compact: true,
      showOverlay: true,
      showConsole: false,
      onSettings: _openSettings,
      settingsFocusNode: focusNode,
      onTap: () => setState(() {
        _focusedPane = index;
        _showOverlay = true;
      }),
    );
  }
}
