import 'dart:isolate' show TransferableTypedData;

import '../models/ocr_models.dart';

sealed class FfiWorkerCommand {
  const FfiWorkerCommand();
}

final class FfiInitCommand extends FfiWorkerCommand {
  const FfiInitCommand({
    required this.detPath,
    required this.clsPath,
    required this.recPath,
    required this.keysPath,
    required this.detBytes,
    required this.clsBytes,
    required this.recBytes,
    required this.keysText,
    required this.numThreads,
    required this.executionProvider,
    required this.executionProviderName,
    required this.enableHardwareAcceleration,
  });

  final String? detPath;
  final String? clsPath;
  final String? recPath;
  final String? keysPath;
  final TransferableTypedData? detBytes;
  final TransferableTypedData? clsBytes;
  final TransferableTypedData? recBytes;
  final String? keysText;
  final int numThreads;
  final int executionProvider;
  final String executionProviderName;
  final bool enableHardwareAcceleration;
}

final class FfiRecognizeFileCommand extends FfiWorkerCommand {
  const FfiRecognizeFileCommand({
    required this.filePath,
    required this.options,
  });

  final String filePath;
  final OcrRecognizeOptions options;
}

final class FfiRecognizeBytesCommand extends FfiWorkerCommand {
  const FfiRecognizeBytesCommand({
    required this.transferableBytes,
    required this.options,
  });

  final TransferableTypedData transferableBytes;
  final OcrRecognizeOptions options;
}

final class FfiRecognizeRawPixelsCommand extends FfiWorkerCommand {
  const FfiRecognizeRawPixelsCommand({
    required this.transferablePixels,
    required this.width,
    required this.height,
    required this.rowStride,
    required this.pixelFormat,
    required this.options,
  });

  final TransferableTypedData transferablePixels;
  final int width;
  final int height;
  final int rowStride;
  final int pixelFormat;
  final OcrRecognizeOptions options;
}

final class FfiDisposeCommand extends FfiWorkerCommand {
  const FfiDisposeCommand();
}

final class FfiWorkerEnvelope {
  const FfiWorkerEnvelope(this.requestId, this.command);

  final int requestId;
  final FfiWorkerCommand command;
}

final class FfiWorkerResponse {
  const FfiWorkerResponse({
    required this.requestId,
    this.payload,
    this.errorMessage,
    this.errorCode,
  });

  final int requestId;
  final dynamic payload;
  final String? errorMessage;
  final int? errorCode;
}
