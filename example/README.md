# niim_blue_flutter Example

Example Flutter application demonstrating how to use the `niim_blue_flutter` library for BLE printing with NIIMBOT thermal printers.

## Features

This example demonstrates all major features of the library:

- 📱 **Device Scanning** - Find nearby NIIMBOT printers
- 🔗 **Connection Management** - Connect/disconnect with auto-reconnect
- ✍️ **Text Rendering** - Add text with custom fonts and styles
- 📝 **QR Codes** - Generate and print QR codes with error correction
- 📊 **Barcodes** - Support for EAN13 and CODE128
- 🖼️ **Images** - Load from network or local sources
- 🎨 **Rich Content** - Combine text, QR, barcodes, and images on one page
- 🔄 **Page Orientation** - Portrait and landscape printing
- 👁️ **Print Preview** - Preview before printing

## Demo Buttons

The example app includes 6 demo buttons showcasing different features:

1. **Print Simple** - Basic text and QR code
2. **Print Styled Text** - Different font weights and styles
3. **Print Landscape** - Landscape mode with image from URL
4. **Print Comprehensive** - All elements with rotation
5. **Print Multipage** - Multiple pages with connectivity check
6. **Print Dark** - Dark mode example with custom density

## Getting Started

### Prerequisites

- Flutter SDK >=3.0.0
- Physical Android/iOS device with Bluetooth LE
- NIIMBOT printer (B1, B21, D110, D11, etc.)

### Installation

1. Navigate to the example directory:
```bash
cd example
```

2. Get dependencies:
```bash
flutter pub get
```

3. Run the app:
```bash
# iOS
flutter run

# Android
flutter run
```

### Permissions

The app will request Bluetooth permissions at runtime. Make sure permissions are configured:

#### Android

Already configured in `android/app/src/main/AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.BLUETOOTH" />
<uses-permission android:name="android.permission.BLUETOOTH_ADMIN" />
<uses-permission android:name="android.permission.BLUETOOTH_SCAN" android:usesPermissionFlags="neverForLocation" />
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
```

#### iOS

Already configured in `ios/Runner/Info.plist`:

```xml
<key>NSBluetoothAlwaysUsageDescription</key>
<string>App needs Bluetooth to connect to NIIMBOT printers</string>
<key>NSBluetoothPeripheralUsageDescription</key>
<string>App needs Bluetooth to connect to NIIMBOT printers</string>
```

## Usage

### 1. Scan and Connect

```dart
// Scan for nearby printers (3 seconds)
final foundDevices = await NiimbotBluetoothClient.listDevices(
  timeout: Duration(seconds: 3),
);

// List already connected devices
final connectedDevices = await NiimbotBluetoothClient.listConnectedDevices();

// Connect to a device
final client = NiimbotBluetoothClient();
client.setDevice(device);
await client.connect();
```

### 2. Create Print Content

```dart
// Create a page
final page = PrintPage(400, 240); // width x height

// Add text (async method)
await page.addText(
  'Hello NIIMBOT!',
  TextOptions(
    x: 200,
    y: 120,
    fontSize: 24,
    align: HAlignment.center,
    vAlign: VAlignment.middle,
  ),
);

// Add QR code
page.addQR(
  'https://example.com',
  QROptions(
    x: 200,
    y: 100,
    width: 100,
    height: 100,
    align: HAlignment.center,
    vAlign: VAlignment.middle,
    ecl: QRErrorCorrection.medium,
  ),
);

// Add barcode
page.addBarcode(
  '123456789012',
  BarcodeOptions(
    encoding: BarcodeEncoding.ean13,
    x: 200,
    y: 180,
    width: 200,
    height: 60,
    align: HAlignment.center,
  ),
);

// Add image from URL (async)
await page.addImageFromUri(
  'https://example.com/image.jpg',
  ImageFromBufferOptions(
    x: 50,
    y: 50,
    width: 100,
    height: 100,
    threshold: 128,
  ),
);
```

### 3. Print

```dart
// Stop heartbeat before printing
client.stopHeartbeat();
client.setPacketInterval(0); // Fast printing

// Create print task (auto-detects printer model)
final task = client.createPrintTask(
  PrintOptions(
    totalPages: 1,
    density: 3, // 1-5, higher = darker
    labelType: 1,
  ),
);

// Print
await task.printInit();
await task.printPage(page.toEncodedImage(), 1);
await task.waitForFinished();

// Resume heartbeat
client.startHeartbeat();
```

### 4. Preview Before Printing

```dart
// Generate PNG preview
final pngBytes = await page.toPreviewImage();

// Display in Image widget
Image.memory(pngBytes);
```

## Code Structure

```
lib/
└── main.dart          # Main app with 6 demo examples

Key sections in main.dart:
- Device scanning and connection
- 6 print demo functions
- Print preview modal
- Permission handling (iOS + Android 12+)
```

## Customization Examples

### Custom Page Size

```dart
// For 40mm × 30mm label at 203 DPI
final page = PrintPage(315, 236); // (40mm * 203/25.4, 30mm * 203/25.4)
```

### Landscape Printing

```dart
// Auto-swaps dimensions and rotates content 90°
final page = PrintPage(240, 400, PageOrientation.landscape);
// Canvas becomes 400×240 with automatic rotation
```

### Text with Rotation

```dart
await page.addText(
  'Rotated',
  TextOptions(
    x: 200,
    y: 100,
    fontSize: 20,
    rotate: 45, // Degrees
    align: HAlignment.center,
  ),
);
```

### Multiple Pages

```dart
for (int i = 1; i <= 3; i++) {
  final page = PrintPage(400, 240);
  await page.addText('Page $i', ...);
  await task.printPage(page.toEncodedImage(), i);
}
```

## Troubleshooting

### Bluetooth Not Available
- Enable Bluetooth in device settings
- Grant all required permissions (Settings → App → Permissions)
- Restart the app after granting permissions

### Printer Not Found
- Power on the printer
- Printer should be in pairing mode (blue LED blinking)
- Try scanning multiple times
- Move closer to the printer

### Connection Issues
- If "Bluetooth state: unknown" appears, wait a moment and try again (iOS issue)
- Use auto-connect: `await client.connect()` without setDevice
- Check printer isn't connected to another device

### Print Quality Issues
- Adjust density: 1 (lightest) to 5 (darkest)
- Default is 3
- For dark labels: use density 4-5
- For light labels: use density 2-3

### Image Not Printing
- Ensure width is multiple of 8 pixels
- Adjust threshold (0-255, default 128)
- Lower threshold = darker image
- Higher threshold = lighter image

### iOS-Specific Issues
- First connection may fail with "unknown" state
- Solution: App handles this automatically with retry logic
- If issue persists: Restart Bluetooth in Settings

### Android 12+ Permissions
- App automatically requests new Bluetooth permissions
- Grant "BLUETOOTH_SCAN" and "BLUETOOTH_CONNECT"
- Location permission still needed for scanning

## Learn More

- [niim_blue_flutter Documentation](https://pub.dev/packages/niim_blue_flutter)
- [API Reference](https://pub.dev/documentation/niim_blue_flutter/latest/)
- [Main README](../README.md)

## License

MIT License - see [LICENSE](../LICENSE) file
