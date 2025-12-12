import 'dart:convert';
import 'dart:ui'; // Wajib untuk ImageFilter
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:animated_notch_bottom_bar/animated_notch_bottom_bar/animated_notch_bottom_bar.dart';
import 'leave_request.dart';
import 'package:shimmer/shimmer.dart';

// Import Custom Bottom Navbar
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

class LeaveOverview extends StatefulWidget {
  const LeaveOverview({super.key});

  @override
  _LeaveOverview createState() => _LeaveOverview();
}

class _LeaveOverview extends State<LeaveOverview>
    with SingleTickerProviderStateMixin {
  final _pageController = PageController(initialPage: 0);
  
  // Index -1 karena ini bukan tab utama di BottomBar, tapi halaman turunan
  final _controller = NotchBottomBarController(index: -1);
  
  final List<Widget> bottomBarPages = [];
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  List<Map<String, dynamic>> newRequests = [];
  List<Map<String, dynamic>> requests = [];
  List<Map<String, dynamic>> requestsCount = [];
  List<Map<String, dynamic>> newApprovedRequests = [];
  int _currentPage = 0;
  final int _itemsPerPage = 5;
  int maxCount = 8;
  late int newRequestsCount = 0;
  late int newApprovedRequestsCount = 0;
  late String baseUrl = '';
  Map<String, dynamic> arguments = {}; // Inisialisasi kosong dulu
  bool isLoading = true;
  bool permissionLeaveTypeCheck = false;
  bool permissionLeaveAssignCheck = false;
  bool permissionLeaveRequestCheck = false;
  bool permissionLeaveOverviewCheck = false;
  bool permissionMyLeaveRequestCheck = false;
  bool permissionLeaveAllocationCheck = false;
  late String getToken = '';


  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    getAllLeaveRequest();
    getBaseUrl();
    fetchToken();
    prefetchData();
  }

  Future<void> fetchToken() async {
    final prefs = await SharedPreferences.getInstance();
    var token = prefs.getString("token");
    setState(() {
      getToken = token ?? '';
    });
  }

  Future<void> checkPermissions() async {
    await permissionLeaveOverviewChecks();
    await permissionLeaveTypeChecks();
    await permissionLeaveRequestChecks();
    await permissionLeaveAssignChecks();
  }

  Future<void> permissionLeaveOverviewChecks() async {
    final prefs = await SharedPreferences.getInstance();
    var token = prefs.getString("token");
    var typedServerUrl = prefs.getString("typed_url");
    var uri = Uri.parse('$typedServerUrl/api/leave/check-perm/');
    var response = await http.get(uri, headers: {
      "Content-Type": "application/json",
      "Authorization": "Bearer $token",
    });
    if (response.statusCode == 200) {
      permissionLeaveOverviewCheck = true;
      permissionMyLeaveRequestCheck = true;
      permissionLeaveAllocationCheck = true;
    } else {
      permissionMyLeaveRequestCheck = true;
      permissionLeaveAllocationCheck = true;
    }
  }

  Future<void> permissionLeaveTypeChecks() async {
    final prefs = await SharedPreferences.getInstance();
    var token = prefs.getString("token");
    var typedServerUrl = prefs.getString("typed_url");
    var uri = Uri.parse('$typedServerUrl/api/leave/check-type/');
    var response = await http.get(uri, headers: {
      "Content-Type": "application/json",
      "Authorization": "Bearer $token",
    });
    if (response.statusCode == 200) {
      permissionLeaveTypeCheck = true;
      permissionMyLeaveRequestCheck = true;
      permissionLeaveAllocationCheck = true;
    } else {
      permissionMyLeaveRequestCheck = true;
      permissionLeaveAllocationCheck = true;
    }
  }

  Future<void> permissionLeaveRequestChecks() async {
    final prefs = await SharedPreferences.getInstance();
    var token = prefs.getString("token");
    var typedServerUrl = prefs.getString("typed_url");
    var uri = Uri.parse('$typedServerUrl/api/leave/check-request/');
    var response = await http.get(uri, headers: {
      "Content-Type": "application/json",
      "Authorization": "Bearer $token",
    });
    if (response.statusCode == 200) {
      permissionLeaveRequestCheck = true;
      permissionMyLeaveRequestCheck = true;
      permissionLeaveAllocationCheck = true;
    } else {
      permissionMyLeaveRequestCheck = true;
      permissionLeaveAllocationCheck = true;
    }
  }

  Future<void> permissionLeaveAssignChecks() async {
    final prefs = await SharedPreferences.getInstance();
    var token = prefs.getString("token");
    var typedServerUrl = prefs.getString("typed_url");
    var uri = Uri.parse('$typedServerUrl/api/leave/check-assign/');
    var response = await http.get(uri, headers: {
      "Content-Type": "application/json",
      "Authorization": "Bearer $token",
    });
    if (response.statusCode == 200) {
      permissionLeaveAssignCheck = true;
      permissionMyLeaveRequestCheck = true;
      permissionLeaveAllocationCheck = true;
    } else {
      permissionMyLeaveRequestCheck = true;
      permissionLeaveAllocationCheck = true;
    }
  }

  Future<void> getBaseUrl() async {
    final prefs = await SharedPreferences.getInstance();
    var typedServerUrl = prefs.getString("typed_url");
    setState(() {
      baseUrl = typedServerUrl ?? '';
    });
  }

  void prefetchData() async {
    final prefs = await SharedPreferences.getInstance();
    var token = prefs.getString("token");
    var typedServerUrl = prefs.getString("typed_url");
    var employeeId = prefs.getInt("employee_id");
    
    if (employeeId == null) return;

    var uri = Uri.parse('$typedServerUrl/api/employee/employees/$employeeId');
    try {
      var response = await http.get(uri, headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $token",
      });

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        setState(() {
          arguments = {
            'employee_id': responseData['id'],
            'employee_name': responseData['employee_first_name'] + ' ' + responseData['employee_last_name'],
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
            'employee_profile': responseData['employee_profile']
          };
        });
      }
    } catch(e) {}
  }

  void _nextPage() {
    setState(() {
      if ((_currentPage + 1) * _itemsPerPage < requests.length) {
        _currentPage++;
      }
    });
  }

  void _previousPage() {
    setState(() {
      if (_currentPage > 0) {
        _currentPage--;
      }
    });
  }

  List<Map<String, dynamic>> getCurrentPageOfflineEmployees() {
    final int startIndex = _currentPage * _itemsPerPage;
    final int endIndex = startIndex + _itemsPerPage;
    if (startIndex >= requests.length) {
      return [];
    }
    return requests.sublist(
        startIndex, endIndex < requests.length ? endIndex : requests.length);
  }

  void handleConnectionError() {
    setState(() {
      isLoading = false;
    });
  }

  Future<void> getAllLeaveRequest() async {
    final prefs = await SharedPreferences.getInstance();
    var token = prefs.getString("token");
    var typedServerUrl = prefs.getString("typed_url");
    if(typedServerUrl == null || token == null) return;

    var now = DateTime.now();
    var formattedDate =
        "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
    await fetchApprovedRequests(typedServerUrl, token, formattedDate, now);
    await fetchAllRequests(typedServerUrl, token);
  }

  Future<void> fetchApprovedRequests(String serverUrl, String token,
      String formattedDate, DateTime now) async {
    var uri = Uri.parse(
        '$serverUrl/api/leave/request/?from_date=$formattedDate&to_date=$formattedDate&status=approved');
    try {
      var response = await http.get(uri, headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $token",
      });
      if (response.statusCode == 200) {
        setState(() {
          var allRequests = List<Map<String, dynamic>>.from(
            jsonDecode(response.body)['results'],
          );
          requests = allRequests;
          isLoading = false;
        });
      } else {
        handleConnectionError();
      }
    } catch (e) {
      handleConnectionError();
    }
  }

  Future<void> fetchAllRequests(String serverUrl, String token) async {
    var uri = Uri.parse('$serverUrl/api/leave/request');
    try {
      var response = await http.get(uri, headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $token",
      });

      if (response.statusCode == 200) {
        setState(() {
          requestsCount = List<Map<String, dynamic>>.from(
            jsonDecode(response.body)['results'],
          );

          newRequests = requestsCount
              .where((request) => request['status'] == 'requested')
              .toList();

          newApprovedRequests = requestsCount
              .where((request) => request['status'] == 'approved')
              .toList();

          newRequestsCount = newRequests.length;
          newApprovedRequestsCount = newApprovedRequests.length;
          isLoading = false;
        });
      } else {
        handleConnectionError();
      }
    } catch (e) {
      handleConnectionError();
    }
  }

  List<Map<String, dynamic>> getCurrentPageRequests() {
    final int startIndex = _currentPage * _itemsPerPage;
    final int endIndex = startIndex + _itemsPerPage;
    if (startIndex >= requests.length) {
      return [];
    }
    return requests.sublist(
        startIndex, endIndex < requests.length ? endIndex : requests.length);
  }

  @override
  Widget build(BuildContext context) {
    final currentPageRequests = getCurrentPageRequests();
    const Color textDark = Color(0xFF1F2937);

    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      key: _scaffoldKey,
      
      // --- APP BAR GLASS ---
      extendBodyBehindAppBar: true,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(80.0),
        child: Container(
          padding: const EdgeInsets.only(top: 10, left: 16, right: 16),
          child: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            automaticallyImplyLeading: false,
            // Title in Glass
            title: GlassContainer(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              borderRadius: BorderRadius.circular(30),
              hasShadow: false,
              opacity: 0.6,
              child: const Text(
                'Leave Overview',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: textDark),
              ),
            ),
            centerTitle: false,
            // Menu Button in Glass
            leading: Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: GlassContainer(
                onTap: () => _scaffoldKey.currentState?.openDrawer(),
                padding: const EdgeInsets.all(8),
                borderRadius: BorderRadius.circular(50),
                hasShadow: false,
                opacity: 0.6,
                child: const Icon(Icons.menu, color: textDark),
              ),
            ),
          ),
        ),
      ),

      body: Stack(
        children: [
           // --- BACKGROUND BLOBS ---
           Positioned(
            top: -50, right: -50,
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 50, sigmaY: 50),
              child: Container(width: 300, height: 300, decoration: BoxDecoration(color: Colors.blue.withOpacity(0.1), shape: BoxShape.circle)),
            ),
          ),
           Positioned(
            bottom: 100, left: -50,
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 50, sigmaY: 50),
              child: Container(width: 300, height: 300, decoration: BoxDecoration(color: Colors.red.withOpacity(0.1), shape: BoxShape.circle)),
            ),
          ),

          // --- CONTENT ---
          Padding(
            padding: const EdgeInsets.only(top: 100), // Offset AppBar
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: isLoading
                  ? _buildShimmerEffect(context)
                  : ListView(
                      padding: const EdgeInsets.only(bottom: 20),
                      children: [
                        // --- STATS CARDS ---
                        GestureDetector(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (context) => const LeaveRequest()),
                            );
                          },
                          child: Row(
                            children: [
                              Expanded(child: _buildGlassStatCard('NEW REQUEST', newRequestsCount, Colors.orangeAccent)),
                              const SizedBox(width: 15),
                              Expanded(child: _buildGlassStatCard('APPROVED', newApprovedRequestsCount, Colors.green)),
                            ],
                          ),
                        ),
                        
                        const SizedBox(height: 30),
                        
                        // --- ON LEAVE TODAY SECTION ---
                        GlassContainer(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            children: [
                              // Header with Arrows
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    'On Leave Today',
                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: textDark),
                                  ),
                                  Row(
                                    children: [
                                      IconButton(
                                        icon: const Icon(Icons.arrow_circle_left, color: Colors.red),
                                        onPressed: _previousPage,
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.arrow_circle_right, color: Colors.red),
                                        onPressed: _nextPage,
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              const Divider(),
                              
                              // List of People
                              SizedBox(
                                height: MediaQuery.of(context).size.height * 0.35,
                                child: currentPageRequests.isEmpty
                                    ? Center(
                                        child: Column(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Icon(Icons.event_busy, color: Colors.grey.shade400, size: 60),
                                            const SizedBox(height: 10),
                                            Text(
                                              'No one is on leave today',
                                              style: TextStyle(color: Colors.grey.shade500, fontWeight: FontWeight.w600),
                                            ),
                                          ],
                                        ),
                                      )
                                    : ListView.builder(
                                        shrinkWrap: true,
                                        physics: const NeverScrollableScrollPhysics(),
                                        itemCount: currentPageRequests.length,
                                        itemBuilder: (context, index) {
                                          final record = currentPageRequests[index];
                                          final fullName = record['employee_id']['full_name'];
                                          final badgeId = record['employee_id']['badge_id'];
                                          final image = record['employee_id']['employee_profile'];
                                          final requestId = record['id'];

                                          return buildLeaveTodayTile(
                                            context, fullName ?? "Unknown", image ?? "", baseUrl, getToken, badgeId ?? "", requestId
                                          );
                                        },
                                      ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
      
      // DRAWER
      drawer: Drawer(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        child: FutureBuilder<void>(
          future: checkPermissions(),
          builder: (context, snapshot) {
            return ListView(
              padding: EdgeInsets.zero,
              children: [
                DrawerHeader(
                  decoration: BoxDecoration(color: Colors.red.shade50),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Image.asset('Assets/horilla-logo.png', width: 60, height: 60),
                      const SizedBox(height: 10),
                      const Text("Leave Menu", style: TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
                if(permissionLeaveOverviewCheck) _drawerItem(Icons.dashboard_outlined, 'Overview', '/leave_overview', isSelected: true),
                if(permissionMyLeaveRequestCheck) _drawerItem(Icons.person_outline, 'My Leave Request', '/my_leave_request'),
                if(permissionLeaveRequestCheck) _drawerItem(Icons.list_alt, 'Leave Request', '/leave_request'),
                if(permissionLeaveTypeCheck) _drawerItem(Icons.category_outlined, 'Leave Type', '/leave_types'),
                if(permissionLeaveAllocationCheck) _drawerItem(Icons.approval, 'Leave Allocation Request', '/leave_allocation_request'),
                if(permissionLeaveAssignCheck) _drawerItem(Icons.assignment_turned_in, 'All Assigned Leave', '/all_assigned_leave'),
              ],
            );
          },
        ),
      ),
      
      // BOTTOM NAV BAR
      extendBody: true,
      bottomNavigationBar: CustomBottomNavBar(
        controller: _controller,
        employeeArguments: arguments,
      ),
    );
  }

  Widget _drawerItem(IconData icon, String title, String route, {bool isSelected = false}) {
    return ListTile(
      leading: Icon(icon, color: isSelected ? Colors.red : Colors.grey),
      title: Text(title, style: TextStyle(color: isSelected ? Colors.red : Colors.black87, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
      selected: isSelected,
      selectedTileColor: Colors.red.shade50,
      onTap: () {
        Navigator.pop(context);
        if (!isSelected) Navigator.pushNamed(context, route);
      },
    );
  }

  Widget _buildGlassStatCard(String title, int count, Color accentColor) {
    return GlassContainer(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: accentColor)),
          const SizedBox(height: 10),
          Text(
            count.toString(), 
            style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Color(0xFF1F2937))
          ),
          const SizedBox(height: 5),
          const Text("Requests", style: TextStyle(fontSize: 12, color: Colors.grey)),
        ],
      ),
    );
  }

  Widget buildLeaveTodayTile(BuildContext context, String fullName, String image,
      String baseUrl, token, String badgeId, int requestId) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.6), // Slightly distinctive background for list items
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.white.withOpacity(0.5))
      ),
      child: Row(
        children: [
          Container(
            width: 50, height: 50,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 5)]
            ),
            child: ClipOval(
              child: image.isNotEmpty
                ? Image.network(baseUrl + image, headers: {"Authorization": "Bearer $token"}, fit: BoxFit.cover,
                    errorBuilder: (ctx, exc, stack) => const Icon(Icons.person, color: Colors.grey))
                : Container(color: Colors.grey.shade200, child: const Icon(Icons.person, color: Colors.grey)),
            ),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(fullName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                Container(
                  margin: const EdgeInsets.only(top: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(6)),
                  child: Text(badgeId, style: TextStyle(fontSize: 10, color: Colors.red.shade700, fontWeight: FontWeight.bold)),
                )
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- SHIMMER LOADING ---
  Widget _buildShimmerEffect(BuildContext context) {
    return ListView(
      children: [
        Row(
          children: [
            Expanded(child: Shimmer.fromColors(baseColor: Colors.grey[300]!, highlightColor: Colors.grey[100]!, child: Container(height: 120, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20))))),
            const SizedBox(width: 15),
            Expanded(child: Shimmer.fromColors(baseColor: Colors.grey[300]!, highlightColor: Colors.grey[100]!, child: Container(height: 120, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20))))),
          ],
        ),
        const SizedBox(height: 30),
        Shimmer.fromColors(
          baseColor: Colors.grey[300]!,
          highlightColor: Colors.grey[100]!,
          child: Container(height: 400, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20))),
        )
      ],
    );
  }
}