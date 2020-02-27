import 'dart:async';
import 'package:flutter_blue/flutter_blue.dart';
import 'uart_config.dart';
import 'serial_connection.dart';

//modified from flutter-bl-uart
//https://github.com/itavero/flutter-ble-uart/blob/master/lib/src/serial_connection_provider.dart

class BleProvider {
  static final BleProvider _singleton = BleProvider._internal();
  UartConfig config;
  FlutterBlue ble = FlutterBlue.instance;

  factory BleProvider() {
    return _singleton;
  }

  BleProvider._internal() {
    config = MyDeviceConfig();
  }

  SerialConnection init(BluetoothDevice device) {
    return SerialConnection(this, device);
  }

  /// Starts a scan for Bluetooth LE devices that advertise the UART Service.
  ///
  /// Internally this calls the [FlutterBlue.scan] method.
  Stream<ScanResult> scan(
      {ScanMode scanMode = ScanMode.lowLatency,
      List<Guid> withDevices = const [],
      Duration timeout}) async* {
    yield* ble.scan(
        scanMode: scanMode,
        withServices: [],
        withDevices: withDevices,
        timeout: timeout);
  }

  void stopScan() {
    ble.stopScan();
  }

  /// Scan for a fixed duration and return all discovered devices afterwards.
  ///
  /// Internally this calls [scan] with the given timeout. By default
  /// the timeout is set to 10 seconds.
  Future<Iterable<BluetoothDevice>> simplifiedScan({Duration timeout}) async {
    if (timeout == null) {
      timeout = Duration(seconds: 10);
    }

    Map<String, BluetoothDevice> devices = {};
    devices.addEntries(await scan(timeout: timeout)
        .map((sr) => MapEntry(sr.device.id.id, sr.device))
        .toList());
    return devices.values;
  }
}
