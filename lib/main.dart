import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:google_places_flutter/google_places_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';


void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        resizeToAvoidBottomInset: false,
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
  String apiKey = dotenv.env['MAPS_API_KEY'] ?? 'No API Key';
  
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
      String addressLine = [buildingNumber, streetName].where((part) => part.isNotEmpty).join(" ");
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
String _cleanSegmentIdentifier(String input) {
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
      googleAPIKey: apiKey, // Replace with your API Key
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
            print(locationAddress);
            _showModalBottomSheet(context);
            },
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
void _showModalBottomSheet(BuildContext context) {
  TextEditingController _directionsController = TextEditingController();
  ValueNotifier<int> _charCount = ValueNotifier<int>(0);
  TextEditingController _apartmentController = TextEditingController();
  TextEditingController _houseController = TextEditingController();
  _directionsController.addListener(() {
    _charCount.value = _directionsController.text.length;
  });
  ValueNotifier<String> selectedTag = ValueNotifier<String>("");
  FlutterSoundRecorder _recorder = FlutterSoundRecorder();
  ValueNotifier<bool> isRecording = ValueNotifier<bool>(false);
  String? recordedFilePath;

  // Error messages
  ValueNotifier<String?> _houseError = ValueNotifier<String?>(null);
  ValueNotifier<String?> _tagError = ValueNotifier<String?>(null);

  Future<void> _initRecorder() async {
    await Permission.microphone.request();
    if (await Permission.microphone.isGranted) {
      await _recorder.openRecorder();
      _recorder.setSubscriptionDuration(Duration(milliseconds: 500));
    } else {
      print("Microphone permission denied");
    }
  }

  Future<void> _startRecording() async {
    Directory tempDir = await getTemporaryDirectory();
    String filePath = "${tempDir.path}/recorded_audio.aac";

    await _recorder.startRecorder(
      toFile: filePath,
      codec: Codec.aacADTS,
    );

    recordedFilePath = filePath;
    isRecording.value = true;
  }

  Future<void> _stopRecording() async {
    String? tempPath = await _recorder.stopRecorder();
    isRecording.value = false;

    if (tempPath != null) {
      Directory appDir = await getApplicationDocumentsDirectory();
      String mobilePath = "${appDir.path}/recorded_audio.aac";

      File tempFile = File(tempPath);
      await tempFile.copy(mobilePath);
      recordedFilePath = mobilePath;
      print("Recording saved on mobile device at: $recordedFilePath");

      try {
        Directory projectDir = Directory('./flutter_audio_files');
        if (!projectDir.existsSync()) {
          projectDir.createSync(recursive: true);
        }
        String projectPath = "${projectDir.path}/recorded_audio.aac";
        await tempFile.copy(projectPath);
        print("Recording saved in Flutter project directory: $projectPath");
      } catch (e) {
        print("Error saving to Flutter project directory: $e");
      }
    } else {
      print("Error: TempPath is null. Recording was not saved.");
    }
  }

  Future<String?> _getSavedRecording() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getString("saved_audio_path");
  }

  Future<void> _loadSavedRecording() async {
    String? savedPath = await _getSavedRecording();
    if (savedPath != null && savedPath.isNotEmpty) {
      recordedFilePath = savedPath;
      print("Loaded saved recording path: $recordedFilePath");
    } else {
      print("No saved recording found.");
    }
  }
  
  Future<void> _saveUserResponse({
  required String locationName,
  required String locationAddress,
  required String houseFlatBlockNo,
  String? apartmentRoadArea,
  String? directionsToReach,
  required String selectedTag,
}) async {
  final url = Uri.parse('http://192.168.0.3:3000/save-location');
  final response = await http.post(
    url,
    headers: {'Content-Type': 'application/json'},
    body: json.encode({
      'locationName': locationName,
      'locationAddress': locationAddress,
      'houseFlatBlockNo': houseFlatBlockNo,
      'apartmentRoadArea': apartmentRoadArea,
      'directionsToReach': directionsToReach,
      'selectedTag': selectedTag,
    }),
  );

  if (response.statusCode == 200) {
    print('Data saved successfully');
  } else {
    print('Failed to save data');
  }
}

  _initRecorder();
  _loadSavedRecording();

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) {
      return FractionallySizedBox(
        heightFactor: 0.8, // Covers 80% of the screen height
        child: Padding(
          padding: EdgeInsets.all(20),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Icon(Icons.location_on, color: Colors.green, size: 24),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _locationName,
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
                SizedBox(height: 15),
                Text(
                  _locationAddress,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 15,
                    color: Colors.grey[700],
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 20),

                // Alert Box (Beige Background)
                Container(
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Color(0xFFFFF3E0),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    "A detailed address will help our Delivery Partner reach your doorstep easily",
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 14,
                      color: Colors.brown,
                    ),
                  ),
                ),
                SizedBox(height: 20),

                // Address Input Fields
                TextField(
                  controller: _houseController,
                  decoration: InputDecoration(
                    labelText: "HOUSE / FLAT / BLOCK NO.",
                    labelStyle: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 14,
                      color: Colors.grey,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                ValueListenableBuilder<String?>(
                  valueListenable: _houseError,
                  builder: (context, error, child) {
                    return error != null
                        ? Padding(
                            padding: EdgeInsets.only(top: 5),
                            child: Text(
                              error,
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 12,
                                color: Colors.red[900],
                                    fontWeight: FontWeight.bold
                              ),
                            ),
                          )
                        : SizedBox.shrink();
                  },
                ),
                SizedBox(height: 15),

                TextField(
                  controller: _apartmentController,
                  decoration: InputDecoration(
                    label: Text.rich(
                      TextSpan(
                        text: "APARTMENT / ROAD / AREA",
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 14,
                          color: Colors.grey,
                          fontWeight: FontWeight.bold,
                        ),
                        children: [
                          TextSpan(
                            text: "(OPTIONAL)",
                            style: TextStyle(
                              fontWeight: FontWeight.normal,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                SizedBox(height: 15),

                
                  
                    
                      RichText(
  text: TextSpan(
    text: "DIRECTIONS TO REACH ",
    style: TextStyle(
      fontFamily: 'Poppins',
      fontSize: 14,
      fontWeight: FontWeight.bold,
      color: Colors.grey,
    ),
    children: [
      TextSpan(
        text: "(OPTIONAL)",
        style: TextStyle(
          fontWeight: FontWeight.normal, // This is optional since it's the default
          color: Colors.grey,
        ),
      ),
    ],
  ),
),
                    
                    
                  
                
                SizedBox(height: 10),

                // Voice Recording Button
                ValueListenableBuilder<bool>(
                  valueListenable: isRecording,
                  builder: (context, recording, child) {
                    return GestureDetector(
                      onTap: () async {
                        if (!recording) {
                          await _startRecording();
                        } else {
                          await _stopRecording();
                          print("Recording saved at: $recordedFilePath");
                        }
                      },
                      child: Container(
                        padding: EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                        decoration: BoxDecoration(
                          color: Colors.grey[200],
                          borderRadius: BorderRadius.circular(50),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              recording ? "Recording... Tap to stop" : "Tap to record voice directions",
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: recording ? Colors.red : Colors.black,
                              ),
                            ),
                            Container(
                              padding: EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: recording ? Colors.red[300] : Colors.grey[300],
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                recording ? Icons.stop : Icons.mic,
                                color: recording ? Colors.white : Colors.grey[700],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
                SizedBox(height: 15),

                // Directions Input Box with Counter Inside (Bottom Left)
                Container(
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Stack(
                    children: [
                      TextField(
                        controller: _directionsController,
                        maxLength: 200,
                        decoration: InputDecoration(
                          hintText: "e.g. Ring the bell on the red gate",
                          hintStyle: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 14,
                            color: Colors.grey,
                          ),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(
                            vertical: 12,
                            horizontal: 16,
                          ),
                        ),
                        maxLines: 3,
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 20),

                // Save As Section with Error Message
                Row(
                  children: [
                    Text(
                      "SAVE AS",
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey[700],
                      ),
                    ),
                    ValueListenableBuilder<String?>(
                      valueListenable: _tagError,
                      builder: (context, error, child) {
                        return error != null
                            ? Padding(
                                padding: EdgeInsets.only(left: 10),
                                child: Text(
                                  error,
                                  style: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: 12,
                                    color: Colors.red[900],
                                    fontWeight: FontWeight.bold
                                  ),
                                ),
                              )
                            : SizedBox.shrink();
                      },
                    ),
                  ],
                ),
                SizedBox(height: 10),

                // Tag Buttons
                ValueListenableBuilder<String>(
                  valueListenable: selectedTag,
                  builder: (context, selected, child) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            _buildTagButton("Home", Icons.home, selected, selectedTag),
                            SizedBox(width: 20),
                            _buildTagButton("Work", Icons.work, selected, selectedTag),
                          ],
                        ),
                        SizedBox(height: 15),
                        Row(
                          children: [
                            _buildTagButton("Friends and Family", Icons.group, selected, selectedTag),
                            SizedBox(width: 20),
                            _buildTagButton("Other", Icons.location_on, selected, selectedTag),
                          ],
                        ),
                      ],
                    );
                  },
                ),
                SizedBox(height: 20),

                // Submit Button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding: EdgeInsets.symmetric(vertical: 16),
                    ),
                    onPressed: () async {
                      // Validate House/Flat/Block No.
                      if (_houseController.text.isEmpty) {
                        _houseError.value = "This field is required";
                      } else {
                        _houseError.value = null;
                      }

                      // Validate Tag Selection
                      if (selectedTag.value.isEmpty) {
                        _tagError.value = "*Select any one from below";
                      } else {
                        _tagError.value = null;
                      }

                      // If both validations pass, proceed
                  if (_houseController.text.isNotEmpty && selectedTag.value.isNotEmpty) {
    // Save the user response
    await _saveUserResponse(
      locationName: _locationName,
      locationAddress: _locationAddress,
      houseFlatBlockNo: _houseController.text,
      apartmentRoadArea: _apartmentController.text, // Add this controller if needed
      directionsToReach: _directionsController.text,
      selectedTag: selectedTag.value,
    );

    // Handle successful submission
  print("Location Name: ${_locationName}");
  print("Location Address: ${_locationAddress}");
  print("House/Flat/Block No.: ${_houseController.text}");
  print("Apartment/Road/Area: ${_apartmentController.text}");
  print("Directions to Reach: ${_directionsController.text}");
  print("Selected Tag: ${selectedTag.value}");
  }


                    },
                    child: Text(
                      "ENTER HOUSE / FLAT / BLOCK NO.",
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                SizedBox(height: MediaQuery.of(context).viewInsets.bottom),
              ],
            ),
          ),
        ),
      );
    },
  );
}

Widget _buildTagButton(String label, IconData icon, String selected, ValueNotifier<String> notifier) {
  bool isSelected = selected == label;

  return GestureDetector(
    onTap: () {
      notifier.value = isSelected ? "" : label;
    },
    child: Container(
      padding: EdgeInsets.symmetric(vertical: 10, horizontal: 20),
      decoration: BoxDecoration(
        color: isSelected ? Colors.green.withOpacity(0.2) : Colors.grey[200],
        borderRadius: BorderRadius.circular(50),
        border: Border.all(
          color: isSelected ? Colors.black : Colors.grey,
          width: 1.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            color: isSelected ? Colors.black : Colors.grey,
            size: 22,
          ),
          SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: isSelected ? Colors.black : Colors.grey,
            ),
          ),
        ],
      ),
    ),
  );
}
}