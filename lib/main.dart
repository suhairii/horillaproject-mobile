import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui'; // Wajib untuk ImageFilter
// import 'package:flutter_face_api_beta/flutter_face_api.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

// Import views Anda
import 'attendance_views/attendance_attendance.dart';
import 'attendance_views/attendance_overview.dart';
import 'attendance_views/attendance_request.dart';
import 'attendance_views/hour_account.dart';
import 'attendance_views/my_attendance_view.dart';
import 'checkin_checkout/checkin_checkout_views/checkin_checkout_form.dart';
import 'employee_views/employee_form.dart';
import 'employee_views/employee_list.dart';
import 'horilla_leave/all_assigned_leave.dart';
import 'horilla_leave/leave_allocation_request.dart';
import 'horilla_leave/leave_overview.dart';
import 'horilla_leave/leave_request.dart';
import 'horilla_leave/leave_types.dart';
import 'horilla_leave/my_leave_request.dart';
import 'horilla_leave/selected_leave_type.dart';
import 'horilla_main/login.dart';
import 'horilla_main/home.dart';
import 'horilla_main/notifications_list.dart';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
// var faceSdk = FaceSDK.instance;
int currentPage = 1;
bool isFirstFetch = true;
Set<int> seenNotificationIds = {};
List<Map<String, dynamic>> notifications = [];
int notificationsCount = 0;
bool isLoading = true;
Timer? _notificationTimer;
Map<String, dynamic> arguments = {};
List<Map<String, dynamic>> fetchedNotifications = [];
Map<String, dynamic> newNotificationList = {};
bool isAuthenticated = false;

// --- WIDGET GLASMORPHISM (CLEAN WHITE VERSION) ---
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
    this.blur = 15.0, // Blur lebih tinggi untuk efek halus
    this.opacity = 0.6, // Opacity lebih tinggi agar terlihat di background putih
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
        // Shadow sangat penting di background putih agar "kaca" terlihat melayang
        boxShadow: hasShadow
            ? [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05), // Bayangan sangat halus
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
              // Gradient Putih ke Putih Transparan (Efek Es)
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white.withOpacity(0.8),
                  Colors.white.withOpacity(0.4),
                ],
              ),
              borderRadius: br,
              // Border putih solid/abu sangat muda untuk outline
              border: Border.all(
                color: Colors.white.withOpacity(0.6),
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
// ------------------------------------------------

@pragma('vm:entry-point')
Future<void> notificationTapBackground(
    NotificationResponse notificationResponse) async {
  if (!isAuthenticated) return;

  print('notification(${notificationResponse.id}) action tapped: '
      '${notificationResponse.actionId} with'
      ' payload: ${notificationResponse.payload}');
  if (notificationResponse.input?.isNotEmpty ?? false) {
    final context = navigatorKey.currentState?.context;
    if (context != null) {
      _onSelectNotification(context);
    }
    print(
        'notification action tapped with input: ${notificationResponse.input}');
  }
}

void _startNotificationTimer() {
  _notificationTimer?.cancel();
  _notificationTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
    if (isAuthenticated) {
      fetchNotifications();
      unreadNotificationsCount();
    } else {
      timer.cancel();
      _notificationTimer = null;
    }
  });
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // await faceSdk.initialize();

  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/horilla_logo');

  const DarwinInitializationSettings initializationSettingsIOS =
      DarwinInitializationSettings(
    requestAlertPermission: true,
    requestBadgePermission: true,
    requestSoundPermission: true,
  );

  final InitializationSettings initializationSettings = InitializationSettings(
    android: initializationSettingsAndroid,
    iOS: initializationSettingsIOS,
  );

  await flutterLocalNotificationsPlugin.initialize(
    initializationSettings,
    onDidReceiveNotificationResponse: (NotificationResponse details) async {
      final context = navigatorKey.currentState?.context;
      if (context != null && isAuthenticated) {
        _onSelectNotification(context);
      }
    },
    onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
  );

  final prefs = await SharedPreferences.getInstance();
  isAuthenticated = prefs.getString('token') != null;

  if (isAuthenticated) {
    _startNotificationTimer();
    prefetchData();
  }

  runApp(const LoginApp());
  clearSharedPrefs();
}

void clearSharedPrefs() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove('clockCheckedIn');
  await prefs.remove('checkout');
  await prefs.remove('checkin');
}

void _onSelectNotification(BuildContext context) {
  Navigator.pushNamed(context, '/notifications_list');
  markAllReadNotification();
}

void _showNotification() async {
  if (!isAuthenticated) return;
  FlutterRingtonePlayer().playNotification();
  const AndroidNotificationDetails androidPlatformChannelSpecifics =
      AndroidNotificationDetails(
          'your_channel_id', 'your_channel_name',
          channelDescription: 'your_channel_description',
          importance: Importance.max,
          priority: Priority.high,
          playSound: false,
          silent: true);

  const NotificationDetails platformChannelSpecifics =
      NotificationDetails(android: androidPlatformChannelSpecifics);
  
  if (newNotificationList.isNotEmpty && newNotificationList['timestamp'] != null) {
      final timestamp = DateTime.parse(newNotificationList['timestamp']);
      final timeAgo = timeago.format(timestamp);
      final user = arguments['employee_name'] ?? 'Unknown';
      print('$timeAgo by User $user');

      await flutterLocalNotificationsPlugin.show(
        newNotificationList['id'] ?? 0,
        newNotificationList['verb'] ?? 'Notification',
        '$timeAgo by User',
        platformChannelSpecifics,
        payload: 'your_payload',
      );
  }
}

Future<void> prefetchData() async {
  if (!isAuthenticated) return;

  final prefs = await SharedPreferences.getInstance();
  var token = prefs.getString("token");
  var typedServerurl = prefs.getString("typed_url");
  var employeeId = prefs.getInt("employee_id");

  if (token == null || typedServerurl == null || employeeId == null) return;

  try {
    var uri = Uri.parse('$typedServerurl/api/employee/employees/$employeeId');
    var response = await http.get(uri, headers: {
      "Content-Type": "application/json",
      "Authorization": "Bearer $token",
    });

    if (response.statusCode == 200) {
      final responseData = jsonDecode(response.body);
      arguments = {
        'employee_id': responseData['id'],
        'employee_name': (responseData['employee_first_name'] ?? '') +
            ' ' +
            (responseData['employee_last_name'] ?? ''),
        'badge_id': responseData['badge_id'],
        'email': responseData['email'],
        'phone': responseData['phone'],
        'date_of_birth': responseData['dob'],
        'gender': responseData['gender'],
        'address': responseData['address'],
        'country': responseData['country'],
        'state': responseData['state'],
        'city': responseData['city'],
        'qualification': responseData['qualification'],
        'experience': responseData['experience'],
        'marital_status': responseData['marital_status'],
        'children': responseData['children'],
        'emergency_contact': responseData['emergency_contact'],
        'emergency_contact_name': responseData['emergency_contact_name'],
        'employee_work_info_id': responseData['employee_work_info_id'],
        'employee_bank_details_id': responseData['employee_bank_details_id'],
        'employee_profile': responseData['employee_profile'],
        'job_position_name': responseData['job_position_name']
      };
    }
  } catch (e) {
    print("Error prefetching data: $e");
  }
}

Future<void> markAllReadNotification() async {
  if (!isAuthenticated) return;

  final prefs = await SharedPreferences.getInstance();
  var token = prefs.getString("token");
  var typedServerurl = prefs.getString("typed_url");

  if (token == null || typedServerurl == null) return;

  try {
    var uri =
        Uri.parse('$typedServerurl/api/notifications/notifications/bulk-read/');
    var response = await http.post(uri, headers: {
      "Content-Type": "application/json",
      "Authorization": "Bearer $token",
    });

    if (response.statusCode == 200) {
      notifications.clear();
      unreadNotificationsCount();
      fetchNotifications();
    }
  } catch (e) {
    print("Error marking notifications read: $e");
  }
}

Future<void> fetchNotifications() async {
  if (!isAuthenticated) {
    print('Notification fetch stopped - unauthenticated');
    return;
  }

  final prefs = await SharedPreferences.getInstance();
  var token = prefs.getString("token");
  var typedServerurl = prefs.getString("typed_url");

  if (token == null || typedServerurl == null) {
    print('Missing required data for notifications');
    return;
  }

  try {
    var uri = Uri.parse(
        '$typedServerurl/api/notifications/notifications/list/unread?page=${currentPage == 0 ? 1 : currentPage}');

    var response = await http.get(uri, headers: {
      "Content-Type": "application/json",
      "Authorization": "Bearer $token",
    }).timeout(const Duration(seconds: 3));

    if (response.statusCode == 200) {
      List<Map<String, dynamic>> fetchedNotifs =
          List<Map<String, dynamic>>.from(
        jsonDecode(response.body)['results']
            .where((notification) => notification['deleted'] == false)
            .toList(),
      );

      if (fetchedNotifs.isNotEmpty) {
        newNotificationList = fetchedNotifs[0];
        List<int> newNotificationIds = fetchedNotifs
            .map((notification) => notification['id'] as int)
            .toList();

        bool hasNewNotifications =
            newNotificationIds.any((id) => !seenNotificationIds.contains(id));

        if (!isFirstFetch && hasNewNotifications) {
          _playNotificationSound();
        }

        seenNotificationIds.addAll(newNotificationIds);
        notifications = fetchedNotifs;
        notificationsCount = jsonDecode(response.body)['count'];
        isFirstFetch = false;
        
        if(newNotificationList['timestamp'] != null) {
             final timestamp = DateTime.parse(newNotificationList['timestamp']);
             final timeAgo = timeago.format(timestamp);
             final user = arguments['employee_name'] ?? 'User';
             print('$timeAgo by User $user');
        }
        isLoading = false;
      }
    } else {
      print('Notification fetch failed with status: ${response.statusCode}');
    }
  } on SocketException catch (e) {
    print('Connection error fetching notifications: $e');
  } on TimeoutException catch (e) {
    print('Timeout fetching notifications: $e');
  } on Exception catch (e) {
    print('Error fetching notifications: $e');
  }
}

Future<void> unreadNotificationsCount() async {
  if (!isAuthenticated) return;

  final prefs = await SharedPreferences.getInstance();
  var token = prefs.getString("token");
  var typedServerurl = prefs.getString("typed_url");

  if (token == null || typedServerurl == null) return;

  try {
    var uri = Uri.parse(
        '$typedServerurl/api/notifications/notifications/list/unread');
    var response = await http.get(uri, headers: {
      "Content-Type": "application/json",
      "Authorization": "Bearer $token",
    });

    if (response.statusCode == 200) {
      notificationsCount = jsonDecode(response.body)['count'];
      isLoading = false;
    }
  } catch (e) {
    print("Error counting notifications: $e");
  }
}

void _playNotificationSound() {
  if (!isAuthenticated) return;
  _showNotification();
}

class LoginApp extends StatelessWidget {
  const LoginApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Definisi Warna Putih Bersih tapi Modern
    const Color backgroundWhite = Color(0xFFFAFAFA); 
    const Color textDark = Color(0xFF1F2937);

    return MaterialApp(
      title: 'Horilla HRMS',
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: backgroundWhite,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF3B82F6),
          brightness: Brightness.light,
          surface: Colors.white,
        ),
        // SAYA MENGHAPUS BLOK 'cardTheme' DISINI UNTUK MENGHINDARI ERROR
        // JIKA ANDA BUTUH CUSTOM CARD, GUNAKAN WIDGET 'GlassContainer' LANGSUNG
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          centerTitle: true,
          iconTheme: IconThemeData(color: textDark),
          titleTextStyle: TextStyle(
            color: textDark,
            fontSize: 18,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
      ),
      home: const FutureBuilderPage(),
      routes: {
        '/login': (context) => const LoginPage(),
        '/home': (context) => const HomePage(),
        '/employees_list': (context) => const EmployeeListPage(),
        '/employees_form': (context) => const EmployeeFormPage(),
        '/attendance_overview': (context) => const AttendanceOverview(),
        '/attendance_attendance': (context) => const AttendanceAttendance(),
        '/attendance_request': (context) => const AttendanceRequest(),
        '/my_attendance_view': (context) => const MyAttendanceViews(),
        '/employee_hour_account': (context) => const HourAccountFormPage(),
        '/employee_checkin_checkout': (context) => const CheckInCheckOutFormPage(),
        '/leave_overview': (context) => const LeaveOverview(),
        '/leave_types': (context) => const LeaveTypes(),
        '/my_leave_request': (context) => const MyLeaveRequest(),
        '/leave_request': (context) => const LeaveRequest(),
        '/leave_allocation_request': (context) => const LeaveAllocationRequest(),
        '/all_assigned_leave': (context) => const AllAssignedLeave(),
        '/selected_leave_type': (context) => const SelectedLeaveType(),
        '/notifications_list': (context) => const NotificationsList(),
      },
    );
  }
}

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      body: Stack(
        children: [
          Positioned(
            top: -50,
            right: -50,
            child: Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.05),
                shape: BoxShape.circle,
              ),
            ),
          ),
           Positioned(
            bottom: -50,
            left: -50,
            child: Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                color: Colors.purple.withOpacity(0.05),
                shape: BoxShape.circle,
              ),
            ),
          ),
          
          Center(
            child: GlassContainer(
              opacity: 0.7, 
              blur: 10,
              hasShadow: true,
              padding: const EdgeInsets.symmetric(horizontal: 50, vertical: 40),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Image.asset(
                    'Assets/horilla-logo.png',
                    width: 150,
                    height: 150,
                  ),
                  const SizedBox(height: 30),
                  const CircularProgressIndicator(),
                  const SizedBox(height: 20),
                  Text(
                    "Loading...",
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 14,
                      letterSpacing: 1.2
                    ),
                  )
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class FutureBuilderPage extends StatefulWidget {
  const FutureBuilderPage({super.key});

  @override
  State<FutureBuilderPage> createState() => _FutureBuilderPageState();
}

class _FutureBuilderPageState extends State<FutureBuilderPage> {
  late Future<bool> _futurePath;

  @override
  void initState() {
    super.initState();
    _futurePath = _initialize();
  }

  Future<bool> _initialize() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString("token") != null;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: Future.delayed(const Duration(seconds: 2), () => _futurePath),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SplashScreen();
        }

        if (snapshot.connectionState == ConnectionState.done) {
          if (snapshot.hasData && snapshot.data == true) {
            return const HomePage();
          } else {
            return const LoginPage();
          }
        }
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      },
    );
  }
}