import 'dart:math' as math;
import 'dart:typed_data';

import 'package:wiro_realtime/core/audio/pcm_level_meter.dart';

/// Keeps steady background sound — a television, traffic, a fan — out of
/// the microphone stream while letting near-field speech through.
///
/// The gate continuously learns the ambient loudness of the room and only
/// opens when a chunk rises clearly above that learned floor. The user
/// speaks centimeters from the microphone while the television plays
/// meters away, so genuine speech lands well above the ambient level even
/// in a noisy room.
///
/// Closed chunks are strongly attenuated instead of being dropped or
/// zeroed, so the outgoing stream keeps real-time pacing and carries real
/// room tone: the server's voice detection hears a quiet room rather than
/// a dead wire, while the attenuated background stays far below anything
/// that could pass for speech.
final class PcmNoiseGate {
  PcmNoiseGate({
    this.minOpenLevel = 0.28,
    this.assistantOpenLevel = 0.45,
    this.floorMultiplier = 1.6,
    this.floorCap = 0.5,
    this.hangover = const Duration(milliseconds: 600),
    this.hangoverFraction = 0.5,
    this.flatnessLimit = 0.15,
    this.closedGain = 0.05,
  });

  /// The gate never opens below this level, which separates near-field
  /// speech from a room at conversational television volume.
  final double minOpenLevel;

  /// Opening bar while assistant audio is audible, matching the barge-in
  /// threshold: speaker bleed that echo cancellation misses must not
  /// reach the server, where its voice detection would transcribe the
  /// assistant's own words as the user's.
  final double assistantOpenLevel;

  /// How far above the learned ambient floor a chunk must rise to count
  /// as the user rather than the room.
  final double floorMultiplier;

  /// Ceiling for the learned floor, so an extremely loud room can never
  /// push the opening threshold beyond what a raised voice reaches.
  final double floorCap;

  /// How long the gate stays open after the last loud chunk, so the dip
  /// between two words does not chop the sentence apart.
  final Duration hangover;

  /// Share of the opening threshold a chunk must still reach to ride the
  /// hangover through.
  ///
  /// The hangover lowers the bar; it must not remove it. With no bar at
  /// all a single knock hands the room the next half second, and steady
  /// noise walks through the door speech opened.
  final double hangoverFraction;

  /// Gain applied to closed chunks. Pure digital zeros can read as a dead
  /// stream and get the task reaped server-side after long quiet spells;
  /// a whisper of genuine room tone keeps the uplink alive while staying
  /// far below any voice-detection threshold.
  final double closedGain;

  /// How little the signal has to move, relative to its own loudness, to
  /// be called a machine rather than a voice.
  ///
  /// This is the one measurement that answers "is this a hum?" directly
  /// instead of guessing from volume. Speech is modulated by syllables at
  /// four to eight a second, so its loudness swings enormously across a
  /// window of a second. A fan, a fridge, an air conditioner or a road
  /// outside holds one level and barely moves. Comparing the spread to
  /// the mean rather than to a fixed number keeps the test honest at any
  /// volume: a loud hum is just as flat as a quiet one.
  final double flatnessLimit;

  /// Chunks of loudness history the flatness test reads, which at fifty
  /// chunks a second is one second — long enough to contain several
  /// syllables, short enough to react before a hum is transcribed.
  static const int _historyLength = 50;

  /// Loud sound that persists for tens of seconds is a room, not a
  /// sentence: this creep rate absorbs a loud television in well under a
  /// minute while a long utterance barely moves the floor.
  static const double _loudCaptureAlpha = 0.001;

  /// Creep rate for sound the flatness test has identified as a machine,
  /// fast enough to close on a hum a second or so after recognising it.
  ///
  /// The slow rate above cannot learn a hum at all, however long it runs:
  /// a hum loud enough to open the gate keeps the floor on the creeping
  /// path, while every quiet moment pulls the floor back down thirty
  /// times faster than the creep raised it.
  static const double _steadyCaptureAlpha = 0.02;

  static final DateTime _epoch = DateTime.fromMillisecondsSinceEpoch(0);

  final Float64List _history = Float64List(_historyLength);
  int _historyCount = 0;
  int _historyCursor = 0;

  double _floor = 0;
  double _lastOutputLevel = 0;
  DateTime _openUntil = _epoch;

  /// Ambient loudness the gate currently attributes to the room.
  double get ambientFloor => _floor;

  /// True while the recent signal has been too flat to be a voice.
  ///
  /// Undecided until a full window has been heard: one chunk of anything
  /// looks flat, and calling a hum on that would shut the gate on the
  /// first syllable of every sentence.
  bool get hearsHum {
    if (_historyCount < _historyLength) {
      return false;
    }
    var sum = 0.0;
    for (final level in _history) {
      sum += level;
    }
    final mean = sum / _historyLength;
    if (mean <= 0) {
      return false;
    }
    var squares = 0.0;
    for (final level in _history) {
      final deviation = level - mean;
      squares += deviation * deviation;
    }
    return math.sqrt(squares / _historyLength) / mean < flatnessLimit;
  }

  /// Loudness of the most recent [process] output, on the same scale as
  /// [pcmNormalizedLevel].
  ///
  /// The gate already measured the incoming chunk, so consumers of the
  /// outgoing one read this instead of running the RMS loop a second
  /// time. Attenuation scales RMS linearly, which is why the closed
  /// value is derived rather than remeasured.
  double get lastOutputLevel => _lastOutputLevel;

  bool get isOpen => DateTime.now().isBefore(_openUntil);

  /// Returns the chunk untouched while the gate is open, or the same
  /// chunk attenuated to a whisper while it is closed.
  ///
  /// [assistantAudible] raises the opening bar to [assistantOpenLevel]
  /// while the assistant is playing through the speaker, so echo leaking
  /// past cancellation cannot open the gate.
  Uint8List process(Uint8List chunk, {bool assistantAudible = false}) {
    final level = pcmNormalizedLevel(chunk);
    _history[_historyCursor] = level;
    _historyCursor = (_historyCursor + 1) % _historyLength;
    if (_historyCount < _historyLength) {
      _historyCount++;
    }
    final now = DateTime.now();
    final baseOpenLevel = assistantAudible
        ? math.max(minOpenLevel, assistantOpenLevel)
        : minOpenLevel;
    final openThreshold = math.max(baseOpenLevel, _floor * floorMultiplier);
    if (level >= openThreshold) {
      _openUntil = now.add(hangover);
      _raiseFloor(
        level,
        hearsHum ? _steadyCaptureAlpha : _loudCaptureAlpha,
      );
      _lastOutputLevel = level;
      return chunk;
    }
    // Quiet chunks teach the floor; rising slowly and falling quickly
    // means a brief racket cannot lock the gate shut for long after the
    // room calms down.
    _raiseFloor(level, level > _floor ? 0.04 : 0.12);
    if (now.isBefore(_openUntil) &&
        level >= openThreshold * hangoverFraction) {
      _lastOutputLevel = level;
      return chunk;
    }
    _lastOutputLevel = level * closedGain;
    return _attenuated(chunk);
  }

  /// Forgets the learned room so a new session starts fresh.
  void reset() {
    _floor = 0;
    _lastOutputLevel = 0;
    _history.fillRange(0, _historyLength, 0);
    _historyCount = 0;
    _historyCursor = 0;
    _openUntil = _epoch;
  }

  void _raiseFloor(double level, double alpha) {
    _floor = math.min(floorCap, _floor + (level - _floor) * alpha);
  }

  Uint8List _attenuated(Uint8List chunk) {
    final copy = Uint8List.fromList(chunk);
    final data = ByteData.sublistView(copy);
    for (var offset = 0; offset + 1 < copy.length; offset += 2) {
      final sample = data.getInt16(offset, Endian.little);
      data.setInt16(offset, (sample * closedGain).round(), Endian.little);
    }
    return copy;
  }
}
