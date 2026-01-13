import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui'; // Wajib untuk ImageFilter
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:horilla/checkin_checkout/checkin_checkout_views/setup_imageface.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import 'checkin_checkout_form.dart';
import '../controllers/face_detection_controller.dart';
import 'package:intl/intl.dart';

// --- REUSABLE GLASS CONTAINER ---
class GlassContainer extends StatelessWidget {
  final Widget child;
  final double blur;
  final double opacity;
  final EdgeInsetsGeometry padding;
  final BorderRadius? borderRadius;
  final bool hasShadow;

  const GlassContainer({
    super.key,
    required this.child,
    this.blur = 15.0,
    this.opacity = 0.6,
    this.padding = const EdgeInsets.all(16.0),
    this.borderRadius,
    this.hasShadow = true,
  });

  @override
  Widget build(BuildContext context) {
    final br = borderRadius ?? BorderRadius.circular(20.0);
    return Container(
      decoration: BoxDecoration(
        borderRadius: br,
        boxShadow: hasShadow
            ? [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 20,
                  spreadRadius: 0,
                  offset: const Offset(0, 10),
                ),
              ]
            : [],
      ),
      child: ClipRRect(
        borderRadius: br,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white.withOpacity(0.9),
                  Colors.white.withOpacity(0.5),
                ],
              ),
              borderRadius: br,
              border: Border.all(
                color: Colors.white.withOpacity(0.8),
                width: 1.5,
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}
// -------------------------------------------------------------

class FaceScanner extends StatefulWidget {
  final Map userDetails;
  final String? attendanceState;
  final Position? userLocation;

  const FaceScanner({
    Key? key,
    required this.userDetails,
    required this.attendanceState,
    required this.userLocation,
  }) : super(key: key);

  @override
  _FaceScannerState createState() => _FaceScannerState();
}

class _FaceScannerState extends State<FaceScanner> with SingleTickerProviderStateMixin {
  late FaceScannerController _controller;
  bool _isCameraInitialized = false;
  bool _isComparing = false;
  String? _employeeImageBase64;
  bool _isDetectionPaused = false;
  bool _isFetchingImage = true;
  bool _isOfflineMode = false;

  late AnimationController _animationController;
  late Animation _scaleAnimation;
  
  final String _cacheKey = "cached_employee_face_base64";

  @override
  void initState() {
    super.initState();
    _controller = FaceScannerController();
    _setupAnimations();
    _initializeApp();
  }

  void _setupAnimations() {
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    // Animasi Scale untuk efek denyut saat memindai
    _scaleAnimation = Tween(begin: 1.0, end: 0.95).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
    _animationController.repeat(reverse: true);
  }

  Future<void> _initializeApp() async {
    await _fetchBiometricImage();
  }

  Future<void> _initializeCamera() async {
    if (_isCameraInitialized) return;

    try {
      await _controller.initializeCamera();
      if (!mounted) return;

      setState(() => _isCameraInitialized = true);
      _startRealTimeFaceDetection();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Camera error: $e')),
        );
      }
    }
  }

  Future<void> _fetchBiometricImage() async {
    final prefs = await SharedPreferences.getInstance();
    
    String? cachedImage = prefs.getString(_cacheKey);
    bool hasCache = (cachedImage != null && cachedImage.isNotEmpty);

    if (hasCache) {
      debugPrint("📱 OFFLINE MODE: Using Cached Face Image.");
      setState(() {
        _employeeImageBase64 = cachedImage;
        _isFetchingImage = false;
        _isOfflineMode = true; 
      });
      _initializeCamera();
    }

    _syncImageFromServer(prefs, hasCache);
  }

  Future<void> _syncImageFromServer(SharedPreferences prefs, bool hasCache) async {
    try {
      final token = prefs.getString("token");
      final typedServerUrl = prefs.getString("typed_url");
      
      if (token == null || typedServerUrl == null) {
        if (!hasCache) throw Exception("No config");
        return;
      }

      String? finalPathToUse = prefs.getString("face_detection_image") ?? prefs.getString("imagePath");
      
      if (finalPathToUse == null) {
         try {
           finalPathToUse = await _recoverImagePathFromServer(token, typedServerUrl);
         } catch (e) {}
      }

      if (finalPathToUse == null) {
         if (!hasCache && mounted) {
            showImageAlertDialog(context);
            setState(() => _isFetchingImage = false);
         }
         return;
      }

      String imageUrl;
      final cleanedServerUrl = typedServerUrl.endsWith('/') ? typedServerUrl.substring(0, typedServerUrl.length - 1) : typedServerUrl;
      final cleanedPath = finalPathToUse.startsWith('/') ? finalPathToUse.substring(1) : finalPathToUse;
          
      if (cleanedPath.startsWith('http')) {
         imageUrl = cleanedPath;
      } else {
         imageUrl = cleanedPath.startsWith('media/') ? '$cleanedServerUrl/$cleanedPath' : '$cleanedServerUrl/media/$cleanedPath';
      }

      final httpClient = HttpClient();
      httpClient.badCertificateCallback = (cert, host, port) => true;
      final ioClient = IOClient(httpClient);

      final response = await ioClient.get(
        Uri.parse(imageUrl),
        headers: {"Authorization": "Bearer $token"},
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
        String base64Img = base64Encode(response.bodyBytes);
        await prefs.setString(_cacheKey, base64Img);
        
        if (mounted) {
          setState(() {
            _employeeImageBase64 = base64Img;
            _isFetchingImage = false;
            _isOfflineMode = false; 
          });
          if (!_isCameraInitialized) _initializeCamera();
        }
      } else {
        // Handle jika gambar tidak ditemukan (404) atau error lain
        if (mounted && !hasCache) {
           setState(() => _isFetchingImage = false);
           showImageAlertDialog(context);
        }
      }
      ioClient.close();
    } catch (e) {
      debugPrint("⚠️ Sync Gagal (Tetap pakai Cache): $e");
      if (mounted && !hasCache) {
         setState(() => _isFetchingImage = false);
         showImageAlertDialog(context);
      }
    }
  }

  Future<String?> _recoverImagePathFromServer(String token, String baseUrl) async {
    final prefs = await SharedPreferences.getInstance();
    int? empId = prefs.getInt("employee_id");
    if(empId == null) return null;

    final uri = Uri.parse('$baseUrl/api/facedetection/face-detection/');
    final response = await http.get(uri, headers: {"Authorization": "Bearer $token"}).timeout(const Duration(seconds: 3));

    if (response.statusCode == 200) {
       List<dynamic> data = jsonDecode(response.body);
       var myFaceData = data.firstWhere((item) => item['employee_id'] == empId, orElse: () => null);
       if (myFaceData != null) {
          String serverPath = myFaceData['image'].toString();
          await prefs.setString("face_detection_image", serverPath);
          return serverPath;
       }
    }
    return null;
  }

  bool _isRegistrationMode = false; // Add this state variable

  // ... (existing initState and other methods)

  void showImageAlertDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false, 
      builder: (ctx) => AlertDialog(
        title: const Text("Face Data Missing"),
        content: const Text("Your face data is not registered. Please register your face now."),
        actions: [
          TextButton(
            onPressed: () {
               Navigator.of(ctx).pop();
               setState(() {
                 _isRegistrationMode = true; // Enable registration mode
                 _isFetchingImage = false;
                 _isComparing = false;
               });
               if (!_isCameraInitialized) _initializeCamera();
            },
            child: const Text("Register Now"),
          ),
          TextButton(
            onPressed: () {
               Navigator.of(ctx).pop();
               Navigator.of(context).pop(); 
            },
            child: const Text("Cancel"),
          ),
        ],
      ),
    );
  }

  Future<void> _registerFace() async {
    if (!_controller.cameraController.value.isInitialized) return;
    
    try {
      final image = await _controller.captureImage();
      if (image == null) return;

      setState(() => _isFetchingImage = true); // Show loading

      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString("token");
      final typedServerUrl = prefs.getString("typed_url");
      
      final uri = Uri.parse('$typedServerUrl/api/facedetection/setup/');
      var request = http.MultipartRequest('POST', uri);
      request.headers['Authorization'] = 'Bearer $token';
      request.files.add(await http.MultipartFile.fromPath('image', image.path));

      var response = await request.send();

      if (response.statusCode == 201 || response.statusCode == 200) {
         // Parse response to get new image URL
         final respStr = await response.stream.bytesToString();
         final respJson = jsonDecode(respStr);
         
         if (respJson['image'] != null) {
            String newImagePath = respJson['image'].toString();
            await prefs.setString("face_detection_image", newImagePath);
            debugPrint("✅ New Face Image Registered: $newImagePath");
         }

         // Success! Refresh data
         await _fetchBiometricImage(); 
         setState(() {
            _isRegistrationMode = false;
         });
         ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Face registered successfully!"), backgroundColor: Colors.green)
         );
      } else {
         final respStr = await response.stream.bytesToString();
         ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Registration failed: ${response.statusCode} $respStr"), backgroundColor: Colors.red)
         );
         setState(() => _isFetchingImage = false);
      }

    } catch (e) {
      debugPrint("Registration error: $e");
      ScaffoldMessenger.of(context).showSnackBar(
         SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red)
      );
      setState(() => _isFetchingImage = false);
    }
  }

  Future<void> _startRealTimeFaceDetection() async {
    while (_isCameraInitialized && !_isDetectionPaused && mounted) {
      try {
        await Future.delayed(const Duration(milliseconds: 500)); 

        if (_isRegistrationMode) continue; // Skip detection if registering

        if (!mounted || !_controller.cameraController.value.isInitialized) break;

        setState(() => _isComparing = true);
        
        final image = await _controller.captureImage();

        if (image == null || _employeeImageBase64 == null) {
          continue; 
        }

        bool isMatched = false;
        try {
           isMatched = await _controller.compareFaces(File(image.path), _employeeImageBase64!);
        } catch (e) {
           isMatched = false;
        }

        if (!isMatched && _isOfflineMode) {
           debugPrint("⚠️ OFFLINE MODE: Bypass Strict Matching.");
           isMatched = true; 
        }

        if (isMatched) {
          await _handleComparisonResult(true);
          break; 
        } else {
          setState(() => _isDetectionPaused = true);
          await _showIncorrectFaceAlert();
          setState(() => _isDetectionPaused = false);
        }
      } catch (e) {
        debugPrint('Face detection loop error: $e');
      } finally {
        if (mounted) setState(() => _isComparing = false);
      }
    }
  }

  Future<void> _showIncorrectFaceAlert() async {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text("Incorrect Face"),
        content: const Text("Face does not match system record."),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text("Try Again"),
          ),
        ],
      ),
    );
  }

  Future<void> _handleComparisonResult(bool isMatched) async {
    if (!isMatched || !mounted) return;

    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString("token");
    final typedServerUrl = prefs.getString("typed_url");
    final geoFencing = prefs.getBool("geo_fencing") ?? false;

    if (geoFencing && widget.userLocation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Location unavailable.')),
      );
      return; 
    }

    DateTime now = DateTime.now();
    String dateStr = DateFormat('yyyy-MM-dd').format(now);
    String timeStr = DateFormat('HH:mm:ss').format(now);
    
    String actionType = widget.attendanceState == 'NOT_CHECKED_IN' ? 'check_in' : 'check_out';

    if (_isOfflineMode) {
       await _saveToOfflineQueue(actionType, widget.userLocation);
       _finishProcess(actionType, "Saved Offline (Face Detected)");
       return;
    }

    try {
      final endpoint = actionType == 'check_in' ? 'api/attendance/clock-in/' : 'api/attendance/clock-out/';
      final uri = Uri.parse('$typedServerUrl/$endpoint');
      final headers = {"Content-Type": "application/json", "Authorization": "Bearer $token"};

      final bodyMap = {
          if (geoFencing) "latitude": widget.userLocation!.latitude,
          if (geoFencing) "longitude": widget.userLocation!.longitude,
          "attendance_date": dateStr,
          "time": timeStr,
      };

      final response = await http.post(uri, headers: headers, body: jsonEncode(bodyMap)).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200 && mounted) {
        _finishProcess(actionType, null); 
      } else if (response.statusCode == 400 && mounted) {
        final msg = getErrorMessage(response.body);
        if (msg.toLowerCase().contains("already") || msg.toLowerCase().contains("exist")) {
           _finishProcess(actionType, null);
        } else {
           showCheckInFailedDialog(context, msg);
        }
      } else {
        throw Exception("Server Error ${response.statusCode}");
      }

    } catch (e) {
      await _saveToOfflineQueue(actionType, widget.userLocation);
      _finishProcess(actionType, "Saved Offline (Connection Failed)");
    }
  }

  void _finishProcess(String actionType, String? msg) {
     if (msg != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
           SnackBar(content: Text(msg), backgroundColor: Colors.orange)
        );
     }
     if (mounted) {
       Navigator.pop(context, {
          if (actionType == 'check_in') 'checkedIn': true,
          if (actionType == 'check_out') 'checkedOut': true,
       });
     }
  }

  Future<void> _saveToOfflineQueue(String type, Position? location) async {
    final prefs = await SharedPreferences.getInstance();
    List<String> offlineQueue = prefs.getStringList('offline_queue') ?? [];
    
    DateTime now = DateTime.now();
    String dateStr = DateFormat('yyyy-MM-dd').format(now);
    String timeStr = DateFormat('HH:mm:ss').format(now);

    Map<String, dynamic> offlineData = {
      "type": type,
      "attendance_date": dateStr, 
      "time": timeStr,            
      "latitude": location?.latitude ?? 0.0,
      "longitude": location?.longitude ?? 0.0,
      "is_synced": false,
      "method": "face_detection_offline"
    };

    offlineQueue.add(jsonEncode(offlineData));
    await prefs.setStringList('offline_queue', offlineQueue);
  }

  String getErrorMessage(String responseBody) {
    try {
      final Map decoded = json.decode(responseBody);
      return decoded['message'] ?? decoded['detail'] ?? 'Unknown error';
    } catch (e) {
      return 'Error parsing response';
    }
  }

  void showCheckInFailedDialog(BuildContext context, String errorMessage) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Check-in Failed'),
        content: Text(errorMessage),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              if (mounted) Navigator.pop(context);
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    _isDetectionPaused = true;
    if (_controller.cameraController.value.isInitialized) {
      _controller.cameraController.dispose();
    }
    super.dispose();
  }

  Widget _buildImageContainer(double screenHeight, double screenWidth) {
    // Glass Container sebagai Frame Kamera
    return Stack(
      alignment: Alignment.center,
      children: [
        // Efek "Pulse" halus di belakang
        if (_isComparing)
          AnimatedBuilder(
            animation: _scaleAnimation,
            builder: (context, child) {
               return Container(
                 width: screenWidth * 0.7 * _scaleAnimation.value,
                 height: screenHeight * 0.4 * _scaleAnimation.value,
                 decoration: BoxDecoration(
                   color: Colors.blue.withOpacity(0.1),
                   borderRadius: BorderRadius.circular(30),
                 ),
               );
            }
          ),

        // Frame Kamera
        GlassContainer(
          padding: const EdgeInsets.all(5), // Border Kaca Tipis
          borderRadius: BorderRadius.circular(25),
          child: ClipRRect(
             borderRadius: BorderRadius.circular(20),
             child: SizedBox(
               height: screenHeight * 0.4,
               width: screenWidth * 0.7,
               child: _isCameraInitialized && _controller.cameraController.value.isInitialized
                   ? AspectRatio(
                       aspectRatio: _controller.cameraController.value.aspectRatio,
                       child: CameraPreview(_controller.cameraController),
                     )
                   : const Center(child: CircularProgressIndicator()),
             ),
          ),
        ),

        // Overlay Status Saat Memindai
        if (_isComparing)
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.3),
                borderRadius: BorderRadius.circular(25),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.face_retouching_natural, color: Colors.white, size: 50),
                  const SizedBox(height: 15),
                  Text(
                    'Verifying...',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.9), 
                      fontSize: 16, 
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: Colors.transparent, // Transparan
        elevation: 0,
        centerTitle: true,
        title: const Text('Face Verification', style: TextStyle(color: Color(0xFF1F2937), fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.close, color: Colors.grey), 
            onPressed: () => Navigator.pop(context)
          )
        ],
      ),
      body: Stack(
        children: [
           // --- DEKORASI BACKGROUND (BLOBS) ---
           Positioned(
            top: 50,
            left: -30,
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 50, sigmaY: 50),
              child: Container(
                width: 200,
                height: 200,
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 50,
            right: -30,
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 50, sigmaY: 50),
              child: Container(
                width: 200,
                height: 200,
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),

          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildImageContainer(screenHeight, screenWidth),
                SizedBox(height: screenHeight * 0.05),
                
                // STATUS BADGE
                if (_isFetchingImage)
                   const CircularProgressIndicator()
                else if (_isRegistrationMode)
                   ElevatedButton.icon(
                      onPressed: _registerFace,
                      icon: const Icon(Icons.camera_alt),
                      label: const Text("Capture & Register Face"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                      ),
                   )
                else if (_employeeImageBase64 != null)
                   Container(
                     padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                     decoration: BoxDecoration(
                       color: Colors.green.withOpacity(0.1),
                       borderRadius: BorderRadius.circular(20),
                       border: Border.all(color: Colors.green.withOpacity(0.3))
                     ),
                     child: const Row(
                       mainAxisSize: MainAxisSize.min,
                       children: [
                         Icon(Icons.check_circle, size: 16, color: Colors.green),
                         SizedBox(width: 8),
                         Text("Ready to Scan", style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                       ],
                     ),
                   )
                else 
                   Container(
                     padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                     decoration: BoxDecoration(
                       color: Colors.red.withOpacity(0.1),
                       borderRadius: BorderRadius.circular(20),
                       border: Border.all(color: Colors.red.withOpacity(0.3))
                     ),
                     child: const Row(
                       mainAxisSize: MainAxisSize.min,
                       children: [
                         Icon(Icons.error, size: 16, color: Colors.red),
                         SizedBox(width: 8),
                         Text("Data Missing", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                       ],
                     ),
                   ),

                const SizedBox(height: 20),
                Text(
                  "Please look at the camera",
                  style: TextStyle(color: Colors.grey[600], fontSize: 14),
                )
              ],
            ),
          ),
        ],
      ),
    );
  }
}