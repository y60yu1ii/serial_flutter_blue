import 'package:flutter_blue/flutter_blue.dart';

class UartConfig {
  final Guid serviceId;
  final Guid txId;
  final Guid rxId;
  final int mtuSize;

  UartConfig(this.serviceId, this.txId, this.rxId, [this.mtuSize = 20]);
}

class MyDeviceConfig extends UartConfig {
  //nordic 128 short
  static Guid NordicShort(String input) {
    return Guid("6E40$input-B5A3-F393-E0A9-E50E24DCCA9E");
  }

  MyDeviceConfig()
      : super(
            NordicShort("0001"), //service
            NordicShort("0002"), //TX
            NordicShort("0003"), //RX
            20);
}
