part of serial_flutterblue;
// modified from flutter-bl-uart
//https://github.com/itavero/flutter-ble-uart/blob/master/lib/src/serial_connection_provider.dart

class UartConfig {
  final String serviceId;
  final String txId;
  final String rxId;
  final int mtuSize;

  UartConfig(this.serviceId, this.txId, this.rxId, [this.mtuSize = 20]);
}

class MyDevice1 extends UartConfig {
  //nordic 128 short
  static String NordicShort(String input) {
    return "6E40$input-B5A3-F393-E0A9-E50E24DCCA9E";
    // 6E400001-B5A3-F393-E0A9-E50E24DCCA9E
  }

  MyDevice1()
      : super(
      NordicShort("0001"), //service
      NordicShort("0002"), //TX
      NordicShort("0003"), //RX
      20); //tested on iphone 6as
}

Future<void> _checkPermissions() async {
  if (Platform.isAndroid) {
    Map<Permission, PermissionStatus> statuses = await [
      Permission.location,
      Permission.locationAlways,
      Permission.storage,
    ].request();
    statuses.forEach((key, value) async {
      if (value.isDenied || value.isUndetermined) {
        if (await key.request().isGranted) {
          print("$key is granted");
        }
      }
    });
  }
}

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
    await _checkPermissions();
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