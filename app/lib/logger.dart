import 'dart:developer' as dev;

class Log {
  final String tag;
  const Log(this.tag);

  void info(String message) {
    dev.log(message, name: tag);
  }

  void error(String message, Object error, [StackTrace? stackTrace]) {
    dev.log(message, name: tag, error: error, stackTrace: stackTrace);
  }
}
