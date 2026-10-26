import 'dart:js_interop';

@JS('Worker')
extension type OcrJSWorker._(JSObject _) implements JSObject {
  external factory OcrJSWorker(JSString scriptUrl);
  external void postMessage(JSAny? message, [JSArray<JSObject>? transfer]);
  external void terminate();
  external set onmessage(JSFunction? handler);
  external set onerror(JSFunction? handler);
}

@JS('Blob')
extension type OcrJSBlob._(JSObject _) implements JSObject {
  external factory OcrJSBlob(JSArray<JSAny?> blobParts, [JSObject? options]);
}

@JS('URL.createObjectURL')
external JSString createOcrObjectUrl(OcrJSBlob blob);

@JS('URL.revokeObjectURL')
external void revokeOcrObjectUrl(JSString url);

@JS('MessageEvent')
extension type OcrJSMessageEvent._(JSObject _) implements JSObject {
  external JSAny? get data;
}
