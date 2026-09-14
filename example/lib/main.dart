import 'dart:io';
import 'dart:typed_data';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:niim_blue_flutter/niim_blue_flutter.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NiimBlueLibRN',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
      ),
      home: const AppContent(),
    );
  }
}

class AppContent extends StatefulWidget {
  const AppContent({super.key});

  @override
  State<AppContent> createState() => _AppContentState();
}

class _AppContentState extends State<AppContent> {
  NiimbotBluetoothClient? _client;
  String _status = 'Disconnected';
  List<BluetoothDevice> _devices = [];
  bool _showDeviceList = false;
  Uint8List? _previewImage;
  bool _showPreview = false;
  Future<void> Function()? _pendingPrintAction;

  int get _printWidth => 472;

  Future<bool> _requestPermissions() async {
    if (Platform.isIOS) {
      // iOS doesn't need runtime permissions
      // Bluetooth permissions are handled via Info.plist
      return true;
    }

    // Android 12+ (SDK 31+) needs bluetoothScan and bluetoothConnect
    // Older Android needs bluetooth and location
    final androidInfo = await DeviceInfoPlugin().androidInfo;
    if (androidInfo.version.sdkInt >= 31) {
      final statuses = await [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
      ].request();
      return statuses.values.every((status) => status.isGranted);
    } else {
      final statuses = await [
        Permission.bluetooth,
        Permission.location,
      ].request();
      return statuses.values.every((status) => status.isGranted);
    }
  }

  Future<void> _handleConnect() async {
    final hasPermission = await _requestPermissions();
    if (!hasPermission) {
      if (mounted) {
        _showAlert('Error', 'Bluetooth permissions are required');
      }
      return;
    }

    try {
      setState(() {
        _status = 'Scanning for devices...';
      });

      final foundDevices = await NiimbotBluetoothClient.listDevices(
        timeout: const Duration(seconds: 3),
      );
      final connectedDevices = FlutterBluePlus.connectedDevices;

      if (foundDevices.isEmpty && connectedDevices.isEmpty) {
        if (mounted) {
          _showAlert(
            'No Devices Found',
            'No compatible printers found. Make sure your printer is turned on and in pairing mode.',
          );
          setState(() => _status = 'No devices found');
        }
        return;
      }

      // Combine and deduplicate devices
      final allDevices = [...foundDevices, ...connectedDevices];
      final uniqueDevices = <BluetoothDevice>[];
      final seenIds = <String>{};
      for (final device in allDevices) {
        final id = device.remoteId.str;
        if (!seenIds.contains(id)) {
          seenIds.add(id);
          uniqueDevices.add(device);
        }
      }

      setState(() {
        _devices = uniqueDevices;
        _showDeviceList = true;
        _status = 'Select a device';
      });
    } catch (error) {
      if (mounted) {
        if (error.toString().contains('Bluetooth is not powered on')) {
          _showAlert(
            'Bluetooth Required',
            'Please enable Bluetooth in your device settings and try connecting again.',
          );
        } else {
          _showAlert('Error', error.toString());
        }
        setState(() => _status = 'Scan failed');
      }
    }
  }

  Future<void> _connectToDevice(BluetoothDevice device) async {
    setState(() {
      _showDeviceList = false;
      _status = 'Connecting...';
    });

    try {
      final client = NiimbotBluetoothClient();
      client.setDevice(device);
      final result = await client.connect();
      final printerInfo = client.getPrinterInfo();
      final model = client.getModelMetadata()?.model.value ?? 'UNKNOWN';
      setState(() {
        _client = client;
        _status =
            'Connected to ${result.deviceName} ($model, ID ${printerInfo.modelId}, protocol ${printerInfo.protocolVersion})';
      });
      _client!.startHeartbeat();
    } catch (error) {
      if (mounted) {
        if (error.toString().contains('Bluetooth is not powered on')) {
          _showAlert(
            'Bluetooth Required',
            'Please enable Bluetooth in your device settings and try connecting again.',
          );
        } else {
          _showAlert('Error', error.toString());
        }
        setState(() => _status = 'Connection failed');
      }
    }
  }

  Future<void> _handleDisconnect() async {
    if (_client == null) return;

    try {
      await _client!.abstraction.printEnd();
      await _client!.disconnect();
      setState(() {
        _status = 'Disconnected';
        _client = null;
      });
    } catch (error) {
      _showAlert('Error', 'Failed to disconnect: ${error.toString()}');
    }
  }

  Future<void> _showPreviewAndPrint(
    PrintPage page,
    Future<void> Function() printAction,
  ) async {
    try {
      final imageData = await page.toPreviewImage();
      setState(() {
        _previewImage = imageData;
        _pendingPrintAction = printAction;
        _showPreview = true;
      });
    } catch (error) {
      _showAlert('Error', 'Failed to generate preview: ${error.toString()}');
    }
  }

  Future<void> _executePrint() async {
    setState(() => _showPreview = false);

    if (_client == null || !_client!.isConnected()) {
      _showAlert('Error', 'Not connected');
      setState(() => _pendingPrintAction = null);
      return;
    }

    if (_pendingPrintAction != null) {
      await _pendingPrintAction!();
      setState(() => _pendingPrintAction = null);
    }
  }

  Future<void> _executePrintTask(PrintPage page, String successMessage) async {
    final client = _client;
    if (client == null || !client.isConnected()) {
      throw Exception('Not connected');
    }

    AbstractPrintTask? task;
    var printEnded = false;

    try {
      client.stopHeartbeat();
      client.setPacketInterval(client.getPrinterInfo().modelId == 4097 ? 2 : 0);

      task = client.createPrintTask(
        const PrintOptions(
          totalPages: 1,
          density: 3,
          labelType: LabelType.withGaps,
          statusPollIntervalMs: 100,
          statusTimeoutMs: 8000,
        ),
      );

      if (task == null) {
        throw Exception(
          'Failed to create print task - printer model not detected',
        );
      }

      await task.printInit();

      final encodedImage = page.toEncodedImage();

      await task.printPage(encodedImage, 1);

      await task.waitForFinished();

      await task.printEnd();
      printEnded = true;

      if (mounted) {
        _showAlert('Success', successMessage);
      }
    } catch (error) {
      if (mounted) {
        _showAlert('Error', 'Failed to print: ${error.toString()}');
      }
    } finally {
      if (task != null && !printEnded && client.isConnected()) {
        try {
          await task.printEnd();
        } catch (_) {
          // Preserve the original print error while still attempting cleanup.
        }
      }

      if (identical(_client, client) && client.isConnected()) {
        client.startHeartbeat();
      }
    }
  }

  Future<void> _handlePrint() async {
    if (_client == null || !_client!.isConnected()) {
      _showAlert('Error', 'Not connected');
      return;
    }
    final modelMetaData = _client?.getModelMetadata();
    debugPrint('densityDefault: ${modelMetaData?.densityDefault}');
    debugPrint('densityMax: ${modelMetaData?.densityMax}');
    debugPrint('densityMin: ${modelMetaData?.densityMin}');
    debugPrint('dpi: ${modelMetaData?.dpi}');
    debugPrint('id: ${modelMetaData?.id}');
    debugPrint('model.value: ${modelMetaData?.model.value}');
    debugPrint('paperTypes: ${modelMetaData?.paperTypes}');
    debugPrint('printDirection: ${modelMetaData?.printDirection}');
    debugPrint('printheadPixels: ${modelMetaData?.printheadPixels}');

    final page = PrintPage(_printWidth, 345);
    // for (int i = 0; i < 8; i++) {
    page.addLine(LineOptions(x: 0, y: 340, endX: 585, endY: 340, thickness: 3));
    // }

    await _executePrintTask(page, 'Print sent');
  }

  Future<void> _handlePrintSimple() async {
    // Match the page width to the connected printer's printable head width.
    final pageWidth = 576;
    final pageHeight = 354;
    final page = PrintPage(pageWidth, pageHeight);
    final centerY = pageHeight ~/ 2;
    final qrSize = (pageWidth * 0.26).round();
    final barcodeWidth = (pageWidth * 0.42).round();

    page.addQR(
      'Hello Niimbot',
      QROptions(
        x: pageWidth ~/ 4,
        y: centerY,
        width: qrSize,
        height: qrSize,
        align: HAlignment.center,
        vAlign: VAlignment.middle,
      ),
    );

    page.addBarcode(
      '123456789012',
      BarcodeOptions(
        encoding: BarcodeEncoding.ean13,
        x: pageWidth * 3 ~/ 4,
        y: centerY,
        width: barcodeWidth,
        height: (pageHeight * 0.3).round(),
        align: HAlignment.center,
        vAlign: VAlignment.middle,
      ),
    );

    await _showPreviewAndPrint(page, () async {
      await _executePrintTask(page, 'Simple demo printed');
    });
  }

  Future<void> _handlePrintBoldText() async {
    final pageWidth = 472;
    final page = PrintPage(pageWidth, 345);
    final centerX = pageWidth ~/ 2;

    await page.addText(
      'Hello World',
      TextOptions(
        x: 0,
        y: 60,
        fontSize: 75,
        align: HAlignment.left,
        vAlign: VAlignment.middle,
      ),
    );

    await page.addText(
      'Bold Text',
      TextOptions(
        x: centerX,
        y: 150,
        fontSize: 75,
        fontWeight: FontWeight.bold,
        align: HAlignment.center,
        vAlign: VAlignment.middle,
      ),
    );

    await page.addText(
      'Light Text',
      const TextOptions(
        x: 60,
        y: 240,
        fontSize: 75,
        fontWeight: FontWeight.w300,
        align: HAlignment.left,
        vAlign: VAlignment.middle,
      ),
    );

    page.addLine(
      LineOptions(x: 60, y: 15, endX: _printWidth, endY: 15, thickness: 3),
    );
    page.addLine(
      LineOptions(x: 60, y: 340, endX: _printWidth, endY: 340, thickness: 3),
    );

    await _showPreviewAndPrint(page, () async {
      await _executePrintTask(page, 'Styled text printed');
    });
  }

  Future<void> _handlePrintLandscape() async {
    // Landscape output is a wide page. PageOrientation is for rotating
    // content on a portrait label, not for changing the physical page size.
    final pageWidth = _printWidth;
    final pageHeight = (pageWidth * 320 / 480).round();
    final page = PrintPage(pageWidth, pageHeight);
    final centerX = pageWidth ~/ 2;
    final centerY = pageHeight ~/ 2;
    final qrSize = (pageHeight * 0.25).round();

    page.addQR(
      'Landscape',
      QROptions(
        x: centerX,
        y: (pageHeight * 0.75).round(),
        width: qrSize,
        height: qrSize,
        align: HAlignment.center,
        vAlign: VAlignment.middle,
      ),
    );

    page.addBarcode(
      '987654321098',
      BarcodeOptions(
        encoding: BarcodeEncoding.code128,
        x: centerX,
        y: (pageHeight * 0.25).round(),
        width: (pageWidth * 0.35).round(),
        height: (pageHeight * 0.2).round(),
        align: HAlignment.center,
        vAlign: VAlignment.middle,
      ),
    );

    page.addLine(
      LineOptions(
        x: 40,
        y: centerY,
        endX: pageWidth - 40,
        endY: centerY,
        thickness: 2,
      ),
    );

    await page.addText(
      'LANDSCAPE MODE',
      TextOptions(
        x: centerX,
        y: centerY,
        fontSize: 24,
        align: HAlignment.center,
        vAlign: VAlignment.middle,
      ),
    );

    final heartData = [
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      1,
      1,
      0,
      0,
      0,
      0,
      1,
      1,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      1,
      1,
      1,
      1,
      0,
      0,
      1,
      1,
      1,
      1,
      0,
      0,
      0,
      0,
      0,
      1,
      1,
      1,
      1,
      1,
      1,
      1,
      1,
      1,
      1,
      1,
      1,
      0,
      0,
      0,
      0,
      1,
      1,
      1,
      1,
      1,
      1,
      1,
      1,
      1,
      1,
      1,
      1,
      0,
      0,
      0,
      0,
      1,
      1,
      1,
      1,
      1,
      1,
      1,
      1,
      1,
      1,
      1,
      1,
      0,
      0,
      0,
      0,
      0,
      1,
      1,
      1,
      1,
      1,
      1,
      1,
      1,
      1,
      1,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      1,
      1,
      1,
      1,
      1,
      1,
      1,
      1,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      1,
      1,
      1,
      1,
      1,
      1,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      1,
      1,
      1,
      1,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      1,
      1,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
    ];

    page.addPixelData(
      ImageOptions(
        data: heartData,
        imageWidth: 16,
        imageHeight: 11,
        x: pageWidth - 16,
        y: 0,
        width: 80,
        height: 80,
        align: HAlignment.right,
        vAlign: VAlignment.top,
      ),
    );

    // Add image from URL (async)
    try {
      await page.addImageFromUri(
        'https://fastly.picsum.photos/id/1/100/100.jpg?hmac=ZFE9J9JWYx84uJzvjw4GTuagMzN4FAmaKE4XeJDMZTY',
        const ImageFromBufferOptions(
          x: 0,
          y: 0,
          width: 100,
          height: 70,
          align: HAlignment.left,
          vAlign: VAlignment.top,
          threshold: 128,
        ),
      );
    } catch (e) {
      print('Failed to load image from URL: $e');
    }

    await _showPreviewAndPrint(page, () async {
      await _executePrintTask(page, 'Landscape page printed');
    });
  }

  Future<void> _handlePrintComprehensive() async {
    final page = PrintPage(400, 240);

    // QR Code top left with rotation
    page.addQR(
      'Hello QR',
      const QROptions(
        x: 60,
        y: 60,
        width: 80,
        height: 80,
        align: HAlignment.center,
        vAlign: VAlignment.middle,
        rotate: 15,
      ),
    );

    await page.addText(
      'Hello NIIMBOT!',
      const TextOptions(
        x: 200,
        y: 120,
        fontSize: 32,
        fontWeight: FontWeight.bold,
        align: HAlignment.center,
        vAlign: VAlignment.middle,
      ),
    );

    await page.addText(
      'v1.0',
      const TextOptions(
        x: 350,
        y: 30,
        fontSize: 20,
        fontWeight: FontWeight.bold,
        align: HAlignment.center,
        vAlign: VAlignment.middle,
        rotate: 45,
      ),
    );

    // Heart image center
    final heartData = [
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      1,
      1,
      0,
      0,
      0,
      0,
      1,
      1,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      1,
      1,
      1,
      1,
      0,
      0,
      1,
      1,
      1,
      1,
      0,
      0,
      0,
      0,
      0,
      1,
      1,
      1,
      1,
      1,
      1,
      1,
      1,
      1,
      1,
      1,
      1,
      0,
      0,
      0,
      0,
      1,
      1,
      1,
      1,
      1,
      1,
      1,
      1,
      1,
      1,
      1,
      1,
      0,
      0,
      0,
      0,
      1,
      1,
      1,
      1,
      1,
      1,
      1,
      1,
      1,
      1,
      1,
      1,
      0,
      0,
      0,
      0,
      0,
      1,
      1,
      1,
      1,
      1,
      1,
      1,
      1,
      1,
      1,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      1,
      1,
      1,
      1,
      1,
      1,
      1,
      1,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      1,
      1,
      1,
      1,
      1,
      1,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      1,
      1,
      1,
      1,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      1,
      1,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
    ];

    page.addPixelData(
      ImageOptions(
        data: heartData,
        imageWidth: 16,
        imageHeight: 11,
        x: 200,
        y: 80,
        width: 50,
        height: 35,
        align: HAlignment.center,
        vAlign: VAlignment.middle,
        rotate: 30,
      ),
    );

    // Barcode bottom
    page.addBarcode(
      '123456789012',
      const BarcodeOptions(
        encoding: BarcodeEncoding.ean13,
        x: 200,
        y: 180,
        width: 150,
        height: 40,
        align: HAlignment.center,
        vAlign: VAlignment.middle,
      ),
    );

    page.addLine(
      const LineOptions(x: 50, y: 220, endX: 350, endY: 220, thickness: 1),
    );

    await _showPreviewAndPrint(page, () async {
      await _executePrintTask(page, 'Comprehensive demo printed');
    });
  }

  void _showAlert(String title, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Scaffold(
          backgroundColor: const Color(0xFFF5FCFF),
          body: SafeArea(
            child: SingleChildScrollView(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(height: 40),
                    const Text(
                      'NiimBlueLibRN',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.red,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Status: $_status',
                      style: const TextStyle(fontSize: 16),
                    ),
                    const SizedBox(height: 20),
                    _buildButton(
                      '🔌 Connect to Printer',
                      _handleConnect,
                      Colors.blue[700]!,
                    ),
                    _buildButton(
                      '⏏️ Disconnect',
                      _handleDisconnect,
                      Colors.blue[700]!,
                    ),
                    _buildButton(
                      '🖨️ Quick Print Test',
                      _handlePrint,
                      Colors.blue[700]!,
                    ),
                    _buildButton(
                      '🅰️ Bold Text Demo',
                      _handlePrintBoldText,
                      Colors.blue[700]!,
                    ),
                    _buildButton(
                      '📋 All-in-One Demo',
                      _handlePrintComprehensive,
                      const Color(0xFF5856D6),
                    ),
                    _buildButton(
                      '🎨 Simple Demo',
                      _handlePrintSimple,
                      const Color(0xFF34C759),
                    ),
                    _buildButton(
                      '📄 Landscape Mode',
                      _handlePrintLandscape,
                      const Color(0xFF34C759),
                    ),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (_showDeviceList) _buildDeviceSelectionModal(),
        if (_showPreview) _buildPreviewModal(),
      ],
    );
  }

  Widget _buildButton(String label, VoidCallback onPressed, Color color) {
    return Container(
      width: MediaQuery.of(context).size.width * 0.8,
      margin: const EdgeInsets.symmetric(vertical: 10),
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          padding: const EdgeInsets.all(15),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
        ),
        child: Text(
          label,
          style: const TextStyle(color: Colors.white, fontSize: 16),
        ),
      ),
    );
  }

  Widget _buildDeviceSelectionModal() {
    return Container(
      color: Colors.black.withValues(alpha: 0.5),
      child: Center(
        child: Container(
          margin: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  'Select a Device',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue[700],
                  ),
                ),
              ),
              const Divider(height: 1),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.5,
                ),
                child: Material(
                  color: Colors.transparent,
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _devices.length,
                    itemBuilder: (context, index) {
                      final device = _devices[index];
                      final name = device.platformName;
                      final id = device.remoteId.str;
                      return ListTile(
                        title: Text(name),
                        subtitle: Text(id),
                        onTap: () => _connectToDevice(device),
                      );
                    },
                  ),
                ),
              ),
              const Divider(height: 1),
              TextButton(
                onPressed: () => setState(() => _showDeviceList = false),
                child: const Text(
                  'Cancel',
                  style: TextStyle(color: Colors.red, fontSize: 16),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPreviewModal() {
    return Material(
      color: Colors.transparent,
      child: Container(
        color: Colors.black.withValues(alpha: 0.5),
        child: Center(
          child: Container(
            margin: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(
                    'Preview',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue[700],
                    ),
                  ),
                ),
                const Divider(height: 1),
                if (_previewImage != null)
                  Container(
                    color: Colors.black,
                    padding: const EdgeInsets.all(20),
                    child: Image.memory(
                      _previewImage!,
                      fit: BoxFit.contain,
                      height: MediaQuery.of(context).size.height * 0.4,
                    ),
                  ),
                const Divider(height: 1),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    TextButton(
                      onPressed: () => setState(() => _showPreview = false),
                      child: const Text(
                        'Cancel',
                        style: TextStyle(color: Colors.red, fontSize: 16),
                      ),
                    ),
                    ElevatedButton(
                      onPressed: _executePrint,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF34C759),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 30,
                          vertical: 12,
                        ),
                      ),
                      child: const Text(
                        'Print',
                        style: TextStyle(color: Colors.white, fontSize: 16),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _client?.disconnect();
    super.dispose();
  }
}
