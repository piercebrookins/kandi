# Festival Assistant 🎵🕶️

Real-time festival/concert companion for smart glasses (MentraOS) with iPhone companion app.

This app provides three key features for festival-goers:
1. **Hearing Protection** - Live decibel monitoring with risk alerts
2. **Friend Finder** - BLE-based proximity detection with directional hints
3. **Song Recognition** - Identify songs playing around you using AudD/Shazam APIs

---

## Features

### 🎧 Hearing Risk Overlay
- Real-time dB monitoring from iPhone mic
- Risk classification: `safe` | `caution` | `risk`
- Safe exposure time remaining
- Smart suggestions ("Safer side: left", "Step back")

### 👥 Friend Proximity
- BLE-based friend discovery (no internet required)
- Distance bands: `IMMEDIATE` | `NEAR` | `AREA` | `WEAK`
- Directional hints: `left` | `right` | `ahead` | `behind`
- Shows 3 nearest friends

### 🎵 Song Recognition
- Multiple API support: **AudD** (primary) → **Gemini** → **Shazam**
- Auto-saves audio for debugging
- Displays song title and artist on glasses

---

## Tech Stack

- **Runtime**: Bun + TypeScript
- **SDK**: `@mentra/sdk` for smart glasses integration
- **APIs**: 
  - AudD (song recognition - primary)
  - Google Gemini (song identification fallback)
  - Shazam via RapidAPI (song recognition fallback)

---

## Quick Start

### 1) Install dependencies

```bash
bun install
```

### 2) Configure environment

```bash
cp .env.example .env
```

Required variables:
```bash
# MentraOS app identity
PACKAGE_NAME=com.wicshackathon.rightsnow
MENTRAOS_API_KEY=your_mentra_api_key

# Song recognition APIs (at least one required)
AUDD_API_KEY=your_audd_key           # Recommended - most reliable
GEMINI_API_KEY=your_gemini_key       # Fallback
SHAZAM_API_KEY=your_shazam_key       # Last resort (RapidAPI)
SHAZAM_API_HOST=shazam.p.rapidapi.com

# Server config
PORT=3000
NGROK_URL=https://your-ngrok-url.ngrok-free.app
```

### 3) Run the app

```bash
# Development mode
bun run dev

# Production mode
bun src/index.ts
```

### 4) Expose with ngrok (required for iPhone companion)

```bash
ngrok http 3000
```

Copy your HTTPS forwarding URL to `.env`:
```bash
NGROK_URL=https://your-ngrok-url.ngrok-free.app
```

---

## API Endpoints

### Health Check
```bash
GET /health
```

### Session Management
```bash
GET /api/session/list          # List active glasses sessions
```

### Overlay Updates
```bash
POST /api/overlay/hearing      # Send decibel/risk data
POST /api/overlay/friends      # Send friend proximity data
POST /api/song/identify        # Identify song from audio
```

### Debug
```bash
POST /api/debug/save-audio     # Save audio for inspection
```

---

## iPhone Companion App

The iPhone app captures sensor data and sends it to the glasses via this backend.

### Required iOS Setup

1. **Audio Session Configuration** (critical for song recognition):
```swift
import AVFoundation

let audioSession = AVAudioSession.sharedInstance()
try audioSession.setCategory(.playAndRecord, 
                              mode: .videoRecording,  // Best for music capture
                              options: [.defaultToSpeaker])
try audioSession.setActive(true)

// Force built-in mic (not AirPods - they have noise cancellation)
if let inputs = audioSession.availableInputs {
    for input in inputs where input.portType == .builtInMic {
        try audioSession.setPreferredInput(input)
        break
    }
}
```

2. **Recording Settings** (for song recognition):
```swift
let settings: [String: Any] = [
    AVFormatIDKey: Int(kAudioFormatLinearPCM),
    AVSampleRateKey: 48000,      // 48kHz for AudD compatibility
    AVNumberOfChannelsKey: 1,     // Mono
    AVLinearPCMBitDepthKey: 16,
    AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
]
```

### API Integration

#### Fetch Active Sessions
```swift
let url = URL(string: "\(ngrokURL)/api/session/list")!
let (data, _) = try await URLSession.shared.data(from: url)
let response = try JSONDecoder().decode(SessionListResponse.self, from: data)
```

#### Send Hearing Data
```swift
let payload = HearingOverlayRequest(
    sessionId: sessionId,
    db: 104.5,
    riskLevel: "risk",
    safeTimeLeftMin: 6,
    trend: "rising",
    suggestion: "Safer side: left"
)
```

#### Send Song Audio
```swift
// Send as text/plain with base64 audio
let url = URL(string: "\(ngrokURL)/api/song/identify")!
var request = URLRequest(url: url)
request.httpMethod = "POST"
request.setValue("text/plain", forHTTPHeaderField: "Content-Type")
request.setValue(sessionId, forHTTPHeaderField: "x-session-id")
request.httpBody = audioBase64.data(using: .utf8)
```

### Posting Cadence
- **Hearing**: Every 1-2 seconds
- **Friends**: Every 1-2 seconds (or on state change)
- **Song**: Every 10 seconds (audio bite)

---

## Song Recognition Details

### Provider Priority
1. **AudD** (primary) - Most reliable, requires API key from [audd.io](https://audd.io)
2. **Gemini** (fallback) - Uses Google's multimodal AI
3. **Shazam** (last resort) - Via RapidAPI, often returns no matches

### Debugging Song Recognition

Audio files are auto-saved to `debug-audio/` folder for inspection:
```bash
ls debug-audio/
# Play back to verify quality:
afplay debug-audio/debug-audio-*.wav
```

**Common Issues**:
- **Volume too low**: iOS mic gain or AirPods noise cancellation
- **No matches**: Song not in database or poor audio quality
- **API failures**: Check API keys and rate limits

---

## Project Structure

```text
src/
  index.ts                    # Main server & Mentra session handling
  config/
    index.ts                  # Environment config
  services/
    songRecognitionService.ts # AudD/Gemini/Shazam integration
    festivalDisplayService.ts # Glasses overlay rendering
    ...
  types/
    index.ts                  # TypeScript types
    festival.ts               # Festival-specific types
debug-audio/                  # Auto-saved audio for debugging
test-shazam.js               # Standalone Shazam API test
```

---

## Environment Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `PACKAGE_NAME` | ✅ | MentraOS app package name |
| `MENTRAOS_API_KEY` | ✅ | From console.mentra.glass |
| `AUDD_API_KEY` | ⚠️ | Primary song recognition |
| `GEMINI_API_KEY` | ⚠️ | Fallback song ID |
| `SHAZAM_API_KEY` | ❌ | Last resort (often fails) |
| `NGROK_URL` | ✅ | Public HTTPS URL for iPhone |
| `PORT` | ❌ | Server port (default: 3000) |
| `LOG_LEVEL` | ❌ | `info` or `debug` |

---

## Testing

### Test Song Recognition
```bash
# Requires .env with API keys
node test-shazam.js
```

### Manual API Tests
```bash
# Health check
curl https://your-ngrok-url.ngrok-free.app/health

# Send hearing data
curl -X POST "https://your-ngrok-url.ngrok-free.app/api/overlay/hearing" \
  -H "Content-Type: application/json" \
  -d '{
    "sessionId": "your-session-id",
    "db": 104,
    "riskLevel": "risk",
    "safeTimeLeftMin": 6
  }'
```

---

## Troubleshooting

### Song Recognition Not Working
1. Check audio volume: `ffmpeg -i debug-audio/*.wav -af volumedetect -f null /dev/null 2>&1 | grep mean_volume`
2. Should be > -30 dB for reliable detection
3. If using AirPods, switch to phone mic (AirPods have noise cancellation)

### No Active Sessions
- Ensure glasses app is running and connected
- Check `GET /api/session/list` returns sessions
- Verify `PACKAGE_NAME` matches Mentra console

### iPhone Can't Connect
- Verify ngrok URL is correct in `.env`
- Ensure ngrok is running
- Check firewall/network settings

---

## Demo Script

1. **Start glasses session** → Shows "Festival Assist Ready"
2. **Enable iPhone companion** → Start mic + BLE scanning
3. **Show hearing overlay** → Live dB + risk level + safe time
4. **Show friend proximity** → BLE detects friends, shows distance + direction
5. **Song recognition** → Play music, app identifies and displays song
6. **Privacy mode** → Toggle invisible mode

---

## Documentation

- [Swift Companion API Handoff](./SWIFT_COMPANION_API_HANDOFF.md) - iOS integration guide
- [Festival Assistant Build Plan](./FESTIVAL_ASSISTANT_BUILD_PLAN.md) - Full product specification
- [Swift MVP Tasklist](./SWIFT_MVP_TASKLIST.md) - iOS development checklist

---

## License

MIT

---

## Credits

Built for MentraOS hackathon. Uses:
- [AudD](https://audd.io) for song recognition
- [Google Gemini](https://ai.google.dev) for AI fallback
- [Shazam via RapidAPI](https://rapidapi.com/apidojo/api/shazam) for additional recognition
