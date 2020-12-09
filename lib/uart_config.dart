//import 'package:flutter_blue/flutter_blue.dart';
part of serial_flutterblue;

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