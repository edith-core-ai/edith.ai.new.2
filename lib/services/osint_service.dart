import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';

/// One nearby aircraft, as reported by OpenSky Network.
class NearbyFlight {
  final String callsign;
  final String originCountry;
  final double? altitudeMeters;
  final double? velocityMps;

  final double? lat;
  final double? lon;
  final bool onGround;

  NearbyFlight({
    required this.callsign,
    required this.originCountry,
    this.altitudeMeters,
    this.velocityMps,
    this.lat,
    this.lon,
    this.onGround = false,
  });
}

/// One public webcam from the Windy Webcams directory.
class PublicCam {
  final String title;
  final String city;
  final String country;
  final String? previewUrl;
  final double? lat;
  final double? lon;
  PublicCam({
    required this.title,
    required this.city,
    required this.country,
    this.previewUrl,
    this.lat,
    this.lon,
  });
}

/// God Screen data source — v0.3.
///
/// Pulls only legally public data: your device's own location (with your
/// permission, standard OS location services) and live aircraft positions
/// from OpenSky Network's open, free API. No telecom interception, no
/// private data — exactly the "legal OSINT" boundary from the blueprint.
///
/// This is v1 of the God Screen: flights only. Ship tracking and public
/// records are follow-up additions, not included yet.
class OsintService {
  static const _openSkyBase = 'https://opensky-network.org/api/states/all';

  Future<Position> getCurrentLocation() async {
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) {
      throw Exception('Location services are off on this device.');
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw Exception('Location permission denied.');
      }
    }
    if (permission == LocationPermission.deniedForever) {
      throw Exception(
          'Location permission permanently denied — check browser/OS settings.');
    }

    return Geolocator.getCurrentPosition();
  }

  /// Returns aircraft currently within roughly a 1-degree box (~110km)
  /// around the given position — a reasonable "nearby" radius.
  Future<List<NearbyFlight>> getNearbyFlights(Position position) async {
    final lamin = position.latitude - 0.5;
    final lamax = position.latitude + 0.5;
    final lomin = position.longitude - 0.5;
    final lomax = position.longitude + 0.5;

    final url = Uri.parse(
      '$_openSkyBase?lamin=$lamin&lomin=$lomin&lamax=$lamax&lomax=$lomax',
    );

    final response = await http.get(url);
    if (response.statusCode != 200) {
      throw Exception('OpenSky request failed (${response.statusCode}).');
    }

    final data = jsonDecode(response.body);
    final states = data['states'] as List<dynamic>?;
    if (states == null) return [];

    // Each state is a fixed-position array per OpenSky's REST spec:
    // [1]=callsign, [2]=origin_country, [7]=baro_altitude, [9]=velocity
    return states.map((s) {
      final row = s as List<dynamic>;
      return NearbyFlight(
        callsign: (row[1] as String? ?? '').trim().isEmpty
            ? 'Unknown'
            : (row[1] as String).trim(),
        originCountry: row[2] as String? ?? 'Unknown',
        altitudeMeters: (row[7] as num?)?.toDouble(),
        velocityMps: (row[9] as num?)?.toDouble(),
        lat: (row[6] as num?)?.toDouble(),
        lon: (row[5] as num?)?.toDouble(),
        onGround: row[8] == true,
      );
    }).toList();
  }

  /// Every aircraft OpenSky currently reports, worldwide.
  Future<List<NearbyFlight>> getWorldFlights() async {
    final response = await http
        .get(Uri.parse(_openSkyBase))
        .timeout(const Duration(seconds: 40));
    if (response.statusCode == 429) {
      throw Exception(
          'OpenSky says too many requests today (free limit). Try again later.');
    }
    if (response.statusCode != 200) {
      throw Exception('OpenSky request failed (${response.statusCode}).');
    }
    final data = jsonDecode(response.body);
    final states = data['states'] as List<dynamic>?;
    if (states == null) return [];
    final out = <NearbyFlight>[];
    for (final s in states) {
      final row = s as List<dynamic>;
      final lat = (row[6] as num?)?.toDouble();
      final lon = (row[5] as num?)?.toDouble();
      if (lat == null || lon == null) continue;
      final cs = (row[1] as String? ?? '').trim();
      out.add(NearbyFlight(
        callsign: cs.isEmpty ? 'Unknown' : cs,
        originCountry: row[2] as String? ?? 'Unknown',
        altitudeMeters: (row[7] as num?)?.toDouble(),
        velocityMps: (row[9] as num?)?.toDouble(),
        lat: lat,
        lon: lon,
        onGround: row[8] == true,
      ));
    }
    return out;
  }

  /// Public webcams from the Windy Webcams directory. Needs a free key.
  /// Give [country] (2-letter code, e.g. NG) or a position for nearby ones.
  Future<List<PublicCam>> getWebcams(String key,
      {String? country, Position? near}) async {
    final q = StringBuffer(
        'https://api.windy.com/webcams/api/v3/webcams?lang=en&limit=50&include=images,location');
    if (country != null && country.trim().isNotEmpty) {
      q.write('&countries=${country.trim().toUpperCase()}');
    } else if (near != null) {
      q.write('&nearby=${near.latitude},${near.longitude},250');
    }
    final r = await http.get(Uri.parse(q.toString()),
        headers: {'x-windy-api-key': key}).timeout(const Duration(seconds: 25));
    if (r.statusCode == 401 || r.statusCode == 403) {
      throw Exception('Windy rejected the key. Check it in Settings.');
    }
    if (r.statusCode != 200) {
      throw Exception('Webcam request failed (${r.statusCode}).');
    }
    final data = jsonDecode(r.body);
    final list = (data['webcams'] as List<dynamic>?) ?? [];
    return list.map((w) {
      final m = w as Map<String, dynamic>;
      final loc = (m['location'] as Map<String, dynamic>?) ?? {};
      final cur = ((m['images'] as Map<String, dynamic>?)?['current']
              as Map<String, dynamic>?) ??
          {};
      return PublicCam(
        title: (m['title'] ?? 'Webcam').toString(),
        city: (loc['city'] ?? '').toString(),
        country: (loc['country'] ?? '').toString(),
        previewUrl: (cur['preview'] ?? cur['thumbnail'])?.toString(),
        lat: (loc['latitude'] as num?)?.toDouble(),
        lon: (loc['longitude'] as num?)?.toDouble(),
      );
    }).toList();
  }
}
