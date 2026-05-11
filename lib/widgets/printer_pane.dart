import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_mjpeg/flutter_mjpeg.dart';
import '../models/printer_state.dart';
import '../services/moonraker_service.dart';
import 'estop_button.dart';
import 'info_overlay.dart';

class PrinterPane extends StatefulWidget {
  final String host;
  final int port;
  final bool compact;
  final bool showOverlay;
  final bool showConsole;
  final bool eStopEnabled;
  final int eStopHoldMs;
  final VoidCallback onSettings;
  final FocusNode? settingsFocusNode;
  final VoidCallback? onTap;
  final VoidCallback? onToggleOverlay;
  final VoidCallback? onBackToSplit;

  const PrinterPane({
    super.key,
    required this.host,
    required this.port,
    required this.compact,
    required this.showOverlay,
    required this.showConsole,
    this.eStopEnabled = true,
    this.eStopHoldMs = 1500,
    required this.onSettings,
    this.settingsFocusNode,
    this.onTap,
    this.onToggleOverlay,
    this.onBackToSplit,
  });

  @override
  State<PrinterPane> createState() => _PrinterPaneState();
}

class _PrinterPaneState extends State<PrinterPane> {
  MoonrakerService? _service;
  PrinterState _state = PrinterState.idle();
  bool _connected = false;
  String? _webcamUrl;
  String? _thumbnailUrl;
  String? _lastThumbnailFilename;
  final List<String> _consoleLines = [];
  final TransformationController _transform = TransformationController();
  bool _eStopDialogOpen = false;

  @override
  void initState() {
    super.initState();
    _connect();
  }

  @override
  void didUpdateWidget(PrinterPane old) {
    super.didUpdateWidget(old);
    if (old.host != widget.host || old.port != widget.port) {
      setState(() {
        _webcamUrl = null;
        _thumbnailUrl = null;
        _lastThumbnailFilename = null;
        _consoleLines.clear();
      });
      _transform.value = Matrix4.identity();
      _connect();
    }
  }

  void _connect() {
    _service?.dispose();
    final svc = MoonrakerService(host: widget.host, port: widget.port);
    svc.stateStream.listen((s) {
      if (!mounted) return;
      setState(() => _state = s);
      _updateThumbnail(s.filename);
    });
    svc.connectionStream.listen((c) {
      if (mounted) setState(() => _connected = c);
    });
    svc.consoleStream.listen((line) {
      if (!mounted) return;
      final now = DateTime.now();
      final ts =
          '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
      setState(() {
        _consoleLines.add('$ts  $line');
        if (_consoleLines.length > 15) _consoleLines.removeAt(0);
      });
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
    try {
      final encoded = Uri.encodeComponent(filename);
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
      final request = await client.getUrl(Uri.parse(
          'http://${widget.host}:${widget.port}/server/files/metadata?filename=$encoded'));
      final response = await request.close();
      if (response.statusCode != 200) return;
      final body = await response.transform(utf8.decoder).join();
      client.close();
      final data = jsonDecode(body) as Map<String, dynamic>;
      final thumbnails = ((data['result'] as Map?)?['thumbnails'] as List?) ?? [];
      if (thumbnails.isEmpty) return;
      thumbnails.sort((a, b) =>
          ((b['width'] as num?) ?? 0).compareTo((a['width'] as num?) ?? 0));
      final relativePath = (thumbnails.first['relative_path'] as String? ?? '').trim();
      if (relativePath.isEmpty) return;
      final dir = filename.contains('/')
          ? filename.substring(0, filename.lastIndexOf('/') + 1)
          : '';
      final url =
          'http://${widget.host}:${widget.port}/server/files/gcodes/$dir$relativePath';
      if (mounted) setState(() => _thumbnailUrl = url);
    } catch (_) {}
  }

  Future<void> _fetchWebcamUrl() async {
    try {
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
      final request = await client.getUrl(
        Uri.parse('http://${widget.host}:${widget.port}/server/webcams/list'),
      );
      final response = await request.close();
      if (response.statusCode != 200) return;
      final body = await response.transform(utf8.decoder).join();
      client.close();
      final data = jsonDecode(body) as Map<String, dynamic>;
      final webcams = ((data['result'] as Map?)?['webcams'] as List?) ?? [];
      for (final wc in webcams) {
        if (wc is! Map) continue;
        if (wc['enabled'] == false) continue;
        final streamUrl = (wc['stream_url'] as String? ?? '').trim();
        if (streamUrl.isEmpty) continue;
        if (streamUrl.startsWith('http')) {
          if (mounted) setState(() => _webcamUrl = streamUrl);
          return;
        }
        if (mounted) {
          setState(() => _webcamUrl = 'http://${widget.host}:4408$streamUrl');
        }
        return;
      }
    } catch (_) {}
  }

  void _handleEStopArmed() {
    if (_eStopDialogOpen || !mounted) return;
    setState(() => _eStopDialogOpen = true);
    showDialog<void>(
      context: context,
      barrierColor: Colors.transparent,
      builder: (ctx) => Dialog.fullscreen(
        backgroundColor: Colors.transparent,
        child: EStopConfirmDialog(
          onConfirm: () {
            Navigator.of(ctx).pop();
            _sendEStop();
          },
          onCancel: () => Navigator.of(ctx).pop(),
        ),
      ),
    ).then((_) {
      if (mounted) setState(() => _eStopDialogOpen = false);
    });
  }

  Future<void> _sendEStop() async {
    try {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 5);
      final request = await client.postUrl(
        Uri.parse(
            'http://${widget.host}:${widget.port}/printer/emergency_stop'),
      );
      final response = await request.close();
      await response.drain<void>();
      client.close();
      if (mounted) {
        showEStopToast(
          context,
          error: response.statusCode < 300
              ? null
              : 'HTTP ${response.statusCode}',
        );
      }
    } catch (e) {
      if (mounted) showEStopToast(context, error: e.toString());
    }
  }

  @override
  void dispose() {
    _service?.dispose();
    _transform.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final stream = _webcamUrl;

    if (widget.compact) {
      return GestureDetector(
        onTap: widget.onTap,
        child: Stack(
          fit: StackFit.expand,
          children: [
            _buildFeed(stream),
            InfoOverlay(
              state: _state,
              connected: _connected,
              onSettings: widget.onSettings,
              settingsFocusNode: widget.settingsFocusNode,
              compact: true,
            ),
          ],
        ),
      );
    }

    return GestureDetector(
      onTap: widget.onToggleOverlay,
      onDoubleTap: () => _transform.value = Matrix4.identity(),
      child: Stack(
        fit: StackFit.expand,
        children: [
          stream == null
              ? const Center(child: CircularProgressIndicator())
              : InteractiveViewer(
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
          if (widget.showOverlay)
            InfoOverlay(
              state: _state,
              connected: _connected,
              thumbnailUrl: _thumbnailUrl,
              onSettings: widget.onSettings,
              settingsFocusNode: widget.settingsFocusNode,
              consoleLines: widget.showConsole ? _consoleLines : null,
              onEStopArmed:
                  widget.eStopEnabled ? _handleEStopArmed : null,
              eStopHoldMs: widget.eStopHoldMs,
              onBackToSplit: widget.onBackToSplit,
            ),
        ],
      ),
    );
  }

  Widget _buildFeed(String? stream) {
    if (stream == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return Mjpeg(
      stream: stream,
      isLive: true,
      fit: BoxFit.contain,
      timeout: const Duration(seconds: 10),
      error: (_, __, ___) => const Center(
        child: Icon(Icons.videocam_off, color: Colors.white38, size: 32),
      ),
    );
  }
}
