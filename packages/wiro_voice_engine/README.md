# wiro_voice_engine

Wiro'nun konuşma (speech-to-speech) özelliği için native ses köprüsü.

Mikrofon kaydı ve PCM oynatma tek native ses grafiğinde çalışır; işletim
sisteminin yankı engelleyicisi (AEC) hoparlör çıkışını mikrofon girişiyle
ancak bu şekilde ilişkilendirebilir. Ayrık kayıt/oynatma paketleri bu
senaryoyu karşılayamadığı için köprü projenin içinde yaşar.

- iOS: `AVAudioEngine` + `AVAudioPlayerNode`, `setVoiceProcessingEnabled`
  ile AEC, `AVAudioConverter` ile 24 kHz Int16 tel formatı dönüşümü.
- Android: `AudioRecord` + `AudioTrack`, `AcousticEchoCanceler` ve
  `NoiseSuppressor`.

Uygulama bu paketi doğrudan değil, `lib/core/audio/voice_engine_pcm_audio.dart`
içindeki `VoiceEnginePcmAudioPair` sarmalayıcısı üzerinden kullanır.
