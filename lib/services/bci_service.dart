import 'dart:async';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'bci_commands.dart';

/// BCI Service — v0.6
///
/// Connects to a Muse EEG headband over Bluetooth Low Energy and
/// streams brain-state data (attention, meditation, blink) which gets
/// decoded into simple command intents.
///
/// This mirrors the non-invasive approach used by BrainCo's
/// brain-to-robot platform [citation:9][citation:17]: an EEG headset
/// reads scalp electrical activity, AI decodes it into intent, intent
/// becomes action. The difference is scale — BrainCo controls robots;
/// we control the EDITH app.
///
/// Muse SDK reference: [citation:4][citation:12]
/// BLE transport pattern: [citation:6][citation:18]
class BciService {
  // Muse EEG service UUID (standard across Muse 2 / Muse S)
  static const _museServiceUuid = '0000fe8d-0000-1000-8000-00805f9b34fb';
  static const _museDataCharUuid = '273e0003-4c4d-454d-96be-f03bac821358';

  BluetoothDevice? _device;
  StreamSubscription<List<int>>? _dataSub;
  final _decoder = BciCommandDecoder();

  final _commandStream = StreamController<BciCommand>.broadcast();
  Stream<BciCommand> get commands => _commandStream.stream;

  bool _connected = false;
  bool get isConnected => _connected;

  /// Scan for Muse headbands. Returns list of found devices.
  Future<List<BluetoothDevice>> scan({Duration timeout = const Duration(seconds: 8)}) async {
    final results = <BluetoothDevice>[];
    await FlutterBluePlus.startScan(timeout: timeout);
    final sub = FlutterBluePlus.scanResults.listen((r) {
      for (final result in r) {
        if (result.device.platformName.toLowerCase().contains('muse')) {
          if (!results.any((d) => d.remoteId == result.device.remoteId)) {
            results.add(result.device);
          }
        }
      }
    });
    await Future.delayed(timeout);
    await sub.cancel();
    await FlutterBluePlus.stopScan();
    return results;
  }

  /// Connect to a specific Muse device.
  Future<bool> connect(BluetoothDevice device) async {
    try {
      await device.connect(timeout: const Duration(seconds: 10));
      _device = device;
      _connected = true;

      final services = await device.discoverServices();
      for (final service in services) {
        if (service.uuid.toString().toLowerCase() == _museServiceUuid) {
          for (final char in service.characteristics) {
            if (char.uuid.toString().toLowerCase() == _museDataCharUuid) {
              await char.setNotifyValue(true);
              _dataSub = char.onValueReceived.listen(_handlePacket);
            }
          }
        }
      }
      return true;
    } catch (_) {
      _connected = false;
      return false;
    }
  }

  void _handlePacket(List<int> bytes) {
    // Muse EEG packets are 20-byte frames per channel.
    // Byte 0-1: packet header, byte 2: EEG channel, bytes 3-18: samples.
    // For simplicity we extract a single aggregate "attention" proxy
    // from signal amplitude. Real Muse SDK decodes proper attention/
    // meditation scores — see [citation:4].
    if (bytes.length < 4) return;

    final amplitude = bytes.sublist(3).fold<int>(0, (a, b) => a + b.abs());
    final normalized = (amplitude / (bytes.length - 3) / 2000).clamp(0.0, 1.0);

    final command = _decoder.feed(
      attention: normalized * 100,
      meditation: (1 - normalized) * 100,
      blinkStrength: normalized > 0.85 ? 1.0 : 0.0,
    );

    if (command != null && !_commandStream.isClosed) {
      _commandStream.add(command);
    }
  }

  Future<void> disconnect() async {
    await _dataSub?.cancel();
    await _device?.disconnect();
    _decoder.reset();
    _device = null;
    _connected = false;
  }

  Future<void> dispose() async {
    await disconnect();
    await _commandStream.close();
  }
}
