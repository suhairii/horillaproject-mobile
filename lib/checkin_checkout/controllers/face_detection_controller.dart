import 'dart:convert';
import 'dart:io';
import 'dart:developer';
import 'package:camera/camera.dart';
import 'package:flutter_face_api/flutter_face_api.dart';
import 'package:permission_handler/permission_handler.dart';

class FaceScannerController {
  late CameraController cameraController;
  late CameraDescription selectedCamera;

  var faceSdk = FaceSDK.instance;

  bool _isInitialized = false;

  Future initializeCamera() async {
    try {
      final status = await Permission.camera.request();
      if (!status.isGranted) {
        throw Exception('Camera permission not granted');
      }

      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        throw Exception('No cameras available');
      }
      selectedCamera = cameras.firstWhere(
            (camera) => camera.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      cameraController = CameraController(
        selectedCamera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await cameraController.initialize();
      _isInitialized = true;
      log('Camera initialized successfully');
    } catch (e) {
      log('Error initializing camera: $e');
      _isInitialized = false;
      rethrow;
    }
  }

  Future<XFile?> captureImage() async {
    if (!_isInitialized || !cameraController.value.isInitialized) {
      log('Camera not initialized or already disposed');
      return null;
    }
    try {
      if (cameraController.value.isTakingPicture) {
        log('Camera is already taking a picture');
        return null;
      }
      await Future.delayed(const Duration(milliseconds: 200));
      final image = await cameraController.takePicture();
      log('Image captured successfully at ${image.path}');
      final file = File(image.path);
      if (!file.existsSync()) {
        throw Exception('Captured image file not found');
      }
      final length = await file.length();
      if (length == 0) {
        throw Exception('Captured image file is empty');
      }
      return image;
    } catch (e) {
      log('Error capturing image: $e');
      return null;
    }
  }

  Future<bool> compareFaces(File capturedImageFile, String storedImageBase64) async {
    try {
      if (!await capturedImageFile.exists()) {
        throw Exception('Captured image file not found at: ${capturedImageFile.path}');
      }
      final storedImageBytes = base64Decode(storedImageBase64);
      if (storedImageBytes.isEmpty) {
        throw Exception('Stored image bytes are empty');
      }
      final capturedImageBytes = await capturedImageFile.readAsBytes();
      if (capturedImageBytes.isEmpty) {
        throw Exception('Captured image bytes are empty');
      }
      log('Stored image size: ${storedImageBytes.length} bytes');
      log('Captured image size: ${capturedImageBytes.length} bytes');

      final storedFaceImage = MatchFacesImage(storedImageBytes, ImageType.PRINTED);
      final capturedFaceImage = MatchFacesImage(capturedImageBytes, ImageType.LIVE);

      final request = MatchFacesRequest([storedFaceImage, capturedFaceImage]);
      final response = await faceSdk.matchFaces(request);
      final split = await faceSdk.splitComparedFaces(response.results, 0.75);

      if (split.matchedFaces.isNotEmpty) {
        final similarity = split.matchedFaces[0].similarity;
        log('Face comparison similarity: $similarity');
        return similarity >= 0.80;
      }
      log('No matched faces found');
      return false;
    } catch (e, stack) {
      log('Error in face comparison: $e\n$stack');
      return false;
    }
  }

  void dispose() {
    if (cameraController.value.isInitialized) {
      cameraController.dispose();
      log('Camera controller disposed');
    }
  }
}
