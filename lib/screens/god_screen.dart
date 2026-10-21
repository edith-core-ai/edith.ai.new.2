import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../services/osint_service.dart';
import '../services/settings_service.dart';
import '../theme/edith_theme.dart';

/// The God Screen: every aircraft OpenSky reports worldwide, plus public
/// webcams worldwide (official Windy directory). Public data only.
class GodScreen extends StatefulWidget {
  const GodScreen({super.key});

  @override
  State<GodScreen> createState() => _GodScreenState();
}

class _GodScreenState extends State<GodScreen> {
  final _osint = OsintService();
  final _search = TextEditingController();
  final _country = TextEditingController();
  Position? _position;
  List<NearbyFlight> _flights = [];
  List<PublicCam> _cams = [];
  bool _loadingFlights = true;
  bool _loadingCams = false;
  String? _flightError;
  String? _camError;
  String _filter = '';

  @override
  void initState() {
    super.initState();
    _loadFlights();
    _osint.getCurrentLocation().then((p) {
      if (mounted) setState(() => _position = p);
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _search.dispose();
    _country.dispose();
    super.dispose();
  }

  Future<void> _loadFlights() async {
    setState(() {
      _loadingFlights = true;
      _flightError = null;
    });
    try {
      final f = await _osint.getWorldFlights();
      if (!mounted) return;
      setState(() {
        _flights = f;
        _loadingFlights = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _flightError = e.toString().replaceFirst('Exception: ', '');
        _loadingFlights = false;
      });
    }
  }

  Future<void> _loadCams({bool nearMe = false}) async {
    final key = SettingsService.windyKey;
    if (key.isEmpty) {
      setState(() => _camError =
          'Add a free Windy Webcams key in Settings to see public cameras.');
      return;
    }
    setState(() {
      _loadingCams = true;
      _camError = null;
    });
    try {
      Position? near;
      if (nearMe) near = _position ?? await _osint.getCurrentLocation();
      final c = await _osint.getWebcams(key,
          country: nearMe ? null : _country.text, near: near);
      if (!mounted) return;
      setState(() {
        _cams = c;
        _loadingCams = false;
        if (c.isEmpty) _camError = 'No public cameras found for that.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _camError = e.toString().replaceFirst('Exception: ', '');
        _loadingCams = false;
      });
    }
  }

  List<NearbyFlight> get _shown {
    if (_filter.isEmpty) return _flights;
    final q = _filter.toLowerCase();
    return _flights
        .where((f) =>
            f.callsign.toLowerCase().contains(q) ||
            f.originCountry.toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('GOD SCREEN',
              style: TextStyle(letterSpacing: 4, fontWeight: FontWeight.bold)),
          bottom: const TabBar(
            tabs: [Tab(text: 'Flights'), Tab(text: 'Cameras')],
          ),
        ),
        body: TabBarView(children: [_flightsTab(), _camsTab()]),
      ),
    );
  }

  Widget _flightsTab() {
    if (_loadingFlights) {
      return Center(
          child: CircularProgressIndicator(color: EdithTheme.electricBlue));
    }
    if (_flightError != null) {
      return _errorBox(_flightError!, _loadFlights);
    }
    final shown = _shown;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _search,
                  onChanged: (v) => setState(() => _filter = v.trim()),
                  decoration: const InputDecoration(
                    hintText: 'Callsign or country',
                    prefixIcon: Icon(Icons.search),
                  ),
                ),
              ),
              IconButton(
                onPressed: _loadFlights,
                icon: const Icon(Icons.refresh),
                tooltip: 'Refresh',
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text('${shown.length} aircraft in the air worldwide',
                style: TextStyle(
                    color: EdithTheme.electricBlue,
                    fontSize: 12,
                    letterSpacing: 1.5)),
          ),
        ),
        SizedBox(
          height: 190,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: CustomPaint(
                painter: _WorldPainter(shown, _position),
                size: Size.infinite,
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: shown.length > 300 ? 300 : shown.length,
            itemBuilder: (_, i) {
              final f = shown[i];
              return ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.flight,
                    color: EdithTheme.electricBlue, size: 18),
                title: Text(f.callsign,
                    style: const TextStyle(color: EdithTheme.textPrimary)),
                subtitle: Text(
                  '${f.originCountry}'
                  '${f.onGround ? " · on ground" : ""}'
                  '${f.altitudeMeters != null ? " · ${(f.altitudeMeters! * 3.281).round()} ft" : ""}'
                  '${f.velocityMps != null ? " · ${(f.velocityMps! * 1.944).round()} kt" : ""}',
                  style: const TextStyle(
                      color: EdithTheme.textSecondary, fontSize: 12),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _camsTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _country,
                  textCapitalization: TextCapitalization.characters,
                  maxLength: 2,
                  decoration: const InputDecoration(
                    hintText: 'Country code, e.g. NG, US, JP',
                    counterText: '',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _loadingCams ? null : () => _loadCams(),
                child: const Text('Show'),
              ),
              IconButton(
                onPressed: _loadingCams ? null : () => _loadCams(nearMe: true),
                icon: const Icon(Icons.my_location),
                tooltip: 'Near me',
              ),
            ],
          ),
        ),
        Expanded(
          child: _loadingCams
              ? Center(
                  child: CircularProgressIndicator(
                      color: EdithTheme.electricBlue))
              : _cams.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          _camError ??
                              'Pick a country or tap the location icon. '
                                  'These are official public webcams only.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              color: EdithTheme.textSecondary),
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: _cams.length,
                      itemBuilder: (_, i) {
                        final c = _cams[i];
                        return Card(
                          color: EdithTheme.surface,
                          margin: const EdgeInsets.only(bottom: 12),
                          clipBehavior: Clip.antiAlias,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (c.previewUrl != null)
                                Image.network(
                                  c.previewUrl!,
                                  height: 180,
                                  width: double.infinity,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => const SizedBox(
                                      height: 60,
                                      child: Center(
                                          child: Text('Preview unavailable'))),
                                ),
                              Padding(
                                padding: const EdgeInsets.all(10),
                                child: Text(
                                  '${c.title}\n${c.city}${c.city.isEmpty ? "" : ", "}${c.country}',
                                  style: const TextStyle(
                                      color: EdithTheme.textPrimary,
                                      fontSize: 13),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }

  Widget _errorBox(String msg, VoidCallback retry) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.warning_amber_rounded,
                  color: EdithTheme.electricBlue, size: 40),
              const SizedBox(height: 12),
              Text(msg,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: EdithTheme.textSecondary)),
              const SizedBox(height: 16),
              ElevatedButton(onPressed: retry, child: const Text('Try again')),
            ],
          ),
        ),
      );
}

/// Flat world plot: each aircraft is a dot, your position a ring.
class _WorldPainter extends CustomPainter {
  final List<NearbyFlight> flights;
  final Position? me;
  _WorldPainter(this.flights, this.me);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height),
        Paint()..color = const Color(0xFF05080F));
    final grid = Paint()
      ..color = const Color(0x22FFFFFF)
      ..strokeWidth = 0.5;
    for (var i = 1; i < 12; i++) {
      final x = size.width * i / 12;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    for (var i = 1; i < 6; i++) {
      final y = size.height * i / 6;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    final dot = Paint()..color = EdithTheme.electricBlue;
    for (final f in flights) {
      if (f.lat == null || f.lon == null) continue;
      final x = (f.lon! + 180) / 360 * size.width;
      final y = (90 - f.lat!) / 180 * size.height;
      canvas.drawCircle(Offset(x, y), 0.9, dot);
    }
    if (me != null) {
      final x = (me!.longitude + 180) / 360 * size.width;
      final y = (90 - me!.latitude) / 180 * size.height;
      canvas.drawCircle(
          Offset(x, y),
          5,
          Paint()
            ..color = Colors.orangeAccent
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5);
    }
  }

  @override
  bool shouldRepaint(covariant _WorldPainter old) =>
      old.flights != flights || old.me != me;
}
