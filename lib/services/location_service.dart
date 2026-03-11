import 'dart:async';
import 'dart:convert';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:geocoding/geocoding.dart';
import '../models/place_model.dart';
import '../constants.dart';

class LocationService {
  static final LocationService _instance = LocationService._internal();
  factory LocationService() => _instance;
  LocationService._internal();

  // --- NEW: Continuous Caching ---
  StreamSubscription<Position>? _positionStream;
  Position? _lastValidPosition;
  String? _lastValidAddress;
  bool _isTracking = false;

  // --- API Rate Limiting ---
  DateTime? _lastMapboxFetch;
  PlaceModel? _cachedNearestStop;

  // Dedicated coffee caching
  DateTime? _lastCoffeeFetch;
  PlaceModel? _cachedNearestCoffee;

  Future<void> requestPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      await Geolocator.requestPermission();
    }
  }

  // --- NEW: Start Background Tracking ---
  void startTracking() async {
    if (_isTracking) return;

    bool hasPermission = await _checkPermissions();
    if (!hasPermission) return;

    _isTracking = true;

    // Force an immediate initial location grab so it's instantly cached
    Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.medium)
        .then((pos) {
          _lastValidPosition = pos;
          _updateAddressCache(pos);
        }).catchError((_) {}); // Ignore error, stream will eventually catch it

    _positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.medium, 
        distanceFilter: 50, // Only update if moved 50 meters (saves battery)
      ),
    ).listen((Position position) {
      _lastValidPosition = position;
      _updateAddressCache(position);
    });
  }

  void stopTracking() {
    _positionStream?.cancel();
    _isTracking = false;
  }

  Future<bool> _checkPermissions() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return false;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.deniedForever) return false;
    
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission != LocationPermission.whileInUse && permission != LocationPermission.always) {
        return false;
      }
    }
    return true;
  }

  Future<void> _updateAddressCache(Position pos) async {
    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(pos.latitude, pos.longitude);
      if (placemarks.isNotEmpty) {
        Placemark place = placemarks.first;
        String city = place.locality ?? place.subAdministrativeArea ?? "Unknown City";
        _lastValidAddress = "$city, Philippines";
      }
    } catch (e) {
      // Keep old address if geocoding fails momentarily
    }
  }

  // --- REFACTORED: Instant Fetching ---
  Future<Position> getCurrentLocation() async {
    if (_lastValidPosition != null) {
      return _lastValidPosition!;
    }
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return Future.error('Location services are disabled.');

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return Future.error('Location permissions are denied');
    }

    try {
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 5), // Reduced to 5s so fallback is fast
      );
    } catch (e) {
      print('⚠️ Live GPS failed ($e). Trying last known...');
      Position? lastKnown = await Geolocator.getLastKnownPosition();
      if (lastKnown != null) {
         _lastValidPosition = lastKnown;
         return lastKnown;
      }
      print('⚠️ No last known GPS. Injecting fallback (Manila).');
      // Fallback location for testing / dead zones
      return Position(
        longitude: 120.9842,
        latitude: 14.5995,
        timestamp: DateTime.now(),
        accuracy: 100,
        altitude: 0,
        heading: 0,
        speed: 0,
        speedAccuracy: 0,
        altitudeAccuracy: 0,
        headingAccuracy: 0,
      );
    }
  }

  Future<String> getCurrentAddress() async {
    if (_lastValidAddress != null) {
      return _lastValidAddress!;
    }
    
    try {
      Position position = await getCurrentLocation();
      await _updateAddressCache(position);
      return _lastValidAddress ?? "Unknown Location";
    } catch (e) {
      print("Geocoding Error: $e");
    }
    return _lastValidAddress ?? "Unknown Location";
  }

  // --- UPDATED: MAPBOX SEARCH BOX API v1 CATEGORY SEARCH ---
  Future<PlaceModel?> findNearestStop(double lat, double lon) async {
    
    // --- RATE LIMITING & SMART CACHING ---
    if (_lastMapboxFetch != null && _cachedNearestStop != null) {
      if (DateTime.now().difference(_lastMapboxFetch!).inMinutes < 15) {
        double currentDistToCached = Geolocator.distanceBetween(
            lat, lon, _cachedNearestStop!.lat, _cachedNearestStop!.lon);
        print('📍 CACHE HIT → ${_cachedNearestStop!.name} (${(currentDistToCached/1000).toStringAsFixed(1)}km)');
        return PlaceModel(
            name: _cachedNearestStop!.name,
            lat: _cachedNearestStop!.lat,
            lon: _cachedNearestStop!.lon,
            distanceKm: currentDistToCached / 1000,
            type: _cachedNearestStop!.type
        );
      }
    }

    final String mapboxToken = AppConstants.mapboxToken;
    
    // Search these categories using Mapbox Search Box API v1
    const List<String> categories = ['gas_station', 'mall', 'hotel', 'parking_garage'];
    
    PlaceModel? closest;
    double minDistance = double.infinity;

    for (String category in categories) {
      try {
        final Uri url = Uri.parse(
          "https://api.mapbox.com/search/searchbox/v1/category/$category?"
          "proximity=$lon,$lat&"
          "limit=3&"
          "language=en&"
          "access_token=$mapboxToken"
        );

        print('🗺️ Mapbox query: $category near ($lat, $lon)');
        final response = await http.get(url);
        print('🗺️ Mapbox response: ${response.statusCode}');

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          List features = data['features'] ?? [];
          print('🗺️ Found ${features.length} results for $category');

          for (var feature in features) {
            // SearchBox API returns coordinates in geometry.coordinates [lon, lat]
            List coords = feature['geometry']['coordinates'];
            double pLon = (coords[0] as num).toDouble();
            double pLat = (coords[1] as num).toDouble();
            
            // Get place name from properties
            String name = feature['properties']?['name'] ?? 
                          feature['properties']?['full_address'] ?? 
                          "Unknown Place";

            double dist = Geolocator.distanceBetween(lat, lon, pLat, pLon);
            print('🗺️   → $name (${(dist/1000).toStringAsFixed(1)}km)');

            if (dist < minDistance && dist <= 20000) {
              minDistance = dist;
              closest = PlaceModel(
                  name: name,
                  lat: pLat,
                  lon: pLon,
                  distanceKm: dist / 1000,
                  type: category
              );
            }
          }
        } else {
          print('🗺️ Mapbox Error for $category: ${response.statusCode} - ${response.body}');
        }
      } catch (e) {
        print('🗺️ Exception for $category: $e');
      }
    }

    // Save to cache on successful fetch
    if (closest != null) {
      _lastMapboxFetch = DateTime.now();
      _cachedNearestStop = closest;
      print('✅ NEAREST STOP: ${closest.name} (${closest.distanceKm.toStringAsFixed(1)}km) [${closest.type}]');
    } else {
      print('⚠️ No nearby stops found within 20km');
    }

    return closest;
  }

  // --- NEW: Mapbox Search specifically for Coffee ---
  Future<PlaceModel?> findNearestCoffee(double lat, double lon) async {
    
    // Check coffee cache
    if (_lastCoffeeFetch != null && _cachedNearestCoffee != null) {
      if (DateTime.now().difference(_lastCoffeeFetch!).inMinutes < 15) {
        double currentDistToCached = Geolocator.distanceBetween(
            lat, lon, _cachedNearestCoffee!.lat, _cachedNearestCoffee!.lon);
        return PlaceModel(
            name: _cachedNearestCoffee!.name,
            lat: _cachedNearestCoffee!.lat,
            lon: _cachedNearestCoffee!.lon,
            distanceKm: currentDistToCached / 1000,
            type: _cachedNearestCoffee!.type
        );
      }
    }

    final String mapboxToken = AppConstants.mapboxToken;
    const List<String> categories = ['cafe', 'coffee_shop'];
    
    PlaceModel? closest;
    double minDistance = double.infinity;

    for (String category in categories) {
      try {
        final Uri url = Uri.parse(
          "https://api.mapbox.com/search/searchbox/v1/category/$category?"
          "proximity=$lon,$lat&"
          "limit=3&"
          "language=en&"
          "access_token=$mapboxToken"
        );

        final response = await http.get(url);

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          List features = data['features'] ?? [];

          for (var feature in features) {
            List coords = feature['geometry']['coordinates'];
            double pLon = (coords[0] as num).toDouble();
            double pLat = (coords[1] as num).toDouble();
            
            String name = feature['properties']?['name'] ?? 
                          feature['properties']?['full_address'] ?? 
                          "Coffee Shop";

            double dist = Geolocator.distanceBetween(lat, lon, pLat, pLon);

            if (dist < minDistance && dist <= 20000) {
              minDistance = dist;
              closest = PlaceModel(
                  name: name,
                  lat: pLat,
                  lon: pLon,
                  distanceKm: dist / 1000,
                  type: category
              );
            }
          }
        }
      } catch (e) {
        print('🗺️ Coffee fetch exception: $e');
      }
    }

    if (closest != null) {
      _lastCoffeeFetch = DateTime.now();
      _cachedNearestCoffee = closest;
    }

    return closest;
  }
}