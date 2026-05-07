import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_mjpeg/flutter_mjpeg.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/printer_state.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../services/moonraker_service.dart';
import '../widgets/info_overlay.dart';
import 'settings_screen.dart';

class ViewerScreen extends StatefulWidget {
  const ViewerScreen({super.key});

  @override
  State<ViewerScreen> createState() => _ViewerScreenState();
}

class _ViewerScreenState extends State<ViewerScreen> {
  String? _moonrakerHost;
  int _moonrakerPort = 7125;
  String? _webcamUrl;
  String? _thumbnailUrl;
  String? _lastThumbnailFilename;
  MoonrakerService? _service;
  PrinterState _state = PrinterState.idle();
  bool _connected = false;
  bool _showOverlay = true;
  final TransformationController _transform = TransformationController();
  final FocusNode _settingsFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadSettings());
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final host = prefs.getString('moonraker_host');
    final port = prefs.getInt('moonraker_port') ?? 7125;
    setState(() {
      _moonrakerHost = host;
      _moonrakerPort = port;
    });
    final keepScreenOn = prefs.getBool('keep_screen_on') ?? true;
    await WakelockPlus.toggle(enable: keepScreenOn);
    if (host == null || host.isEmpty) {
      _openSettings();
    } else {
      _connect();
    }
  }

  void _connect() {
    _service?.dispose();
    final host = _moonrakerHost;
    if (host == null || host.isEmpty) return;
    final svc = MoonrakerService(host: host, port: _moonrakerPort);
    svc.stateStream.listen((s) {
      if (!mounted) return;
      setState(() => _state = s);
      _updateThumbnail(s.filename);
    });
    svc.connectionStream.listen((c) {
      if (mounted) setState(() => _connected = c);
    });
    svc.connect();
    _service = svc;
    _fetchWebcamUrl();
  }

  void _updateThumbnail(String? filename) {
    if (filename == null || filename == _lastThumbnailFilename) return;
    _lastThumbnailFilename = filename;
    _fetchThumbnail(filename);
  }

  Future<void> _fetchThumbnail(String filename) async {
    final host = _moonrakerHost;
    if (host == null || host.isEmpty) return;
    try {
      final encoded = Uri.encodeComponent(filename);
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 5);
      final request = await client.getUrl(Uri.parse(
          'http://$host:$_moonrakerPort/server/files/metadata?filename=$encoded'));
      final response = await request.close();
      if (response.statusCode != 200) return;
      final body = await response.transform(utf8.decoder).join();
      client.close();
      final data = jsonDecode(body) as Map<String, dynamic>;
      final thumbnails =
          ((data['result'] as Map?)?['thumbnails'] as List?) ?? [];
      if (thumbnails.isEmpty) return;
      // Pick the largest thumbnail available
      thumbnails.sort((a, b) =>
          ((b['width'] as num?) ?? 0).compareTo((a['width'] as num?) ?? 0));
      final relativePath =
          (thumbnails.first['relative_path'] as String? ?? '').trim();
      if (relativePath.isEmpty) return;
      final dir = filename.contains('/')
          ? filename.substring(0, filename.lastIndexOf('/') + 1)
          : '';
      final url =
          'http://$host:$_moonrakerPort/server/files/gcodes/$dir$relativePath';
      if (mounted) setState(() => _thumbnailUrl = url);
    } catch (_) {
      // thumbnail stays null — placeholder shown
    }
  }

  Future<void> _fetchWebcamUrl() async {
    final host = _moonrakerHost;
    if (host == null || host.isEmpty) return;
    try {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 5);
      final request = await client.getUrl(
        Uri.parse('http://$host:$_moonrakerPort/server/webcams/list'),
      );
      final response = await request.close();
      if (response.statusCode != 200) return;
      final body = await response.transform(utf8.decoder).join();
      client.close();
      final data = jsonDecode(body) as Map<String, dynamic>;
      final webcams =
          ((data['result'] as Map?)?['webcams'] as List?) ?? [];
      for (final wc in webcams) {
        if (wc is! Map) continue;
        if (wc['enabled'] == false) continue;
        final streamUrl = (wc['stream_url'] as String? ?? '').trim();
        if (streamUrl.isEmpty) continue;
        if (streamUrl.startsWith('http')) {
          if (mounted) setState(() => _webcamUrl = streamUrl);
          return;
        }
        // Relative URL: resolve against port 4408 (Creality K1/K1C nginx proxy)
        if (mounted) {
          setState(() => _webcamUrl = 'http://$host:4408$streamUrl');
        }
        return;
      }
    } catch (_) {
      // _webcamUrl stays null
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
        _moonrakerHost = prefs.getString('moonraker_host');
        _moonrakerPort = prefs.getInt('moonraker_port') ?? 7125;
        _webcamUrl = null;
        _thumbnailUrl = null;
        _lastThumbnailFilename = null;
      });
      _transform.value = Matrix4.identity();
      _connect();
    }
  }

  @override
  void dispose() {
    _service?.dispose();
    _transform.dispose();
    _settingsFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final host = _moonrakerHost;
    final stream = _webcamUrl;
    return PopScope(
      canPop: !_showOverlay,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _showOverlay = false);
      },
      child: Scaffold(
      backgroundColor: Colors.black,
      body: Focus(
        autofocus: true,
        onKeyEvent: (node, event) {
          if (event is! KeyDownEvent) return KeyEventResult.ignored;
          final key = event.logicalKey;
          // D-pad center / Enter / select → toggle overlay (same as screen tap)
          if (key == LogicalKeyboardKey.select ||
              key == LogicalKeyboardKey.enter ||
              key == LogicalKeyboardKey.gameButtonA) {
            // Show overlay if hidden, then move focus to the settings cog so
            // the user can press select a second time to open settings.
            if (!_showOverlay) setState(() => _showOverlay = true);
            _settingsFocusNode.requestFocus();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: GestureDetector(
        onTap: () => setState(() => _showOverlay = !_showOverlay),
        onDoubleTap: () => _transform.value = Matrix4.identity(),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (host == null || host.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'Tap the gear icon to configure your printer.',
                    style: TextStyle(color: Colors.white70, fontSize: 16),
                  ),
                ),
              )
            else if (stream == null)
              const Center(child: CircularProgressIndicator())
            else
              InteractiveViewer(
                transformationController: _transform,
                minScale: 1.0,
                maxScale: 6.0,
                clipBehavior: Clip.hardEdge,
                child: SizedBox.expand(
                  child: Mjpeg(
                    stream: stream,
                    isLive: true,
                    fit: BoxFit.contain,
                    timeout: const Duration(seconds: 10),
                    error: (context, error, stack) => Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          'Camera feed unavailable\n$error',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              color: Colors.redAccent, fontSize: 14),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            if (_showOverlay)
              InfoOverlay(
                state: _state,
                connected: _connected,
                thumbnailUrl: _thumbnailUrl,
                onSettings: _openSettings,
                settingsFocusNode: _settingsFocusNode,
              ),
          ],
        ),
        ),  // GestureDetector
      ),    // Focus
      ),    // Scaffold
    );      // PopScope
  }
}
