import 'dart:async';
import 'dart:convert';
import 'dart:ui'; // Wajib untuk ImageFilter
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:multiselect_dropdown_flutter/multiselect_dropdown_flutter.dart';
import 'package:animated_notch_bottom_bar/animated_notch_bottom_bar/animated_notch_bottom_bar.dart';
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

class AllAssignedLeave extends StatefulWidget {
  const AllAssignedLeave({super.key});

  @override
  _AllAssignedLeave createState() => _AllAssignedLeave();
}

class _AllAssignedLeave extends State<AllAssignedLeave> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  
  // Set index -1 karena ini bukan main tab, tapi menggunakan navbar yang sama
  final _controller = NotchBottomBarController(index: -1);
  
  final List<Widget> bottomBarPages = [];
  List<Map<String, dynamic>> leaveType = [];
  List<dynamic> leaveTypes = [];
  List<Map<String, dynamic>> requestsEmployeesName = [];
  List<Map<String, dynamic>> allEmployeeList = [];
  List<dynamic> filteredRecords = [];
  List<String> createItems = [];
  List<dynamic> selectedLeaveIds = [];
  List<String> selectedEmployeeNames = [];
  List<int> selectedEmployeeIds = [];
  List<String> selectedLeaveItems = [];
  List<String> selectedEmpItems = [];
  List<dynamic> createRecords = [];
  List<String> selectedEmployeeItems = [];
  List<dynamic> leaveItems = [];
  List<Map<String, dynamic>> allLeaveList = [];
  List<int> assignedTypeItem = [];
  var employeeItems = [];
  var employeeItemsId = [];
  var leaveItemsId = [];
  int? selectedLeaveId;
  int maxCount = 5;
  bool isLoading = true;
  bool isAction = true;
  bool _isShimmer = true;
  bool _isShimmerVisible = true;
  bool permissionLeaveTypeCheck = false;
  bool permissionLeaveAssignCheck = false;
  bool permissionLeaveRequestCheck = false;
  bool permissionLeaveOverviewCheck = false;
  bool permissionMyLeaveRequestCheck = false;
  bool permissionLeaveAllocationCheck = false;
  String searchText = '';
  String? selectedLeaveType;
  late String baseUrl = '';
  Map<String, dynamic> arguments = {};
  late String getToken = '';


  @override
  void initState() {
    super.initState();
    leaveType.clear();
    getLeaveType();
    getAssignedLeaveType();
    getLeaveTypes();
    getEmployees();
    fetchToken();
    getBaseUrl();
    prefetchData();
    _simulateLoading();
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

  Future<void> _simulateLoading() async {
    // Dikurangi durasinya agar tidak terlalu lama menunggu
    await Future.delayed(const Duration(seconds: 2)); 
    setState(() {
      _isShimmer = false;
    });
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

  void prefetchData() async {
    final prefs = await SharedPreferences.getInstance();
    var token = prefs.getString("token");
    var typedServerUrl = prefs.getString("typed_url");
    var employeeId = prefs.getInt("employee_id");
    if(employeeId == null) return;
    
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

  Future<void> getBaseUrl() async {
    final prefs = await SharedPreferences.getInstance();
    var typedServerUrl = prefs.getString("typed_url");
    setState(() {
      baseUrl = typedServerUrl ?? '';
    });
  }

  Future<void> getEmployees() async {
    final prefs = await SharedPreferences.getInstance();
    var token = prefs.getString("token");
    var typedServerUrl = prefs.getString("typed_url");

    employeeItems.clear();
    employeeItemsId.clear();
    allEmployeeList = [];

    for (var page = 1;; page++) {
      var uri = Uri.parse(
          '$typedServerUrl/api/employee/employee-selector/?page=$page');
      var response = await http.get(uri, headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $token",
      });

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final results = data['results'];

        if (results.isEmpty) break;

        setState(() {
          for (var employee in results) {
            String fullName =
            "${employee['employee_first_name'] ?? ''} ${employee['employee_last_name'] ?? ''}".trim();
            employeeItems.add(fullName);
            employeeItemsId.add(employee['id']);
          }
          allEmployeeList.addAll(List<Map<String, dynamic>>.from(results));
        });
      } else {
        break;
      }
    }
  }

  Future<void> getLeaveTypes() async {
    final prefs = await SharedPreferences.getInstance();
    var token = prefs.getString("token");
    var typedServerUrl = prefs.getString("typed_url");
    var uri = Uri.parse('$typedServerUrl/api/leave/leave-type/');
    var response = await http.get(uri, headers: {
      "Content-Type": "application/json",
      "Authorization": "Bearer $token",
    });

    if (response.statusCode == 200) {
      setState(() {
        for (var type in jsonDecode(response.body)['results']) {
          String fullName = type['name'];

          leaveItems.add(fullName);
          leaveItemsId.add(type['id']);
        }
        allLeaveList = List<Map<String, dynamic>>.from(
          jsonDecode(response.body)['results'],
        );
      });
    }
  }

  void showAssignAnimation() {
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
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset(imagePath, width: 150, height: 150),
                const SizedBox(height: 16),
                const Text(
                  "Leave Assigned Successfully",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.red),
                ),
              ],
            ),
          ),
        );
      },
    );
    Future.delayed(const Duration(seconds: 2), () {
      Navigator.of(context).pop();
    });
  }

  Future<void> getLeaveType() async {
    final prefs = await SharedPreferences.getInstance();
    var token = prefs.getString("token");
    var typedServerUrl = prefs.getString("typed_url");
    var uri = Uri.parse('$typedServerUrl/api/leave/leave-type/');
    var response = await http.get(uri, headers: {
      "Content-Type": "application/json",
      "Authorization": "Bearer $token",
    });
    if (response.statusCode == 200) {
      setState(() {
        var assignedType = jsonDecode(response.body)['results'];
        for (var recAssignedType in assignedType) {
          assignedTypeItem.add(recAssignedType['id']);
        }
      });
    }
  }

  _showCreateDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) {
            return AlertDialog(
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              title: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Assign Leaves', style: TextStyle(fontWeight: FontWeight.bold)),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.grey),
                    onPressed: () {
                      selectedLeaveIds.clear();
                      selectedEmployeeIds.clear();
                      selectedEmployeeNames.clear();
                      Navigator.of(context).pop();
                    },
                  ),
                ],
              ),
              content: SizedBox(
                width: MediaQuery.of(context).size.width * 0.95,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("Leave Type", style: TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      MultiSelectDropdown.simpleList(
                        list: leaveItems,
                        initiallySelected: const [],
                        onChange: (selectedItems) {
                          setState(() {
                            selectedLeaveIds.clear();
                            selectedLeaveIds.addAll(selectedItems);
                          });
                        },
                        includeSearch: true,
                        includeSelectAll: true,
                        isLarge: true,
                        numberOfItemsLabelToShow: 3,
                        checkboxFillColor: Colors.grey,
                        boxDecoration: BoxDecoration(
                          border: Border.all(color: Colors.red.shade200),
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8.0,
                        children: selectedLeaveIds.map((leave) {
                          return Chip(
                            backgroundColor: Colors.red.shade50,
                            label: Text(leave, style: const TextStyle(fontSize: 12)),
                            deleteIcon: const Icon(Icons.cancel, size: 18),
                            onDeleted: () {
                              setState(() {
                                selectedLeaveIds.remove(leave);
                              });
                            },
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 15),
                      const Text("Employee", style: TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      MultiSelectDropdown.simpleList(
                        list: employeeItems,
                        initiallySelected: const [],
                        onChange: (selectedItems) {
                          setState(() {
                            selectedEmployeeNames.clear();
                            selectedEmployeeIds.clear();
                            if (selectedItems.contains('Select All')) {
                              selectedEmployeeNames = List.from(employeeItems);
                              selectedEmployeeIds = List.from(employeeItemsId);
                              selectedEmployeeNames.remove('Select All');
                            } else {
                              for (var item in selectedItems) {
                                selectedEmployeeNames.add(item);
                                int index = employeeItems.indexOf(item);
                                if (index != -1) {
                                  selectedEmployeeIds.add(employeeItemsId[index]);
                                }
                              }
                            }
                          });
                        },
                        includeSearch: true,
                        includeSelectAll: true,
                        isLarge: true,
                        width: 300,
                        numberOfItemsLabelToShow: 2,
                        checkboxFillColor: Colors.grey,
                        boxDecoration: BoxDecoration(
                          border: Border.all(color: Colors.red.shade200),
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8.0,
                        children: selectedEmployeeNames.map((name) {
                          return Chip(
                            backgroundColor: Colors.blue.shade50,
                            label: Text(name, style: const TextStyle(fontSize: 12)),
                            deleteIcon: const Icon(Icons.cancel, size: 18),
                            onDeleted: () {
                              setState(() {
                                int index = selectedEmployeeNames.indexOf(name);
                                if (index != -1) {
                                  selectedEmployeeNames.removeAt(index);
                                  selectedEmployeeIds.removeAt(index);
                                }
                              });
                            },
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () async {
                            setState(() => isAction = true);
                            await createAssignedLeaveType(
                                selectedEmployeeIds, selectedLeaveIds);
                            await getAssignedLeaveType();
                            setState(() => isAction = false);
                            Navigator.of(context).pop(true);
                            showAssignAnimation();
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            padding: const EdgeInsets.symmetric(vertical: 15)
                          ),
                          child: isAction 
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) 
                            : const Text('Save', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> createAssignedLeaveType(selectedEmployeeIds, selectedLeaveIds) async {
    final prefs = await SharedPreferences.getInstance();
    var token = prefs.getString("token");
    var typedServerUrl = prefs.getString("typed_url");
    for (var leave in selectedLeaveIds) {
      var uri = Uri.parse('$typedServerUrl/api/leave/assign-leave/');
      for (var allLeave in allLeaveList) {
        if (allLeave['name'] == leave) {
          var leaveId = allLeave['id'];
          var body = jsonEncode({
            "employee_ids": selectedEmployeeIds,
            "leave_type_ids": [leaveId],
          });

          await http.post(uri,
              headers: {
                "Content-Type": "application/json",
                "Authorization": "Bearer $token",
              },
              body: body);
        }
      }
    }
  }

  Future<void> getAssignedLeaveType() async {
    final prefs = await SharedPreferences.getInstance();
    var token = prefs.getString("token");
    var typedServerUrl = prefs.getString("typed_url");
    int page = 1;
    bool hasMoreData = true;

    List<Map<String, dynamic>> allLeaveTypes = [];

    while (hasMoreData) {
      var uri = Uri.parse(
          '$typedServerUrl/api/leave/assign-leave/?leave_type_id=$assignedTypeItem&page=$page');
      var response = await http.get(uri, headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $token",
      });
      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        List<dynamic> results = responseData['results'];

        if (results.isNotEmpty) {
          allLeaveTypes.addAll(List<Map<String, dynamic>>.from(results));
          page++;
        } else {
          hasMoreData = false;
        }

        if (mounted) {
          setState(() {
            leaveType = allLeaveTypes;
            isLoading = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _isShimmerVisible = false;
            hasMoreData = false;
          });
        }
      }
    }
  }

  List<Map<String, dynamic>> filterRecords(String searchText) {
    List<Map<String, dynamic>> allRecords = [];
    allRecords.addAll(allEmployeeList);

    List<Map<String, dynamic>> filteredRecords = allRecords.where((record) {
      String firstName = record['employee_first_name'].toString().toLowerCase();
      String lastName = record['employee_last_name'].toString().toLowerCase();
      String fullName = '$firstName $lastName';
      String search = searchText.toLowerCase();
      return fullName.startsWith(search);
    }).toList();

    return filteredRecords;
  }

  @override
  Widget build(BuildContext context) {
    const Color textDark = Color(0xFF1F2937);

    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      key: _scaffoldKey,
      
      // -- APP BAR MODERN --
      extendBodyBehindAppBar: true,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(80.0),
        child: Container(
          padding: const EdgeInsets.only(top: 10, left: 16, right: 16),
          child: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            automaticallyImplyLeading: false,
            // Custom Glass Title
            title: GlassContainer(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              borderRadius: BorderRadius.circular(30),
              hasShadow: false,
              opacity: 0.6,
              child: const Text(
                'Assigned Leave',
                style: TextStyle(fontWeight: FontWeight.bold, color: textDark, fontSize: 16),
              ),
            ),
            centerTitle: false,
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
            actions: [
              GlassContainer(
                onTap: () {
                  isAction = false;
                  _showCreateDialog(context);
                },
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                borderRadius: BorderRadius.circular(30),
                hasShadow: false,
                opacity: 0.6,
                child: const Row(
                  children: [
                    Icon(Icons.add, color: Colors.red, size: 20),
                    SizedBox(width: 4),
                    Text("ASSIGN", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 12)),
                  ],
                ),
              ),
            ],
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
            child: _isShimmerVisible ? _buildLoadingWidget() : _buildAllAssignedLeaveWidget(),
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
                      const Text("Leave Management", style: TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
                if (permissionLeaveOverviewCheck) _drawerItem(Icons.dashboard_outlined, 'Overview', '/leave_overview'),
                if (permissionMyLeaveRequestCheck) _drawerItem(Icons.person_outline, 'My Leave Request', '/my_leave_request'),
                if (permissionLeaveRequestCheck) _drawerItem(Icons.list_alt, 'Leave Request', '/leave_request'),
                if (permissionLeaveTypeCheck) _drawerItem(Icons.category_outlined, 'Leave Type', '/leave_types'),
                if (permissionLeaveAllocationCheck) _drawerItem(Icons.approval, 'Leave Allocation Request', '/leave_allocation_request'),
                if (permissionLeaveAssignCheck) _drawerItem(Icons.assignment_turned_in, 'All Assigned Leave', '/all_assigned_leave', isSelected: true),
              ],
            );
          },
        ),
      ),
      
      // BOTTOM NAV
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

  Widget _buildLoadingWidget() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Column(
        children: [
          Shimmer.fromColors(
            baseColor: Colors.grey[300]!,
            highlightColor: Colors.grey[100]!,
            child: Container(
              height: 50,
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15)),
            ),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: ListView.builder(
              itemCount: 5,
              itemBuilder: (ctx, index) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Shimmer.fromColors(
                  baseColor: Colors.grey[300]!,
                  highlightColor: Colors.grey[100]!,
                  child: Container(height: 60, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10))),
                ),
              ),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildAllAssignedLeaveWidget() {
    return Column(
      children: [
        // SEARCH BAR
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: GlassContainer(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: TextField(
              onChanged: (val) {
                setState(() {
                  searchText = val;
                  filteredRecords = filterRecords(searchText);
                });
              },
              decoration: InputDecoration(
                hintText: 'Search employee...',
                border: InputBorder.none,
                prefixIcon: Icon(Icons.search, color: Colors.blueGrey.shade300),
                contentPadding: const EdgeInsets.symmetric(vertical: 12.0),
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),
        
        // LIST
        Expanded(
          child: buildTabContentAttendance(leaveType, searchText, getToken),
        ),
      ],
    );
  }

  Widget buildTabContentAttendance(List<Map<String, dynamic>> leaveType, String searchText, token) {
    List<Map<String, dynamic>> filteredLeaveType = leaveType.where((leave) {
      String employeeFullName = leave['employee_id']['full_name'].toString().toLowerCase();
      return employeeFullName.contains(searchText.toLowerCase());
    }).toList();

    Map<String, List<Map<String, dynamic>>> leaveGroups = {};
    for (var record in filteredLeaveType) {
      final leaveName = record['leave_type_id']['name'] ?? 'Unnamed Leave Type';
      leaveGroups.putIfAbsent(leaveName, () => []).add(record);
    }

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      children: leaveGroups.entries.map((entry) {
        final leaveName = entry.key;
        final leaveRecords = entry.value;
        final leaveIcon = leaveRecords.isNotEmpty && leaveRecords[0]['leave_type_id']['icon'] != null
            ? leaveRecords[0]['leave_type_id']['icon']
            : null;

        return Padding(
          padding: const EdgeInsets.only(bottom: 12.0),
          child: GlassContainer(
            padding: EdgeInsets.zero,
            child: Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                leading: Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withOpacity(0.5)),
                  child: ClipOval(
                    child: leaveIcon != null
                      ? Image.network(baseUrl + leaveIcon, headers: {"Authorization": "Bearer $token"}, fit: BoxFit.cover, errorBuilder: (c,e,s) => const Icon(Icons.calendar_today, size: 20, color: Colors.red))
                      : const Icon(Icons.calendar_today, size: 20, color: Colors.red),
                  ),
                ),
                title: Text(leaveName, style: const TextStyle(fontWeight: FontWeight.bold)),
                trailing: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.redAccent),
                  child: Text(leaveRecords.length.toString(), style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                ),
                children: leaveRecords.map((record) {
                  final fullName = record['employee_id']['full_name'];
                  final profile = record['employee_id']['employee_profile'];

                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                    leading: CircleAvatar(
                      radius: 18,
                      backgroundColor: Colors.grey.shade200,
                      backgroundImage: (profile != null && profile.isNotEmpty)
                          ? NetworkImage(baseUrl + profile, headers: {"Authorization": "Bearer $token"})
                          : null,
                      child: (profile == null || profile.isEmpty) ? const Icon(Icons.person, size: 20, color: Colors.grey) : null,
                    ),
                    title: Text(fullName, style: const TextStyle(fontSize: 14)),
                  );
                }).toList(),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}