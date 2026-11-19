APK Sandbox PC Bridge - Windows / iOS 12+
==========================================
1. Install Node.js 18+ on your Windows computer.
2. Double-click START-PC-BRIDGE.bat and keep the window open.
3. Read the local PC URL and pairing key printed in that window.
4. Put iPhone and PC on the same trusted Wi-Fi.
5. Open APK Sandbox > PC Bridge, enter the address + key, tap Connect.
6. Take Photo or Record Microphone on iPhone, and choose Send to PC.
   Files are saved in PCBridge/received. iOS requests sensor permission.
7. Copy an MP3, M4A or WAV (up to 20 MB) to PCBridge/pc-audio.
   Tap Play PC Audio on your iPhone and select the filename.
8. Close the server window to stop the bridge.
9. To test the Node server: node test-server.js

This uses unencrypted HTTP on your private LAN and a temporary key.
Never expose port 8765 to the internet or use the bridge on public Wi-Fi.
Nothing turns on the camera or microphone without an explicit action.
It does not add arbitrary Android camera/audio APIs to APKs, and does
not make incompatible APKs run as if they were on a real Android phone.
