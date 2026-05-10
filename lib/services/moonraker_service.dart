import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/printer_state.dart';

class MoonrakerService {
  final String host;
  final int port;

  WebSocketChannel? _channel;
  int _msgId = 1;
  Timer? _reconnectTimer;
  Timer? _pingTimer;
  bool _disposed = false;

  final _stateController = StreamController<PrinterState>.broadcast();
  final _connectionController = StreamController<bool>.broadcast();
  final _consoleController = StreamController<String>.broadcast();
  final Map<String, dynamic> _accumulated = {};

  Stream<PrinterState> get stateStream => _stateController.stream;
  Stream<bool> get connectionStream => _connectionController.stream;
  Stream<String> get consoleStream => _consoleController.stream;

  MoonrakerService({required this.host, this.port = 7125});

  String get _wsUrl => 'ws://$host:$port/websocket';

  static const _objects = {
    'print_stats': null,
    'virtual_sdcard': null,
    'display_status': null,
    'extruder': null,
    'heater_bed': null,
    'gcode_move': null,
  };

  void connect() {
    if (_disposed) return;
    try {
      _channel = WebSocketChannel.connect(Uri.parse(_wsUrl));
      _channel!.ready.then((_) {
        if (_disposed) return;
        _connectionController.add(true);
        _subscribe();
        _queryOnce();
        _pingTimer?.cancel();
        _pingTimer = Timer.periodic(
          const Duration(seconds: 20),
          (_) => _queryOnce(),
        );
      }).catchError((_) { _scheduleReconnect(); });
      _channel!.stream.listen(
        _onMessage,
        onError: (_) => _scheduleReconnect(),
        onDone: _scheduleReconnect,
        cancelOnError: true,
      );
    } catch (_) {
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (_disposed) return;
    _connectionController.add(false);
    _pingTimer?.cancel();
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 3), connect);
  }

  void _subscribe() {
    _send({
      'jsonrpc': '2.0',
      'method': 'printer.objects.subscribe',
      'params': {'objects': _objects},
      'id': _msgId++,
    });
  }

  void _queryOnce() {
    _send({
      'jsonrpc': '2.0',
      'method': 'printer.objects.query',
      'params': {'objects': _objects},
      'id': _msgId++,
    });
  }

  void _send(Map<String, dynamic> msg) {
    try {
      _channel?.sink.add(jsonEncode(msg));
    } catch (_) {
      _scheduleReconnect();
    }
  }

  void _onMessage(dynamic raw) {
    try {
      final data = jsonDecode(raw as String) as Map<String, dynamic>;
      Map<String, dynamic>? status;

      if (data.containsKey('result')) {
        final result = data['result'];
        if (result is Map && result['status'] is Map) {
          status = (result['status'] as Map).cast<String, dynamic>();
        }
      } else if (data['method'] == 'notify_gcode_response') {
        final params = data['params'];
        if (params is List) {
          for (final p in params) {
            if (p is String && p.isNotEmpty) _consoleController.add(p);
          }
        }
      } else if (data['method'] == 'notify_status_update') {
        final params = data['params'];
        if (params is List && params.isNotEmpty && params[0] is Map) {
          status = (params[0] as Map).cast<String, dynamic>();
        }
      }

      if (status != null) {
        _merge(status);
        _stateController.add(PrinterState.fromMoonraker(_accumulated));
      }
    } catch (_) {
      // ignore parse errors
    }
  }

  void _merge(Map<String, dynamic> incoming) {
    incoming.forEach((key, value) {
      if (value is Map) {
        final existing = _accumulated[key];
        if (existing is Map) {
          _accumulated[key] = {
            ...existing.cast<String, dynamic>(),
            ...value.cast<String, dynamic>(),
          };
        } else {
          _accumulated[key] = value.cast<String, dynamic>();
        }
      } else {
        _accumulated[key] = value;
      }
    });
  }

  void dispose() {
    _disposed = true;
    _reconnectTimer?.cancel();
    _pingTimer?.cancel();
    _channel?.sink.close();
    _stateController.close();
    _connectionController.close();
    _consoleController.close();
  }
}
