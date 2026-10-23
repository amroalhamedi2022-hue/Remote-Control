import 'package:flutter/foundation.dart';
import 'dart:typed_data';
import '../network/lan_discovery.dart';
import '../security/pairing_lab.dart';

enum AppSection { devices, control, files, clipboard, multiDevice, settings }
enum InputMode { touch, mouse, keyboard }

class SampleDevice {
  final String name;
  final String subtitle;
  final bool windows;
  const SampleDevice(this.name, this.subtitle, {this.windows = false});
}

const sampleDevices = [
  SampleDevice('Xiaomi Pad 5', 'Android · Tablet'),
  SampleDevice('Android Phone', 'Android · Phone'),
  SampleDevice('MSI Sword 15', 'Windows 11 · Laptop', windows: true),
];

/// UI design with real LAN discovery + connectivity probes only.
/// Discovered devices are untrusted and cannot be remotely controlled.
class PrototypeState extends ChangeNotifier {
  final LanDiscovery lan = LanDiscovery();
  final PairingLab pairing = PairingLab();
  PrototypeState() {
    lan.addListener(notifyListeners);
    pairing.onChange = notifyListeners;
  }
  Future<void> startPairHost(AskForPairConsent ask) => pairing.startListening(ask);
  Future<PairResult> pairSelected(AskForPairConsent ask) async {
    final matches = lan.peers.where((p) => p.id == selectedPeerId).toList();
    if (matches.length != 1) throw StateError('Select a discovered device first');
    return pairing.connect(matches.single.address, ask);
  }

  Uint8List? previewImage;
  bool previewActive = false;
  String? previewError;
  Future<void> previewSelected(AskForPairConsent ask) async {
    final matches = lan.peers.where((p) => p.id == selectedPeerId).toList();
    if (matches.length != 1) throw StateError('Select a real discovered device first');
    return previewIp(matches.single.address, ask);
  }
  Future<void> previewIp(String ip, AskForPairConsent ask) async {
    if (previewActive) throw StateError('Preview already active');
    previewActive = true; previewError = null; previewImage = null;
    section = AppSection.control; notifyListeners();
    try {
      await pairing.preview(ip, ask, (frame) {
        previewImage = frame; notifyListeners();
      });
    } catch (e) {
      // Expected when user presses Disconnect, not an error.
      if (previewActive) previewError = '$e';
      rethrow;
    } finally {
      previewActive = false; previewImage = null; notifyListeners();
    }
  }
  void stopPreview() {
    previewActive = false;
    pairing.stopPreview();
    previewImage = null;
    notifyListeners();
  }

  Future<void> startLan() => lan.start();
  Future<void> manualProbe(String input) async {
    await lan.probeManual(input);
    notifyListeners();
  }
  @override
  void dispose() {
    pairing.onChange = null;
    pairing.stopPreview();
    pairing.stop();
    lan.removeListener(notifyListeners);
    lan.dispose();
    super.dispose();
  }

  AppSection section = AppSection.devices;
  int selectedDeviceIndex = 2;
  String? selectedPeerId;
  SampleDevice get sessionDevice {
    if(selectedPeerId != null) {
      for(final p in lan.peers) {
        if(p.id == selectedPeerId) {
          return SampleDevice(p.name, '${p.platform} · ${p.address}',windows:p.platform=='Windows');
        }
      }
    }
    return sampleDevices[selectedDeviceIndex];
  }
  List<SampleDevice> get connectionDevices => lan.peers.isEmpty ? sampleDevices :
    lan.peers.map((p)=>SampleDevice(p.name,'${p.platform} · ${p.address}',windows:p.platform=='Windows')).toList();
  void selectPeer(String id) { selectedPeerId=id; notifyListeners(); }
  InputMode inputMode = InputMode.touch;
  bool lightMode = false;
  bool reduceMotion = true;
  bool fullscreen = false;
  String quality = 'Auto';
  String resolution = '1080p';
  int fps = 60;
  String searchQuery = '';
  String clipboardText = 'Hello from Remote Control! 💙';

  void setSection(AppSection value) { section = value; notifyListeners(); }
  void selectDevice(int index) { selectedPeerId=null;selectedDeviceIndex = index; notifyListeners(); }
  void setMode(InputMode value) { inputMode = value; notifyListeners(); }
  void setLight(bool value) { lightMode = value; notifyListeners(); }
  void setReduceMotion(bool value) { reduceMotion = value; notifyListeners(); }
  void setFullscreen(bool value) { fullscreen = value; notifyListeners(); }
  void setQuality(String value) { quality = value; notifyListeners(); }
  void setResolution(String value) { resolution = value; notifyListeners(); }
  void setFps(int value) { fps = value; notifyListeners(); }
  void setSearch(String value) { searchQuery = value; notifyListeners(); }
  void setClipboardText(String value) { clipboardText = value; notifyListeners(); }
}
