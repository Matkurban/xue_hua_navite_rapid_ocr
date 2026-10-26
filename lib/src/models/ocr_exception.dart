/// Exception thrown by `XueHuaNaviteRapidOcr` when initialization or inference fails.
class XueHuaOcrException implements Exception {
  const XueHuaOcrException(this.message, {this.code});

  final String message;
  final int? code;

  @override
  String toString() =>
      'XueHuaOcrException(${code != null ? 'code: $code, ' : ''}message: $message)';
}
