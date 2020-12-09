part of serial_flutterblue;

class SerialConnection {
  int reconnectCounter = 0; //for android
  int sendDelay = 0; //for device that too slow

  final BleProvider _provider;
  final Peripheral _peripheral;

  final StreamController<SerialConnectionState> _onStateChangeController =
  StreamController<SerialConnectionState>.broadcast();
  final StreamController<List<int>> _onDataReceivedController =
  StreamController<List<int>>.broadcast();

  final StreamController<String> _onTextReceivedController =
  StreamController<String>.broadcast();

  final StreamController<int> _onChunkIndexUpdateController =
  StreamController<int>.broadcast();

  SerialConnectionState _state = SerialConnectionState.disconnected;
  Characteristic _txCharacteristic;
  Characteristic _rxCharacteristic;
  StreamSubscription _deviceConnection;
  StreamSubscription _deviceStateSubscription;
  StreamSubscription _incomingDataSubscription;
  bool isReceiving = false;

  /// Subscribe/listen to get notified of state changes.
  Stream<SerialConnectionState> get onStateChange =>
      _onStateChangeController.stream;

  /// Subscribe/listen to get incoming raw data.
  Stream<List<int>> get onDataReceived => _onDataReceivedController.stream;

  /// Subscribe/listen to get incoming data after it is decode as UTF-8 string.
  Stream<String> get onTextReceived => _onTextReceivedController.stream;

  //Subscribe/listen to get updates of chunk index, could be used as sending progress
  Stream<int> get onChunkIndexUpdated => _onChunkIndexUpdateController.stream;

  /// Device which this instance was created with.
  Peripheral get peripheral => _peripheral;

  String get deviceId => _peripheral.identifier.toString();

  SerialConnection(this._provider, this._peripheral);

  //define Tx write type from properties
  bool isWriteWithoutResponse = false;

  bool isWriting = false;
  var connectionError;

  void setSendDelay(int delay) {
    sendDelay = delay;
  }

  void _updateState(SerialConnectionState state) {
    if (_state != state) {
      _state = state;
      if (_onStateChangeController.hasListener) {
        _onStateChangeController.add(state);
      }
    }
  }

  void _onIncomingData(List<int> data) {
    if (_onDataReceivedController.hasListener) {
      _onDataReceivedController.add(data);
    }
    if (_onTextReceivedController.hasListener) {
      try {
        String text = utf8.decode(data, allowMalformed: true);
        if (text.length > 0) {
          _onTextReceivedController.add(text);
        }
      } catch (Exception) {
        // ignore errors for now
        // TODO Find a solution for this.
      }
    }
  }

  Future<void> _handlePeripheralState(
      PeripheralConnectionState connectionState) async {
    print("====================== state connection is $connectionState");
    if (connectionState == PeripheralConnectionState.connected) {
      if (Platform.isAndroid) {
        await Future.delayed(
            Duration(milliseconds: 1600)); //await 1600ms like nrfconnect
      }
      await _discoverServices();
      reconnectCounter = 0;
    } else if (connectionState == PeripheralConnectionState.disconnected) {
      disconnect();
    }
  }

  Future<void> _discoverServices() async {
    _updateState(SerialConnectionState.discovering);
    await _peripheral.discoverAllServicesAndCharacteristics(
        transactionId: "discovery");
    List<Service> services =
    await _peripheral.services(); //getting all services
    //find pre-defined characteristics (provide configs) from all services
    List<Characteristic> characteristics = await services
        .firstWhere((service) =>
    service.uuid.toLowerCase() ==
        _provider.config.serviceId.toLowerCase())
        .characteristics();

    Service serialService = services.firstWhere((s) =>
    s.uuid.toLowerCase() == _provider.config.serviceId.toLowerCase());
    if (serialService == null) {
      disconnect();
      print('BLE UART service NOT found on device $deviceId');
      throw SerialConnectionServiceNotFoundException(_provider.config);
    }

    _updateState(SerialConnectionState.subscribing);

    _txCharacteristic =
        _findCharacteristic(characteristics, _provider.config.txId);
    _rxCharacteristic =
        _findCharacteristic(characteristics, _provider.config.rxId);

    isWriteWithoutResponse = _txCharacteristic.isWritableWithoutResponse;

    // Set up notifications for RX characteristic(notify)
    if (_rxCharacteristic.isNotifiable) {
      _incomingDataSubscription?.cancel();
      _rxCharacteristic
          .monitor(transactionId: "monitor")
          .listen(_onIncomingData);
    }
    // Done!
    _updateState(SerialConnectionState.connected);
  }

  Characteristic _findCharacteristic(
      List<Characteristic> characteristics, String characteristicId) {
    Characteristic ch = characteristics.firstWhere(
            (c) => c.uuid.toLowerCase() == characteristicId.toLowerCase());
    if (ch == null) {
      print('BLE UART Characteristic (${characteristicId.toString()} NOT '
          'found on device $deviceId.');
      throw SerialConnectionCharacteristicNotFoundException(characteristicId);
    }
    return ch;
  }

  /// Disconnect from the device
  Future<void> disconnect() async {
    if (_state != SerialConnectionState.disconnected) {
      _updateState(SerialConnectionState.disconnecting);
    }
    if (_rxCharacteristic != null) {
      await _provider.bleManager.cancelTransaction("monitor");
    }
    await _peripheral.disconnectOrCancelConnection();

    // await _provider.bleManager.cancelTransaction("discovery");
    await _provider.bleManager.destroyClient();

    _incomingDataSubscription?.cancel();
    _deviceStateSubscription?.cancel();
    _deviceConnection?.cancel();
    _deviceConnection = null;
    _txCharacteristic = null;
    _rxCharacteristic = null;
    _incomingDataSubscription = null;
    _deviceStateSubscription = null;

    _updateState(SerialConnectionState.disconnected);
  }

  /// Connect to the device over Bluetooth LE.
  ///
  /// This will start the connection procedure: from connecting to the device,
  /// to discovering the configured service (and its characteristics) and
  /// setting up notifications for the RX characteristic.
  ///
  /// Timeout defaults to 30 seconds.
  ///
  /// In case the device is already connected or busy connecting, this will
  /// throw a [SerialConnectionWrongStateException].
  Future<void> connect({Duration timeout}) async {
    if (_state != SerialConnectionState.disconnected) {
      throw SerialConnectionWrongStateException(_state);
    }
    if (timeout == null) {
      timeout = Duration(seconds: 30);
    }
    // Set-up timeout for connect attempt
    Future.delayed(timeout, () async {
      if (_state == SerialConnectionState.connecting) {
        // print(
        //     'SerialConnection $deviceId: Cancelled connection attempt due to timeout, origin state is $_state');
        disconnect();
      }
      // print("time out running");
    });
    // Connect to device
    _updateState(SerialConnectionState.connecting);

    try {
      _deviceConnection = _peripheral
          .observeConnectionState(
          emitCurrentValue: false, completeOnDisconnect: true)
          .listen(_handlePeripheralState);

      _peripheral.connect(
        refreshGatt: true,
        isAutoConnect: false,
      );

    } on Exception catch (ex) {
      print('SerialConnection exception during connect: ${ex.toString()}');
      disconnect();
    }
  }

  /// Close the connection entirely.
  ///
  /// Note that you will *NOT* be able to use this instance afterwards.
  /// This should be called for instance when your app is shutdown or the
  /// page that is using this connection is exited (disposed).
  Future<void> close() async {
    reconnectCounter = 0;
    disconnect();
    await _onTextReceivedController?.close();
    await _onDataReceivedController?.close();
    await _onChunkIndexUpdateController?.close();
    await _onStateChangeController?.close();
    _state = SerialConnectionState.disconnected;
  }

  /// Send raw data (bytes) over the connection.
  /// important !!!
  /// Every raw data should chopped in to small chunks with MTU Size
  ///
  Future<void> sendRawData(List<int> raw) async {
    if (isWriting) return;
    isWriting = true;
    if (_state != SerialConnectionState.connected ||
        _txCharacteristic == null) {
      isWriting = false;
      throw SerialConnectionNotReadyException();
    }
    int offset = 0;
    final int chunkSize = _provider.config.mtuSize;
    while (offset < raw.length) {
      var chunk = raw.skip(offset).take(chunkSize).toList();
      // print(".. chunk $chunk");
      offset += chunkSize;
      await _txCharacteristic.write(Uint8List.fromList(chunk),
          !isWriteWithoutResponse); //write with response
      if (_onChunkIndexUpdateController.hasListener) {
        _onChunkIndexUpdateController.add(offset);
      }
      //pre set delays
      await Future.delayed(Duration(milliseconds: sendDelay));
    }
    isWriting = false;
  }

  /// Send a text string over the connection.
  /// The text will be UTF-8 encoded before being transmitted.
  Future<void> sendText(String text) async {
    await sendRawData(utf8.encode(text));
  }

  Future<int> readRSSI() async {
    if (_state == SerialConnectionState.connected) {
      return await _peripheral?.rssi();
    } else {
      return 127;
    }
  }
}

// /// Represents the current state of a [SerialConnection]
enum SerialConnectionState {
  /// Disconnected.
  disconnected,

  /// Connection process started.
  connecting,

  /// Bluetooth connection set-up, busy discovering services.
  discovering,

  /// UART service discovered, busy subscribing to the RX characteristic.
  subscribing,

  /// Connection process completed, [SerialConnection] instance is now usable.
  connected,

  /// Busy cleaning up internal streams and disconnecting from device.
  disconnecting
}
