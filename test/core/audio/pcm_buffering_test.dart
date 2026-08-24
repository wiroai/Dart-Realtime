import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wiro_realtime/core/audio/bounded_pcm_queue.dart';
import 'package:wiro_realtime/core/audio/pcm_chunker.dart';

void main() {
  test('PCM chunker emits fixed chunks and keeps a bounded remainder', () {
    final chunker = PcmChunker(chunkSizeInBytes: 4);

    final first = chunker.add(Uint8List.fromList([1, 2, 3]));
    final second = chunker.add(Uint8List.fromList([4, 5, 6, 7, 8, 9]));

    expect(first, isEmpty);
    expect(second, [
      [1, 2, 3, 4],
      [5, 6, 7, 8],
    ]);
    expect(chunker.remainderLength, 1);
  });

  test('bounded queue preserves FIFO order', () async {
    final queue = BoundedPcmQueue(capacityInChunks: 2);
    await queue.add(Uint8List.fromList([1]));
    await queue.add(Uint8List.fromList([2]));

    expect(await queue.take(), [1]);
    expect(await queue.take(), [2]);
  });

  test('bounded queue applies producer backpressure', () async {
    final queue = BoundedPcmQueue(capacityInChunks: 1);
    await queue.add(Uint8List.fromList([1]));
    var secondAdded = false;
    final secondAdd = queue.add(Uint8List.fromList([2])).then((_) {
      secondAdded = true;
    });

    await pumpEventQueue();
    expect(secondAdded, isFalse);

    expect(await queue.take(), [1]);
    await secondAdd;
    expect(secondAdded, isTrue);
    expect(await queue.take(), [2]);
  });

  test('bounded queue sheds non-blocking overflow and tracks metrics', () {
    final queue = BoundedPcmQueue(capacityInChunks: 1);

    expect(queue.tryAdd(Uint8List.fromList([1])), isTrue);
    expect(queue.tryAdd(Uint8List.fromList([2])), isFalse);

    expect(queue.highWaterMarkInChunks, 1);
    expect(queue.rejectedChunks, 1);
    expect(queue.length, 1);
  });

  test('closing a queue releases pending consumers', () async {
    final queue = BoundedPcmQueue(capacityInChunks: 1);
    final pendingTake = queue.take();

    queue.close();

    expect(await pendingTake, isNull);
    expect(queue.isClosed, isTrue);
  });
}
