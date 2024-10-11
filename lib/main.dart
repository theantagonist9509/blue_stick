import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_joystick/flutter_joystick.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

void main() {
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
  ));
  runApp(const App());
}

class App extends StatefulWidget {
  const App({super.key});

  @override
  State<App> createState() => _AppState();
}

// TODO try-catch and error snackbar where relevant
class _AppState extends State<App> {
  bool isBluetoothSupported = false;

  StreamSubscription<BluetoothAdapterState>? adapterStateSubscription;
  bool isBluetoothOn = false;

  bool havePermissions = false;

  StreamSubscription<bool>? isScanningSubscription;
  bool isScanning = false;

  bool isConnecting = false;
  List<ScanResult> results = [];

  StreamSubscription<OnConnectionStateChangedEvent>?
      connectionStateSubscription;
  BluetoothDevice? device;

  BluetoothCharacteristic? characteristic;

  Future<void> checkBluetooth() async {
    if (!await FlutterBluePlus.isSupported) {
      return;
    }

    setState(() => isBluetoothSupported = true);
    adapterStateSubscription =
        FlutterBluePlus.adapterState.listen((final state) {
      if (state == BluetoothAdapterState.on) {
        setState(() => isBluetoothOn = true);
        checkPermissions();
        return;
      }

      setState(() => isBluetoothOn = false);
    });
  }

  Future<void> checkPermissions() async {
    List<Permission> permissions = [
      Permission.bluetooth,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ];

    for (final permission in permissions) {
      if ((await permission.request()).isDenied) {
        setState(() => havePermissions = false);
        return;
      }
    }

    setState(() => havePermissions = true);

    isScanningSubscription?.cancel();
    isScanningSubscription = FlutterBluePlus.isScanning
        .listen((pIsScanning) => setState(() => isScanning = pIsScanning));

    connectionStateSubscription?.cancel();
    connectionStateSubscription = FlutterBluePlus
        .events.onConnectionStateChanged
        .listen((change) => setState(() => device =
            change.connectionState == BluetoothConnectionState.disconnected
                ? null
                : change.device));
  }

  @override
  void initState() {
    super.initState();
    checkBluetooth();
  }

  @override
  void dispose() {
    connectionStateSubscription?.cancel();
    isScanningSubscription?.cancel();
    adapterStateSubscription?.cancel();
    super.dispose();
  }

  Widget getActionWidget() {
    if (!isBluetoothSupported) {
      return ElevatedButton(
        onPressed: () {},
        child: const Text('Bluetooth Unsupported'),
      );
    }

    if (!isBluetoothOn) {
      return ElevatedButton(
        onPressed: () {},
        child: const Text('Bluetooth Off'),
      );
    }

    if (!havePermissions) {
      return ElevatedButton(
        onPressed: () {},
        child: const Text('Not Enough Permissions'),
      );
    }

    if (isScanning) {
      return const ElevatedButton(
        onPressed: FlutterBluePlus.stopScan,
        child: Text('Stop'),
      );
    }

    if (isConnecting) {
      return const Center(
        child: CircularProgressIndicator(
          color: Colors.white,
        ),
      );
    }

    if (device == null) {
      return ElevatedButton(
        onPressed: () async {
          final subscription =
              FlutterBluePlus.scanResults.listen((scanResults) {
            setState(() {
              results = scanResults;
              results.removeWhere((result) => result.device.advName.isEmpty);
            });
            debugPrint(results[0].device.advName);
          });

          // https://electronics.stackexchange.com/questions/82098/ble-scan-interval-and-window
          await FlutterBluePlus.startScan(timeout: const Duration(seconds: 11));
          FlutterBluePlus.cancelWhenScanComplete(subscription);
        },
        child: const Text('Scan'),
      );
    }

    return ElevatedButton(
      onPressed: () async => await device?.disconnect(),
      child: const Text('Disconnect'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final surfaceColor = Theme.of(context).colorScheme.surface;

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        appBar: AppBar(
          backgroundColor:
              device == null ? Colors.amber[600] : Colors.blueAccent,
          title: Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 40,
                  child: getActionWidget(),
                ),
              ),
              const SizedBox(width: 16),
              DropdownMenu(
                width: 0.5 * screenWidth,
                inputDecorationTheme: InputDecorationTheme(
                  filled: true,
                  fillColor: surfaceColor,
                  constraints: const BoxConstraints(maxHeight: 40),
                ),
                enabled: results.isNotEmpty && !isConnecting,
                onSelected: (pDevice) async {
                  if (pDevice == null || pDevice == device) {
                    return;
                  }

                  device?.disconnect();

                  setState(() => isConnecting = true);
                  await FlutterBluePlus.stopScan();
                  try {
                    await pDevice.connect(timeout: const Duration(seconds: 5));
                    final services = await pDevice.discoverServices(timeout: 5);
                    setState(() {
                      characteristic = services.isEmpty ||
                              services.last.characteristics.isEmpty
                          ? null
                          : services.last.characteristics.last;
                      isConnecting = false;
                    });
                  } catch (e) {
                    if (!context.mounted) {
                      return;
                    }

                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(e.toString()),
                      ),
                    );
                  }
                },
                dropdownMenuEntries: results
                    .map<DropdownMenuEntry<BluetoothDevice>>((result) =>
                        DropdownMenuEntry<BluetoothDevice>(
                            value: result.device, label: result.device.advName))
                    .toList(),
              ),
            ],
          ),
        ),
        body: JoystickArea(
          initialJoystickAlignment: Alignment.center,
          listener: (details) async {
            if (device == null || characteristic == null) {
              return;
            }

            await characteristic!.write(
              Float32List.fromList([details.x, -details.y])
                  .buffer
                  .asUint8List()
                  .toList(),
              allowLongWrite: true,
            );
          },
        ),
      ),
    );
  }
}
