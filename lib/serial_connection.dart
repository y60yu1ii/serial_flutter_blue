//import 'dart:async';
//import 'dart:convert';
//import 'package:flutter_blue/flutter_blue.dart';
//import 'exceptions.dart';
//import 'ble_provider.dart';
//import 'dart:developer';

part of serial_flutterblue;

class SerialConnection {
  int reconnectCounter = 0; //for android
  int sendDelay = 0; //for device that too slow

  final BleProvider _provider;
  final BluetoothDevice _device;
  final StreamController<SerialConnectionState> _onStateChangeController =
      StreamController<SerialConnectionState>.broadcast();
  final StreamController<List<int>> _onDataReceivedController =
      StreamController<List<int>>.broadcast();

  final StreamController<String> _onTextReceivedController =
      StreamController<String>.broadcast();

  final StreamController<int> _onChunkIndexUpdateController =
      StreamController<int>.broadcast();

  SerialConnectionState _state = SerialConnectionState.disconnected;
  BluetoothCharacteristic _txCharacteristic;
  BluetoothCharacteristic _rxCharacteristic;
  StreamSubscription _deviceConnection;
  StreamSubscription _deviceStateSubscription;
  StreamSubscription _incomingDataSubscription;

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
  BluetoothDevice get device => _device;

  /// String representation of the [BluetoothDevice] identifier.
  String get deviceId => _device.id.toString();

  SerialConnection(this._provider, this._device);

  //define Tx write type from properties
  bool isWriteWithoutResponse = false;

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

  Future<void> _handleBluetoothDeviceState(
      BluetoothDeviceState deviceState) async {
    if (deviceState == BluetoothDeviceState.connected) {
      reconnectCounter = 0;
      await _discoverServices();
    } else if (deviceState == BluetoothDeviceState.disconnected) {
      if (_state == SerialConnectionState.connecting && reconnectCounter < 3) {
        reconnectCounter++;
        return;
      } //reconnect protection for android
      reconnectCounter = 0;
      _txCharacteristic = null;
      _rxCharacteristic = null;
      _incomingDataSubscription?.cancel();
      _incomingDataSubscription = null;
      _deviceStateSubscription?.cancel();
      _deviceStateSubscription = null;
      _deviceConnection?.cancel();
      _deviceConnection = null;
      _updateState(SerialConnectionState.disconnected);
//      log("disconnected start check state is $_state");
    }
  }

  Future<void> _discoverServices() async {
    _updateState(SerialConnectionState.discovering);

    // Search for serial service
    List<BluetoothService> services = await _device.discoverServices();

    BluetoothService serialService =
        services.firstWhere((s) => s.uuid == _provider.config.serviceId);
    if (serialService == null) {
      await disconnect();
      log('BLE UART service NOT found on device $deviceId');
      throw SerialConnectionServiceNotFoundException(_provider.config);
    } else {}

    _txCharacteristic =
        _findCharacteristic(serialService, _provider.config.txId);
    _rxCharacteristic =
        _findCharacteristic(serialService, _provider.config.rxId);

    isWriteWithoutResponse = _txCharacteristic.properties.writeWithoutResponse;

    // Set up notifications for RX characteristic
    _updateState(SerialConnectionState.subscribing);
    await _rxCharacteristic.setNotifyValue(true);
    _incomingDataSubscription?.cancel();
    _incomingDataSubscription = _rxCharacteristic.value.listen(_onIncomingData);
    // Done!
    _updateState(SerialConnectionState.connected);
  }

  BluetoothCharacteristic _findCharacteristic(
      BluetoothService service, Guid characteristicId) {
    BluetoothCharacteristic characteristic =
        service.characteristics.firstWhere((c) => c.uuid == characteristicId);
    if (characteristic == null) {
      log('BLE UART Characteristic (${characteristicId.toString()} NOT '
          'found on device $deviceId.');
      throw SerialConnectionCharacteristicNotFoundException(characteristicId);
    }
    return characteristic;
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
      if (Platform.isAndroid) {
        timeout = Duration(seconds: 15);
      } else {
        timeout = Duration(seconds: 10);
      }
    }

    // Set-up timeout
    Future.delayed(timeout, () {
      if (_state != SerialConnectionState.connected ||
          _state != SerialConnectionState.subscribing) {
        disconnect();
        log('SerialConnection $deviceId: Cancelled connection attempt due to timeout');
      }
    });

    // Connect to device
    _updateState(SerialConnectionState.connecting);
    try {
//      _provider.stopScan();
      _device.connect(autoConnect: false);
      _deviceStateSubscription =
          _device.state.listen(_handleBluetoothDeviceState);
    } on Exception catch (ex) {
      log('SerialConnection exception during connect: ${ex.toString()}');
      disconnect();
    }
  }

  /// Close the connection entirely.
  ///
  /// Note that you will *NOT* be able to use this instance afterwards.
  /// This should be called for instance when your app is shutdown or the
  /// page that is using this connection is exited (disposed).
  Future<void> close() async {
    await disconnect();
    await _onTextReceivedController?.close();
    await _onDataReceivedController?.close();
    await _onChunkIndexUpdateController?.close();
    await _onStateChangeController?.close();
    _state = SerialConnectionState.disconnected;
  }

  /// Send raw data (bytes) over the connection.
  Future<void> sendRawData(List<int> raw) async {
    if (_state != SerialConnectionState.connected ||
        _txCharacteristic == null) {
      throw SerialConnectionNotReadyException();
    }

//    log("sending $raw");
//    log("sending ${utf8.decode(raw)}");

    int offset = 0;
    final int chunkSize = _provider.config.mtuSize;
    while (offset < raw.length) {
      var chunk = raw.skip(offset).take(chunkSize).toList();
//      log(".. chunk $chunk");
      offset += chunkSize;
      await _txCharacteristic.write(chunk,
          withoutResponse: isWriteWithoutResponse);
      await Future.delayed(Duration(milliseconds: sendDelay));
      if (_onChunkIndexUpdateController.hasListener) {
        _onChunkIndexUpdateController.add(offset);
      }
    }
  }

  /// Send a text string over the connection.
  ///
  /// The text will be UTF-8 encoded before being transmitted.
  Future<void> sendText(String text) async {
    await sendRawData(utf8.encode(text));
  }

  /// Disconnect from the device
  Future<void> disconnect() async {
    if (_state != SerialConnectionState.disconnected) {
      _updateState(SerialConnectionState.disconnecting);
      _txCharacteristic = null;
      if (_rxCharacteristic != null) {
        await _rxCharacteristic.setNotifyValue(false);
      }
      _rxCharacteristic = null;
      _incomingDataSubscription?.cancel();
      _incomingDataSubscription = null;
      _deviceStateSubscription?.cancel();
      _deviceStateSubscription = null;
      _deviceConnection?.cancel();
      _deviceConnection = null;
      _updateState(SerialConnectionState.disconnected);
    }
    await _device.disconnect();
  }
}

/// Represents the current state of a [SerialConnection]
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
