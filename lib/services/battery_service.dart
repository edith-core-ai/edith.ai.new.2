import 'package:battery_plus/battery_plus.dart';

/// Battery status — read-only, no permissions beyond BATTERY_STATS.
class BatteryService {
  final Battery _battery = Battery();

  Future<int> get level => _battery.batteryLevel;
  Stream<BatteryState> get stateStream => _battery.onBatteryStateChanged;
}
