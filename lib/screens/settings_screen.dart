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
  final _hostFocus = FocusNode();
  final _portFocus = FocusNode();
  final _saveFocus = FocusNode();
  bool _loaded = false;
  bool _keepScreenOn = true;
  bool _showConsole = false;
  bool _secondPrinterEnabled = false;
  bool _eStopEnabled = true;
  int _eStopHoldMs = 1500;

  @override
  void initState() {
    super.initState();
    // Arrow-key D-pad navigation between fields
    _hostFocus.onKeyEvent = (node, event) {
      if (event is KeyDownEvent &&
          event.logicalKey == LogicalKeyboardKey.arrowDown) {
        _portFocus.requestFocus();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    };
    _portFocus.onKeyEvent = (node, event) {
      if (event is KeyDownEvent) {
        if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
          _hostFocus.requestFocus();
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
          _saveFocus.requestFocus();
          return KeyEventResult.handled;
        }
        // Note: wakelock toggle is handled by SwitchListTile itself
      }
      return KeyEventResult.ignored;
    };
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    _hostController.text = prefs.getString('moonraker_host') ?? '';
    _portController.text = (prefs.getInt('moonraker_port') ?? 7125).toString();
    _host2Controller.text = prefs.getString('moonraker_host_2') ?? '';
    _port2Controller.text = (prefs.getInt('moonraker_port_2') ?? 7125).toString();
    setState(() {
      _keepScreenOn = prefs.getBool('keep_screen_on') ?? true;
      _showConsole = prefs.getBool('show_console') ?? false;
      _secondPrinterEnabled = prefs.getBool('second_printer_enabled') ?? false;
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
                    onEditingComplete: () => _saveFocus.requestFocus(),
                    decoration: const InputDecoration(
                      hintText: '7125',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 24),
                  SwitchListTile(
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
                    value: _secondPrinterEnabled,
                    onChanged: (v) => setState(() => _secondPrinterEnabled = v),
                    title: const Text('Enable second printer',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
                    subtitle: const Text(
                      'Show two printers side by side.',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                    contentPadding: EdgeInsets.zero,
                  ),
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
                          style: TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _host2Controller,
                          autocorrect: false,
                          keyboardType: TextInputType.url,
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
                          autocorrect: false,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly
                          ],
                          decoration: const InputDecoration(
                            hintText: '7125',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
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
                          value: _eStopHoldMs.toDouble(),
                          min: 800,
                          max: 3000,
                          divisions: 22,
                          onChanged: (v) =>
                              setState(() => _eStopHoldMs = v.round()),
                        ),
                        const Text(
                          'Press & hold the E-stop button this long to trigger confirmation. A dialog will still ask before sending the command.',
                          style:
                              TextStyle(color: Colors.white38, fontSize: 12),
                        ),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
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
