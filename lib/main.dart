import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:google_places_flutter/google_places_flutter.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFFEFEFF4),
        appBar: AppBar(
          elevation: 1,
          backgroundColor: Colors.white,
          leading: Padding(
            padding: const EdgeInsets.only(top: 15.0),
            child: IconButton(
              icon: const Icon(
                Icons.arrow_back,
                color: Colors.black,
              ),
              onPressed: () {
                Navigator.pop(context);
              },
            ),
          ),
          title: Padding(
            padding: const EdgeInsets.only(top: 15.0),
            child: const Text(
              "Select Delivery Location",
              style: TextStyle(
                fontFamily: 'Poppins',
                color: Colors.black,
                fontSize: 19,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          centerTitle: true,
          toolbarHeight: 75,
        ),
        body: MapScreen(),
      ),
    );
  }
}

class MapScreen extends StatefulWidget {
  @override
  _MapScreenState createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  late GoogleMapController mapController;
  late String _mapStyle;
  LatLng _selectedLocation = LatLng(12.9091, 80.2279); // Default SSN location
  BitmapDescriptor? _customMarkerIcon;
  String _locationName = "Fetching location...";
  String _locationAddress = "Fetching location...";
  TextEditingController _searchController = TextEditingController();
  FocusNode _searchFocusNode = FocusNode();
  @override
  void initState() {
    super.initState();
    _loadMapStyle();
    _loadCustomMarker();
    _showLocationPermissionPopup(); // Call the method to show the permission popup
  }
  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose(); // Dispose the FocusNode
    super.dispose();
  }
  
  Future<void> _loadMapStyle() async {
    _mapStyle = await rootBundle.loadString('assets/map_style.json');
  }

  Future<void> _loadCustomMarker() async {
    final ByteData data = await rootBundle.load('assets/custom_marker.png');
    final Uint8List bytes = data.buffer.asUint8List();
    final ui.Codec codec = await ui.instantiateImageCodec(bytes);
    final ui.FrameInfo frameInfo = await codec.getNextFrame();
    final double scaleFactor = 0.35;
    final ui.Image resizedImage = await _resizeImage(
      frameInfo.image,
      (frameInfo.image.width * scaleFactor).toInt(),
      (frameInfo.image.height * scaleFactor).toInt(),
    );

    final ByteData? resizedBytes =
        await resizedImage.toByteData(format: ui.ImageByteFormat.png);
    if (resizedBytes != null) {
      final Uint8List resizedUint8List = resizedBytes.buffer.asUint8List();
      setState(() {
        _customMarkerIcon = BitmapDescriptor.fromBytes(resizedUint8List);
      });
    }
  }

  Future<ui.Image> _resizeImage(ui.Image image, int width, int height) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final paint = Paint();
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      paint,
    );
    final picture = recorder.endRecording();
    return await picture.toImage(width, height);
  }

  void _onMapCreated(GoogleMapController controller) {
    mapController = controller;
    mapController.setMapStyle(_mapStyle);
  }

// Method to show the location permission popup
void _showLocationPermissionPopup() {
  Future.delayed(Duration(seconds: 2), () {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        title: Text(
          "Allow DropSi to access this device's location?",
          style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.bold),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              _getUserLocation(); // Call the method to get the user's location
            },
            child: Text(
              "ALLOW ONLY WHILE USING THE APP",
              style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
            ),
          ),
          Padding(
            padding: EdgeInsets.only(right: 220.0),
            child: TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                "DENY",
                style: TextStyle(color: Colors.red),
              ),
            ),
          ),
        ],
      ),
    );
  });
}

  // Method to get the user's location
  Future<void> _getUserLocation() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        // Handle the case when the user denies the permission
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Location permission is required to fetch accurate location details.")),
        );
        return;
      }
    }

    Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high);
    _updateLocationDetails(position.latitude, position.longitude);
  }
Future<void> _updateLocationDetails(double latitude, double longitude) async {
  try {
    // Perform reverse geocoding
    List<Placemark> placemarks = await placemarkFromCoordinates(latitude, longitude);
    if (placemarks.isNotEmpty) {
      Placemark place = placemarks.first;

      // Extract and prioritize relevant fields
      String buildingNumber = place.subThoroughfare ?? ""; // Building number
      String streetName = place.thoroughfare ?? ""; // Street name
      String locationName = _cleanSegmentIdentifier(place.name ?? ""); // Location name/building
      String locality = place.locality ?? ""; // City or town
      String administrativeArea = place.administrativeArea ?? ""; // State
      String postalCode = place.postalCode ?? ""; // Postal code
      String country = place.country ?? ""; // Country name

      // Combine building number and street name
      String addressLine = [buildingNumber, streetName].where((part) => part.isNotEmpty).join(" ");

      // Construct full address
      String fullAddress = [
        if (locationName.isNotEmpty) locationName,
        if (addressLine.isNotEmpty) addressLine,
        if (locality.isNotEmpty) locality,
        if (administrativeArea.isNotEmpty) administrativeArea,
        if (postalCode.isNotEmpty) postalCode,
        if (country.isNotEmpty) country,
      ].join(", ");

      // Update the state
      setState(() {
        _selectedLocation = LatLng(latitude, longitude);
        _locationName = locationName.isNotEmpty ? locationName : "Unnamed Location";
        _locationAddress = fullAddress.isNotEmpty ? fullAddress : "Address not available";
      });

      // Move the map camera to the new location
      mapController.animateCamera(CameraUpdate.newLatLngZoom(_selectedLocation, 16.0));
    } else {
      // Handle the case when no placemarks are found
      setState(() {
        _locationName = "Unknown Place";
        _locationAddress = "Address not available";
      });
    }
  } catch (e) {
    // Handle errors during reverse geocoding
    setState(() {
      _locationName = "Error Fetching Location";
      _locationAddress = "Please try again later.";
    });
    print("Error in reverse geocoding: $e");
  }
}

// Helper method to clean segment identifiers (e.g., numbers like "91")
String _cleanSegmentIdentifier(String input) {
  // Use regex to remove numeric segment identifiers at the beginning of the string
  RegExp segmentPattern = RegExp(r"^\d+\s*");
  return input.replaceAll(segmentPattern, "").trim();
}
  // Method to locate the user
  void _locateMe() {
    _getUserLocation();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          flex: 4,
          child: Stack(
            children: [
              GoogleMap(
                onMapCreated: _onMapCreated,
                initialCameraPosition: CameraPosition(
                  target: _selectedLocation,
                  zoom: 16.0,
                ),
                markers: {
                  Marker(
                    markerId: MarkerId("deliveryLocation"),
                    position: _selectedLocation,
                    draggable: true,
                    onDragEnd: (LatLng newPosition) {
                      _updateLocationDetails(newPosition.latitude, newPosition.longitude);
                    },
                    icon: _customMarkerIcon ??
                        BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
                  ),
                },
                onTap: (LatLng latLng) {
                  _updateLocationDetails(latLng.latitude, latLng.longitude);
                },
                zoomControlsEnabled: false,
              ),
              // Floating Search Bar
              Positioned(
  top: 20,
  left: 15,
  right: 15,
  child: Container(
    padding: EdgeInsets.symmetric(horizontal: 10),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(10.0),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.1),
          blurRadius: 10,
          offset: Offset(0, 5),
        ),
      ],
    ),
    child: GooglePlaceAutoCompleteTextField(
      textEditingController: _searchController,
      googleAPIKey: "AIzaSyCazP9litaMcU6wy-MkHk4PN0NrY1P3o0M", // Replace with your API Key
      inputDecoration: InputDecoration(
        border: InputBorder.none,
        hintText: "Search location...",
        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 15),
        hintStyle: TextStyle(
          color: Colors.grey,
          fontSize: 14,
        ),
      ),
      debounceTime: 500, // Delay in milliseconds before API request
      isLatLngRequired: true, // Get Latitude & Longitude
      getPlaceDetailWithLatLng: (prediction) async {
        double lat = double.parse(prediction.lat!);
        double lng = double.parse(prediction.lng!);
        _updateLocationDetails(lat, lng);
      },
      itemClick: (prediction) {
        _searchController.text = prediction.description!;
      },
      boxDecoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: Offset(0, 5),
          ),
        ],
      ),
      focusNode: _searchFocusNode,
    ),
  ),
),

              Positioned(
                bottom: 50,
                left: MediaQuery.of(context).size.width / 2 - 65,
                child: GestureDetector(
                  onTap: _locateMe,
                  child: Container(
                    height: 50,
                    width: 130,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10.0),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 10,
                          offset: Offset(0, 5),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.my_location, color: Colors.green),
                        SizedBox(width: 5),
                        Text(
                          "LOCATE ME",
                          style: TextStyle(
                            color: Colors.green,
                            fontWeight: FontWeight.normal,
                            fontFamily: 'Poppins',
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        _buildBottomBar(_locationName, _locationAddress),
      ],
    );
  }

  // Method to build the bottom bar
  Widget _buildBottomBar(String locationName, String locationAddress) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 15, vertical: 15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10.0),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: Offset(0, -5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Icon(Icons.location_on, color: Colors.green),
                    SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        locationName, // Dynamic place name
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 21,
                          fontWeight: FontWeight.bold,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: () {
                  FocusScope.of(context).requestFocus(_searchFocusNode);
                },
                child: Text(
                  "CHANGE",
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    color: Colors.green,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 5),
          Text(
            locationAddress, // Dynamic address
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 15,
              color: Colors.grey,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 10),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              minimumSize: Size(double.infinity, 45),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () {print(locationName);
            print(locationAddress);},
            child: Text(
              "CONFIRM LOCATION",
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 16,
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}