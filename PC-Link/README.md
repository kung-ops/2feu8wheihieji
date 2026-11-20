# APK Sandbox PC Link (iOS 12+)

Keeps the original APK **+ picker** and existing interpreter unchanged.

Windows:
1. Install Node.js LTS.
2. Double-click PC-Link/START.bat.
3. Allow port 8765 on Windows Firewall for **Private** network only.
4. Put your PC and iPhone on the same trusted Wi-Fi network.
5. On iPhone, tap **PC Link** and enter the server's http://LAN-IP:8765 and pairing token.
6. Test Connection. To play audio on iPhone, place pc-audio.mp3 / pc-audio.m4a / pc-audio.wav beside server.js, then tap Play.
7. To send a photo, tap Take photo & send. To send microphone audio, tap Start recording, then Stop & send. Files appear in PC-Link/uploads.

Security: PC Link uses unencrypted HTTP on your local network. Never port-forward or use a public Wi-Fi network. Media capture starts only on the iPhone with its permission prompt. Delete pairing-token.txt while server is stopped to rotate the token.

Scope: This plays an audio FILE from Windows, not Windows system audio. Camera and microphone are iOS-native opt-in tools on the PC Link screen, NOT automatic implementations of Android APK camera/microphone APIs. It does not make unsupported APKs execute.
