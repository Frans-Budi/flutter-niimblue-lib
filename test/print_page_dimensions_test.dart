import 'package:flutter_test/flutter_test.dart';
import 'package:niim_blue_flutter/niim_blue_flutter.dart';

void main() {
  test('encoded page keeps the requested printable dimensions', () {
    final page = PrintPage(576, 346);

    page.addQR(
      'Hello Niimbot',
      const QROptions(
        x: 144,
        y: 173,
        width: 150,
        height: 150,
        align: HAlignment.center,
        vAlign: VAlignment.middle,
      ),
    );

    final encoded = page.toEncodedImage();

    expect(encoded.cols, 576);
    expect(encoded.rows, 346);
  });

  test('landscape output dimensions are explicit', () {
    final page = PrintPage(576, 323);

    final encoded = page.toEncodedImage();

    expect(encoded.cols, 576);
    expect(encoded.rows, 323);
  });

  test('splits empty rows when content starts after row 255', () {
    final page = PrintPage(576, 354);
    page.addLine(
      const LineOptions(x: 0, y: 290, endX: 576, endY: 290, thickness: 1),
    );

    final packets = PacketGenerator.writeImageData(
      page.toEncodedImage(),
      options: const ImagePacketsGenerateOptions(printheadPixels: 576),
    );
    final emptyPackets = packets
        .where((packet) => packet.command == RequestCommandId.printEmptyRow)
        .toList();
    final bitmapPacket = packets.singleWhere(
      (packet) => packet.command == RequestCommandId.printBitmapRow,
    );

    expect(emptyPackets, hasLength(3));
    expect(emptyPackets[0].data[2], 255);
    expect(emptyPackets[1].data[2], 35);
    expect(Utils.bytesToU16(bitmapPacket.data), 290);
  });
}
