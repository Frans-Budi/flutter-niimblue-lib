import 'abstract_print_task.dart';
import '../packets/packet_generator.dart';
import '../print_page.dart';

/// Print task for D110 MV4, B21 Pro, and B1 Pro printer models.
class D110MV4PrintTask extends AbstractPrintTask {
  D110MV4PrintTask(super.abstraction, [super.options]);

  @override
  Future<void> printInit() {
    return abstraction.sendAll([
      PacketGenerator.setDensity(
        printOptions.density ?? PrintOptionsDefaults.density,
      ),
      PacketGenerator.setLabelType(
        (printOptions.labelType ?? PrintOptionsDefaults.labelType).value,
      ),
      PacketGenerator.printStart9b(
        printOptions.totalPages ?? PrintOptionsDefaults.totalPages,
        pageColor: 0,
        quality: 1,
      ),
    ]);
  }

  @override
  Future<void> printPage(EncodedImage image, [int quantity = 1]) async {
    checkAddPage(quantity);

    // These models may not respond on the first packet after PrintStart over BLE.
    // Originally PrintStatus is sent, no response waited.
    final statusPacket = PacketGenerator.printStatus();
    statusPacket.oneWay = true;
    await abstraction.send(statusPacket);

    return abstraction.sendAll(
      [
        PacketGenerator.setPageSize13b(image.rows, image.cols, quantity),
        ...PacketGenerator.writeImageData(
          image,
          options: ImagePacketsGenerateOptions(
            printheadPixels: printheadPixels(),
          ),
        ),
        PacketGenerator.pageEnd(),
      ],
      printOptions.pageTimeoutMs,
    );
  }

  @override
  Future<void> waitForFinished() {
    abstraction.setPacketTimeout(
      printOptions.statusTimeoutMs ?? PrintOptionsDefaults.statusTimeoutMs,
    );

    return abstraction
        .waitUntilPrintFinishedByStatusPoll(
          printOptions.totalPages ?? 1,
          printOptions.statusPollIntervalMs ??
              PrintOptionsDefaults.statusPollIntervalMs,
        )
        .whenComplete(() => abstraction.setDefaultPacketTimeout());
  }

  @override
  Future<bool> printEnd() async {
    // These models may drop the first packet after PrintEnd.
    // Originally `Heartbeat` is sent, no response waited.
    final pkt = PacketGenerator.heartbeat(1);
    pkt.oneWay = true;
    await abstraction.send(pkt);

    return abstraction.printEnd();
  }
}
