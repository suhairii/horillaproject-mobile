import 'dart:async';
import 'dart:convert';
import 'dart:io'; 
import 'dart:ui'; // Wajib untuk ImageFilter
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:horilla/checkin_checkout/checkin_checkout_views/stopwatch.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:animated_notch_bottom_bar/animated_notch_bottom_bar/animated_notch_bottom_bar.dart';
import 'package:geolocator/geolocator.dart';
import '../../horilla_main/home.dart';
import 'face_detection.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'package:internet_connection_checker/internet_connection_checker.dart'; // Tambahkan ini jika belum ada

// IMPORT WIDGET BOTTOM NAVBAR
import '../../widgets/custom_bottom_nav_bar.dart'; 

// --- REUSABLE GLASS CONTAINER ---
class GlassContainer extends StatelessWidget {
  final Widget child;
  final double blur;
  final double opacity;
  final EdgeInsetsGeometry padding;
  final BorderRadius? borderRadius;
  final bool hasShadow;
  final VoidCallback? onTap;

  const GlassContainer({
    super.key,
    required this.child,
    this.blur = 15.0,
    this.opacity = 0.6,
    this.padding = const EdgeInsets.all(16.0),
    this.borderRadius,
    this.hasShadow = true,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final br = borderRadius ?? BorderRadius.circular(20.0);
    return GestureDetector(
      onTap: onTap,
      child: Container(
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
      ),
    );
  }
}
// -------------------------------------------------------------

class CheckInCheckOutFormPage extends StatefulWidget {
  const CheckInCheckOutFormPage({super.key});

  @override
  _CheckInCheckOutFormPageState createState() => _CheckInCheckOutFormPageState();
}

class _CheckInCheckOutFormPageState extends State<CheckInCheckOutFormPage> {
  Timer? _serverSyncTimer;
  late StreamSubscription subscription; // Tambahkan subscription koneksi

  bool _isOnline = true; 
  bool _isBackgroundSyncing = false;

  List<Map<String, dynamic>> attendanceList = [];
  late String swipeDirection;
  late String baseUrl = '';
  
  late String requestsEmpMyFirstName = '';
  late String requestsEmpMyLastName = '';
  late String requestsEmpMyBadgeId = '';
  late String requestsEmpMyDepartment = '';
  late String requestsEmpProfile = '';
  late String requestsEmpMyWorkInfoId = '';
  late String requestsEmpMyShiftName = '';
  
  bool clockCheckBool = false;
  bool clockCheckedIn = false;
  bool isLoading = true;
  bool isCheckIn = false;
  bool _isProcessingDrag = false;
  
  bool isAdmin = false; 

  String? checkInFormattedTime = '00:00';
  String elapsedTimeString = '00:00:00';
  String? checkOutFormattedTime = '00:00';
  String? checkInFormattedTimeTopR;
  String? workingTime = '00:00:00';
  String? clockIn;
  String? clockInTimes;
  String? duration;
  
  final StopwatchManager stopwatchManager = StopwatchManager();
  
  final _controller = NotchBottomBarController(index: 1);
  
  Map<String, dynamic> arguments = {};
  Duration elapsedTime = Duration.zero;
  Position? userLocation;
  Duration accumulatedDuration = Duration.zero;
  bool _locationSnackBarShown = false;
  bool _locationUnavailableSnackBarShown = false;
  late String getToken = '';

  @override
  void initState() {
    super.initState();
    fetchToken();
    swipeDirection = 'Swipe to Check-In';
    
    // Cek koneksi awal
    InternetConnectionChecker().hasConnection.then((value) {
      if (mounted) {
        setState(() {
          _isOnline = value;
        });
      }
    });

    getConnectivity(); // Listener koneksi aktif

    _serverSyncTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
       _runSilentBackgroundSync();
    });

    _initializeData();
  }

  // LOGIK KONEKSI SEPERTI DI HOME.DART
  void getConnectivity() {
    subscription = InternetConnectionChecker().onStatusChange.listen((status) {
      if (mounted) {
        setState(() {
          _isOnline = status == InternetConnectionStatus.connected;
        });
      }
    });
  }

  Future<void> _runSilentBackgroundSync() async {
    if (_isBackgroundSyncing) return;
    _isBackgroundSyncing = true;

    try {
      bool hasInternet = await _checkRealConnection();
      
      if (mounted && hasInternet != _isOnline) {
        setState(() {
          _isOnline = hasInternet;
        });
      }

      if (hasInternet) {
        await _checkSyncCondition();
      }
    } catch (e) {
    } finally {
      _isBackgroundSyncing = false;
    }
  }

  Future<bool> _checkRealConnection() async {
    try {
      final result = await InternetAddress.lookup('google.com');
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<void> _checkSyncCondition() async {
    final prefs = await SharedPreferences.getInstance();
    List<String> offlineQueue = prefs.getStringList('offline_queue') ?? [];
    
    if (offlineQueue.isNotEmpty) {
      await _syncOfflineData();
    } 
    else if (clockCheckedIn) {
      await getCheckIn(forceUpdate: false); 
    }
  }

  @override
  void dispose() {
    _serverSyncTimer?.cancel();
    super.dispose();
  }

  Future<void> fetchToken() async {
    final prefs = await SharedPreferences.getInstance();
    var token = prefs.getString("token");
    setState(() {
      getToken = token ?? '';
    });
  }

  Future<void> _initializeData() async {
    try {
      var faceConfigFromServer = await getFaceDetection();
      final prefs = await SharedPreferences.getInstance();
      
      if (faceConfigFromServer != null) {
         prefs.setBool("face_detection", faceConfigFromServer);
      } else {
         if (prefs.getBool("face_detection") == null) {
            prefs.setBool("face_detection", true);
         }
      }
      
      await _checkAdminStatus(); 
      await _loadClockState(); 
      await _syncOfflineData(); 
      await _initializeLocation();

      await Future.wait<void>([
        prefetchData(),
        getBaseUrl(),
        getLoginEmployeeRecord(),
        getCheckIn(), 
      ]);

      accumulatedDuration = await _loadAccumulatedDuration();
      
      if (clockCheckedIn) {
        if (duration != null && duration != "00:00:00") {
             Duration initialDuration = parseDuration(duration!);
             if (initialDuration != Duration.zero) {
                _restoreTimer(initialDuration);
             } else if (accumulatedDuration != Duration.zero) {
                _restoreTimer(accumulatedDuration);
             }
        } else if (accumulatedDuration != Duration.zero) {
             _restoreTimer(accumulatedDuration);
        } else {
             if(!stopwatchManager.isRunning) stopwatchManager.startStopwatch();
        }
      } else {
        stopwatchManager.stopStopwatch();
      }

      setState(() {
        isLoading = false;
      });
    } catch (e) {
      print('Error initializing data: $e');
    }
  }

  void _restoreTimer(Duration initialDuration) {
      if (initialDuration == Duration.zero) return;
      accumulatedDuration = initialDuration;
      stopwatchManager.resetStopwatch();
      stopwatchManager.startStopwatch(initialTime: initialDuration);
      elapsedTimeString = formatDuration(initialDuration);
      workingTime = formatDuration(initialDuration);
      _saveAccumulatedDuration(initialDuration);
  }

  Future<void> _checkAdminStatus() async {
    final prefs = await SharedPreferences.getInstance();
    bool isAdminPref = prefs.getBool("is_admin") ?? false;
    int empId = prefs.getInt("employee_id") ?? 0;
    
    setState(() {
      isAdmin = (isAdminPref == true || empId == 1);
    });
  }

  Future<void> getCheckIn({bool forceUpdate = false}) async {
    final prefs = await SharedPreferences.getInstance();
    var token = prefs.getString("token");
    var typedServerUrl = prefs.getString("typed_url");
    
    try {
      var uri = Uri.parse('$typedServerUrl/api/attendance/checking-in');
      var response = await http.get(uri, headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $token",
      }).timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        var responseBody = jsonDecode(response.body);
        
        setState(() {
          List<String> offlineQueue = prefs.getStringList('offline_queue') ?? [];
          
          bool hasPendingCheckIn = offlineQueue.any((item) => item.contains('"type":"check_in"'));
          bool hasPendingCheckOut = offlineQueue.any((item) => item.contains('"type":"check_out"'));

          if (responseBody['status'] == true) {
            // --- STATUS: SUDAH CHECK IN ---
            if (hasPendingCheckOut) {
               // Ada antrian checkout offline, jadi tampilan harus posisi Checkout
               clockIn = false.toString();
               clockCheckedIn = false;
               swipeDirection = 'Swipe to Check-In';
               stopwatchManager.stopStopwatch();
            } else {
               // Posisi Sedang Kerja (Check In)
               clockIn = true.toString();
               clockIn = responseBody['clock_in']; 
               
               // 1. AMBIL DURASI DARI SERVER (Misal: "00:07:23")
               duration = responseBody['duration']; 

               // 2. PARSING DURASI
               Duration workedDuration = Duration.zero;
               if (duration != null && duration != "00:00:00") {
                  workedDuration = parseDuration(duration!);
               }

               // 3. LOGIKA BARU: HITUNG MUNDUR (Sekarang - Durasi)
               // Ini menjamin jam "Started At" selalu ada dan masuk akal
               DateTime now = DateTime.now();
               DateTime calculatedStartTime = now.subtract(workedDuration);
               
               // 4. Format jam hasil hitungan (Misal: 08:53 AM)
               checkInFormattedTime = DateFormat("h:mm a").format(calculatedStartTime);
               
               clockCheckedIn = true;
               swipeDirection = 'Swipe to Check-out';
               
               // Simpan ke lokal agar saat restart aplikasi jam tidak hilang
               _saveClockState(true, 1, checkInFormattedTime);

               // 5. Sinkronisasi Stopwatch
               Duration appDuration = stopwatchManager.elapsed;
               // Jika selisih waktu aplikasi dan server lebih dari 1 menit, atau dipaksa update
               if (forceUpdate || (workedDuration - appDuration).abs().inMinutes >= 1) {
                  stopwatchManager.stopStopwatch();
                  stopwatchManager.resetStopwatch();
                  stopwatchManager.startStopwatch(initialTime: workedDuration);
                  elapsedTimeString = formatDuration(workedDuration);
                  workingTime = formatDuration(workedDuration);
               }
            }

          } else {
            // --- STATUS: TIDAK CHECK IN (ATAU BELUM) ---
            if (hasPendingCheckIn) {
               // Ada data offline checkin, gunakan waktu lokal saat user klik tombol
               clockCheckedIn = true;
               clockIn = true.toString();
               swipeDirection = 'Swipe to Check-out';
               if (!stopwatchManager.isRunning) {
                  stopwatchManager.startStopwatch();
               }
            } else {
               // Benar-benar belum absen
               clockIn = false.toString();
               clockInTimes = responseBody['clock_in_time'];
               duration = responseBody['duration'];
               clockCheckedIn = false;
               checkInFormattedTime = "00:00";
               swipeDirection = 'Swipe to Check-In';
               stopwatchManager.stopStopwatch(); 
               _saveClockState(false, 2, checkOutFormattedTime);
            }
          }
        });
      }
    } catch(e) {
       print("GetCheckIn Error: $e");
    }
  }

  Future<void> _syncOfflineData() async {
    final prefs = await SharedPreferences.getInstance();
    List<String> offlineQueue = prefs.getStringList('offline_queue') ?? [];

    if (offlineQueue.isEmpty) return;

    List<String> remainingQueue = List.from(offlineQueue);
    var token = prefs.getString("token");
    var typedServerUrl = prefs.getString("typed_url");
    bool needsTimeUpdate = false;

    for (String dataString in offlineQueue) {
      Map<String, dynamic> data = jsonDecode(dataString);
      String endpoint = data['type'] == 'check_in' ? 'clock-in' : 'clock-out';
      
      try {
        var uri = Uri.parse('$typedServerUrl/api/attendance/$endpoint/');
        
        String dateToSend;
        String timeToSend;

        if (data.containsKey('attendance_date') && data.containsKey('time')) {
           dateToSend = data['attendance_date'];
           timeToSend = data['time'];
        } else {
           DateTime ts = DateTime.parse(data['timestamp']);
           dateToSend = DateFormat('yyyy-MM-dd').format(ts);
           timeToSend = DateFormat('HH:mm:ss').format(ts);
        }

        Map<String, dynamic> requestBody = {
            "latitude": data['latitude'],
            "longitude": data['longitude'],
            "image": null, 
            "attendance_date": dateToSend, 
            "time": timeToSend 
        };

        var response = await http.post(
          uri,
          headers: {
            "Content-Type": "application/json",
            "Authorization": "Bearer $token",
          },
          body: jsonEncode(requestBody),
        ).timeout(const Duration(seconds: 10));

        if (response.statusCode == 200) {
          remainingQueue.remove(dataString);
          needsTimeUpdate = true;
        } else if (response.statusCode == 400) {
          var responseBody = jsonDecode(response.body);
          String msg = responseBody['message'] ?? responseBody['detail'] ?? "";
          bool isDuplicate = msg.toLowerCase().contains("already") || 
                             msg.toLowerCase().contains("duplicate") ||
                             msg.toLowerCase().contains("exist");

          if (isDuplicate) {
             remainingQueue.remove(dataString); 
             needsTimeUpdate = true;
          }
        }
      } catch (e) {
      }
    }

    await prefs.setStringList('offline_queue', remainingQueue);
    
    if (needsTimeUpdate) {
       await Future.delayed(const Duration(seconds: 1));
       await getCheckIn(forceUpdate: true);
    }
  }

  Future<void> _saveOfflineAttendance(String type) async {
    final prefs = await SharedPreferences.getInstance();
    List<String> offlineQueue = prefs.getStringList('offline_queue') ?? [];

    double lat = userLocation?.latitude ?? 0.0;
    double long = userLocation?.longitude ?? 0.0;
    
    DateTime now = DateTime.now();
    String dateStr = DateFormat('yyyy-MM-dd').format(now);
    String timeStr = DateFormat('HH:mm:ss').format(now);

    Map<String, dynamic> offlineData = {
      "type": type, 
      "attendance_date": dateStr,
      "time": timeStr,
      "timestamp": now.toIso8601String(),
      "latitude": lat,
      "longitude": long,
      "is_synced": false
    };

    offlineQueue.add(jsonEncode(offlineData));
    await prefs.setStringList('offline_queue', offlineQueue);
  }

  Future<bool> postCheckIn() async {
    final prefs = await SharedPreferences.getInstance();
    var token = prefs.getString("token");
    var typedServerUrl = prefs.getString("typed_url");
    var uri = Uri.parse('$typedServerUrl/api/attendance/clock-in/');

    double lat = userLocation?.latitude ?? 0.0;
    double long = userLocation?.longitude ?? 0.0;
    
    DateTime now = DateTime.now();
    String dateStr = DateFormat('yyyy-MM-dd').format(now);
    String timeStr = DateFormat('HH:mm:ss').format(now);

    try {
      var response = await http.post(
        uri,
        headers: {
          "Content-Type": "application/json",
          "Authorization": "Bearer $token",
        },
        body: jsonEncode({
          "latitude": lat,
          "longitude": long,
          "image": null,
          "attendance_date": dateStr, 
          "time": timeStr,            
        }),
      ).timeout(const Duration(seconds: 10));

      var responseBody = jsonDecode(response.body);

      if (response.statusCode == 200) {
        bool isSuccess = responseBody['status'] == true || 
                         responseBody['status'] == "success" ||
                         responseBody['message'] == "Clocked-In";

        if (isSuccess) {
            await Future.delayed(const Duration(milliseconds: 500));
            await getCheckIn(forceUpdate: true); 
            _handleCheckInSuccess();
            return true;
        } else {
             if (mounted) showCheckInFailedDialog(context, responseBody['message'] ?? "Unknown Error");
             return false;
        }
      } 
      else if (response.statusCode == 400) {
        String errorMsg = responseBody['message'] ?? responseBody.toString();
        if (errorMsg.toLowerCase().contains("already") || errorMsg.toLowerCase().contains("exists")) {
           await getCheckIn(forceUpdate: true); 
           return true;
        }
        if (mounted) showCheckInFailedDialog(context, "Server Error: $errorMsg");
        return false; 
      }
      else {
         throw Exception('Server Error: ${response.statusCode}');
      }

    } catch (e) {
      await _saveOfflineAttendance('check_in');

      setState(() {
        isCheckIn = true;
        clockCheckedIn = true;
        clockCheckBool = true;
        DateTime now = DateTime.now();
        checkInFormattedTime = DateFormat('h:mm a').format(now);
        checkInFormattedTimeTopR = DateFormat('h:mm').format(now);
        
        stopwatchManager.resetStopwatch();
        stopwatchManager.startStopwatch(initialTime: Duration.zero);
        
        _saveClockState(true, 1, checkInFormattedTime.toString());
        swipeDirection = 'Swipe to Check-out';
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Saved Offline.'), backgroundColor: Colors.orange)
        );
      }
      return true; 
    }
  }

  Future<bool> postCheckout() async {
    final prefs = await SharedPreferences.getInstance();
    var token = prefs.getString("token");
    var typedServerUrl = prefs.getString("typed_url");
    var uri = Uri.parse('$typedServerUrl/api/attendance/clock-out/');

    double lat = userLocation?.latitude ?? 0.0;
    double long = userLocation?.longitude ?? 0.0;

    DateTime now = DateTime.now();
    String dateStr = DateFormat('yyyy-MM-dd').format(now);
    String timeStr = DateFormat('HH:mm:ss').format(now);

    try {
      var response = await http.post(
        uri,
        headers: {
          "Content-Type": "application/json",
          "Authorization": "Bearer $token",
        },
        body: jsonEncode({
          "latitude": lat,
          "longitude": long,
          "attendance_date": dateStr, 
          "time": timeStr,            
        }),
      ).timeout(const Duration(seconds: 10));

      var responseBody = jsonDecode(response.body);

      if (response.statusCode == 200) {
         bool isSuccess = responseBody['status'] == true || 
                          responseBody['status'] == "success" ||
                          responseBody['message'] == "Clocked-Out";

         if (isSuccess) {
             _handleCheckOutSuccess();
             return true;
         } else {
            if (mounted) showCheckInFailedDialog(context, responseBody['message'] ?? "Unknown Error");
            return false;
         }
      } 
      else if (response.statusCode == 400) {
         if (mounted) showCheckInFailedDialog(context, "Server Error: ${responseBody['message'] ?? responseBody}");
         return false;
      }
      throw Exception('Server Error: ${response.statusCode}');

    } catch (e) {
      await _saveOfflineAttendance('check_out');

      setState(() {
        isCheckIn = false;
        clockCheckedIn = false;
        stopwatchManager.stopStopwatch();
        storeCheckoutTime();
        clockCheckBool = false;
        DateTime now = DateTime.now();
        checkOutFormattedTime = DateFormat('h:mm a').format(now);
        swipeDirection = 'Swipe to Check-In';
        _saveClockState(false, 2, checkOutFormattedTime.toString());
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Saved Offline.'), backgroundColor: Colors.orange)
        );
      }
      return true;
    }
  }

  void _handleCheckInSuccess() {
    setState(() {
      isCheckIn = true;
      clockCheckedIn = true;
      clockCheckBool = true;
      DateTime now = DateTime.now();
      
      checkInFormattedTime = DateFormat('h:mm a').format(now);
      checkInFormattedTimeTopR = DateFormat('h:mm').format(now);
      
      _saveClockState(true, 1, checkInFormattedTime.toString());

      if (duration?.isNotEmpty ?? false) {
          Duration initialDuration = parseDuration(duration!);
          stopwatchManager.resetStopwatch();
          stopwatchManager.startStopwatch(initialTime: initialDuration);
      } else {
        if (!stopwatchManager.isRunning) {
            stopwatchManager.startStopwatch(initialTime: Duration.zero);
        }
      }
      swipeDirection = 'Swipe to Check-out';
    });
  }

  void _handleCheckOutSuccess() {
    setState(() {
      isCheckIn = false;
      clockCheckedIn = false;
      stopwatchManager.stopStopwatch();
      storeCheckoutTime();
      Duration initialElapsedTime = stopwatchManager.elapsed;
      workingTime = formatDuration(initialElapsedTime);
      clockCheckBool = false;
      DateTime now = DateTime.now();
      checkOutFormattedTime = DateFormat('h:mm a').format(now);
      swipeDirection = 'Swipe to Check-In';
      _saveClockState(false, 2, checkOutFormattedTime.toString());
    });
  }

  Future<void> _adminDirectAction() async {
    setState(() {
      _isProcessingDrag = true; 
    });

    if (clockCheckedIn) {
      await postCheckout(); 
    } else {
      await postCheckIn(); 
    }

    setState(() {
      _isProcessingDrag = false;
    });
  }

  Future<void> _saveAccumulatedDuration(Duration duration) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('accumulated_duration_seconds', duration.inSeconds);
  }

  Future<void> _initializeLocation() async {
    final prefs = await SharedPreferences.getInstance();
    var geoFencing = prefs.getBool("geo_fencing");
    if (geoFencing == true) {
      try {
        bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
        if (!serviceEnabled) {
          if (!_locationSnackBarShown && mounted) {
            _locationSnackBarShown = true;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Location services disabled.')),
            );
          }
          return;
        }

        LocationPermission permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) {
          permission = await Geolocator.requestPermission();
        }

        Position position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
        setState(() {
          userLocation = position;
        });
      } catch (e) {
        print('Error fetching location: $e');
      }
    }
  }

  Future<Duration> _loadAccumulatedDuration() async {
    final prefs = await SharedPreferences.getInstance();
    int seconds = prefs.getInt('accumulated_duration_seconds') ?? 0;
    return Duration(seconds: seconds);
  }

  Duration parseDuration(String durationString) {
    try {
      List<String> parts = durationString.split(':');
      if (parts.length == 3) {
        return Duration(
          hours: int.parse(parts[0]), 
          minutes: int.parse(parts[1]), 
          seconds: int.parse(parts[2].split('.')[0])
        );
      } else if (parts.length == 2) {
        return Duration(
          hours: int.parse(parts[0]), 
          minutes: int.parse(parts[1])
        );
      }
      return Duration.zero;
    } catch (e) {
      return Duration.zero;
    }
  }

  Future<void> prefetchData() async {
    final prefs = await SharedPreferences.getInstance();
    var token = prefs.getString("token");
    var typedServerUrl = prefs.getString("typed_url");
    var employeeId = prefs.getInt("employee_id");
    
    if (employeeId != null) {
        try {
          var uri = Uri.parse('$typedServerUrl/api/employee/employees/$employeeId');
          var response = await http.get(uri, headers: {
            "Content-Type": "application/json",
            "Authorization": "Bearer $token",
          });
          if (response.statusCode == 200) {
             final responseData = jsonDecode(response.body);
             arguments = {
                'employee_id': responseData['id'],
                'employee_name': '${responseData['employee_first_name']} ${responseData['employee_last_name']}',
             };
          }
        } catch(e) {}
    }
  }

  _loadClockState() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      clockCheckedIn = prefs.getBool('clockCheckedIn') ?? false;
      checkInFormattedTime = prefs.getString('checkin') ?? '00:00';
      checkOutFormattedTime = prefs.getString('checkout') ?? '00:00';
      
      if (clockCheckedIn) {
        swipeDirection = 'Swipe to Check-out';
        clockCheckBool = true; 
      } else {
        swipeDirection = 'Swipe to Check-In';
      }
    });
  }

  _saveClockState(bool isCheckedIn, int option, [String? check]) async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setBool('clockCheckedIn', isCheckedIn);
    if (check != null && option == 2) {
      prefs.setString('checkout', check);
    } else {
      if(check != null) prefs.setString('checkin', check);
    }
  }

  Future<void> getBaseUrl() async {
    final prefs = await SharedPreferences.getInstance();
    var typedServerUrl = prefs.getString("typed_url");
    setState(() {
      baseUrl = typedServerUrl ?? '';
    });
  }

  Future<void> getLoginEmployeeRecord() async {
    final prefs = await SharedPreferences.getInstance();
    var token = prefs.getString("token");
    var typedServerUrl = prefs.getString("typed_url");
    var employeeId = prefs.getInt("employee_id");
    if(employeeId == null) return;

    try {
      var uri = Uri.parse('$typedServerUrl/api/employee/employees/$employeeId');
      var response = await http.get(uri, headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $token",
      });
      if (response.statusCode == 200) {
        var responseBody = jsonDecode(response.body);
        setState(() {
          requestsEmpMyFirstName = responseBody['employee_first_name'] ?? '';
          requestsEmpMyLastName = responseBody['employee_last_name'] ?? '';
          requestsEmpMyBadgeId = responseBody['badge_id'] ?? '';
          requestsEmpMyDepartment = responseBody['department_name'] ?? '';
          requestsEmpProfile = responseBody['employee_profile'] ?? '';
          requestsEmpMyWorkInfoId = responseBody['employee_work_info_id'] ?? '';
        });
        if(requestsEmpMyWorkInfoId.isNotEmpty) {
           getLoginEmployeeWorkInfoRecord(requestsEmpMyWorkInfoId);
        }
      }
    } catch(e) {}
  }

  Future<void> getLoginEmployeeWorkInfoRecord(String requestsEmpMyWorkInfoId) async {
     final prefs = await SharedPreferences.getInstance();
    var token = prefs.getString("token");
    var typedServerUrl = prefs.getString("typed_url");
    try {
      var uri = Uri.parse('$typedServerUrl/api/employee/employee-work-information/$requestsEmpMyWorkInfoId');
      var response = await http.get(uri, headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $token",
      });
      if (response.statusCode == 200) {
        var responseBody = jsonDecode(response.body);
        setState(() {
          requestsEmpMyShiftName = responseBody['shift_name'] ?? "None";
        });
      }
    } catch(e) {}
  }

  Future<bool?> getFaceDetection() async {
    final prefs = await SharedPreferences.getInstance();
    var token = prefs.getString("token");
    var typedServerUrl = prefs.getString("typed_url");
    try {
      var uri = Uri.parse('$typedServerUrl/api/facedetection/config/');
      var response = await http.get(uri, headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $token",
      }).timeout(const Duration(seconds: 3));

      if (response.statusCode == 200) {
        var data = jsonDecode(response.body);
        return data['start'] ?? false;
      }
    } catch(e) {
       return null;
    }
    return null;
  }

  Future<void> clearToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }

  String getErrorMessage(String responseBody) {
    try {
      final Map<String, dynamic> decoded = json.decode(responseBody);
      return decoded['message'] ?? 'Unknown error occurred';
    } catch (e) {
      return 'Error parsing server response';
    }
  }

  void showCheckInFailedDialog(BuildContext context, String errorMessage) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Check-in Failed'),
          content: Text(errorMessage),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (context) => const HomePage()),
                );
              },
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    const Color textDark = Color(0xFF1F2937);

    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      
      // 1. Agar AppBar transparan (Konten terlihat di belakangnya)
      extendBodyBehindAppBar: true, 
      
      // 2. Agar Background BLOBS tetap memenuhi layar (termasuk belakang navbar)
      extendBody: false, 

      // -- UPDATED APP BAR --
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(80.0), 
        child: Container(
          padding: const EdgeInsets.only(top: 10, left: 16, right: 16),
          child: AppBar(
            backgroundColor: Colors.transparent, // Transparan
            elevation: 0,
            automaticallyImplyLeading: false,
            
            // TITLE DI DALAM GLASS PILL
            title: GlassContainer(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              borderRadius: BorderRadius.circular(30),
              hasShadow: false,
              opacity: 0.6,
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.access_time_filled_rounded, color: textDark, size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Attendance',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: textDark,
                      fontSize: 16
                    ),
                  ),
                ],
              ),
            ),
            centerTitle: false,
            
            actions: [
               // INDIKATOR ONLINE (Hijau) / OFFLINE (Kuning) - DI DALAM GLASS PILL
               GlassContainer(
                 padding: const EdgeInsets.all(8),
                 borderRadius: BorderRadius.circular(50),
                 hasShadow: false,
                 child: Row(
                   children: [
                     Container(
                       width: 10,
                       height: 10,
                       decoration: BoxDecoration(
                         shape: BoxShape.circle,
                         color: _isOnline ? Colors.green : Colors.amber,
                         boxShadow: [
                           BoxShadow(color: (_isOnline ? Colors.green : Colors.amber).withOpacity(0.4), blurRadius: 4, spreadRadius: 1)
                         ]
                       ),
                     ),
                     const SizedBox(width: 6),
                     Text(
                       _isOnline ? "Online" : "Offline", 
                       style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)
                     )
                   ],
                 ),
               ),
               // TOMBOL LOGOUT DIHAPUS SESUAI PERMINTAAN
            ],
          ),
        ),
      ),
      
      body: Stack(
        children: [
          // 3. LAYER BACKGROUND (BLOBS)
          Positioned(
            top: -50,
            left: -50,
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 60, sigmaY: 60),
              child: Container(
                width: 250,
                height: 250,
                decoration: BoxDecoration(
                  color: (clockCheckedIn ? Colors.red : Colors.green).withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 100,
            right: -50,
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 60, sigmaY: 60),
              child: Container(
                width: 250,
                height: 250,
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
          
          // 4. LAYER KONTEN (TERBATAS SCROLLNYA)
          Padding(
            padding: const EdgeInsets.only(
              top: 110,  // Batas atas (Agar tidak ketabrak AppBar)
              bottom: 20 // Batas bawah (Agar tidak ketabrak Navbar)
            ),
            child: isLoading ? _buildLoadingWidget() : _buildCheckInCheckoutWidget(getToken),
          ),
        ],
      ),
      
      // MENGGUNAKAN CUSTOM BOTTOM NAV BAR
      bottomNavigationBar: CustomBottomNavBar(
        controller: _controller,
        employeeArguments: arguments,
      ),
    );
  }

  void storeCheckoutTime() {
    elapsedTime = stopwatchManager.elapsed;
    elapsedTimeString = elapsedTime.toString().split('.').first.padLeft(8, '0');
  }

  Widget _buildLoadingWidget() {
    return const Center(child: CircularProgressIndicator());
  }

  Widget _buildCheckInCheckoutWidget(token) {
    return RefreshIndicator(
      onRefresh: () async {
        await _initializeData();
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16.0),
        
        children: [
          // --- HEADER JAM (STATUS) ---
          GlassContainer(
            padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 20),
            child: Column(
              children: [
                Text(
                  clockCheckedIn ? 'CLOCK IN' : 'CLOCK OUT',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2,
                    color: clockCheckedIn ? Colors.red : Colors.grey[700],
                  ),
                ),
                const SizedBox(height: 10),
                StreamBuilder<int>(
                  stream: Stream.periodic(const Duration(milliseconds: 1000), (_) {
                    return stopwatchManager.elapsed.inMilliseconds;
                  }),
                  builder: (context, snapshot) {
                    String formattedTime = '00:00:00';
                    if (clockCheckedIn) {
                        int milliseconds = stopwatchManager.elapsed.inMilliseconds;
                        Duration duration = Duration(milliseconds: milliseconds);
                        formattedTime = '${duration.inHours.toString().padLeft(2, '0')}:${(duration.inMinutes % 60).toString().padLeft(2, '0')}:${(duration.inSeconds % 60).toString().padLeft(2, '0')}';
                    } else {
                        formattedTime = elapsedTimeString;
                    }
                    
                    return Text(
                      formattedTime,
                      style: const TextStyle(
                        fontSize: 48,
                        fontWeight: FontWeight.w300,
                        color: Colors.black87,
                      ),
                    );
                  },
                ),
                const SizedBox(height: 10),
                Text(
                  clockCheckedIn 
                     ? "Working since ${checkInFormattedTime ?? '--:--'}" 
                     : "Check out at ${checkOutFormattedTime ?? '--:--'}",
                  style: TextStyle(color: Colors.grey[600]),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 20),
          
          // --- PROFILE CARD ---
          GlassContainer(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                 Row(
                   children: [
                     Container(
                        width: 60.0,
                        height: 60.0,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle, 
                          border: Border.all(color: Colors.white, width: 2),
                          boxShadow: [
                            BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10)
                          ]
                        ),
                        child: ClipOval(
                          child: requestsEmpProfile.isNotEmpty
                            ? Image.network(
                                baseUrl + requestsEmpProfile,
                                headers: {"Authorization": "Bearer $token"},
                                fit: BoxFit.cover,
                                errorBuilder: (context, exception, stackTrace) => 
                                  const Icon(Icons.person, color: Colors.grey, size: 30),
                              )
                            : Container(color: Colors.grey[200], child: const Icon(Icons.person, size: 30)),
                        ),
                      ),
                      const SizedBox(width: 15),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '$requestsEmpMyFirstName $requestsEmpMyLastName',
                              style: const TextStyle(fontSize: 18.0, fontWeight: FontWeight.bold),
                            ),
                            Text(requestsEmpMyBadgeId, style: const TextStyle(color: Colors.grey)),
                          ],
                        ),
                      )
                   ],
                 ),
                 const Divider(height: 30),
                 _buildInfoRow('Department', requestsEmpMyDepartment),
                 _buildInfoRow('Shift', requestsEmpMyShiftName),
                 _buildInfoRow(
                    clockCheckedIn ? 'Started At' : 'Last Check-In', 
                    checkInFormattedTime ?? '--:--'
                 ),
              ],
            ),
          ),

          const SizedBox(height: 30),

          // --- ADMIN ACTION ---
          if (isAdmin)
             Padding(
               padding: const EdgeInsets.only(bottom: 20),
               child: Column(
                children: [
                  InkWell(
                    onTap: _isProcessingDrag ? null : _adminDirectAction,
                    borderRadius: BorderRadius.circular(30.0),
                    child: Container(
                      width: double.infinity,
                      height: 50,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(30.0),
                        color: Colors.blueGrey.shade50, 
                        border: Border.all(color: Colors.blueGrey.shade200),
                      ),
                      alignment: Alignment.center,
                      child: _isProcessingDrag 
                        ? const SizedBox(height:20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : Text(
                          "QUICK ADMIN ${clockCheckedIn ? 'CLOCK-OUT' : 'CLOCK-IN'}",
                          style: TextStyle(
                            color: Colors.blueGrey.shade700,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1
                          ),
                        ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text("- OR SLIDE BELOW (FACE ID) -", style: TextStyle(fontSize: 10, color: Colors.grey)),
                ],
              ),
             ),

          // --- SLIDE BUTTON ---
          GestureDetector(
            onPanUpdate: (details) async {
              if (!_isProcessingDrag) {
                final prefs = await SharedPreferences.getInstance();
                
                var faceDetection = prefs.getBool("face_detection") ?? true;
                var geoFencing = prefs.getBool("geo_fencing");
                
                if (faceDetection == true) {
                  if (details.delta.dx.abs() > details.delta.dy.abs() && details.delta.dx.abs() > 10) {
                    _isProcessingDrag = true;
                    if (userLocation == null && geoFencing == true) {
                        if (!_locationUnavailableSnackBarShown) {
                          _locationUnavailableSnackBarShown = true;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Location unavailable. Cannot proceed.')),
                          );
                        }
                        _isProcessingDrag = false;
                        return;
                    }

                    if (details.delta.dx < 0 && clockCheckedIn) {
                      final result = await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => FaceScanner(
                            userLocation: userLocation,
                            userDetails: arguments,
                            attendanceState: 'CHECKED_IN',
                          ),
                        ),
                      );
                      if (result != null && result['checkedOut'] == true) {
                        _handleCheckOutSuccess();
                        _syncOfflineData(); 
                      }
                      _isProcessingDrag = false;
                    } 
                    else if (details.delta.dx > 0 && !clockCheckedIn) {
                      final result = await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => FaceScanner(
                            userLocation: userLocation,
                            userDetails: arguments,
                            attendanceState: 'NOT_CHECKED_IN',
                          ),
                        ),
                      );
                      if (result != null && result['checkedIn'] == true) {
                        _handleCheckInSuccess();
                        _syncOfflineData(); 
                      }
                      _isProcessingDrag = false;
                    } else {
                       _isProcessingDrag = false;
                    }
                  }
                }
                else {
                  if (details.delta.dx.abs() > details.delta.dy.abs() &&
                      details.delta.dx.abs() > 10) {
                    _isProcessingDrag = true;
                    
                    if (details.delta.dx < 0 && clockCheckedIn) {
                       await postCheckout();
                    } else if (details.delta.dx > 0 && !clockCheckedIn) {
                       await postCheckIn();
                    }
                    _isProcessingDrag = false;
                  }
                }
              }
            },
            onPanEnd: (details) {
              _isProcessingDrag = false;
            },
            child: Container(
              width: double.infinity,
              height: 60,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(30.0),
                // Gradient sesuai status
                gradient: LinearGradient(
                  colors: clockCheckedIn 
                      ? [Colors.red.shade400, Colors.red.shade700]
                      : [Colors.green.shade400, Colors.green.shade700],
                ),
                boxShadow: [
                  BoxShadow(
                    color: (clockCheckedIn ? Colors.red : Colors.green).withOpacity(0.4),
                    blurRadius: 10,
                    offset: const Offset(0, 5),
                  )
                ]
              ),
              alignment: Alignment.center,
              child: Stack(
                children: [
                   Center(
                     child: Text(
                        swipeDirection,
                        style: const TextStyle(color: Colors.white, fontSize: 16.0, fontWeight: FontWeight.bold, letterSpacing: 1),
                      ),
                   ),
                   if (!clockCheckedIn)
                      Positioned(
                        left: 5, top: 5, bottom: 5,
                        child: Container(
                          width: 50,
                          decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                          child: const Icon(Icons.chevron_right, color: Colors.green, size: 30),
                        ),
                      ),
                   if (clockCheckedIn)
                      Positioned(
                        right: 5, top: 5, bottom: 5,
                        child: Container(
                          width: 50,
                          decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                          child: const Icon(Icons.chevron_left, color: Colors.red, size: 30),
                        ),
                      ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 50),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.w500)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black87)),
        ],
      ),
    );
  }

  String formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    return "${twoDigits(duration.inHours)}:$twoDigitMinutes:$twoDigitSeconds";
  }
}