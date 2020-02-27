# serial_flutterblue

- Package to easily integrate UART/Serial over Bluetooth Low Energy into your Flutter app.
- Based on https://github.com/itavero/flutter-ble-uart
- Add some modification to make it better and more stable

## Getting Started

- Add it to your `pubspec.yaml` like this:

``` dart

dependencies:
  serial_flutterblue:
      git: git@github.com:y60yu1ii/serial_flutter_blue.git
```

- Extend the uartconfig clas if you are not using the Nordic UART service UUID, or you wish to set up MTU

``` dart

import 'package:serial_flutterblue/serial_flutterblue.dart';
import 'package:flutter_blue/flutter_blue.dart';

class MyConfig extends UartConfig {
  //nordic 128 short
  static Guid TIShort(String input) {
    return Guid("0000$input-0000-1000-8000-00805f9b34fb");
  }

  Myconfig()
      : super(
      TIShort("1801"), //service
      TIShort("ffe1"), //TX
      TIShort("ffe2"), //RX
      20);
}

```

