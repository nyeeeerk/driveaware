class PlaceModel {
  final String name;
  final double lat;
  final double lon;
  final double distanceKm;
  final String type;

  PlaceModel({
    required this.name,
    required this.lat,
    required this.lon,
    required this.distanceKm,
    this.type = "Safe Stop",
  });
}