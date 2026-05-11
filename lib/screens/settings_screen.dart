import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _hostController = TextEditingController();
  final _portController = TextEditingController();
  final _host2Controller = TextEditingController();
  final _port2Controller = TextEditingController();

  // One FocusNode per interactive element, in top-to-bottom order.
  final _hostFocus = FocusNode();
  final _portFocus = FocusNode();
  final _keepScreenOnFocus = FocusNode();
  final _showConsoleFocus = FocusNode();
  final _secondPrinterFocus = FocusNode();
  final _host2Focus = FocusNode();
  final _port2Focus = FocusNode();
  final _eStopFocus = FocusNode();
  final _holdDurationFocus = FocusNode();
  final _saveFocus = FocusNode();

  bool _loaded = false;
  bool _keepScreenOn = true;
  bool _showConsole = false;
  bool _secondPrinterEnabled = false;
  bool _eStopEnabled = true;
  int _eStopHoldMs = 1500;

  // Ordered list of currently visible/reachable nodes (state-dependent).
  List<FocusNode> get _navOrder => [
        _hostFocus,
        _portFocus,
        _keepScreenOnFocus,
        _showConsoleFocus,
        _secondPrinterFocus,
        if (_secondPrinterEnabled) ...[_host2Focus, _port2Focus],
        _eStopFocus,
        if (_eStopEnabled) _holdDurationFocus,
        _saveFocus,
      ];

  @override
  void initState() {
    super.initState();
    _setupNav();
    _load();
  }

  // Wire up arrow-key navigation and D-pad select on every focusable node.
  void _setupNav() {
    void nav(
      FocusNode node, {
      VoidCallback? onSelect,
    }) {
      node.onKeyEvent = (_, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final key = event.logicalKey;

        if (key == LogicalKeyboardKey.arrowDown ||
            key == LogicalKeyboardKey.arrowUp) {
          final order = _navOrder;
          final idx = order.indexOf(node);
          if (idx == -1) return KeyEventResult.ignored;

          final next = key == LogicalKeyboardKey.arrowDown
              ? (idx < order.length - 1 ? order[idx + 1] : null)
              : (idx > 0 ? order[idx - 1] : null);

          if (next != null) {
            next.requestFocus();
            _scrollTo(next);
          }
          // Consume even at boundaries to stop focus leaking to the AppBar.
          return KeyEventResult.handled;
        }

        // D-pad center (select) toggles switches; Enter/Space are handled
        // natively by SwitchListTile's InkWell.
        if (onSelect != null && key == LogicalKeyboardKey.select) {
          onSelect();
          return KeyEventResult.handled;
        }

        return KeyEventResult.ignored;
      };
    }

    nav(_hostFocus);
    nav(_portFocus);
    nav(_keepScreenOnFocus,
        onSelect: () => setState(() => _keepScreenOn = !_keepScreenOn));
    nav(_showConsoleFocus,
        onSelect: () => setState(() => _showConsole = !_showConsole));
    nav(_secondPrinterFocus,
        onSelect: () =>
            setState(() => _secondPrinterEnabled = !_secondPrinterEnabled));
    nav(_host2Focus);
    nav(_port2Focus);
    nav(_eStopFocus,
        onSelect: () => setState(() => _eStopEnabled = !_eStopEnabled));
    nav(_holdDurationFocus);
    nav(_saveFocus);
  }

  void _scrollTo(FocusNode node) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = node.context;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    _hostController.text = prefs.getString('moonraker_host') ?? '';
    _portController.text = (prefs.getInt('moonraker_port') ?? 7125).toString();
    _host2Controller.text = prefs.getString('moonraker_host_2') ?? '';
    _port2Controller.text =
        (prefs.getInt('moonraker_port_2') ?? 7125).toString();
    setState(() {
      _keepScreenOn = prefs.getBool('keep_screen_on') ?? true;
      _showConsole = prefs.getBool('show_console') ?? false;
      _secondPrinterEnabled =
          prefs.getBool('second_printer_enabled') ?? false;
      _eStopEnabled = prefs.getBool('estop_enabled') ?? true;
      _eStopHoldMs = prefs.getInt('estop_hold_ms') ?? 1500;
      _loaded = true;
    });
  }

  Future<void> _save() async {
    final port = int.tryParse(_portController.text.trim()) ?? 7125;
    final port2 = int.tryParse(_port2Controller.text.trim()) ?? 7125;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('moonraker_host', _hostController.text.trim());
    await prefs.setInt('moonraker_port', port);
    await prefs.setBool('keep_screen_on', _keepScreenOn);
    await prefs.setBool('show_console', _showConsole);
    await prefs.setBool('second_printer_enabled', _secondPrinterEnabled);
    await prefs.setString('moonraker_host_2', _host2Controller.text.trim());
    await prefs.setInt('moonraker_port_2', port2);
    await prefs.setBool('estop_enabled', _eStopEnabled);
    await prefs.setInt('estop_hold_ms', _eStopHoldMs);
    await WakelockPlus.toggle(enable: _keepScreenOn);
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    _host2Controller.dispose();
    _port2Controller.dispose();
    _hostFocus.dispose();
    _portFocus.dispose();
    _keepScreenOnFocus.dispose();
    _showConsoleFocus.dispose();
    _secondPrinterFocus.dispose();
    _host2Focus.dispose();
    _port2Focus.dispose();
    _eStopFocus.dispose();
    _holdDurationFocus.dispose();
    _saveFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: Colors.black,
      ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── Printer 1 ────────────────────────────────────────
                  const Text('Moonraker host',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  const Text(
                    'IP address or hostname of your printer.',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _hostController,
                    focusNode: _hostFocus,
                    autocorrect: false,
                    keyboardType: TextInputType.url,
                    onEditingComplete: () => _portFocus.requestFocus(),
                    decoration: const InputDecoration(
                      hintText: '192.168.1.50',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text('Moonraker port',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  const Text(
                    'Default is 7125. The camera URL is fetched automatically from Moonraker.',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _portController,
                    focusNode: _portFocus,
                    autocorrect: false,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onEditingComplete: () =>
                        _keepScreenOnFocus.requestFocus(),
                    decoration: const InputDecoration(
                      hintText: '7125',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // ── Toggles ──────────────────────────────────────────
                  SwitchListTile(
                    focusNode: _keepScreenOnFocus,
                    value: _keepScreenOn,
                    onChanged: (v) => setState(() => _keepScreenOn = v),
                    title: const Text('Keep screen on',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
                    subtitle: const Text(
                      'Prevent the screen from turning off while the app is open.',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                    contentPadding: EdgeInsets.zero,
                  ),
                  SwitchListTile(
                    focusNode: _showConsoleFocus,
                    value: _showConsole,
                    onChanged: (v) => setState(() => _showConsole = v),
                    title: const Text('Show console overlay',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
                    subtitle: const Text(
                      'Show the last 15 Klipper messages in the bottom-right corner.',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                    contentPadding: EdgeInsets.zero,
                  ),
                  SwitchListTile(
                    focusNode: _secondPrinterFocus,
                    value: _secondPrinterEnabled,
                    onChanged: (v) =>
                        setState(() => _secondPrinterEnabled = v),
                    title: const Text('Enable second printer',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
                    subtitle: const Text(
                      'Show two printers side by side.',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                    contentPadding: EdgeInsets.zero,
                  ),

                  // ── Second printer fields (conditional) ──────────────
                  AnimatedCrossFade(
                    duration: const Duration(milliseconds: 200),
                    crossFadeState: _secondPrinterEnabled
                        ? CrossFadeState.showSecond
                        : CrossFadeState.showFirst,
                    firstChild: const SizedBox.shrink(),
                    secondChild: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Divider(color: Colors.white24),
                        const SizedBox(height: 8),
                        const Text('Second printer host',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        const Text(
                          'IP address or hostname of your second printer.',
                          style:
                              TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _host2Controller,
                          focusNode: _host2Focus,
                          autocorrect: false,
                          keyboardType: TextInputType.url,
                          onEditingComplete: () =>
                              _port2Focus.requestFocus(),
                          decoration: const InputDecoration(
                            hintText: '192.168.1.51',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 24),
                        const Text('Second printer port',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _port2Controller,
                          focusNode: _port2Focus,
                          autocorrect: false,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly
                          ],
                          onEditingComplete: () => _eStopFocus.requestFocus(),
                          decoration: const InputDecoration(
                            hintText: '7125',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),

                  // ── Safety ───────────────────────────────────────────
                  const Divider(color: Colors.white24),
                  const SizedBox(height: 8),
                  const Text(
                    'Safety',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.white38,
                        letterSpacing: 0.8),
                  ),
                  SwitchListTile(
                    focusNode: _eStopFocus,
                    value: _eStopEnabled,
                    onChanged: (v) => setState(() => _eStopEnabled = v),
                    title: const Text('Emergency Stop',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
                    subtitle: const Text(
                      'Show button on camera view.',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                    contentPadding: EdgeInsets.zero,
                  ),
                  AnimatedCrossFade(
                    duration: const Duration(milliseconds: 200),
                    crossFadeState: _eStopEnabled
                        ? CrossFadeState.showSecond
                        : CrossFadeState.showFirst,
                    firstChild: const SizedBox.shrink(),
                    secondChild: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Hold Duration',
                                style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold)),
                            Text(
                              '${(_eStopHoldMs / 1000).toStringAsFixed(1)}s',
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 14),
                            ),
                          ],
                        ),
                        Slider(
                          focusNode: _holdDurationFocus,
                          value: _eStopHoldMs.toDouble(),
                          min: 800,
                          max: 3000,
                          divisions: 22,
                          onChanged: (v) =>
                              setState(() => _eStopHoldMs = v.round()),
                        ),
                        const Text(
                          'Press & hold the E-stop button this long to trigger confirmation. A dialog will still ask before sending the command.',
                          style: TextStyle(
                              color: Colors.white38, fontSize: 12),
                        ),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),

                  // ── Save ─────────────────────────────────────────────
                  const SizedBox(height: 24),
                  ElevatedButton(
                    focusNode: _saveFocus,
                    onPressed: _save,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text('Save & connect',
                          style: TextStyle(fontSize: 16)),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
