import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:niim_blue_flutter/niim_blue_flutter.dart';
import 'package:niim_blue_flutter/src/print_tasks/print_task_factory.dart';

class _ImmediateResponseClient extends NiimbotAbstractClient {
  @override
  Future<ConnectionInfo> connect() => throw UnimplementedError();

  @override
  Future<void> disconnect() async {}

  @override
  bool isConnected() => true;

  @override
  Future<void> sendRaw(Uint8List data, {bool force = false}) async {
    // A fast response must not be lost between writing and subscribing.
    processRawPacket(Uint8List.fromList([
      0x55,
      0x55,
      0xc2,
      0x01,
      0x02,
      0xc1,
      0xaa,
      0xaa,
    ]));
  }
}

class _B1ProStatusClient extends NiimbotAbstractClient {
  int statusRequests = 0;

  _B1ProStatusClient() {
    info.modelId = 4097;
  }

  @override
  Future<ConnectionInfo> connect() => throw UnimplementedError();

  @override
  Future<void> disconnect() async {}

  @override
  bool isConnected() => true;

  @override
  Future<void> sendRaw(Uint8List data, {bool force = false}) async {
    if (data[2] != RequestCommandId.printStatus.value) return;

    statusRequests++;
    final response = NiimbotPacket(
      command: ResponseCommandId.inPrintStatus,
      data: Uint8List.fromList([0x00, 0x01, 0x64, 0x00]),
    );
    processRawPacket(response.toBytes());
  }
}

void main() {
  test('recognizes the B1 Pro model metadata', () {
    final metadata = getPrinterMetaById(4097);

    expect(metadata, isNotNull);
    expect(metadata!.model, PrinterModel.b1Pro);
    expect(metadata.dpi, 300);
    expect(metadata.printheadPixels, 576);
    expect(findPrintTask(PrinterModel.b1Pro, 5), PrintTaskName.d110mV4);
  });

  test('does not lose an immediate connect response', () async {
    final client = _ImmediateResponseClient();

    final response = await client.sendPacketWaitResponse(
      PacketGenerator.connect(),
    );

    expect(response.command, ResponseCommandId.inConnect);
    expect(response.data, [0x02]);
  });

  test('accepts B1 Pro status completion reported as 100/0', () async {
    final client = _B1ProStatusClient();

    await client.abstraction.waitUntilPrintFinishedByStatusPoll(1, 1);

    expect(client.statusRequests, 1);
  });
}
