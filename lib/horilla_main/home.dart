import 'dart:async';
import 'dart:ui'; // Wajib untuk ImageFilter
import 'package:flutter/material.dart';
import 'package:animated_notch_bottom_bar/animated_notch_bottom_bar/animated_notch_bottom_bar.dart';
import 'package:flutter_map_animations/flutter_map_animations.dart';
import 'package:geocoding/geocoding.dart';
import 'package:internet_connection_checker/internet_connection_checker.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shimmer/shimmer.dart';
import 'package:timeago/timeago.dart' as timeago;

// Pastikan path import ini sesuai dengan lokasi file di project Anda
import '../../checkin_checkout/checkin_checkout_views/geofencing.dart';
import '../widgets/custom_bottom_nav_bar.dart';

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

class HomePage extends StatefulWidget {
  const HomePage({Key? key}) : super(key: key);

  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with TickerProviderStateMixin {
  late StreamSubscription subscription;
  var isDeviceConnected = false;
  final ScrollController _scrollController = ScrollController();
  final _pageController = PageController(initialPage: 0);
  final _controller = NotchBottomBarController(index: 0);
  late Map<String, dynamic> arguments = {};
  
  // Permission Flags
  bool permissionCheck = false;
  bool isLoading = true;
  bool isFirstFetch = true;
  bool isAlertSet = false;
  bool permissionLeaveOverviewCheck = false;
  bool permissionLeaveTypeCheck = false;
  bool permissionGeoFencingMapViewCheck = false;
  bool geoFencingEnabled = false;
  bool permissionWardCheck = false;
  bool permissionLeaveAssignCheck = false;
  bool permissionLeaveRequestCheck = false;
  bool permissionMyLeaveRequestCheck = false;
  bool permissionLeaveAllocationCheck = false;
  
  int initialTabIndex = 0;
  int notificationsCount = 0;
  int maxCount = 5;
  String? duration;
  List<Map<String, dynamic>> notifications = [];
  Timer? _notificationTimer;
  Set<int> seenNotificationIds = {};
  int currentPage = 0;
  List<dynamic> responseDataLocation = [];
  final List<LocationWithRadius> locations = [];
  LocationWithRadius? selectedLocation;
  late final AnimatedMapController _mapController;
  bool _isPermissionLoading = true;
  bool isAuthenticated = true;

  @override
  void initState() {
    super.initState();
    _mapController = AnimatedMapController(vsync: this);
    _scrollController.addListener(_scrollListener);
    
    // Cek koneksi awal
    InternetConnectionChecker().hasConnection.then((value) {
      if (mounted) {
        setState(() {
          isDeviceConnected = value;
        });
        _initializePermissionsAndData();
      }
    });

    getConnectivity();
  }

  // --- LOGIC: Load Cached Data First, Then Network ---
  Future _initializePermissionsAndData() async {
    // 1. Load Local Data First (Offline Capability)
    await _loadOfflineData();

    // 2. Fetch Fresh Data (Only if Online)
    if (isDeviceConnected) {
      await checkAllPermissions();
      await Future.wait([
        permissionGeoFencingMapView(),
        loadGeoFencingPreference(),
        permissionLeaveOverviewChecks(),
        permissionLeaveTypeChecks(),
        permissionLeaveRequestChecks(),
        permissionLeaveAssignChecks(),
        permissionWardChecks(),
        fetchNotifications(),
        unreadNotificationsCount(),
        prefetchData(),
        fetchData(),
      ]);
    }

    if (mounted) {
      setState(() {
        _isPermissionLoading = false;
        isLoading = false;
      });
    }
  }

  // --- Helper to load cached data ---
  Future<void> _loadOfflineData() async {
    final prefs = await SharedPreferences.getInstance();
    
    if (mounted) {
      setState(() {
        // Load Cached Permissions
        permissionLeaveOverviewCheck = prefs.getBool('cache_perm_leave_overview') ?? false;
        permissionMyLeaveRequestCheck = prefs.getBool('cache_perm_my_leave_request') ?? false;
        permissionLeaveAllocationCheck = prefs.getBool('cache_perm_leave_allocation') ?? false;
        permissionCheck = prefs.getBool('cache_perm_attendance') ?? false;
        permissionGeoFencingMapViewCheck = prefs.getBool('cache_perm_geofence') ?? false;
        permissionWardCheck = prefs.getBool('cache_perm_ward') ?? false;

        // Load Cached Employee Data
        String? cachedEmployee = prefs.getString('cached_employee_data');
        if (cachedEmployee != null) {
          _parseAndSetEmployeeData(jsonDecode(cachedEmployee));
        }

        // Load Cached Notifications
        String? cachedNotifs = prefs.getString('cached_notifications');
        if (cachedNotifs != null) {
          List<dynamic> decoded = jsonDecode(cachedNotifs);
          notifications = decoded.cast<Map<String, dynamic>>().toList();
          notificationsCount = notifications.length;
        }
        
        // Load Geofencing
        geoFencingEnabled = prefs.getBool("geo_fencing") ?? false;
      });
    }
  }

  Future<void> loadGeoFencingPreference() async {
    final prefs = await SharedPreferences.getInstance();
    bool? geoFencing = prefs.getBool("geo_fencing");
    if (mounted) {
      setState(() {
        geoFencingEnabled = geoFencing ?? false;
      });
    }
  }

  // --- API CALLS ---
  
  Future<void> permissionLeaveOverviewChecks() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      var token = prefs.getString("token");
      var typedServerUrl = prefs.getString("typed_url");
      if (token == null || typedServerUrl == null) return;

      var uri = Uri.parse('$typedServerUrl/api/leave/check-perm/');
      var response = await http.get(uri, headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $token",
      });

      bool isAllowed = response.statusCode == 200;
      await prefs.setBool('cache_perm_leave_overview', isAllowed);
      
      if (mounted) {
        setState(() {
          permissionLeaveOverviewCheck = isAllowed;
          permissionMyLeaveRequestCheck = true; 
          permissionLeaveAllocationCheck = true; 
          
          prefs.setBool('cache_perm_my_leave_request', true);
          prefs.setBool('cache_perm_leave_allocation', true);
        });
      }
    } catch (e) {
      // Offline handled by cache
    }
  }

  Future<void> permissionLeaveTypeChecks() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      var token = prefs.getString("token");
      var typedServerUrl = prefs.getString("typed_url");
      if (token == null || typedServerUrl == null) return;
      
      var uri = Uri.parse('$typedServerUrl/api/leave/check-type/');
      var response = await http.get(uri, headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $token",
      });

      bool isAllowed = response.statusCode == 200;
      
      if (mounted) {
        setState(() {
          permissionLeaveTypeCheck = isAllowed;
          permissionMyLeaveRequestCheck = true; 
          permissionLeaveAllocationCheck = true;
        });
      }
    } catch (e) {
      // Offline
    }
  }

  Future<void> permissionGeoFencingMapView() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      var token = prefs.getString("token");
      var typedServerUrl = prefs.getString("typed_url");
      if (token == null || typedServerUrl == null) return;

      var uri = Uri.parse('$typedServerUrl/api/geofencing/setup-check/');
      var response = await http.get(uri, headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $token",
      });
      
      bool isAllowed = response.statusCode == 200;
      await prefs.setBool('cache_perm_geofence', isAllowed);

      if (mounted) {
        setState(() {
          permissionGeoFencingMapViewCheck = isAllowed;
        });
      }
    } catch (e) {
       // Offline
    }
  }

  Future<void> permissionLeaveRequestChecks() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      var token = prefs.getString("token");
      var typedServerUrl = prefs.getString("typed_url");
      if (token == null || typedServerUrl == null) return;

      var uri = Uri.parse('$typedServerUrl/api/leave/check-request/');
      var response = await http.get(uri, headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $token",
      });

      if (mounted) {
        setState(() {
          if (response.statusCode == 200) {
            permissionLeaveRequestCheck = true;
            permissionMyLeaveRequestCheck = true;
            permissionLeaveAllocationCheck = true;
          } else {
            permissionMyLeaveRequestCheck = true;
            permissionLeaveAllocationCheck = true;
          }
        });
      }
    } catch (e) {
      // Offline
    }
  }

  Future<void> permissionLeaveAssignChecks() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      var token = prefs.getString("token");
      var typedServerUrl = prefs.getString("typed_url");
      if (token == null || typedServerUrl == null) return;

      var uri = Uri.parse('$typedServerUrl/api/leave/check-assign/');
      var response = await http.get(uri, headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $token",
      });
      
      if (mounted) {
        setState(() {
          if (response.statusCode == 200) {
            permissionLeaveAssignCheck = true;
            permissionMyLeaveRequestCheck = true;
            permissionLeaveAllocationCheck = true;
          } else {
            permissionMyLeaveRequestCheck = true;
            permissionLeaveAllocationCheck = true;
          }
        });
      }
    } catch (e) {
      // Offline
    }
  }

  void getConnectivity() {
    subscription = InternetConnectionChecker().onStatusChange.listen((status) {
      if (mounted) {
        setState(() {
          isDeviceConnected = status == InternetConnectionStatus.connected;
          if (isDeviceConnected) {
            _initializePermissionsAndData();
          }
        });
      }
    });
  }

  final List<Widget> bottomBarPages = [
    const Home(),
    const Overview(),
    const User(),
  ];

  void _scrollListener() {
    if (_scrollController.offset >=
            _scrollController.position.maxScrollExtent &&
        !_scrollController.position.outOfRange) {
      currentPage++;
      fetchNotifications();
    }
  }

  Future<void> fetchData() async {
    await permissionWardChecks();
    if (mounted) {
      setState(() {});
    }
  }

  void permissionChecks() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      var token = prefs.getString("token");
      var typedServerUrl = prefs.getString("typed_url");
      var uri = Uri.parse('$typedServerUrl/api/attendance/permission-check/attendance');
      var response = await http.get(uri, headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $token",
      });
      
      bool isAllowed = response.statusCode == 200;
      await prefs.setBool('cache_perm_attendance', isAllowed);

      if (mounted) {
        setState(() {
          permissionCheck = isAllowed;
        });
      }
    } catch (e) {
      // Already handled by _loadOfflineData
    }
  }

  Future<void> permissionWardChecks() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      var token = prefs.getString("token");
      var typedServerUrl = prefs.getString("typed_url");
      var uri = Uri.parse('$typedServerUrl/api/ward/check-ward/');
      var response = await http.get(uri, headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $token",
      });
      
      bool isAllowed = response.statusCode == 200;
      await prefs.setBool('cache_perm_ward', isAllowed);
      
      if (mounted) {
        setState(() {
          permissionWardCheck = isAllowed;
        });
      }
    } catch (e) {
      // Already handled by _loadOfflineData
    }
  }

  Future<void> prefetchData() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      var token = prefs.getString("token");
      var typedServerUrl = prefs.getString("typed_url");
      var employeeId = prefs.getInt("employee_id");
      
      if (token == null || typedServerUrl == null) return;

      var uri = Uri.parse('$typedServerUrl/api/employee/employees/$employeeId');
      var response = await http.get(uri, headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $token",
      });

      if (response.statusCode == 200) {
        // 1. Save JSON to Cache
        await prefs.setString('cached_employee_data', response.body);
        
        // 2. Parse and Update State
        final responseData = jsonDecode(response.body);
        _parseAndSetEmployeeData(responseData);
      }
    } catch (e) {
       // Fallback handled
    }
  }

  void _parseAndSetEmployeeData(Map<String, dynamic> responseData) {
    if (mounted) {
      setState(() {
        arguments = {
          'employee_id': responseData['id'] ?? '',
          'employee_name': (responseData['employee_first_name'] ?? '') +
              ' ' +
              (responseData['employee_last_name'] ?? ''),
          'badge_id': responseData['badge_id'] ?? '',
          'email': responseData['email'] ?? '',
          'phone': responseData['phone'] ?? '',
          'date_of_birth': responseData['dob'] ?? '',
          'gender': responseData['gender'] ?? '',
          'address': responseData['address'] ?? '',
          'country': responseData['country'] ?? '',
          'state': responseData['state'] ?? '',
          'city': responseData['city'] ?? '',
          'qualification': responseData['qualification'] ?? '',
          'experience': responseData['experience'] ?? '',
          'marital_status': responseData['marital_status'] ?? '',
          'children': responseData['children'] ?? '',
          'emergency_contact': responseData['emergency_contact'] ?? '',
          'emergency_contact_name': responseData['emergency_contact_name'] ?? '',
          'employee_work_info_id': responseData['employee_work_info_id'] ?? '',
          'employee_bank_details_id': responseData['employee_bank_details_id'] ?? '',
          'employee_profile': responseData['employee_profile'] ?? '',
          'job_position_name': responseData['job_position_name'] ?? ''
        };
      });
    }
  }

  Future<void> fetchNotifications() async {
    final prefs = await SharedPreferences.getInstance();
    
    try {
      var token = prefs.getString("token");
      var typedServerUrl = prefs.getString("typed_url");
      if (token == null || typedServerUrl == null) return;

      List<Map<String, dynamic>> allNotifications = [];
      int page = 1;
      bool hasMore = true;

      while (hasMore) {
        var uri = Uri.parse(
            '$typedServerUrl/api/notifications/notifications/list/unread?page=$page');

        var response = await http.get(uri, headers: {
          "Content-Type": "application/json",
          "Authorization": "Bearer $token",
        });

        if (response.statusCode == 200) {
          var responseData = jsonDecode(response.body);
          var results = responseData['results'] as List;

          if (results.isEmpty) break;

          List<Map<String, dynamic>> fetched = results
              .where((n) => n['deleted'] == false)
              .cast<Map<String, dynamic>>()
              .toList();

          allNotifications.addAll(fetched);

          if (responseData['next'] == null) {
            hasMore = false;
          } else {
            page++;
          }
        } else {
          hasMore = false;
        }
      }

      Set<String> uniqueMapStrings = allNotifications
          .map((notification) => jsonEncode(notification))
          .toSet();

      List<Map<String, dynamic>> finalNotifications = uniqueMapStrings
          .map((jsonString) => jsonDecode(jsonString))
          .cast<Map<String, dynamic>>()
          .toList();

      // Save to Cache
      await prefs.setString('cached_notifications', jsonEncode(finalNotifications));

      if (mounted) {
        setState(() {
          notifications = finalNotifications;
          notificationsCount = notifications.length;
          isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  Future<void> unreadNotificationsCount() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      var token = prefs.getString("token");
      var typedServerUrl = prefs.getString("typed_url");
      var uri = Uri.parse(
          '$typedServerUrl/api/notifications/notifications/list/unread');
      var response = await http.get(uri, headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $token",
      });

      if (response.statusCode == 200) {
        if (mounted) {
          setState(() {
            notificationsCount = jsonDecode(response.body)['count'];
            isLoading = false;
          });
        }
      }
    } catch (e) {
      // Keep cached count
    }
  }

  Future<void> markReadNotification(int notificationId) async {
    if (!isDeviceConnected) return; 

    final prefs = await SharedPreferences.getInstance();
    try {
      var token = prefs.getString("token");
      var typedServerUrl = prefs.getString("typed_url");
      var uri = Uri.parse(
          '$typedServerUrl/api/notifications/notifications/$notificationId/');
      var response = await http.post(uri, headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $token",
      });
      if (response.statusCode == 200) {
        if (mounted) {
          setState(() {
            notifications.removeWhere((item) => item['id'] == notificationId);
            prefs.setString('cached_notifications', jsonEncode(notifications));
            unreadNotificationsCount();
            fetchNotifications();
          });
        }
      }
    } catch (e) {
      // Error
    }
  }

  Future<void> markAllReadNotification() async {
    if (!isDeviceConnected) return;

    final prefs = await SharedPreferences.getInstance();
    try {
      var token = prefs.getString("token");
      var typedServerUrl = prefs.getString("typed_url");
      var uri =
      Uri.parse('$typedServerUrl/api/notifications/notifications/bulk-read/');
      var response = await http.post(uri, headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $token",
      });
      if (response.statusCode == 200) {
        if (mounted) {
          setState(() {
            notifications.clear();
            prefs.setString('cached_notifications', jsonEncode([]));
            unreadNotificationsCount();
            fetchNotifications();
          });
        }
      }
    } catch (e) {
      // Error
    }
  }

  Future checkAllPermissions() async {
    final prefs = await SharedPreferences.getInstance();
    var token = prefs.getString("token");
    var typedServerUrl = prefs.getString("typed_url");

    Future<bool> getPerm(String endpoint) async {
      try {
        var uri = Uri.parse('$typedServerUrl$endpoint');
        var res = await http.get(uri, headers: {
          "Content-Type": "application/json",
          "Authorization": "Bearer $token",
        });
        return res.statusCode == 200;
      } catch (e) {
        return false;
      }
    }

    bool overview = await getPerm("/api/attendance/permission-check/attendance");
    bool att = true;
    bool attReq = true;
    bool hourAcc = true;

    await prefs.setBool("perm_overview", overview);
    await prefs.setBool("perm_attendance", att);
    await prefs.setBool("perm_attendance_request", attReq);
    await prefs.setBool("perm_hour_account", hourAcc);
  }

  Future<void> clearAllUnreadNotifications() async {
    if (!isDeviceConnected) return;
    
    final prefs = await SharedPreferences.getInstance();
    try {
      var token = prefs.getString("token");
      var typedServerUrl = prefs.getString("typed_url");
      var uri = Uri.parse(
          '$typedServerUrl/api/notifications/notifications/bulk-delete-unread/');
      var response = await http.delete(uri, headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $token",
      });
      if (response.statusCode == 200) {
        if (mounted) {
          setState(() {
            notifications.clear();
            prefs.setString('cached_notifications', jsonEncode([]));
            unreadNotificationsCount();
            fetchNotifications();
          });
        }
      }
    } catch (e) {
      // Error
    }
  }

  Future<void> clearToken(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    String? typedServerUrl = prefs.getString("typed_url");
    await prefs.remove('token');
    
    await prefs.remove('cached_employee_data');
    await prefs.remove('cached_notifications');
    
    isAuthenticated = false;
    _notificationTimer?.cancel();
    _notificationTimer = null;

    if (mounted) {
      Navigator.pushNamed(context, '/login', arguments: typedServerUrl);
    }
  }

  // --- LOGIC GEOFENCING & FACE DETECTION ---

  Future<void> enableFaceDetection() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      var token = prefs.getString("token");
      var typedServerUrl = prefs.getString("typed_url");
      var uri = Uri.parse('$typedServerUrl/api/facedetection/config/');
      await http.put(
        uri,
        headers: {
          "Content-Type": "application/json",
          "Authorization": "Bearer $token",
        },
        body: jsonEncode({
          'start': true,
        }),
      );
    } catch (e) {
      // Offline
    }
  }

  Future<void> disableFaceDetection() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      var token = prefs.getString("token");
      var typedServerUrl = prefs.getString("typed_url");
      var uri = Uri.parse('$typedServerUrl/api/facedetection/config/');
      await http.put(
        uri,
        headers: {
          "Content-Type": "application/json",
          "Authorization": "Bearer $token",
        },
        body: jsonEncode({
          'start': false,
        }),
      );
    } catch (e) {
       // Offline
    }
  }

  Future<bool> getFaceDetection() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      var token = prefs.getString("token");
      var typedServerUrl = prefs.getString("typed_url");
      var uri = Uri.parse('$typedServerUrl/api/facedetection/config/');
      var response = await http.get(uri, headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $token",
      });
      if (response.statusCode == 200) {
        var data = jsonDecode(response.body);
        bool isEnabled = data['start'] ?? false;
        return isEnabled;
      }
      return false;
    } catch (e) {
      return prefs.getBool('face_detection') ?? false;
    }
  }

  Future<bool?> getGeoFence() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      var token = prefs.getString("token");
      var typedServerUrl = prefs.getString("typed_url");
      var uri = Uri.parse('$typedServerUrl/api/geofencing/setup/');

      var response = await http.get(uri, headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $token",
      });

      if (response.statusCode == 200 && response.body.isNotEmpty) {
        var data = jsonDecode(response.body);
        bool isEnabled = data['start'] ?? false;
        return isEnabled;
      } else if (response.statusCode == 404) {
        return null;
      }
      return false;
    } catch (e) {
      return prefs.getBool('geo_fencing') ?? false;
    }
  }

  Future<void> enableGeoFenceLocation() async {
    await getGeoFenceLocation();
    if (responseDataLocation.isEmpty) return;
    try {
      var locationId = responseDataLocation[0]['id'];
      final prefs = await SharedPreferences.getInstance();
      var companyId = prefs.getInt("company_id");
      var token = prefs.getString("token");
      var typedServerUrl = prefs.getString("typed_url");
      var uri = Uri.parse('$typedServerUrl/api/geofencing/setup/$locationId/');
      await http.put(
        uri,
        headers: {
          "Content-Type": "application/json",
          "Authorization": "Bearer $token",
        },
        body: jsonEncode({
          'latitude': selectedLocation?.coordinates.latitude,
          'longitude': selectedLocation?.coordinates.longitude,
          'radius_in_meters': selectedLocation?.radius,
          'start': true,
          'company_id': companyId
        }),
      );
    } catch (e) {
      // offline handle
    }
  }

  Future<void> disableGeoFenceLocation() async {
    await getGeoFenceLocation();
    if (responseDataLocation.isEmpty) return;
    try {
      var locationId = responseDataLocation[0]['id'];
      final prefs = await SharedPreferences.getInstance();
      var companyId = prefs.getInt("company_id");
      var token = prefs.getString("token");
      var typedServerUrl = prefs.getString("typed_url");
      var uri = Uri.parse('$typedServerUrl/api/geofencing/setup/$locationId/');
      await http.put(
        uri,
        headers: {
          "Content-Type": "application/json",
          "Authorization": "Bearer $token",
        },
        body: jsonEncode({
          'latitude': selectedLocation?.coordinates.latitude,
          'longitude': selectedLocation?.coordinates.longitude,
          'radius_in_meters': selectedLocation?.radius,
          'start': false,
          'company_id': companyId
        }),
      );
    } catch (e) {
      // offline handle
    }
  }

  Future<void> getGeoFenceLocation() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      var token = prefs.getString("token");
      var typedServerUrl = prefs.getString("typed_url");
      var uri = Uri.parse('$typedServerUrl/api/geofencing/setup/');

      var response = await http.get(uri, headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $token",
      });

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is Map && data.isNotEmpty) {
          final lat = data['latitude'];
          final lng = data['longitude'];
          final rad = data['radius_in_meters'];

          if (lat != null && lng != null && rad != null) {
            final locationName = await _getLocationName(lat, lng);
            final location = LocationWithRadius(
              LatLng(lat, lng),
              locationName,
              (rad).toDouble(),
            );

            if (mounted) {
              setState(() {
                responseDataLocation = [data];
                locations.clear();
                locations.add(location);
                selectedLocation = location;
                _mapController.animateTo(dest: location.coordinates, zoom: 12.0);
              });
            }
          }
        }
      }
    } catch (e) {
      // Offline
    }
  }

  Future<String> _getLocationName(double latitude, double longitude) async {
    try {
      if (!isDeviceConnected) {
        return "Offline Location";
      }
      List<Placemark> placemarks =
          await placemarkFromCoordinates(latitude, longitude);
      if (placemarks.isNotEmpty) {
        Placemark place = placemarks[0];
        String name = "${place.locality ?? ''}, ${place.country ?? ''}".trim();
        return name.isEmpty ? "Unknown Location" : name;
      }
      return "Unknown Location";
    } catch (e) {
      return "Unknown Location";
    }
  }

  // --- DIALOGS & ANIMATIONS (Updated Style) ---

  Future<void> showSavedAnimation() async {
    String jsonContent = '{"imagePath": "Assets/gif22.gif"}';
    Map<String, dynamic> jsonData = json.decode(jsonContent);
    String imagePath = jsonData['imagePath'];

    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return Dialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset(imagePath, width: 150, height: 150, fit: BoxFit.cover),
                const SizedBox(height: 16),
                const Text("Successfully Updated", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.green)),
              ],
            ),
          ),
        );
      },
    );
    Future.delayed(const Duration(seconds: 2), () async {
      if (mounted) Navigator.pop(context);
    });
  }

  // Dialog Logout Baru
  Future<void> _showLogoutConfirmation() async {
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Column(
          children: [
            Icon(Icons.warning_amber_rounded, size: 50, color: Colors.orange),
            SizedBox(height: 10),
            Text("Confirm Logout", style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: const Text(
          "Are you sure you want to log out of your account?",
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey),
        ),
        actions: [
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: Colors.grey.shade300))
                  ),
                  child: const Text("Cancel", style: TextStyle(color: Colors.black)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    clearToken(context);
                  },
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    backgroundColor: Colors.red,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))
                  ),
                  child: const Text("Logout", style: TextStyle(color: Colors.white)),
                ),
              ),
            ],
          )
        ],
      ),
    );
  }

  // Dialog Settings Baru
  Future<void> _showSettingsDialog() async {
    if (!isDeviceConnected) return;

    var faceDetection = await getFaceDetection();
    var geoFencingResponse = await getGeoFence();
    final prefs = await SharedPreferences.getInstance();

    bool geoFencingSetupExists = geoFencingResponse != null;
    bool geoFencingEnabled = geoFencingSetupExists ? geoFencingResponse : false;

    prefs.remove('face_detection');
    prefs.setBool("face_detection", faceDetection);
    prefs.remove('geo_fencing');
    prefs.setBool("geo_fencing", geoFencingEnabled);

    showDialog(
      context: context,
      builder: (context) {
        bool tempFaceDetection = faceDetection;
        bool tempGeofencing = geoFencingEnabled;
        bool isGeofencingSetup = geoFencingSetupExists;

        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: const Row(
                children: [
                  Icon(Icons.settings, color: Color(0xFF1F2937)),
                  SizedBox(width: 10),
                  Text('Settings', style: TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: SwitchListTile(
                      activeColor: Colors.red,
                      secondary: const Icon(Icons.face_retouching_natural, color: Colors.blueGrey),
                      title: const Text('Face Detection', style: TextStyle(fontWeight: FontWeight.w600)),
                      value: tempFaceDetection,
                      onChanged: (val) {
                        setState(() {
                          tempFaceDetection = val;
                        });
                        if (val) {
                          enableFaceDetection();
                        } else {
                          disableFaceDetection();
                        }
                      },
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: SwitchListTile(
                      activeColor: Colors.red,
                      secondary: const Icon(Icons.location_on_outlined, color: Colors.blueGrey),
                      title: const Text('Geofencing', style: TextStyle(fontWeight: FontWeight.w600)),
                      value: tempGeofencing,
                      onChanged: (val) async {
                        setState(() {
                          tempGeofencing = val;
                        });
                        
                        if (!isGeofencingSetup && val) {
                          Navigator.pop(context); 
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const MapScreen(),
                            ),
                          );
                          return;
                        }

                        if (val) {
                          await enableGeoFenceLocation();
                        } else {
                          await disableGeoFenceLocation();
                        }
                      },
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setBool("face_detection", tempFaceDetection);
                    await prefs.setBool("geo_fencing", tempGeofencing);

                    // Update parent state
                    this.setState(() {
                      this.geoFencingEnabled = tempGeofencing;
                    });

                    Navigator.pop(context);
                    await showSavedAnimation();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))
                  ),
                  child: const Text('Save Changes'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    const Color textDark = Color(0xFF1F2937);

    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      extendBodyBehindAppBar: true, // Agar background blobs terlihat di balik AppBar
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(80.0), 
        child: Container(
          padding: const EdgeInsets.only(top: 10, left: 16, right: 16),
          child: AppBar(
            forceMaterialTransparency: true,
            backgroundColor: Colors.transparent,
            elevation: 0,
            automaticallyImplyLeading: false,
            // Custom Glass Title
           
            centerTitle: false,
            actions: [
              // --- INDIKATOR KONEKSI ---
              Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: GlassContainer(
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
                          color: isDeviceConnected ? Colors.green : Colors.amber,
                          boxShadow: [
                            BoxShadow(color: (isDeviceConnected ? Colors.green : Colors.amber).withOpacity(0.4), blurRadius: 4, spreadRadius: 1)
                          ]
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(isDeviceConnected ? "Online" : "Offline", style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold))
                    ],
                  ),
                ),
              ),

              if (!_isPermissionLoading) ...[
                // Settings Button (Glass)
                Visibility(
                  visible: permissionGeoFencingMapViewCheck,
                  child: IconButton(
                    icon: const Icon(Icons.settings, color: textDark),
                    tooltip: "Settings",
                    onPressed: _showSettingsDialog, 
                  ),
                ),
                
                // Map Button (Glass)
                Visibility(
                  visible: permissionGeoFencingMapViewCheck && geoFencingEnabled,
                  child: IconButton(
                    icon: const Icon(Icons.map_outlined, color: textDark),
                    tooltip: "Geofencing Map",
                    onPressed: () {
                      Navigator.push(context, MaterialPageRoute(builder: (context) => const MapScreen()));
                    },
                  ),
                ),

                // Notifications
                Stack(
                  alignment: Alignment.topRight,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.notifications_outlined, color: textDark),
                      onPressed: () {
                        if (isDeviceConnected) markAllReadNotification();
                        Navigator.pushNamed(context, '/notifications_list');
                        setState(() {
                          fetchNotifications();
                          unreadNotificationsCount();
                        });
                      },
                    ),
                    if (notificationsCount > 0)
                      Positioned(
                        right: 8,
                        top: 8,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                            '$notificationsCount',
                            style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                  ],
                ),

                // Logout Button
                IconButton(
                  icon: const Icon(Icons.logout_rounded, color: Colors.redAccent),
                  tooltip: "Logout",
                  onPressed: _showLogoutConfirmation, 
                )
              ],
            ],
          ),
        ),
      ),
      body: Stack(
        children: [
           // --- BACKGROUND DECORATION ---
           Positioned(
            top: -50,
            right: -50,
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 50, sigmaY: 50),
              child: Container(
                width: 300,
                height: 300,
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
           Positioned(
            bottom: 100,
            left: -50,
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 50, sigmaY: 50),
              child: Container(
                width: 300,
                height: 300,
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
          
          // --- CONTENT ---
          Padding(
            padding: const EdgeInsets.only(top: 100), // Offset karena AppBar tinggi
            child: _isPermissionLoading
                ? Shimmer.fromColors(
                    baseColor: Colors.grey[300]!,
                    highlightColor: Colors.grey[100]!,
                    child: ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: 3,
                      itemBuilder: (context, index) => Padding(
                        padding: const EdgeInsets.only(bottom: 16.0),
                        child: Container(
                          height: 80,
                          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
                        ),
                      ),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.all(16.0),
                    children: [
                      // MENU 1: EMPLOYEES
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16.0),
                        child: GlassContainer(
                          onTap: () {
                             Navigator.pushNamed(context, '/employees_list', arguments: permissionCheck);
                          },
                          child: ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.blue.shade50,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(Icons.people, color: Colors.blue),
                            ),
                            title: const Text('Employees', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                            subtitle: Text('Manage your employees', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                            trailing: const Icon(Icons.arrow_forward_ios_rounded, color: Colors.grey, size: 16),
                          ),
                        ),
                      ),
            
                      // MENU 2: ATTENDANCE
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16.0),
                        child: GlassContainer(
                          onTap: () {
                             if (permissionCheck) {
                              Navigator.pushNamed(context, '/attendance_overview', arguments: permissionCheck);
                            } else {
                              Navigator.pushNamed(context, '/employee_hour_account', arguments: permissionCheck);
                            }
                          },
                          child: ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.green.shade50,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(Icons.checklist_rtl, color: Colors.green),
                            ),
                            title: const Text('Attendances', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                            subtitle: Text('Track working hours', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                            trailing: const Icon(Icons.arrow_forward_ios_rounded, color: Colors.grey, size: 16),
                          ),
                        ),
                      ),
            
                      // MENU 3: LEAVES
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16.0),
                        child: GlassContainer(
                          onTap: () {
                             if (permissionLeaveOverviewCheck) {
                                Navigator.pushNamed(context, '/leave_overview');
                              } else {
                                Navigator.pushNamed(context, '/my_leave_request');
                              }
                          },
                          child: ListTile(
                             contentPadding: EdgeInsets.zero,
                             leading: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.orange.shade50,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(Icons.calendar_month_outlined, color: Colors.orange),
                            ),
                            title: const Text('Leaves', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                            subtitle: Text('Manage leave requests', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                            trailing: const Icon(Icons.arrow_forward_ios_rounded, color: Colors.grey, size: 16),
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
      extendBody: true,
      bottomNavigationBar: (bottomBarPages.length <= maxCount)
          ? CustomBottomNavBar(
              controller: _controller,
              employeeArguments: arguments,
            )
          : null,
    );
  }
}

class Home extends StatelessWidget {
  const Home({Key? key}) : super(key: key);
  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => Navigator.pushNamed(context, '/home'));
    return const SizedBox.shrink();
  }
}

class Overview extends StatelessWidget {
  const Overview({Key? key}) : super(key: key);
  @override
  Widget build(BuildContext context) {
    return const Center(child: Text('Overview'));
  }
}

class User extends StatelessWidget {
  const User({Key? key}) : super(key: key);
  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => Navigator.pushNamed(context, '/user'));
    return const SizedBox.shrink();
  }
}