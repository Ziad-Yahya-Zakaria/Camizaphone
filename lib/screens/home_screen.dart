import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:image_picker/image_picker.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  CameraController? _cameraController;
  List<CameraDescription> _cameras = [];
  bool _isCameraInitialized = false;
  bool _isCapturing = false;
  bool _permissionDenied = false;
  String? _errorMessage;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Pulse animation for capture button
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.12).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Fade-in animation for UI elements
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    );

    _initializeCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cameraController?.dispose();
    _pulseController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }
    if (state == AppLifecycleState.inactive) {
      _cameraController?.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initializeCamera();
    }
  }

  /// Request camera permission and initialize the camera
  Future<void> _initializeCamera() async {
    // Request camera permission
    final cameraStatus = await Permission.camera.request();

    if (!cameraStatus.isGranted) {
      setState(() {
        _permissionDenied = true;
        _errorMessage = 'Camera permission is required to use Camizaphone.';
      });
      return;
    }

    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        setState(() {
          _errorMessage = 'No cameras found on this device.';
        });
        return;
      }

      // Use back camera (index 0)
      final backCamera = _cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => _cameras.first,
      );

      _cameraController = CameraController(
        backCamera,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await _cameraController!.initialize();

      // Enable auto-focus
      await _cameraController!.setFocusMode(FocusMode.auto);

      if (!mounted) return;

      setState(() {
        _isCameraInitialized = true;
        _errorMessage = null;
      });

      _fadeController.forward();
    } catch (e) {
      setState(() {
        _errorMessage = 'Camera initialization failed: ${e.toString()}';
      });
    }
  }

  /// Capture a high-quality photo
  Future<void> _capturePhoto() async {
    if (_cameraController == null ||
        !_cameraController!.value.isInitialized ||
        _isCapturing) {
      return;
    }

    setState(() => _isCapturing = true);

    try {
      // Set flash mode off for document capture
      await _cameraController!.setFlashMode(FlashMode.off);

      final XFile photo = await _cameraController!.takePicture();

      if (!mounted) return;

      // Navigate to CropScreen with the captured image path
      Navigator.pushNamed(context, '/crop', arguments: photo.path);
    } catch (e) {
      _showSnackbar('Failed to capture photo: ${e.toString()}');
    } finally {
      if (mounted) setState(() => _isCapturing = false);
    }
  }

  /// Pick an image from the gallery
  Future<void> _pickFromGallery() async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 100,
      );

      if (image != null && mounted) {
        Navigator.pushNamed(context, '/crop', arguments: image.path);
      }
    } catch (e) {
      _showSnackbar('Failed to pick image: ${e.toString()}');
    }
  }

  void _showSnackbar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(fontFamily: 'Cairo'),
        ),
        backgroundColor: const Color(0xFF1C2333),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _permissionDenied
          ? _buildPermissionDeniedView()
          : _errorMessage != null
              ? _buildErrorView()
              : !_isCameraInitialized
                  ? _buildLoadingView()
                  : _buildCameraView(),
    );
  }

  /// === Loading View ===
  Widget _buildLoadingView() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF0D1117), Color(0xFF161B22)],
        ),
      ),
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 48,
              height: 48,
              child: CircularProgressIndicator(
                color: Color(0xFF6C63FF),
                strokeWidth: 3,
              ),
            ),
            SizedBox(height: 24),
            Text(
              'Initializing Camera...',
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 18,
                color: Colors.white70,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// === Permission Denied View ===
  Widget _buildPermissionDeniedView() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF0D1117), Color(0xFF161B22)],
        ),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF6B6B).withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.camera_alt_outlined,
                  size: 64,
                  color: Color(0xFFFF6B6B),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Camera Permission Required',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                _errorMessage ?? 'Please grant camera access to continue.',
                style: const TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 15,
                  color: Colors.white54,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              ElevatedButton.icon(
                onPressed: () => openAppSettings(),
                icon: const Icon(Icons.settings),
                label: const Text('Open Settings'),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: _initializeCamera,
                child: const Text(
                  'Retry',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    color: Color(0xFF6C63FF),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// === Error View ===
  Widget _buildErrorView() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF0D1117), Color(0xFF161B22)],
        ),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Color(0xFFFF6B6B)),
              const SizedBox(height: 16),
              Text(
                _errorMessage ?? 'An error occurred.',
                style: const TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 16,
                  color: Colors.white70,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _initializeCamera,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// === Camera View ===
  Widget _buildCameraView() {
    final controller = _cameraController!;
    final size = MediaQuery.of(context).size;

    return FadeTransition(
      opacity: _fadeAnimation,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // === Camera Preview (full screen) ===
          Positioned.fill(
            child: FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: controller.value.previewSize?.height ?? size.width,
                height: controller.value.previewSize?.width ?? size.height,
                child: CameraPreview(controller),
              ),
            ),
          ),

          // === Top dark gradient overlay ===
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 140,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withOpacity(0.7),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          // === Bottom dark gradient overlay ===
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            height: 220,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    Colors.black.withOpacity(0.85),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          // === Document Frame Guide ===
          Center(
            child: Container(
              width: size.width * 0.85,
              height: size.height * 0.45,
              decoration: BoxDecoration(
                border: Border.all(
                  color: const Color(0xFF6C63FF).withOpacity(0.5),
                  width: 2,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Stack(
                children: [
                  // Corner markers
                  ..._buildCornerMarkers(),
                ],
              ),
            ),
          ),

          // === Top Bar ===
          Positioned(
            top: MediaQuery.of(context).padding.top + 12,
            left: 20,
            right: 20,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.4),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: const Color(0xFF6C63FF).withOpacity(0.3),
                    ),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.table_chart_rounded,
                          color: Color(0xFF6C63FF), size: 20),
                      SizedBox(width: 8),
                      Text(
                        'Camizaphone',
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // === Guide message ===
          Positioned(
            bottom: 190,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'Align the table within the frame',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 14,
                    color: Colors.white70,
                  ),
                ),
              ),
            ),
          ),

          // === Bottom Controls ===
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Gallery Button
                _buildControlButton(
                  icon: Icons.photo_library_rounded,
                  label: 'Gallery',
                  onTap: _pickFromGallery,
                  size: 56,
                ),

                // Capture Button (center, larger)
                ScaleTransition(
                  scale: _pulseAnimation,
                  child: GestureDetector(
                    onTap: _isCapturing ? null : _capturePhoto,
                    child: Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFF6C63FF), Color(0xFF9B59FF)],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF6C63FF).withOpacity(0.4),
                            blurRadius: 20,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: _isCapturing
                          ? const Padding(
                              padding: EdgeInsets.all(22),
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 3,
                              ),
                            )
                          : const Icon(
                              Icons.camera_alt_rounded,
                              color: Colors.white,
                              size: 36,
                            ),
                    ),
                  ),
                ),

                // Flash Toggle (placeholder for symmetry)
                _buildControlButton(
                  icon: Icons.flash_off_rounded,
                  label: 'Flash',
                  onTap: () => _toggleFlash(),
                  size: 56,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Toggle flash mode
  Future<void> _toggleFlash() async {
    if (_cameraController == null) return;
    final currentMode = _cameraController!.value.flashMode;
    final newMode =
        currentMode == FlashMode.off ? FlashMode.torch : FlashMode.off;
    await _cameraController!.setFlashMode(newMode);
    setState(() {});
  }

  /// Build a control button with icon + label
  Widget _buildControlButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    double size = 56,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.12),
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withOpacity(0.2),
              ),
            ),
            child: Icon(icon, color: Colors.white, size: size * 0.45),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: const TextStyle(
              fontFamily: 'Cairo',
              fontSize: 12,
              color: Colors.white60,
            ),
          ),
        ],
      ),
    );
  }

  /// Corner markers for the document frame guide
  List<Widget> _buildCornerMarkers() {
    const markerLength = 24.0;
    const markerThickness = 3.0;
    const color = Color(0xFF6C63FF);

    Widget corner(Alignment alignment) {
      final isTop = alignment.y < 0;
      final isLeft = alignment.x < 0;
      return Positioned(
        top: isTop ? 0 : null,
        bottom: !isTop ? 0 : null,
        left: isLeft ? 0 : null,
        right: !isLeft ? 0 : null,
        child: SizedBox(
          width: markerLength,
          height: markerLength,
          child: Stack(
            children: [
              Positioned(
                top: isTop ? 0 : null,
                bottom: !isTop ? 0 : null,
                left: isLeft ? 0 : null,
                right: !isLeft ? 0 : null,
                child: Container(
                  width: markerLength,
                  height: markerThickness,
                  color: color,
                ),
              ),
              Positioned(
                top: isTop ? 0 : null,
                bottom: !isTop ? 0 : null,
                left: isLeft ? 0 : null,
                right: !isLeft ? 0 : null,
                child: Container(
                  width: markerThickness,
                  height: markerLength,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return [
      corner(Alignment.topLeft),
      corner(Alignment.topRight),
      corner(Alignment.bottomLeft),
      corner(Alignment.bottomRight),
    ];
  }
}
