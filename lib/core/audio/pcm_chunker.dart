import 'dart:typed_data';

final class PcmChunker {
  PcmChunker({required this.chunkSizeInBytes})
    : assert(chunkSizeInBytes > 0, 'Chunk size must be positive.');

  final int chunkSizeInBytes;
  Uint8List _remainder = Uint8List(0);

  int get remainderLength => _remainder.length;

  List<Uint8List> add(Uint8List bytes) {
    if (bytes.isEmpty) {
      return const [];
    }

    final combined = Uint8List(_remainder.length + bytes.length)
      ..setAll(0, _remainder)
      ..setAll(_remainder.length, bytes);
    final chunks = <Uint8List>[];
    var offset = 0;
    while (combined.length - offset >= chunkSizeInBytes) {
      chunks.add(
        Uint8List.fromList(
          Uint8List.sublistView(
            combined,
            offset,
            offset + chunkSizeInBytes,
          ),
        ),
      );
      offset += chunkSizeInBytes;
    }
    _remainder = Uint8List.fromList(
      Uint8List.sublistView(combined, offset),
    );
    return chunks;
  }

  void reset() {
    _remainder = Uint8List(0);
  }
}
