import 'dart:async';

class StopwatchManager {
  static final StopwatchManager _instance = StopwatchManager._internal();

  factory StopwatchManager() {
    return _instance;
  }

  StopwatchManager._internal();

  final Stopwatch _stopwatch = Stopwatch();
  Duration _initialElapsedTime = Duration.zero;
  Duration _savedElapsedTime = Duration.zero;

  Stopwatch get stopwatch => _stopwatch;

  // --- INI YANG DITAMBAHKAN AGAR ERROR HILANG ---
  bool get isRunning => _stopwatch.isRunning;
  // ----------------------------------------------

  /// Starts or resumes the stopwatch.
  void startStopwatch({Duration initialTime = Duration.zero}) {
    if (!_stopwatch.isRunning) {
      if (_savedElapsedTime != Duration.zero) {
        _initialElapsedTime = _savedElapsedTime;
        _savedElapsedTime = Duration.zero;
      } else {
        _initialElapsedTime = initialTime;
      }
      _stopwatch.start(); // Hapus .reset() disini agar offset tidak hilang jika resume
    } else {
       // Jika sudah jalan, tidak perlu di-reset atau di-start ulang
    }
  }

  /// Stops the stopwatch and saves the elapsed time.
  void stopStopwatch() {
    _stopwatch.stop();
    _savedElapsedTime = _stopwatch.elapsed + _initialElapsedTime;
  }

  /// Resets the stopwatch to zero.
  void resetStopwatch() {
    _stopwatch.reset();
    _initialElapsedTime = Duration.zero;
    _savedElapsedTime = Duration.zero;
  }

  /// Gets the total elapsed time of the stopwatch.
  Duration get elapsed {
    return _stopwatch.elapsed + _initialElapsedTime;
  }
}