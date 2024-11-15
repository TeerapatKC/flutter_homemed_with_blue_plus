import 'dart:async';
import 'dart:developer';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter/material.dart';

import '../models/oximeter.dart';

class OximeterMeasureScreen extends StatefulWidget {
  const OximeterMeasureScreen({super.key});

  @override
  State<OximeterMeasureScreen> createState() => O2RateState();
}

class O2RateState extends State<OximeterMeasureScreen> {
  late StreamSubscription<List<ScanResult>> _scanResultsSubscription;
  late StreamSubscription<bool> _isScanningSubscription;
  List<ScanResult> _scanResults = [];
  BluetoothDevice? _connectedDevice;
  bool _isConnected = false;
  bool _isScanning = false;
  Color? _statusColor;
  int? _oxygenValue;

  @override
  void initState() {
    super.initState();

    listenScan();
    startScan();
  }

  @override
  void dispose() {
    _isScanningSubscription.cancel();
    _scanResultsSubscription.cancel();
    super.dispose();
  }

  void startScan() async {
    setState(() {
      _oxygenValue = null;
      _isScanning = true;
    });

    try {
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 15));
    } catch (e) {
      log('startScan: on Error $e');
    }
  }

  void stopScan() {
    log("FlutterBluePlus Stop Scan");
    FlutterBluePlus.stopScan();
    _isScanningSubscription.cancel();
    _scanResultsSubscription.cancel();

    setState(() {
      _isScanning = false;
    });
  }

  void listenScan() {
    _scanResultsSubscription = FlutterBluePlus.onScanResults.listen(
      (results) {
        setState(() {
          _scanResults = results;
        });
        log('Scan results: $_scanResults');
        findDevice(results);
      },
      onError: (e) {
        log('Error: $e');
      },
    );

    _isScanningSubscription = FlutterBluePlus.isScanning.listen((state) {
      setState(() {
        _isScanning = state;
      });
    });
  }

  void findDevice(List<ScanResult> results) {
    for (ScanResult result in results) {
      log('Found device: ${result.device.platformName}');

      if (result.device.platformName == OximeterModel.deviceName) {
        log("Found target device: $_connectedDevice");
        connectToDevice(result.device);
        break;
      }
    }
  }

  void connectToDevice(BluetoothDevice device) async {
    device.connectionState.listen((state) {
      if (mounted) {
        setState(() {
          _isConnected =
              (state == BluetoothConnectionState.connected) ? true : false;
        });
      }
    });

    try {
      await device.connect(autoConnect: true, mtu: null);
      await device.connectionState
          .where((val) => val == BluetoothConnectionState.connected)
          .first;

      if (mounted) {
        setState(() {
          _connectedDevice = device;
        });
      }

      stopScan();

      log("Scanning stopped after successful connection");
      await getDeviceService(device);
    } catch (e) {
      log("FlutterBluePlus Error during Bluetooth operation: $e");
    }
  }

  Future<void> getDeviceService(BluetoothDevice device) async {
    try {
      List<BluetoothService> services = await device.discoverServices();
      log("discoverServices: $services");
      for (BluetoothService service in services) {
        if (service.uuid.toString() == OximeterModel.serviceUUID) {
          log("Service found");

          List<BluetoothCharacteristic> characteristics =
              service.characteristics;
          for (BluetoothCharacteristic characteristic in characteristics) {
            if (characteristic.uuid.toString() ==
                OximeterModel.characteristicUUID) {
              log("Characteristic found");

              await characteristic.setNotifyValue(true);

              final subscription =
                  characteristic.onValueReceived.listen((value) async {
                if (mounted) {
                  await convertCharacteristicValue(value);
                }
              });
              device.cancelWhenDisconnected(subscription);
            }
          }
        }
      }
    } catch (e) {
      log("Error while retrieving services: $e");
    }
  }

  Future<void> convertCharacteristicValue(List<int> value) async {
    log('CharacteristicValue: $value'); // 1a e 0 fe 2

    if (mounted) {
      if (value.isNotEmpty && value.length < 5) {
        setState(() {
          int sys = value[2];
          if (sys != 127) {
            _oxygenValue = sys;
            log("_oxygenValue: $_oxygenValue");
            if (_oxygenValue != null) {
              if (_oxygenValue! < 95) {
                _statusColor = Colors.amber;
              } else if (_oxygenValue! < 90) {
                _statusColor = Colors.red;
              } else {
                _statusColor = Colors.greenAccent;
              }
            }
          }
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new),
            onPressed: () {
              setState(() {
                _isScanning = false;
              });
              stopScan();
              Navigator.of(context).pop();
            }),
        title: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text("Blood oxygen"),
          ],
        ),
        actions: [
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 10, top: 5),
                child: IconButton(
                    onPressed: _isScanning || _isConnected
                        ? null
                        : () async {
                            try {
                              startScan();
                            } catch (e) {
                              log("FlutterBluePlus Error during Scan operation: $e");
                            }
                          },
                    icon: const Icon(Icons.refresh)),
              )
            ],
          )
        ],
        centerTitle: true,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _isConnected
                ? Column(
                    children: [
                      _oxygenValue == null
                          ? const Column(
                              children: [
                                Icon(
                                  Icons.check_circle,
                                  color: Colors.green,
                                  size: 200,
                                ),
                                SizedBox(height: 10),
                                Text(
                                  "Device connected successfully!",
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                                SizedBox(height: 10),
                                Text(
                                  "Waiting for reading...",
                                  style: TextStyle(fontStyle: FontStyle.italic),
                                ),
                              ],
                            )
                          : Column(
                              children: [
                                Text(
                                  "Oxygen Value: $_oxygenValue%",
                                  style: const TextStyle(fontSize: 18),
                                ),
                                const SizedBox(height: 20),
                                ElevatedButton(
                                  onPressed: () {
                                    startScan();
                                  },
                                  child: const Text("Read Again"),
                                ),
                              ],
                            ),
                    ],
                  )
                : Column(
                    children: [
                      if (_oxygenValue != null)
                        Column(
                          children: [
                            Text(
                              "Oxygen Value: $_oxygenValue%",
                              style:
                                  TextStyle(fontSize: 18, color: _statusColor),
                            ),
                            const SizedBox(height: 20),
                            ElevatedButton(
                              onPressed: () {
                                startScan();
                              },
                              child: const Text("Read Again"),
                            ),
                          ],
                        )
                      else
                        Column(
                          children: [
                            _isScanning
                                ? const Column(
                                    children: [
                                      CircularProgressIndicator(),
                                      SizedBox(height: 20),
                                      Text("Scanning for devices..."),
                                    ],
                                  )
                                : Column(
                                    children: [
                                      const Icon(
                                        Icons.error,
                                        color: Colors.red,
                                        size: 200,
                                      ),
                                      const SizedBox(height: 10),
                                      const Text(
                                        "Device not found",
                                        style: TextStyle(
                                            fontWeight: FontWeight.bold),
                                      ),
                                      const SizedBox(height: 10),
                                      const Text("Please connect the device."),
                                      const SizedBox(height: 50),
                                      ElevatedButton(
                                        onPressed: _isScanning
                                            ? null
                                            : () {
                                                startScan();
                                              },
                                        child: const Text("Scan Device"),
                                      ),
                                    ],
                                  ),
                          ],
                        ),
                    ],
                  ),
          ],
        ),
      ),
    );
  }
}
