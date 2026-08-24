import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

final class BoundedPcmQueue {
  BoundedPcmQueue({required this.capacityInChunks})
    : assert(capacityInChunks > 0, 'Queue capacity must be positive.');

  final int capacityInChunks;
  final Queue<Uint8List> _chunks = Queue<Uint8List>();

  Completer<void>? _dataAvailable;
  Completer<void>? _spaceAvailable;
  bool _closed = false;
  int _queuedBytes = 0;
  int _highWaterMarkInChunks = 0;
  int _rejectedChunks = 0;

  int get length => _chunks.length;

  int get queuedBytes => _queuedBytes;

  int get highWaterMarkInChunks => _highWaterMarkInChunks;

  int get rejectedChunks => _rejectedChunks;

  bool get isClosed => _closed;

  bool tryAdd(Uint8List chunk) {
    if (chunk.isEmpty) {
      return true;
    }
    if (_closed || _chunks.length >= capacityInChunks) {
      _rejectedChunks++;
      return false;
    }
    _addOwnedChunk(chunk);
    return true;
  }

  Future<void> add(Uint8List chunk) async {
    if (chunk.isEmpty) {
      return;
    }
    while (_chunks.length >= capacityInChunks && !_closed) {
      final waiter = _spaceAvailable ??= Completer<void>();
      await waiter.future;
    }
    if (_closed) {
      return;
    }

    _addOwnedChunk(chunk);
  }

  void _addOwnedChunk(Uint8List chunk) {
    final ownedChunk = Uint8List.fromList(chunk);
    _chunks.addLast(ownedChunk);
    _queuedBytes += ownedChunk.length;
    if (_chunks.length > _highWaterMarkInChunks) {
      _highWaterMarkInChunks = _chunks.length;
    }
    _signalDataAvailable();
  }

  Future<Uint8List?> take() async {
    while (_chunks.isEmpty && !_closed) {
      final waiter = _dataAvailable ??= Completer<void>();
      await waiter.future;
    }
    if (_chunks.isEmpty) {
      return null;
    }

    final chunk = _chunks.removeFirst();
    _queuedBytes -= chunk.length;
    _signalSpaceAvailable();
    return chunk;
  }

  Stream<Uint8List> drain() async* {
    while (true) {
      final chunk = await take();
      if (chunk == null) {
        return;
      }
      yield chunk;
    }
  }

  void clear() {
    _chunks.clear();
    _queuedBytes = 0;
    _signalSpaceAvailable();
  }

  void close() {
    if (_closed) {
      return;
    }
    _closed = true;
    _signalDataAvailable();
    _signalSpaceAvailable();
  }

  void _signalDataAvailable() {
    final waiter = _dataAvailable;
    _dataAvailable = null;
    if (waiter != null && !waiter.isCompleted) {
      waiter.complete();
    }
  }

  void _signalSpaceAvailable() {
    final waiter = _spaceAvailable;
    _spaceAvailable = null;
    if (waiter != null && !waiter.isCompleted) {
      waiter.complete();
    }
  }
}
