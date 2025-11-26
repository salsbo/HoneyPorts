# HoneyPorts

A lightweight macOS menu bar honeypot application that monitors network connection attempts on configurable ports.

**The full source code is available in this repository for security audit and review.**

## Download

[Download HoneyPorts-1.0.dmg](https://github.com/salsbo/HoneyPorts/releases/download/v1.0/HoneyPorts-1.0.dmg) (Signed & Notarized by Apple)

## Features

- **Menu bar application** - Runs discreetly in your menu bar
- **TCP/UDP monitoring** - Listen on custom ports for connection attempts
- **ICMP detection** - Monitor ping requests
- **Real-time notifications** - Get alerts when connection attempts are detected
- **Connection logging** - JSON logs of all detected attempts with IP, port, timestamp
- **IP Whitelist** - Exclude trusted IPs from detection
- **Bilingual** - French and English interface

## Requirements

- macOS 13.0 or later
- Apple Silicon or Intel Mac

## Installation

1. Download `HoneyPorts-1.0.dmg` from [Releases](../../releases)
2. Open the DMG and drag HoneyPorts to Applications
3. Launch HoneyPorts from Applications

The app is signed and notarized by Apple for safe distribution.

## Usage

1. Click the HoneyPorts icon in the menu bar
2. Configure the ports you want to monitor
3. Click "Start" to begin monitoring
4. View connection attempts in the logs

## Building from Source

```bash
# Clone the repository
git clone https://github.com/YOUR_USERNAME/HoneyPorts.git
cd HoneyPorts

# Open in Xcode
open HoneyPorts.xcodeproj

# Build and run
```

## Privacy

HoneyPorts runs entirely locally. No data is sent to external servers.

## License

MIT License - see LICENSE file for details.

## Author

Oscar Robert-Besle
