import 'dart:convert';
import 'dart:ui'; // Wajib untuk ImageFilter
import 'package:horilla/horilla_main/home.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map_marker_popup/flutter_map_marker_popup.dart';
import 'package:flutter_map_animations/flutter_map_animations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geocoding/geocoding.dart';
import '../../horilla_main/login.dart';

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
                    color: Colors.black.withOpacity(0.1),
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
                    Colors.white.withOpacity(0.6),
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

class MapScreen extends StatefulWidget {
  const MapScreen({Key? key}) : super(key: key);

  @override
  _MapScreenState createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> with TickerProviderStateMixin {
  final List<LocationWithRadius> locations = [];
  LocationWithRadius? selectedLocation;
  final PopupController _popupController = PopupController();
  late final AnimatedMapController _mapController;
  double _currentRadius = 50.0;
  Position? userLocation;
  Map<String, dynamic> responseData = {};
  bool _showCurrentLocationCircle = false;
  bool _showTappedLocationCircle = false;
  bool _isExistingGeofence = false;
  bool _isDisposed = false;

  @override
  void initState() {
    super.initState();
    _mapController = AnimatedMapController(vsync: this);
    getGeoFenceLocation().then((_) {
      if (mounted && selectedLocation != null) {
        _mapController.animateTo(dest: selectedLocation!.coordinates, zoom: 12.0);
      }
    });
  }

  @override
  void dispose() {
    _isDisposed = true;
    _mapController.dispose();
    super.dispose();
  }

  Future<String> _getLocationName(double latitude, double longitude) async {
    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(latitude, longitude);
      if (placemarks.isNotEmpty) {
        Placemark place = placemarks[0];
        String name = "${place.locality ?? ''}, ${place.country ?? ''}".trim();
        return name.isEmpty ? "Unknown Location" : name;
      }
      return "Unknown Location";
    } catch (e) {
      print('Error getting location name: $e');
      return "Unknown Location";
    }
  }

  Future<void> createGeoFenceLocation() async {
    if (_isDisposed) return;

    final prefs = await SharedPreferences.getInstance();
    var companyId = prefs.getInt("company_id");
    var token = prefs.getString("token");
    var typedServerUrl = prefs.getString("typed_url");
    var uri = Uri.parse('$typedServerUrl/api/geofencing/setup/');

    try {
      var response = await http.post(
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

      if (_isDisposed) return;

      if (response.statusCode == 201) {
        await showCreateAnimation();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Error in Saving'),
              duration: Duration(seconds: 2),
            ),
          );
          Navigator.pop(context);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error in Saving'),
            duration: Duration(seconds: 2),
          ),
        );
        Navigator.pop(context);
      }
    }
  }

  Future<void> updateGeoFenceLocation() async {
    if (_isDisposed) return;
    var locationId = responseData['id'];
    final prefs = await SharedPreferences.getInstance();
    var companyId = prefs.getInt("company_id");
    var token = prefs.getString("token");
    var typedServerUrl = prefs.getString("typed_url");
    var uri = Uri.parse('$typedServerUrl/api/geofencing/setup/$locationId/');

    try {
      var response = await http.put(
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

      if (_isDisposed) return;
      if (response.statusCode == 200) {
        await showCreateAnimation();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Error in Saving'),
              duration: Duration(seconds: 2),
            ),
          );
          Navigator.pop(context);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error in Saving'),
            duration: Duration(seconds: 2),
          ),
        );
        Navigator.pop(context);
      }
    }
  }

  Future<void> deleteGeoFenceLocation() async {
    if (_isDisposed) return;

    final prefs = await SharedPreferences.getInstance();
    var locationId = responseData['id'];
    var token = prefs.getString("token");
    var typedServerUrl = prefs.getString("typed_url");
    var uri = Uri.parse('$typedServerUrl/api/geofencing/setup/$locationId/');

    try {
      var response = await http.delete(
        uri,
        headers: {
          "Content-Type": "application/json",
          "Authorization": "Bearer $token",
        },
      );

      if (_isDisposed) return;

      if (response.statusCode == 204) {
        await showDeleteAnimation();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Error in delete'),
                duration: Duration(seconds: 2),
              )
          );
          Navigator.pop(context);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Error in delete'),
              duration: Duration(seconds: 2),
            )
        );
        Navigator.pop(context);
      }
    }
  }

  Future<void> getGeoFenceLocation() async {
    if (_isDisposed) return;

    final prefs = await SharedPreferences.getInstance();
    var token = prefs.getString("token");
    var typedServerUrl = prefs.getString("typed_url");
    var uri = Uri.parse('$typedServerUrl/api/geofencing/setup/');

    try {
      var response = await http.get(uri, headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $token",
      });

      if (_isDisposed) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data.isNotEmpty) {
          final lat = data['latitude'];
          final lng = data['longitude'];
          final rad = data['radius_in_meters'];

          if (lat != null && lng != null && rad != null) {
            final locationName = await _getLocationName(lat, lng);
            final location = LocationWithRadius(
              LatLng(lat, lng),
              locationName,
              (rad).toDouble(),
              isExisting: true,
            );
            if (mounted) {
              setState(() {
                responseData = data;
                locations.clear();
                locations.add(location);
                selectedLocation = location;
                _currentRadius = rad.toDouble();
                _isExistingGeofence = true;
              });
            }
          }
        }
      } else {
        print('Failed to load data: ${response.statusCode}');
      }
    } catch (e) {
      print("Error fetching geofence data: $e");
    }
  }

  Future<void> showCreateAnimation() async {
    if (_isDisposed) return;

    String jsonContent = '''
{
  "imagePath": "Assets/gif22.gif"
}
''';
    Map<String, dynamic> jsonData = json.decode(jsonContent);
    String imagePath = jsonData['imagePath'];

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return Dialog(
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.3,
            width: MediaQuery.of(context).size.width * 0.85,
            child: SingleChildScrollView(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Image.asset(imagePath,
                        width: 180, height: 180, fit: BoxFit.cover),
                    const SizedBox(height: 16),
                    const Text(
                      "Geofence Location Added Successfully",
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.red),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );

    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const HomePage(),
          ),
        );
      }
    });
  }

  Future<void> showDeleteAnimation() async {
    if (_isDisposed) return;

    String jsonContent = '''
{
  "imagePath": "Assets/gif22.gif"
}
''';
    Map<String, dynamic> jsonData = json.decode(jsonContent);
    String imagePath = jsonData['imagePath'];

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return Dialog(
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.3,
            width: MediaQuery.of(context).size.width * 0.85,
            child: SingleChildScrollView(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Image.asset(imagePath,
                        width: 180, height: 180, fit: BoxFit.cover),
                    const SizedBox(height: 16),
                    const Text(
                      "Geofence Location Deleted Successfully",
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.red),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );

    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const HomePage(),
          ),
        );
      }
    });
  }

  Future<Position?> fetchCurrentLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return null;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return null;
      }

      if (permission == LocationPermission.deniedForever) return null;

      return await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
    } catch (e) {
      print('Error fetching location: $e');
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    const Color textDark = Color(0xFF1F2937);

    return Scaffold(
      extendBodyBehindAppBar: true, // Agar peta memenuhi layar di belakang AppBar
      appBar: AppBar(
        backgroundColor: Colors.transparent, // AppBar Transparan
        elevation: 0,
        automaticallyImplyLeading: false,
        centerTitle: true,
        title: GlassContainer(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          borderRadius: BorderRadius.circular(30),
          hasShadow: false,
          opacity: 0.8,
          child: const Text(
            'Geofencing Map', 
            style: TextStyle(color: textDark, fontWeight: FontWeight.bold, fontSize: 16)
          ),
        ),
      ),
      body: Stack(
        children: [
          // 1. LAYER PETA (BACKGROUND)
          FlutterMap(
            mapController: _mapController.mapController,
            options: MapOptions(
              center: selectedLocation != null
                  ? selectedLocation!.coordinates
                  : userLocation != null
                  ? LatLng(userLocation!.latitude, userLocation!.longitude)
                  : const LatLng(40.0, 0.0),
              zoom: (selectedLocation != null || userLocation != null) ? 12.0 : 2.0,
              minZoom: 2.0,
              maxZoom: 18.0,
              interactiveFlags: InteractiveFlag.all,
              onTap: (_, latLng) async {
                String locationName = await _getLocationName(
                  latLng.latitude,
                  latLng.longitude,
                );
                if (mounted) {
                  setState(() {
                    locations.clear();
                    final newLocation = LocationWithRadius(
                      latLng,
                      locationName,
                      _currentRadius,
                    );
                    locations.add(newLocation);
                    selectedLocation = newLocation;
                    _showCurrentLocationCircle = false;
                    _showTappedLocationCircle = true;
                    _isExistingGeofence = false;
                  });
                  _mapController.animateTo(
                    dest: latLng,
                    zoom: 12.0,
                  );
                }
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.cybrosys.horilla',
              ),
              CircleLayer(
                circles: [
                  if (selectedLocation != null && _showTappedLocationCircle)
                    CircleMarker(
                      point: selectedLocation!.coordinates,
                      color: Colors.red.withOpacity(0.2), // Merah transparan sesuai tema
                      borderColor: Colors.red,
                      borderStrokeWidth: 2.0,
                      radius: selectedLocation!.radius,
                    ),
                  if (_showCurrentLocationCircle && userLocation != null)
                    CircleMarker(
                      point: LatLng(userLocation!.latitude, userLocation!.longitude),
                      color: Colors.green.withOpacity(0.3),
                      borderColor: Colors.green,
                      borderStrokeWidth: 2.0,
                      radius: _currentRadius,
                    ),
                  if (responseData.isNotEmpty && !_showCurrentLocationCircle && !_showTappedLocationCircle)
                    CircleMarker(
                      point: LatLng(responseData['latitude'], responseData['longitude']),
                      color: Colors.green.withOpacity(0.3),
                      borderColor: Colors.green,
                      borderStrokeWidth: 2.0,
                      radius: _currentRadius,
                    ),
                ],
              ),
              PopupMarkerLayerWidget(
                options: PopupMarkerLayerOptions(
                  popupController: _popupController,
                  markers: locations
                      .map((loc) => Marker(
                    point: loc.coordinates,
                    width: 40.0,
                    height: 40.0,
                    child: GestureDetector(
                      onTap: () {
                        if (mounted) {
                          setState(() {
                            selectedLocation = loc;
                            if (loc.isExisting) {
                              _isExistingGeofence = true;
                            }
                          });
                          _mapController.animateTo(
                            dest: loc.coordinates,
                            zoom: 12.0,
                          );
                        }
                      },
                      child: const Icon(
                        Icons.location_on,
                        color: Colors.red,
                        size: 40.0,
                      ),
                    ),
                  ))
                      .toList(),
                  popupDisplayOptions: PopupDisplayOptions(
                    builder: (BuildContext context, Marker marker) {
                      final loc = locations.firstWhere(
                            (loc) => loc.coordinates == marker.point,
                      );
                      // Custom Glass Popup
                      return GlassContainer(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        borderRadius: BorderRadius.circular(12),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              loc.name,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                            ),
                            Text(
                              'Radius: ${loc.radius.toStringAsFixed(1)} m',
                              style: const TextStyle(fontSize: 10),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),

          // 2. PANEL DETAIL BAWAH (Glass Effect)
          if (selectedLocation != null)
            Positioned(
              left: 20,
              right: 20,
              bottom: 30,
              child: GlassContainer(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                selectedLocation!.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  color: textDark
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                "Lat: ${selectedLocation!.coordinates.latitude.toStringAsFixed(4)}, Lng: ${selectedLocation!.coordinates.longitude.toStringAsFixed(4)}",
                                style: TextStyle(fontSize: 10, color: Colors.grey[700]),
                              )
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () {
                            if (mounted) {
                              setState(() {
                                locations.remove(selectedLocation);
                                selectedLocation = null;
                                _showTappedLocationCircle = false;
                                _isExistingGeofence = false;
                              });
                            }
                          },
                          icon: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 5)]),
                            child: const Icon(Icons.close, color: Colors.red, size: 18),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 15),
                    const Text('Geofence Radius', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                    Row(
                      children: [
                        Expanded(
                          child: SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              activeTrackColor: Colors.red,
                              inactiveTrackColor: Colors.red.withOpacity(0.2),
                              thumbColor: Colors.red,
                              overlayColor: Colors.red.withOpacity(0.1),
                            ),
                            child: Slider(
                              value: _currentRadius,
                              min: 1,
                              max: 10000,
                              divisions: 99,
                              label: '${_currentRadius.round()} m',
                              onChanged: (value) {
                                if (mounted) {
                                  setState(() {
                                    _currentRadius = value.roundToDouble();
                                    if (selectedLocation != null) {
                                      final index = locations.indexOf(selectedLocation!);
                                      locations[index] = LocationWithRadius(
                                        selectedLocation!.coordinates,
                                        selectedLocation!.name,
                                        _currentRadius,
                                        isExisting: selectedLocation!.isExisting,
                                      );
                                      selectedLocation = locations[index];
                                    }
                                  });
                                }
                              },
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
                          child: Text('${_currentRadius.toStringAsFixed(0)} m', style: const TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 15),
                    Row(
                      children: [
                        if (_isExistingGeofence)
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(right: 8.0),
                              child: ElevatedButton(
                                onPressed: () async {
                                  await showGeofencingDelete(context);
                                  if (mounted) {
                                    setState(() {
                                      locations.remove(selectedLocation);
                                      selectedLocation = null;
                                      _showTappedLocationCircle = false;
                                      _isExistingGeofence = false;
                                    });
                                  }
                                },
                                style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.white,
                                    foregroundColor: Colors.red,
                                    side: const BorderSide(color: Colors.red),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
                                ),
                                child: const Text('Delete'),
                              ),
                            ),
                          ),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () async {
                              await showGeofencingSetting(context);
                            },
                            style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
                            ),
                            child: const Text('Save Zone'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
      
      // FLOATING ACTION BUTTON (My Location)
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.white,
        elevation: 4,
        onPressed: () async {
          final newLocation = await fetchCurrentLocation();
          if (newLocation != null && mounted) {
            String locationName = await _getLocationName(
              newLocation.latitude,
              newLocation.longitude,
            );
            setState(() {
              userLocation = newLocation;
              locations.clear();
              final newLoc = LocationWithRadius(
                LatLng(newLocation.latitude, newLocation.longitude),
                locationName,
                _currentRadius,
              );
              locations.add(newLoc);
              selectedLocation = newLoc;
              _showCurrentLocationCircle = true;
              _showTappedLocationCircle = false;
              _isExistingGeofence = false;
            });
            _mapController.animateTo(
              dest: LatLng(newLocation.latitude, newLocation.longitude),
              zoom: 12.0,
            );
          }
        },
        child: const Icon(Icons.my_location, color: Colors.blueAccent),
      ),
    );
  }

  Future<void> showGeofencingSetting(BuildContext context) async {
    if (!mounted) return;

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text("Set Geofencing Location"),
          content: const Text("Do you want to set this location for Geofencing?"),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text("Cancel"),
            ),
            TextButton(
              onPressed: () async {
                Navigator.of(context).pop();
                final prefs = await SharedPreferences.getInstance();
                var geoFencing = prefs.getBool("geo_fencing");
                if (geoFencing == true) {
                  await updateGeoFenceLocation();
                }
                else {
                  await createGeoFenceLocation();
                }
              },
              child: const Text("Confirm"),
            ),
          ],
        );
      },
    );
  }

  Future<void> showGeofencingDelete(BuildContext context) async {
    if (!mounted) return;

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text("Delete Geofencing Location"),
          content: const Text("Do you want to delete this location for Geofencing?"),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text("Cancel"),
            ),
            TextButton(
              onPressed: () async {
                Navigator.of(context).pop();
                await deleteGeoFenceLocation();
              },
              child: const Text("Confirm"),
            ),
          ],
        );
      },
    );
  }
}

class LocationWithRadius {
  final LatLng coordinates;
  final String name;
  double radius; // in meters
  bool isExisting;

  LocationWithRadius(this.coordinates, this.name, double radius, {this.isExisting = false})
      : radius = radius.roundToDouble().clamp(1, double.infinity);  // Ensure at least 1
}