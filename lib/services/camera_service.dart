import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

class CameraService {
  static final CameraService _instance = CameraService._internal();
  factory CameraService() => _instance;
  CameraService._internal();

  CameraController? _controller;
  CameraDescription? _camera;
  bool _isStreaming = false;

  CameraController? get controller => _controller;

  Future<void> initialize({VoidCallback? onInitialized}) async {
    if (_controller != null && _controller!.value.isInitialized) {
      onInitialized?.call();
      return;
    }

    final cameras = await availableCameras();
    _camera = cameras.firstWhere(
      (cam) => cam.lensDirection == CameraLensDirection.front,
      orElse: () => cameras.first,
    );

    _controller = CameraController(
      _camera!,
      ResolutionPreset.low,
      enableAudio: false,
      imageFormatGroup: Platform.isAndroid
          ? ImageFormatGroup.nv21
          : ImageFormatGroup.bgra8888,
    );

    await _controller!.initialize();
    onInitialized?.call();
  }

  // ✅ MODIFICATION: Now passes only the ML Kit InputImage
  void startStream(Function(InputImage) onImage) {
    if (_controller == null || _isStreaming) return;
    _isStreaming = true;

    int frameSkip = 0;
    _controller!.startImageStream((CameraImage image) {
      frameSkip++;
      // Process 1 out of every 3 frames for battery efficiency
      if (frameSkip % 3 != 0) return;

      final inputImage = _convertCameraImage(image);
      if (inputImage != null) {
        onImage(inputImage);
      }
    });
  }

  // stopStream stops only the image stream
  // Camera controller stays alive so startStream works again instantly
  Future<void> stopStream() async {
    if (!_isStreaming) return;
    _isStreaming = false;
    try {
      if (_controller != null &&
          _controller!.value.isInitialized &&
          _controller!.value.isStreamingImages) {
        await _controller!.stopImageStream();
      }
    } catch (e) {
      // Already stopped or disposed — safe to ignore
    }
  }

  // Full stop — disposes camera controller entirely
  Future<void> stop() async {
    await stopStream();
    await _controller?.dispose();
    _controller  = null;
    _isStreaming = false;
  }

  InputImage? _convertCameraImage(CameraImage image) {
    if (_camera == null) return null;

    final WriteBuffer allBytes = WriteBuffer();
    for (final Plane plane in image.planes) {
      allBytes.putUint8List(plane.bytes);
    }
    final bytes = allBytes.done().buffer.asUint8List();

    final Size imageSize =
        Size(image.width.toDouble(), image.height.toDouble());
    final InputImageRotation imageRotation =
        _mapRotation(_camera!.sensorOrientation);
    final InputImageFormat inputImageFormat = Platform.isAndroid
        ? InputImageFormat.nv21
        : InputImageFormat.bgra8888;

    final inputImageData = InputImageMetadata(
      size: imageSize,
      rotation: imageRotation,
      format: inputImageFormat,
      bytesPerRow: image.planes[0].bytesPerRow,
    );

    return InputImage.fromBytes(bytes: bytes, metadata: inputImageData);
  }

  InputImageRotation _mapRotation(int sensorOrientation) {
    switch (sensorOrientation) {
      case 0:   return InputImageRotation.rotation0deg;
      case 90:  return InputImageRotation.rotation90deg;
      case 180: return InputImageRotation.rotation180deg;
      case 270: return InputImageRotation.rotation270deg;
      default:  return InputImageRotation.rotation0deg;
    }
  }
}