class PrinterState {
  final String state;
  final String? filename;
  final double progress;
  final double printDuration;
  final double totalDuration;
  final double? estimatedTotalTime;
  final double extruderTemp;
  final double extruderTarget;
  final double extruderPower;
  final double bedTemp;
  final double bedTarget;
  final double bedPower;
  final String? message;
  final double speed;        // mm/s
  final double speedFactor;  // multiplier (1.0 = 100%)
  final double extrudeFactor;
  final int? currentLayer;
  final int? totalLayer;

  PrinterState({
    required this.state,
    this.filename,
    required this.progress,
    required this.printDuration,
    required this.totalDuration,
    this.estimatedTotalTime,
    required this.extruderTemp,
    required this.extruderTarget,
    this.extruderPower = 0.0,
    required this.bedTemp,
    required this.bedTarget,
    this.bedPower = 0.0,
    this.message,
    this.speed = 0.0,
    this.speedFactor = 1.0,
    this.extrudeFactor = 1.0,
    this.currentLayer,
    this.totalLayer,
  });

  factory PrinterState.idle() => PrinterState(
        state: 'standby',
        progress: 0,
        printDuration: 0,
        totalDuration: 0,
        extruderTemp: 0,
        extruderTarget: 0,
        bedTemp: 0,
        bedTarget: 0,
      );

  factory PrinterState.fromMoonraker(Map<String, dynamic> status) {
    Map<String, dynamic> sub(String k) =>
        (status[k] as Map?)?.cast<String, dynamic>() ?? const {};

    final printStats = sub('print_stats');
    final virtualSdcard = sub('virtual_sdcard');
    final displayStatus = sub('display_status');
    final extruder = sub('extruder');
    final heaterBed = sub('heater_bed');
    final gcodeMove = sub('gcode_move');
    final info =
        (printStats['info'] as Map?)?.cast<String, dynamic>() ?? const {};

    final double progress =
        (displayStatus['progress'] as num?)?.toDouble() ??
            (virtualSdcard['progress'] as num?)?.toDouble() ??
            0.0;

    final printDuration =
        (printStats['print_duration'] as num?)?.toDouble() ?? 0.0;
    final totalDuration =
        (printStats['total_duration'] as num?)?.toDouble() ?? 0.0;

    double? estimated;
    if (progress > 0.005 && printDuration > 5) {
      estimated = printDuration / progress;
    }

    return PrinterState(
      state: (printStats['state'] as String?) ?? 'unknown',
      filename: (printStats['filename'] as String?)?.isEmpty == true
          ? null
          : printStats['filename'] as String?,
      progress: progress.clamp(0.0, 1.0),
      printDuration: printDuration,
      totalDuration: totalDuration,
      estimatedTotalTime: estimated,
      extruderTemp: (extruder['temperature'] as num?)?.toDouble() ?? 0.0,
      extruderTarget: (extruder['target'] as num?)?.toDouble() ?? 0.0,
      extruderPower: (extruder['power'] as num?)?.toDouble() ?? 0.0,
      bedTemp: (heaterBed['temperature'] as num?)?.toDouble() ?? 0.0,
      bedTarget: (heaterBed['target'] as num?)?.toDouble() ?? 0.0,
      bedPower: (heaterBed['power'] as num?)?.toDouble() ?? 0.0,
      message: displayStatus['message'] as String?,
      speed: (gcodeMove['speed'] as num?)?.toDouble() ?? 0.0,
      speedFactor: (gcodeMove['speed_factor'] as num?)?.toDouble() ?? 1.0,
      extrudeFactor: (gcodeMove['extrude_factor'] as num?)?.toDouble() ?? 1.0,
      currentLayer: (info['current_layer'] as num?)?.toInt(),
      totalLayer: (info['total_layer'] as num?)?.toInt(),
    );
  }

  String get formatElapsed => _fmt(printDuration);

  String get formatRemaining {
    if (estimatedTotalTime == null) return '--:--';
    final remaining = estimatedTotalTime! - printDuration;
    return remaining < 0 ? '00:00' : _fmt(remaining);
  }

  String get etaWallClock {
    if (estimatedTotalTime == null) return '';
    final remaining = estimatedTotalTime! - printDuration;
    if (remaining <= 0) return '';
    final eta = DateTime.now().add(Duration(seconds: remaining.round()));
    return '${eta.hour}:${eta.minute.toString().padLeft(2, '0')}';
  }

  static String _fmt(double seconds) {
    final d = Duration(seconds: seconds.round());
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    if (h > 0) return '${h}h ${m.toString().padLeft(2, '0')}m';
    return '${m}m ${s.toString().padLeft(2, '0')}s';
  }
}
