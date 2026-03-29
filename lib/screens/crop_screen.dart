import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_cropper/image_cropper.dart';

class CropScreen extends StatefulWidget {
  final String imagePath;

  const CropScreen({super.key, required this.imagePath});

  @override
  State<CropScreen> createState() => _CropScreenState();
}

class _CropScreenState extends State<CropScreen> {
  bool _isCropping = false;

  @override
  void initState() {
    super.initState();
    // Automatically open the cropper when the screen loads
    WidgetsBinding.instance.addPostFrameCallback((_) => _openCropper());
  }

  /// Open the image cropper UI
  Future<void> _openCropper() async {
    if (_isCropping) return;
    setState(() => _isCropping = true);

    try {
      final croppedFile = await ImageCropper().cropImage(
        sourcePath: widget.imagePath,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: 'Crop Table Area',
            toolbarColor: const Color(0xFF0D1117),
            toolbarWidgetColor: Colors.white,
            backgroundColor: const Color(0xFF0D1117),
            activeControlsWidgetColor: const Color(0xFF6C63FF),
            cropGridColor: const Color(0xFF6C63FF).withOpacity(0.4),
            cropFrameColor: const Color(0xFF6C63FF),
            dimmedLayerColor: Colors.black.withOpacity(0.7),
            statusBarColor: const Color(0xFF0D1117),
            cropGridRowCount: 3,
            cropGridColumnCount: 3,
            hideBottomControls: false,
            lockAspectRatio: false,
            initAspectRatio: CropAspectRatioPreset.original,
            aspectRatioPresets: [
              CropAspectRatioPreset.original,
              CropAspectRatioPreset.square,
              CropAspectRatioPreset.ratio3x2,
              CropAspectRatioPreset.ratio4x3,
              CropAspectRatioPreset.ratio16x9,
            ],
          ),
          IOSUiSettings(
            title: 'Crop Table Area',
            doneButtonTitle: 'Confirm',
            cancelButtonTitle: 'Cancel',
            aspectRatioPresets: [
              CropAspectRatioPreset.original,
              CropAspectRatioPreset.square,
              CropAspectRatioPreset.ratio3x2,
              CropAspectRatioPreset.ratio4x3,
            ],
          ),
        ],
      );

      if (!mounted) return;

      if (croppedFile != null) {
        // Navigate to PreviewScreen with the cropped image
        Navigator.pushReplacementNamed(
          context,
          '/preview',
          arguments: croppedFile.path,
        );
      } else {
        // User canceled cropping → go back to HomeScreen
        Navigator.pop(context);
      }
    } catch (e) {
      if (!mounted) return;
      _showError('Cropping failed: ${e.toString()}');
      Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _isCropping = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(fontFamily: 'Cairo'),
        ),
        backgroundColor: const Color(0xFFFF6B6B),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // While the cropper is loading/displaying, show a loading indicator
    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Animated icon
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.0, end: 1.0),
              duration: const Duration(milliseconds: 600),
              builder: (context, value, child) {
                return Opacity(
                  opacity: value,
                  child: Transform.scale(
                    scale: 0.8 + (value * 0.2),
                    child: Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: const Color(0xFF6C63FF).withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.crop_rounded,
                        size: 48,
                        color: Color(0xFF6C63FF),
                      ),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 24),
            const Text(
              'Opening Image Cropper...',
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Adjust the crop area to fit your table',
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 14,
                color: Colors.white54,
              ),
            ),
            const SizedBox(height: 32),
            const SizedBox(
              width: 40,
              height: 40,
              child: CircularProgressIndicator(
                color: Color(0xFF6C63FF),
                strokeWidth: 3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
