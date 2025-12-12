import 'dart:async';
import 'dart:convert';
import 'dart:ui'; // Wajib untuk ImageFilter
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:internet_connection_checker/internet_connection_checker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:animated_notch_bottom_bar/animated_notch_bottom_bar/animated_notch_bottom_bar.dart';
import 'package:shimmer/shimmer.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';

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

class EmployeeListPage extends StatefulWidget {
  const EmployeeListPage({super.key});

  @override
  _EmployeeListPageState createState() => _EmployeeListPageState();
}

class StateInfo {
  final Color color;
  final String displayString;

  StateInfo(this.color, this.displayString);
}

class _EmployeeListPageState extends State<EmployeeListPage> {
  // --- CONNECTION STATE ---
  late StreamSubscription subscription;
  var isDeviceConnected = false;
  // ------------------------

  List<Map<String, dynamic>> requests = [];
  String searchText = '';
  List<dynamic> filteredRecords = [];
  final ScrollController _scrollController = ScrollController();
  final List<Widget> bottomBarPages = [];
  final _pageController = PageController(initialPage: 0);
  
  // Set index ke 2 (Tab Employee)
  final _controller = NotchBottomBarController(index: 2);
  
  int currentPage = 1;
  int requestsCount = 0;
  int maxCount = 5;
  late Map<String, dynamic> arguments = {}; 
  late String baseUrl = '';
  late String getToken = '';
  bool isLoading = true;
  bool _isShimmer = true;
  bool hasMore = true;
  bool hasNoMore = false;
  String nextPage = '';

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_scrollListener);
    
    getConnectivity();
    InternetConnectionChecker().hasConnection.then((value) {
      setState(() {
        isDeviceConnected = value;
      });
      _initializeData();
    });
  }

  void _scrollListener() {
    if (_scrollController.offset >=
            _scrollController.position.maxScrollExtent &&
        !_scrollController.position.outOfRange) {
      if (isDeviceConnected) {
        currentPage++;
        getEmployeeDetails();
      }
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    _scrollController.removeListener(_scrollListener);
    _scrollController.dispose();
    subscription.cancel(); 
    super.dispose();
  }

  // --- CONNECTIVITY & DATA LOGIC ---

  void getConnectivity() {
    subscription = InternetConnectionChecker().onStatusChange.listen((status) {
      setState(() {
        isDeviceConnected = status == InternetConnectionStatus.connected;
        if (isDeviceConnected) {
          getEmployeeDetails(); 
        }
      });
    });
  }

  Future<void> _initializeData() async {
    await getBaseUrl();
    await fetchToken();
    await prefetchData();
    await _loadFromCache();
    await _simulateLoading();

    if (isDeviceConnected) {
      await getEmployeeDetails();
    } else {
      setState(() {
        isLoading = false;
      });
    }
  }

  Future<void> _loadFromCache() async {
    final prefs = await SharedPreferences.getInstance();
    String? cachedList = prefs.getString('cache_employee_list');
    
    if (cachedList != null) {
      setState(() {
        List<dynamic> decoded = jsonDecode(cachedList);
        requests = decoded.cast<Map<String, dynamic>>().toList();
        requestsCount = requests.length;
        filteredRecords = requests; 
      });
    }
  }

  Future<void> getBaseUrl() async {
    final prefs = await SharedPreferences.getInstance();
    var typedServerUrl = prefs.getString("typed_url");
    setState(() {
      baseUrl = typedServerUrl ?? '';
    });
  }

  Future<void> fetchToken() async {
    final prefs = await SharedPreferences.getInstance();
    var token = prefs.getString("token");
    setState(() {
      getToken = token ?? '';
    });
  }

  Future<void> prefetchData() async {
    final prefs = await SharedPreferences.getInstance();
    if (isDeviceConnected) {
      try {
        var token = prefs.getString("token");
        var typedServerUrl = prefs.getString("typed_url");
        var employeeId = prefs.getInt("employee_id");
        if (token == null || typedServerUrl == null || employeeId == null) return;

        var uri = Uri.parse('$typedServerUrl/api/employee/employees/$employeeId');
        var response = await http.get(uri, headers: {
          "Content-Type": "application/json",
          "Authorization": "Bearer $token",
        });

        if (response.statusCode == 200) {
          await prefs.setString('cache_my_profile_data', response.body);
          final responseData = jsonDecode(response.body);
          setState(() {
            arguments = _parseProfileData(responseData);
          });
        }
      } catch (e) {
      }
    } else {
      String? cachedProfile = prefs.getString('cache_my_profile_data');
      if (cachedProfile != null) {
        setState(() {
          arguments = _parseProfileData(jsonDecode(cachedProfile));
        });
      }
    }
  }

  Map<String, dynamic> _parseProfileData(Map<String, dynamic> responseData) {
    return {
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
      'employee_profile': responseData['employee_profile']
    };
  }

  Future<void> _simulateLoading() async {
    await Future.delayed(const Duration(seconds: 2));
    setState(() {
      _isShimmer = false;
    });
  }

  Future<void> getEmployeeDetails() async {
    if (!isDeviceConnected && requests.isNotEmpty) {
      setState(() {
        isLoading = false;
      });
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    var token = prefs.getString("token");
    var typedServerUrl = prefs.getString("typed_url");
    
    if (token == null || typedServerUrl == null) return;

    try {
      var uri = Uri.parse(
          '$typedServerUrl/api/employee/list/employees?page=$currentPage&search=$searchText');
      var response = await http.get(uri, headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $token",
      });
      
      if (response.statusCode == 200) {
        var responseBody = jsonDecode(response.body);
        List<Map<String, dynamic>> newResults = List<Map<String, dynamic>>.from(responseBody['results']);
        
        setState(() {
          if (currentPage == 1 && searchText.isEmpty) {
             prefs.setString('cache_employee_list', jsonEncode(newResults));
          }

          requests.addAll(newResults);
          requestsCount = responseBody['count'];

          String serializeMap(Map<String, dynamic> map) {
            return jsonEncode(map);
          }

          Map<String, dynamic> deserializeMap(String jsonString) {
            return jsonDecode(jsonString);
          }

          List<String> mapStrings = requests.map(serializeMap).toList();
          Set<String> uniqueMapStrings = mapStrings.toSet();
          requests = uniqueMapStrings.map(deserializeMap).toList();
          
          filteredRecords = filterRecords(searchText);
          isLoading = false;
          nextPage = responseBody['next'] ?? '';
        });
      } else {
        setState(() {
          hasNoMore = true;
          isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        isLoading = false;
      });
    }
  }

  List<dynamic> filterRecords(String searchText) {
    List<dynamic> allRecords = requests;
    if (searchText.isEmpty) return allRecords;

    List<dynamic> filtered = allRecords.where((record) {
      final firstName = record['employee_first_name'] ?? '';
      final lastName = record['employee_last_name'] ?? '';
      final fullName = (firstName + ' ' + lastName).toLowerCase();
      final jobPosition = record['job_position_name'] ?? '';
      return fullName.contains(searchText.toLowerCase()) ||
          jobPosition.toLowerCase().contains(searchText.toLowerCase());
    }).toList();

    return filtered;
  }

  Color _getColorForPosition(String position) {
    int hashCode = position.hashCode;
    return Color((hashCode & 0xFFFFFF).toInt()).withOpacity(1.0);
  }

  Widget buildListItem(Map<String, dynamic> record, baseUrl, token) {
    String position = record['job_position_name'] ?? 'Unknown';
    Color positionColor = _getColorForPosition(position);
    
    // --- UPDATED LIST ITEM (GLASS STYLE) ---
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: GlassContainer(
        padding: const EdgeInsets.all(10),
        onTap: () {
          final args = ModalRoute.of(context)?.settings.arguments;
          Navigator.pushNamed(context, '/employees_form', arguments: {
            'employee_id': record['id'],
            'employee_name': record['employee_first_name'] +
                ' ' +
                record['employee_last_name'],
            'permission_check': args,
          });
        },
        child: Row(
          children: [
            // AVATAR
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 5)
                ]
              ),
              child: CircleAvatar(
                radius: 25.0,
                backgroundColor: Colors.grey[200],
                child: ClipOval(
                  child: (record['employee_profile'] != null && record['employee_profile'].isNotEmpty)
                    ? Image.network(
                        baseUrl + record['employee_profile'],
                        headers: {"Authorization": "Bearer $token"},
                        fit: BoxFit.cover,
                        width: 50, height: 50,
                        errorBuilder: (context, exception, stackTrace) => const Icon(Icons.person, color: Colors.grey),
                      )
                    : const Icon(Icons.person, color: Colors.grey),
                ),
              ),
            ),
            const SizedBox(width: 15),
            
            // INFO
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    record['employee_first_name'] + ' ' + (record['employee_last_name'] ?? ''),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16.0, color: Color(0xFF1F2937)),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    record['email'],
                    style: TextStyle(fontWeight: FontWeight.normal, fontSize: 12.0, color: Colors.grey[600]),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  // BADGE POSITION
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: positionColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: positionColor.withOpacity(0.3))
                    ),
                    child: Text(
                      position,
                      style: TextStyle(fontSize: 10.0, color: positionColor, fontWeight: FontWeight.bold),
                    ),
                  )
                ],
              ),
            ),
            
            const Icon(Icons.arrow_forward_ios_rounded, size: 16, color: Colors.grey),
          ],
        ),
      ),
    );
  }

  Future<void> loadMoreData() async {
    if (isDeviceConnected) {
      currentPage++;
      await getEmployeeDetails();
    }
  }

  @override
  Widget build(BuildContext context) {
    const Color textDark = Color(0xFF1F2937);

    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      
      // 1. App Bar Transparan
      extendBodyBehindAppBar: true, 
      extendBody: false,

      // -- UPDATED APP BAR --
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(80.0), 
        child: Container(
          padding: const EdgeInsets.only(top: 10, left: 16, right: 16),
          child: AppBar(
            forceMaterialTransparency: true,
            backgroundColor: Colors.transparent,
            elevation: 0,
            automaticallyImplyLeading: false,
            
            // TITLE GLASS
            title: GlassContainer(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              borderRadius: BorderRadius.circular(30),
              hasShadow: false,
              opacity: 0.6,
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.people_alt_rounded, color: textDark, size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Employees',
                    style: TextStyle(fontWeight: FontWeight.bold, color: textDark, fontSize: 16),
                  ),
                ],
              ),
            ),
            centerTitle: false,
            
            actions: [
               // INDIKATOR KONEKSI
               GlassContainer(
                 padding: const EdgeInsets.all(8),
                 borderRadius: BorderRadius.circular(50),
                 hasShadow: false,
                 child: Row(
                   children: [
                     Container(
                       width: 10, height: 10,
                       decoration: BoxDecoration(
                         shape: BoxShape.circle,
                         color: isDeviceConnected ? Colors.green : Colors.amber,
                         boxShadow: [BoxShadow(color: (isDeviceConnected ? Colors.green : Colors.amber).withOpacity(0.4), blurRadius: 4)]
                       ),
                     ),
                     const SizedBox(width: 6),
                     Text(isDeviceConnected ? "Online" : "Offline", style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold))
                   ],
                 ),
               ),
            ],
          ),
        ),
      ),
      
      body: Stack(
        children: [
          // BACKGROUND BLOBS
          Positioned(
            top: -50, right: -50,
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 50, sigmaY: 50),
              child: Container(width: 250, height: 250, decoration: BoxDecoration(color: Colors.blue.withOpacity(0.1), shape: BoxShape.circle)),
            ),
          ),
          Positioned(
            bottom: 100, left: -50,
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 50, sigmaY: 50),
              child: Container(width: 250, height: 250, decoration: BoxDecoration(color: Colors.red.withOpacity(0.1), shape: BoxShape.circle)),
            ),
          ),

          // CONTENT
          Padding(
            padding: const EdgeInsets.only(top: 100), // Offset AppBar
            child: Column(
              children: [
                // SEARCH BAR
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                  child: GlassContainer(
                    padding: EdgeInsets.zero,
                    child: TextField(
                      enabled: true,
                      onChanged: (val) {
                        setState(() {
                          searchText = val;
                          if (isDeviceConnected) getEmployeeDetails();
                          else filteredRecords = filterRecords(searchText);
                        });
                      },
                      decoration: InputDecoration(
                        hintText: isDeviceConnected ? 'Search employees...' : 'Search (Offline)',
                        border: InputBorder.none,
                        prefixIcon: const Icon(Icons.search, color: Colors.grey),
                        contentPadding: const EdgeInsets.symmetric(vertical: 15),
                      ),
                    ),
                  ),
                ),

                // LIST OR LOADING
                Expanded(
                  child: isLoading
                      ? _buildShimmerList()
                      : requests.isEmpty
                          ? const Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.search_off, color: Colors.grey, size: 60),
                                  SizedBox(height: 10),
                                  Text("No employees found", style: TextStyle(color: Colors.grey)),
                                ],
                              ),
                            )
                          : ListView.builder(
                              controller: _scrollController,
                              padding: const EdgeInsets.only(bottom: 20),
                              itemCount: searchText.isEmpty
                                  ? requests.length + (hasMore && isDeviceConnected ? 1 : 0)
                                  : filteredRecords.length,
                              itemBuilder: (context, index) {
                                if (index == requests.length && searchText.isEmpty && hasMore && isDeviceConnected) {
                                  return nextPage != ''
                                      ? Center(child: Padding(padding: const EdgeInsets.all(20), child: LoadingAnimationWidget.bouncingBall(size: 25, color: Colors.grey)))
                                      : const SizedBox();
                                }
                                
                                if (index >= (searchText.isEmpty ? requests.length : filteredRecords.length)) return const SizedBox();

                                final record = searchText.isEmpty ? requests[index] : filteredRecords[index];
                                return buildListItem(record, baseUrl, getToken);
                              },
                            ),
                ),
              ],
            ),
          )
        ],
      ),
      
      // CUSTOM NAVBAR
      bottomNavigationBar: CustomBottomNavBar(
        controller: _controller,
        employeeArguments: arguments,
      ),
    );
  }

  Widget _buildShimmerList() {
    return ListView.builder(
      itemCount: 6,
      padding: const EdgeInsets.all(16),
      itemBuilder: (context, index) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 16.0),
          child: Shimmer.fromColors(
            baseColor: Colors.grey[300]!,
            highlightColor: Colors.grey[100]!,
            child: Container(
              height: 80,
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
            ),
          ),
        );
      },
    );
  }
}