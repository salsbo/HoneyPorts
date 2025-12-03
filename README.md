# HoneyPorts

A lightweight macOS menu bar honeypot application that monitors network connection attempts on configurable ports.

*Une application honeypot légère pour macOS qui surveille les tentatives de connexion réseau sur des ports configurables.*

**The full source code is available in this repository for security audit and review.**

*Le code source complet est disponible dans ce dépôt pour audit et revue de sécurité.*

## Download / Téléchargement

[Download HoneyPorts-1.2.dmg](https://github.com/salsbo/HoneyPorts/releases/download/v1.2/HoneyPorts-1.2.dmg) (Signed & Notarized by Apple)

**v1.2** - Security update with vulnerability fixes / *Mise à jour de sécurité avec corrections de vulnérabilités*

## Security / Sécurité

- **No root password required** - HoneyPorts runs entirely in user space, no administrator privileges needed
- **No system modifications** - The app doesn't modify any system files or settings
- **Sandboxed architecture** - Uses XPC services for network operations, isolated from the main app
- **100% local** - No data is ever sent to external servers, everything stays on your Mac
- **Open source** - Full source code available for audit

---

- **Aucun mot de passe root requis** - HoneyPorts fonctionne entièrement en espace utilisateur, aucun privilège administrateur nécessaire
- **Aucune modification système** - L'application ne modifie aucun fichier ou paramètre système
- **Architecture sandboxée** - Utilise des services XPC pour les opérations réseau, isolés de l'application principale
- **100% local** - Aucune donnée n'est envoyée à des serveurs externes, tout reste sur votre Mac
- **Open source** - Code source complet disponible pour audit

## Features / Fonctionnalités

- **Menu bar application** - Runs discreetly in your menu bar / *Fonctionne discrètement dans la barre de menus*
- **TCP/UDP monitoring** - Listen on custom ports / *Écoute sur des ports personnalisés*
- **ICMP detection** - Monitor ping requests / *Détection des requêtes ping*
- **Real-time notifications** - Alerts on connection attempts / *Alertes en temps réel*
- **Connection logging** - JSON logs with IP, port, timestamp / *Logs JSON avec IP, port, horodatage*
- **IP Whitelist** - Exclude trusted IPs / *Exclusion des IPs de confiance*
- **Bilingual interface** - French and English / *Interface en français et anglais*

## Requirements / Configuration requise

- macOS 13.0 or later / *macOS 13.0 ou ultérieur*
- Apple Silicon or Intel Mac

## Installation

1. Download `HoneyPorts-1.2.dmg` from [Releases](../../releases)
2. Open the DMG and drag HoneyPorts to Applications
3. Launch HoneyPorts from Applications

The app is signed and notarized by Apple for safe distribution.

---

1. Téléchargez `HoneyPorts-1.2.dmg` depuis [Releases](../../releases)
2. Ouvrez le DMG et glissez HoneyPorts dans Applications
3. Lancez HoneyPorts depuis Applications

L'application est signée et notarisée par Apple pour une distribution sécurisée.

## Usage / Utilisation

1. Click the HoneyPorts icon in the menu bar / *Cliquez sur l'icône HoneyPorts dans la barre de menus*
2. Configure the ports you want to monitor / *Configurez les ports à surveiller*
3. Click "Start" to begin monitoring / *Cliquez sur "Démarrer" pour commencer la surveillance*
4. View connection attempts in the logs / *Consultez les tentatives de connexion dans les logs*

## Building from Source / Compilation depuis les sources

```bash
git clone https://github.com/salsbo/HoneyPorts.git
cd HoneyPorts
open HoneyPorts.xcodeproj
# Build and run in Xcode
```

## License / Licence

MIT License - see LICENSE file for details.

## Authors / Auteurs

Oscar Robert-Besle & Julien ROBERT
