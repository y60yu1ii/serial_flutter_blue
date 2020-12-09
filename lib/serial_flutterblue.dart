library serial_flutterblue;

import 'package:flutter_ble_lib/flutter_ble_lib.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:typed_data';
import 'dart:io' show Platform;

import 'package:permission_handler/permission_handler.dart';

part 'exceptions.dart';
part 'ble_provider.dart';
part 'serial_connection.dart';
