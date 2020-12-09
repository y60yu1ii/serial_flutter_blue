import 'dart:async';
import 'package:flutter_ble_lib/flutter_ble_lib.dart';
import 'package:serial_flutterblue/uart_config.dart';
import 'package:serial_flutterblue/serial_connection.dart';
// modified from flutter-bl-uart
//https://github.com/itavero/flutter-ble-uart/blob/master/lib/src/serial_connection_provider.dart

class BleProvider {
  static final BleProvider _singleton = BleProvider._internal();
  UartConfig config;
  BleManager bleManager = BleManager();

  factory BleProvider() {
    return _singleton;
  }

  BleProvider._internal() {
    config = MyDevice1();
  }

  Future<void> setupBleManager() async {
    await bleManager.createClient(); //ready to go!
  }

  Future<void> releaseManager() async{
    await bleManager.destroyClient(); //remember to release native resources when you're done!
  }

  SerialConnection init(Peripheral peripheral) {
    return SerialConnection(this, peripheral);
  }

  /// Starts a scan for Bluetooth LE devices that advertise the UART Service.
  Stream<ScanResult> scan({
    List<String> uuids = const[],
  }) async* {
    yield* bleManager.startPeripheralScan(scanMode: ScanMode.lowLatency, uuids: uuids, allowDuplicates: false, callbackType: CallbackType.allMatches);
  }

  Future<void> stopScan() async{
    await bleManager.stopPeripheralScan();
  }

}