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
  final _hostFocus = FocusNode();
  final _portFocus = FocusNode();
  final _saveFocus = FocusNode();
  bool _loaded = false;
  bool _keepScreenOn = true;
  bool _showConsole = false;

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
    setState(() {
      _keepScreenOn = prefs.getBool('keep_screen_on') ?? true;
      _showConsole = prefs.getBool('show_console') ?? false;
      _loaded = true;
    });
  }

  Future<void> _save() async {
    final port = int.tryParse(_portController.text.trim()) ?? 7125;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('moonraker_host', _hostController.text.trim());
    await prefs.setInt('moonraker_port', port);
    await prefs.setBool('keep_screen_on', _keepScreenOn);
    await prefs.setBool('show_console', _showConsole);
    await WakelockPlus.toggle(enable: _keepScreenOn);
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
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
                  const SizedBox(height: 32),
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
