import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_selector/file_selector.dart';
import 'models/app_state.dart';
import 'ui/liquid_theme.dart';
import 'security/pairing_lab.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const LiquidRemoteControlPrototype());
}

class LiquidRemoteControlPrototype extends StatefulWidget {
  const LiquidRemoteControlPrototype({super.key});
  @override State<LiquidRemoteControlPrototype> createState() => _LiquidRemoteControlPrototypeState();
}

class _LiquidRemoteControlPrototypeState extends State<LiquidRemoteControlPrototype> {
  final PrototypeState app = PrototypeState();
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  @override void initState() {
    super.initState();
    app.startLan();
    app.pairing.onClipboardConsent = _confirmClipboard;
    app.pairing.onClipboardWrite = (text) async {
      await Clipboard.setData(ClipboardData(text: text));
    };
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) app.startPairHost(_confirmPair);
    });
  }
  Future<bool> _confirmPair(PairChallenge challenge) async {
    if (!mounted || navigatorKey.currentContext == null) return false;
    BuildContext? activeDialog;
    Timer? consentTimer;
    bool? answer;
    try {
      answer = await showDialog<bool>(
        context: navigatorKey.currentContext!,
        barrierDismissible: false,
        builder: (context) {
          activeDialog = context;
          consentTimer ??= Timer(const Duration(seconds: 45), () {
            final dialog = activeDialog;
            if (dialog != null && dialog.mounted &&
                (ModalRoute.of(dialog)?.isCurrent ?? false)) {
              Navigator.of(dialog).pop(false);
            }
          });
          return AlertDialog(
        title: const Text('Secure LAN pairing · experimental'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Compare the six digits shown on BOTH devices before accepting.'),
          const SizedBox(height: 12),
          Center(child: SelectableText(challenge.code,
            style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w900, letterSpacing: 5))),
          const SizedBox(height: 8),
          Text(challenge.previouslyTrusted ? 'Previously trusted identity' : 'NEW identity — check carefully',
            style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          SelectableText('Identity: ${challenge.fingerprint}', style: const TextStyle(fontSize: 11)),
          const SizedBox(height: 8),
          const Text('Pairing grants no unattended access. Clipboard requires a separate local approval; screen, input and files are not granted.'),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Reject')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Codes match · approve')),
        ],
          );
        },
      );
    } finally {
      consentTimer?.cancel();
    }
    return answer == true;
  }
  Future<bool> _confirmClipboard(String fingerprint, String text) async {
    if (!mounted || navigatorKey.currentContext == null) return false;
    BuildContext? activeDialog;
    Timer? timer;
    try {
      return await showDialog<bool>(
        context: navigatorKey.currentContext!,
        barrierDismissible: false,
        builder: (context) {
          activeDialog = context;
          timer ??= Timer(const Duration(seconds: 45), () {
            final dialog = activeDialog;
            if (dialog != null && dialog.mounted &&
                (ModalRoute.of(dialog)?.isCurrent ?? false)) {
              Navigator.of(dialog).pop(false);
            }
          });
          return AlertDialog(
            title: const Text('Receive clipboard text?'),
            content: SizedBox(
              width: 380,
              child: Column(mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('A paired LAN device requests to REPLACE your Android clipboard once.'),
                  const SizedBox(height: 8),
                  SelectableText('Peer: ${fingerprint.substring(0, 20)}…',
                    style: const TextStyle(fontSize: 11)),
                  const SizedBox(height: 12),
                  SizedBox(height: 150,
                    child: SingleChildScrollView(child: SelectableText(text))),
                  const SizedBox(height: 8),
                  const Text('No background sync. Automatically denied after 45 seconds.',
                    style: TextStyle(fontSize: 12)),
                ]),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false),
                child: const Text('Deny')),
              FilledButton(onPressed: () => Navigator.pop(context, true),
                child: const Text('Replace clipboard once')),
            ],
          );
        },
      ) == true;
    } finally {
      timer?.cancel();
    }
  }
  @override void dispose() {
    app.pairing.onClipboardConsent = null;
    app.pairing.onClipboardWrite = null;
    app.dispose();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: app,
    builder: (context, _) => MaterialApp(
      navigatorKey: navigatorKey,
      title: 'Remote Control · Liquid Fusion v0.8 Discovery Lab', debugShowCheckedModeBanner: false,
      themeMode: app.lightMode ? ThemeMode.light : ThemeMode.dark,
      theme: ThemeData(useMaterial3: true,brightness: Brightness.light,fontFamily: 'Segoe UI',scaffoldBackgroundColor: const Color(0xFFE8F8FF)),
      darkTheme: ThemeData(useMaterial3: true,brightness: Brightness.dark,fontFamily: 'Segoe UI',scaffoldBackgroundColor: const Color(0xFF0B1127)),
      home: _Home(app: app),
    ),
  );
}

const _sections = <AppSection, (String, IconData)>{
  AppSection.devices: ('Devices',Icons.devices_outlined),
  AppSection.control: ('Remote Control',Icons.cast_connected_outlined),
  AppSection.files: ('File Transfer',Icons.folder_copy_outlined),
  AppSection.clipboard: ('Shared Clipboard',Icons.content_paste_outlined),
  AppSection.multiDevice: ('Multi-Device',Icons.hub_outlined),
  AppSection.settings: ('Settings',Icons.settings_outlined),
};

class _Home extends StatelessWidget {
  final PrototypeState app;
  const _Home({required this.app});
  void _demo(BuildContext context,String message) {
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('UI DEMO · $message'),duration: const Duration(seconds: 3)));
  }
  void _notice(BuildContext context, String message) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), duration: const Duration(seconds: 5)));
  }
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final w = constraints.maxWidth;
      final mobile = w < 720;
      final tablet = w >= 720 && w < 1140;
      final c = LiquidColors(app.lightMode);
      return Scaffold(
        body: LiquidBackdrop(light: app.lightMode,
          child: SafeArea(child: Center(child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 1600,maxHeight: mobile ? double.infinity : 970),
            child: Container(margin: EdgeInsets.all(mobile?0:18),
              decoration: BoxDecoration(color: c.panelDark.withValues(alpha: mobile ? .68 : .82),
                border: mobile?null:Border.all(color:c.border),borderRadius: BorderRadius.circular(mobile?0:18)),
              clipBehavior: Clip.antiAlias,
              child: Row(children: [
                if (!mobile) _Sidebar(app:app, compact:tablet),
                Expanded(child: Column(children: [
                  _TopBar(app:app,mobile:mobile,onTheme:()=>app.setLight(!app.lightMode)),
                  Expanded(child: _Body(app:app,mobile:mobile,tablet:tablet,onDemo:(m)=>_demo(context,m),onNotice:(m)=>_notice(context,m))),
                  if(mobile) _MobileNav(app:app),
                ])),
              ]),
            ),
          ))),
        ),
      );
    },
  );
}

class _Logo extends StatelessWidget {
  final double size;
  const _Logo({this.size=35});
  @override Widget build(BuildContext context) => Container(
    width:size,height:size,
    decoration:BoxDecoration(borderRadius:BorderRadius.circular(size*.26),
      gradient:const LinearGradient(colors:[Color(0xFF0DE0FF),Color(0xFF2178FE),Color(0xFF9D57FF)],begin:Alignment.topLeft,end:Alignment.bottomRight),
      boxShadow:[BoxShadow(color:const Color(0xFF3682FF).withValues(alpha:.35),blurRadius:15)]),
    child:Icon(Icons.connected_tv,size:size*.60,color:Colors.white),
  );
}

class _Sidebar extends StatelessWidget {
  final PrototypeState app;
  final bool compact;
  const _Sidebar({required this.app,required this.compact});
  @override Widget build(BuildContext context) {
    final c=LiquidColors(app.lightMode);
    return Container(width:compact?70:218,
      padding:EdgeInsets.symmetric(horizontal:compact?8:12,vertical:20),
      decoration:BoxDecoration(gradient:LinearGradient(begin:Alignment.topLeft,end:Alignment.bottomRight,
          colors:[c.panel,c.panelDark]),border:Border(right:BorderSide(color:c.border))),
      child:Column(children:[
        Row(mainAxisAlignment:compact?MainAxisAlignment.center:MainAxisAlignment.start,
          children:[const _Logo(),if(!compact)...[const SizedBox(width:10),Flexible(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            Text('Remote Control',style:TextStyle(fontSize:15,color:c.text,fontWeight:FontWeight.bold)),
            Text('Local Device Control',style:TextStyle(fontSize:10,color:c.muted)),
          ]))]]),
        const SizedBox(height:30),
        ..._sections.entries.map((entry) => Padding(padding:const EdgeInsets.only(bottom:5),
          child:_NavItem(app:app,section:entry.key,compact:compact))),
        const Spacer(),
        GlassPanel(padding:EdgeInsets.all(compact?8:12),child:Row(mainAxisSize:MainAxisSize.min,children:[
          const Icon(Icons.circle_outlined,color:LiquidColors.aqua,size:22),
          if(!compact)...[const SizedBox(width:8),Flexible(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            Text('My Devices',style:TextStyle(fontSize:11,color:c.text,fontWeight:FontWeight.w700)),
            Text('3 sample devices',style:TextStyle(fontSize:10,color:c.muted)),
          ]))],
        ])),
      ]),
    );
  }
}
class _NavItem extends StatelessWidget {
  final PrototypeState app;
  final AppSection section;
  final bool compact;
  const _NavItem({required this.app,required this.section,required this.compact});
  @override Widget build(BuildContext context) {
    final active = app.section == section;
    final c=LiquidColors(app.lightMode);
    return Tooltip(message:_sections[section]!.$1,child:Material(color:Colors.transparent,child:InkWell(
      borderRadius:BorderRadius.circular(10),onTap:()=>app.setSection(section),
      child:AnimatedContainer(duration:const Duration(milliseconds:140),height:47,
        padding:EdgeInsets.symmetric(horizontal:compact?0:10),
        decoration:BoxDecoration(borderRadius:BorderRadius.circular(10),
          gradient:active?const LinearGradient(colors:[Color(0xFF2379EE),Color(0x663B58B5)]):null,
          border:Border.all(color:active?c.border:Colors.transparent)),
        child:Row(mainAxisAlignment:compact?MainAxisAlignment.center:MainAxisAlignment.start,children:[
          Icon(_sections[section]!.$2,color:active?Colors.white:c.text,size:20),
          if(!compact)...[const SizedBox(width:12),Flexible(child:Text(_sections[section]!.$1,
            style:TextStyle(fontSize:12,fontWeight:FontWeight.w600,color:active?Colors.white:c.text)))],
        ]),
      ),
    )));
  }
}

class _TopBar extends StatelessWidget {
  final PrototypeState app;
  final bool mobile;
  final VoidCallback onTheme;
  const _TopBar({required this.app,required this.mobile,required this.onTheme});
  @override Widget build(BuildContext context) {
    final c=LiquidColors(app.lightMode);
    return Padding(padding:EdgeInsets.fromLTRB(mobile?14:17,14,mobile?14:17,8),
      child:Row(children:[
        if(mobile)...[const _Logo(size:32),const SizedBox(width:10)],
        Flexible(child:Text(mobile?'Remote Control':_sections[app.section]!.$1,overflow:TextOverflow.ellipsis,
          style:TextStyle(fontSize:mobile?15:17,fontWeight:FontWeight.w700,color:c.text))),
        if(!mobile)...[const SizedBox(width:24),Flexible(child:SizedBox(width:300,height:38,
          child:TextField(onChanged:app.setSearch,decoration:InputDecoration(
            prefixIcon:const Icon(Icons.search,size:19),hintText:'Search devices...',hintStyle:TextStyle(fontSize:12,color:c.muted),
            contentPadding:const EdgeInsets.symmetric(vertical:10),filled:true,fillColor:c.panel,border:OutlineInputBorder(borderRadius:BorderRadius.circular(28),borderSide:BorderSide.none)),
          )))],
        const Spacer(),
        Container(padding:const EdgeInsets.symmetric(horizontal:10,vertical:7),
          decoration:BoxDecoration(borderRadius:BorderRadius.circular(22),color:const Color(0x3321C9BB)),
          child:Row(children:[const Icon(Icons.circle,size:8,color:Color(0xFF3BF5A4)),const SizedBox(width:7),Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            const Text('LAN Mode',style:TextStyle(fontSize:11,fontWeight:FontWeight.bold,color:Color(0xFF3CF3A5))),
            if(!mobile)Text(app.lan.running?'Discovery running':'Discovery offline',style:TextStyle(fontSize:9,color:c.muted)),
          ])])),
        const SizedBox(width:7),IconButton(tooltip:'Toggle dark / light',icon:Icon(Icons.tune,color:c.text,size:21),onPressed:onTheme),
      ]),
    );
  }
}

class _MobileNav extends StatelessWidget {
  final PrototypeState app;
  const _MobileNav({required this.app});
  @override Widget build(BuildContext context) {
    final c=LiquidColors(app.lightMode);
    final items=[AppSection.devices,AppSection.control,AppSection.files,AppSection.clipboard,AppSection.settings];
    return Container(height:70,padding:const EdgeInsets.only(top:5),
      decoration:BoxDecoration(color:c.panel,border:Border(top:BorderSide(color:c.border))),
      child:Row(children:items.map((s)=>Expanded(child:InkWell(onTap:()=>app.setSection(s),
        child:Column(mainAxisAlignment:MainAxisAlignment.center,children:[
          Icon(_sections[s]!.$2,color:app.section==s?LiquidColors.aqua:c.muted,size:22),
          const SizedBox(height:4),Text(s==AppSection.control?'Control':s==AppSection.files?'Files':s==AppSection.clipboard?'Clipboard':_sections[s]!.$1,
            style:TextStyle(fontSize:10,color:app.section==s?LiquidColors.aqua:c.muted)),
        ]),
      ))).toList()),
    );
  }
}

class _Body extends StatelessWidget {
  final PrototypeState app;
  final bool mobile;
  final bool tablet;
  final ValueChanged<String> onDemo;
  final ValueChanged<String> onNotice;
  const _Body({required this.app,required this.mobile,required this.tablet,required this.onDemo,required this.onNotice});
  @override Widget build(BuildContext context) {
    final c=LiquidColors(app.lightMode);
    final section = app.section;
    final devicePage = section==AppSection.devices;
    final controlPage = section==AppSection.control;
    return ListView(padding:EdgeInsets.fromLTRB(mobile?13:18,13,mobile?13:18,20),children:[
      Text(_sections[section]!.$1,style:TextStyle(fontWeight:FontWeight.bold,fontSize:17,color:c.text)),
      const SizedBox(height:4),Text(devicePage?'Discover and connect to your devices on the local network.':
        section==AppSection.clipboard
          ? 'Opt-in Android → Android/Windows text transfer; receiver approves each request.'
          : 'Liquid Fusion · ${_sections[section]!.$1} · UI demonstration only',
        style:TextStyle(fontSize:11,color:c.muted)),
      const SizedBox(height:7),Text('LIVE LAN DISCOVERY · REMOTE CONTROL NOT CONNECTED',
        style:TextStyle(fontSize:10,color:c.muted,fontWeight:FontWeight.w700)),
      const SizedBox(height:15),
      if(devicePage || section==AppSection.multiDevice)...[
        _Devices(app:app,mobile:mobile,onDemo:onDemo,onNotice:onNotice),const SizedBox(height:14),
      ],
      if((devicePage && !mobile) || controlPage)...[
        _SessionSection(app:app,mobile:mobile,tablet:tablet,onDemo:onDemo),const SizedBox(height:14),
      ],
      if(devicePage && !mobile)
        _SecondaryPanels(app:app,tablet:tablet,onDemo:onDemo),
      if(section==AppSection.files) _FileCard(app:app),
      if(section==AppSection.clipboard) _ClipboardCard(app:app),
      if(section==AppSection.settings) _SettingsCard(app:app),
      if(section==AppSection.multiDevice)GlassPanel(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text('Multi-device control',style:TextStyle(fontSize:17,fontWeight:FontWeight.bold,color:c.text)),
        const SizedBox(height:9),Text('Design preview only. Multi-session connections are not implemented yet.',style:TextStyle(color:c.muted)),
      ])),
    ]);
  }
}

class _Devices extends StatelessWidget {
  final PrototypeState app;
  final bool mobile;
  final ValueChanged<String> onDemo;
  final ValueChanged<String> onNotice;
  const _Devices({required this.app,required this.mobile,required this.onDemo,required this.onNotice});
  @override Widget build(BuildContext context) {
    final peers = app.lan.peers.where((p) => p.name.toLowerCase().contains(app.searchQuery.toLowerCase())).toList();
    final entries=<Widget>[];
    if (app.lan.peers.isNotEmpty) {
      for (final p in peers) {
        final device=SampleDevice(p.name,'${p.platform} · ${p.address}',windows:p.platform=='Windows');
        entries.add(_DeviceTile(device:device,selected:app.selectedPeerId==p.id,
          light:app.lightMode,subtitle:app.pairing.isPairedInThisSession(p.address) ? '● Paired · encrypted test passed' : '● Discovered · unpaired',onTap:() async {
            app.selectPeer(p.id);
            final rtt=await app.lan.ping(p);
            onDemo(rtt==null?'${p.name}: LAN probe failed · not paired':
              '${p.name}: LAN TCP RTT ${rtt.inMilliseconds} ms · pairing pending');
          }));
      }
    } else {
      for(var i=0;i<sampleDevices.length;i++) {
        final d=sampleDevices[i];
        if(!d.name.toLowerCase().contains(app.searchQuery.toLowerCase()))continue;
        entries.add(_DeviceTile(device:d,selected:app.selectedPeerId==null && app.selectedDeviceIndex==i,
          light:app.lightMode,subtitle:'● Design placeholder',onTap:(){app.selectDevice(i);onDemo('${d.name} is a sample device');}));
      }
    }
    entries.add(_DeviceTile(device:null,selected:false,light:app.lightMode,
      onTap:()=>_showManualIpDialog(context,app,onDemo)));
    final c=LiquidColors(app.lightMode);
    return Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Row(children:[Icon(app.lan.running?Icons.wifi:Icons.wifi_off,size:14,color:LiquidColors.aqua),
        const SizedBox(width:5),Expanded(child:Text(
        app.lan.peers.isEmpty?'Sample cards · no discovered device yet':
          '${app.lan.peers.length} nearby devices · secure lab ${app.pairing.listening ? 'ready' : 'offline'}',style:TextStyle(fontSize:10,color:c.muted))),
        if (app.selectedPeerId != null)
          TextButton.icon(
            onPressed: app.previewActive ? null : () async {
              try {
                await app.previewSelected((challenge) => _pairDialog(context, challenge));
              } catch(e) { if (context.mounted) onNotice('Preview closed: $e'); }
            }, icon:const Icon(Icons.ondemand_video_outlined,size:14),
            label:const Text('View screen (lab)')),
        if (app.selectedPeerId != null)
          TextButton.icon(
            onPressed: () async {
              final ctx = context;
              try {
                final result = await app.pairSelected((challenge) => _pairDialog(ctx, challenge));
                onNotice('Encrypted PING succeeded · trusted ${result.fingerprint.substring(0, 12)}… · remote control still disabled');
              } catch (e) { onNotice('Pairing not completed: $e'); }
            }, icon: const Icon(Icons.verified_user_outlined,size:14),label: const Text('Pair securely')),
        TextButton.icon(onPressed:app.lan.refresh,icon:const Icon(Icons.refresh,size:14),label:const Text('Rescan'))]),
      if (app.pairing.error != null) Text(app.pairing.error!,style:const TextStyle(color:Color(0xFFFF9B9B),fontSize:11)),
      if(app.lan.error!=null)Text(app.lan.error!,style:const TextStyle(color:Color(0xFFFF9B9B),fontSize:11)),
      if(mobile)Column(children:entries.map((e)=>Padding(padding:const EdgeInsets.only(bottom:9),child:e)).toList())
      else LayoutBuilder(builder:(context,constr){
        final cols=constr.maxWidth>875?4:2;
        return GridView.count(crossAxisCount:cols,childAspectRatio:cols==4?2.75:3.5,
          mainAxisSpacing:10,crossAxisSpacing:10,shrinkWrap:true,
          physics:const NeverScrollableScrollPhysics(),children:entries);
      }),
    ]);
  }
}
Future<bool> _pairDialog(BuildContext context, PairChallenge challenge) async {
  if (!context.mounted) return false;
  BuildContext? activeDialog;
  Timer? consentTimer;
  try {
    final approved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        activeDialog = ctx;
        // PairConsentPolicy also expires the handshake, but its Future.timeout
        // cannot dismiss a Flutter route by itself. Never leave a stale approval
        // dialog visible after the underlying encrypted socket has timed out.
        consentTimer ??= Timer(const Duration(seconds: 45), () {
          final dialog = activeDialog;
          if (dialog != null && dialog.mounted &&
              (ModalRoute.of(dialog)?.isCurrent ?? false)) {
            Navigator.of(dialog).pop(false);
          }
        });
        return AlertDialog(
          title: const Text('Verify pairing code'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Compare the 6-digit code on BOTH devices. Do not approve if different.'),
            const SizedBox(height: 12),
            SelectableText(challenge.code,
              style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, letterSpacing: 5)),
            Text(challenge.previouslyTrusted ? 'Previously trusted device' : 'New device identity'),
            const SizedBox(height: 8),
            SelectableText(challenge.fingerprint, style: const TextStyle(fontSize: 10)),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Reject')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Codes match')),
          ],
        );
      },
    );
    return approved == true;
  } finally {
    consentTimer?.cancel();
  }
}

class _DeviceTile extends StatelessWidget {
  final SampleDevice? device;
  final bool selected,light;
  final VoidCallback onTap;
  final String? subtitle;
  const _DeviceTile({required this.device,required this.selected,required this.light,required this.onTap,this.subtitle});
  @override Widget build(BuildContext context) {
    final c=LiquidColors(light);
    return Material(color:Colors.transparent,child:InkWell(onTap:onTap,borderRadius:BorderRadius.circular(12),
      child:AnimatedContainer(duration:const Duration(milliseconds:140),padding:const EdgeInsets.all(10),
        decoration:BoxDecoration(borderRadius:BorderRadius.circular(12),
          border:Border.all(color:selected?LiquidColors.aqua:c.border,width:selected?1.4:1),
          gradient:LinearGradient(colors:[c.panel,c.panelDark])),
        child:Row(children:[
          Container(width:45,height:45,decoration:BoxDecoration(borderRadius:BorderRadius.circular(9),
            gradient:LinearGradient(colors:(device?.windows ?? false) ? const [Color(0xFF1E5DCE),Color(0xFF25CDF3)]
              :const [Color(0xFF2F65E2),Color(0xFF943DDF),Color(0xFFFF6CAB)])),
            child:Icon(device==null?Icons.add:device!.windows?Icons.desktop_windows_outlined:Icons.phone_android_outlined,size:29,color:Colors.white)),
          const SizedBox(width:10),Expanded(child:Column(mainAxisAlignment:MainAxisAlignment.center,
            crossAxisAlignment:CrossAxisAlignment.start,children:[
            Text(device?.name??'Add Device',maxLines:1,overflow:TextOverflow.ellipsis,
              style:TextStyle(fontSize:12,fontWeight:FontWeight.w700,color:c.text)),
            const SizedBox(height:4),Text(device?.subtitle??'Manual IP',maxLines:1,
              style:TextStyle(fontSize:10,color:c.muted)),
            if(device!=null)...[const SizedBox(height:5),Text(subtitle ?? '● Sample device',
              maxLines:1,overflow:TextOverflow.ellipsis,
              style:TextStyle(fontSize:10,color:Color(0xFF45E9A5)))],
          ]))
        ]),
      ),
    ));
  }
}
void _showManualIpDialog(BuildContext context,PrototypeState app,ValueChanged<String> onDemo) {
  final controller=TextEditingController();
  showDialog<void>(context:context,builder:(dialogContext)=>AlertDialog(
    title:const Text('Add device by IP'),
    content:Column(mainAxisSize:MainAxisSize.min,children:[
      const Text('Manual discovery or secure pairing test. No remote-control permissions are enabled.'),
      const SizedBox(height:12),TextField(controller:controller,decoration:const InputDecoration(labelText:'LAN IPv4 address',hintText:'192.168.1.42')),
    ]),
    actions:[TextButton(onPressed:()=>Navigator.pop(dialogContext),child:const Text('Cancel')),
      TextButton(onPressed:() async {
        final v=controller.text.trim(); Navigator.pop(dialogContext);
        if (v.isEmpty) { onDemo('Enter a local IPv4 address'); return; }
        final found=await app.lan.probeManual(v);
        if(context.mounted){
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(
            found?'LAN agent found at $v (not paired)':'No LAN discovery agent replied at $v')));
        }
      },child:const Text('Discover')),
      FilledButton(onPressed:() async {
        final ip=controller.text.trim(); Navigator.pop(dialogContext);
        try {
          final result=await app.pairing.connect(ip, (challenge)=>_pairDialog(context, challenge));
          if(context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content:Text('Encrypted PING OK · ${result.fingerprint.substring(0,12)}… · no remote control granted')));
          }
        }catch(e){
          if(context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content:Text('Could not pair by IP: $e')));
          }
        }
      },child:const Text('Pair IP')),
      TextButton(onPressed:() async {
        final ip=controller.text.trim(); Navigator.pop(dialogContext);
        try {
          await app.pairing.sendClipboard(ip,
            (challenge)=>_pairDialog(context, challenge), app.clipboardText);
          if(context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content:Text('LAN receiver approved and wrote the clipboard text')));
          }
        } catch(e) {
          if(context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content:Text('Clipboard by IP failed: $e')));
          }
        }
      },child:const Text('Send text IP')),
      TextButton(onPressed:() async {
        final ip=controller.text.trim();Navigator.pop(dialogContext);
        try { await app.previewIp(ip, (challenge)=>_pairDialog(context,challenge)); }
        catch(e) {
          if(context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content:Text('Preview ended: $e')));
          }
        }
      },child:const Text('View IP (lab)'))],
  )).then((_)=>controller.dispose());
}

class _SessionSection extends StatelessWidget {
  final PrototypeState app;
  final bool mobile,tablet;
  final ValueChanged<String> onDemo;
  const _SessionSection({required this.app,required this.mobile,required this.tablet,required this.onDemo});
  @override Widget build(BuildContext context) {
    final device = app.sessionDevice;
    final c=LiquidColors(app.lightMode);
    final desktopPanel = !mobile && !tablet;
    final screen = GlassPanel(strong:true,child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      Row(children:[const _Logo(size:26),const SizedBox(width:9),
        Flexible(child:Text(device.name,maxLines:1,overflow:TextOverflow.ellipsis,
          style:TextStyle(fontWeight:FontWeight.bold,fontSize:13,color:c.text))),
        const SizedBox(width:9),Text(app.previewActive ? '● VIEW-ONLY LAB' : '● Display demo only',
          style:const TextStyle(color:Color(0xFF42EDA3),fontSize:10)),
        if(!mobile)...[const Spacer(),Text('1920 × 1080 · sample display',style:TextStyle(fontSize:10,color:c.muted))],
      ]),const SizedBox(height:12),
      Row(crossAxisAlignment:CrossAxisAlignment.start,children:[
        if(desktopPanel)...[
          SizedBox(width:87,child:Column(children:[
            for(final (label,icon,selection) in <(String,IconData,bool)>[
              ('Screen',Icons.monitor_outlined,true),('Mouse',Icons.mouse_outlined,app.inputMode==InputMode.mouse),
              ('Keyboard',Icons.keyboard_outlined,app.inputMode==InputMode.keyboard),
              ('Clipboard',Icons.content_paste_outlined,false),('Files',Icons.folder_outlined,false),('Audio',Icons.volume_up_outlined,false),
            ]) Padding(padding:const EdgeInsets.only(bottom:6),child:InkWell(
              onTap:()=>onDemo('$label panel selected'),borderRadius:BorderRadius.circular(7),
              child:Container(padding:const EdgeInsets.symmetric(horizontal:6,vertical:10),
                decoration:BoxDecoration(borderRadius:BorderRadius.circular(7),
                  color:selection?c.selected:c.panel),child:Row(children:[Icon(icon,size:14,color:selection?Colors.white:c.text),
                    const SizedBox(width:4),Expanded(child:Text(label,maxLines:1,overflow:TextOverflow.ellipsis,
                      style:TextStyle(fontSize:10,color:selection?Colors.white:c.text)))])),
            )),
          ])),const SizedBox(width:11),
        ],
        Expanded(child:Container(decoration:BoxDecoration(borderRadius:BorderRadius.circular(10),
          border:Border.all(color:const Color(0xFF3E93EC))),child:ClipRRect(borderRadius:BorderRadius.circular(9),child:Column(children:[
          AspectRatio(aspectRatio:16/9,child:Stack(children:[
            if (app.previewImage != null && app.previewActive)
              Positioned.fill(child:Image.memory(app.previewImage!,fit:BoxFit.contain,gaplessPlayback:true))
            else const Positioned.fill(child:CustomPaint(painter:_DemoScreenPainter())),
            Positioned(top:10,right:10,child:Container(padding:const EdgeInsets.symmetric(horizontal:9,vertical:7),
              decoration:BoxDecoration(color:const Color(0xDC08152F),borderRadius:BorderRadius.circular(7)),
              child:Text(app.previewActive ? 'LIVE MJPEG LAB · VIEW ONLY' : 'DEMO · NOT LIVE',
                style:const TextStyle(color:Colors.white,fontSize:10,fontWeight:FontWeight.w800))))
          ])),
          Container(height:30,color:const Color(0xF207172E),padding:const EdgeInsets.symmetric(horizontal:10),
            child:Row(children:[const Icon(Icons.circle,size:8,color:LiquidColors.aqua),const SizedBox(width:5),
              Flexible(child:Text(app.previewActive?'Encrypted JPEG preview · NO INPUT':'Local-only design',overflow:TextOverflow.ellipsis,style:const TextStyle(fontSize:10,color:LiquidColors.aqua))),
              if(!mobile)...[const SizedBox(width:12),Text(app.previewActive?'View only · no input':'No active remote input',style:const TextStyle(fontSize:10,color:Color(0xFFA9BCD7)))],
            ])),
          ])))),
      ]),
    ]));
    final controls=_SessionControls(app:app,onDemo:onDemo,mobile:mobile);
    if(mobile || tablet) return Column(children:[screen,const SizedBox(height:10),controls]);
    return Row(crossAxisAlignment:CrossAxisAlignment.start,children:[Expanded(child:screen),const SizedBox(width:11),SizedBox(width:193,child:controls)]);
  }
}
class _SessionControls extends StatelessWidget {
  final PrototypeState app;
  final bool mobile;
  final ValueChanged<String> onDemo;
  const _SessionControls({required this.app,required this.mobile,required this.onDemo});
  @override Widget build(BuildContext context) {
    final c=LiquidColors(app.lightMode);
    final buttons = [
      LiquidAction(label:'Disconnect',icon:Icons.power_settings_new,danger:true,
        onTap:()=>app.previewActive ? app.stopPreview() : onDemo('No remote session is connected')),
      for(final mode in InputMode.values)
        LiquidAction(label:'${mode.name[0].toUpperCase()}${mode.name.substring(1)} Mode',
          icon:mode==InputMode.touch?Icons.touch_app_outlined:mode==InputMode.mouse?Icons.mouse_outlined:Icons.keyboard_outlined,
          active:app.inputMode==mode,onTap:(){app.setMode(mode);onDemo('${mode.name} selected, no actual input sent');}),
    ];
    final options=Column(children:[
      _SettingSelect<String>(label:'Quality',value:app.quality,
        options:const ['Auto','Low','High'],onChanged:app.setQuality),
      _SettingSelect<String>(label:'Resolution',value:app.resolution,
        options:const ['1080p','720p','480p'],onChanged:app.setResolution),
      _SettingSelect<int>(label:'FPS',value:app.fps,options:const [60,30,15],onChanged:app.setFps),
    ]);
    return GlassPanel(child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      if(mobile) Wrap(spacing:7,runSpacing:7,children:[for(final b in buttons) b])
      else for(final b in buttons)...[b,const SizedBox(height:8)],
      const SizedBox(height:10),Divider(color:c.border),options,
      const SizedBox(height:10),LiquidAction(label:'More Settings',icon:Icons.settings_outlined,
        onTap:()=>app.setSection(AppSection.settings)),
    ]));
  }
}
class _SettingSelect<T> extends StatelessWidget {
  final String label;
  final T value;
  final List<T> options;
  final ValueChanged<T> onChanged;
  const _SettingSelect({required this.label,required this.value,required this.options,required this.onChanged});
  @override Widget build(BuildContext context) {
    final c=LiquidColors(Theme.of(context).brightness==Brightness.light);
    return Padding(padding:const EdgeInsets.symmetric(vertical:5),child:Row(children:[
      Expanded(child:Text(label,style:TextStyle(fontSize:11,color:c.text))),
      Container(padding:const EdgeInsets.symmetric(horizontal:7),
        decoration:BoxDecoration(color:c.panel,borderRadius:BorderRadius.circular(7),border:Border.all(color:c.border)),
        child:DropdownButtonHideUnderline(child:DropdownButton<T>(value:value,isDense:true,
          dropdownColor:Theme.of(context).scaffoldBackgroundColor,
          style:TextStyle(fontSize:11,color:c.text),
          items:[for(final o in options)DropdownMenuItem<T>(value:o,child:Text(o.toString()))],
          onChanged:(x){if(x!=null)onChanged(x);},
        )),
      ),
    ]));
  }
}

/// An original illustrated backdrop. NOT a screenshot and NOT an actual stream.
class _DemoScreenPainter extends CustomPainter {
  const _DemoScreenPainter();
  @override void paint(Canvas canvas,Size size) {
    final rect=Offset.zero&size;
    canvas.drawRect(rect,Paint()..shader=const LinearGradient(begin:Alignment.topLeft,end:Alignment.bottomRight,
      colors:[Color(0xFFDAF1FF),Color(0xFF5DA0E9),Color(0xFFCCE6FF)]).createShader(rect));
    final s=size.width/1000.0;
    canvas.save();
    canvas.translate(size.width*.20,-size.height*.13);
    canvas.scale(s,s);
    final path=Path()..moveTo(122,415)..cubicTo(180,65,810,42,855,190)
      ..cubicTo(900,310,290,330,415,472)..cubicTo(540,610,880,500,906,405)
      ..cubicTo(835,669,270,730,160,540)..close();
    canvas.drawPath(path,Paint()..shader=const LinearGradient(colors:[Color(0xFF0D39AF),Color(0xFF1E82FA),Color(0xFF061961)],
      begin:Alignment.topLeft,end:Alignment.bottomRight).createShader(const Rect.fromLTWH(120,60,900,700)));
    final path2=Path()..moveTo(154,429)..cubicTo(225,192,718,108,804,217)
      ..cubicTo(860,290,468,350,465,465)..cubicTo(462,615,766,498,860,435)
      ..cubicTo(726,638,350,625,225,558)..cubicTo(159,522,139,484,154,429)..close();
    canvas.drawPath(path2,Paint()..shader=const LinearGradient(colors:[Color(0xFF2481FD),Color(0xFF74DFFF),Color(0xFF1B49C4)]).createShader(const Rect.fromLTWH(150,150,760,470)));
    final inner=Path()..moveTo(285,441)..cubicTo(355,288,687,253,713,317)
      ..cubicTo(756,383,445,372,470,454)..cubicTo(489,526,642,485,709,440)
      ..cubicTo(599,552,293,567,285,441)..close();
    canvas.drawPath(inner,Paint()..shader=const LinearGradient(colors:[Color(0xFF6DDCFF),Color(0xFF309AFF),Color(0xFF1036AE)]).createShader(const Rect.fromLTWH(280,250,510,310)));
    canvas.restore();
    canvas.drawRect(Rect.fromLTWH(0,size.height-24,size.width,24),Paint()..color=const Color(0xE5EDF9FF));
    for(var i=0;i<5;i++){
      canvas.drawCircle(Offset(size.width*.43+i*18,size.height-12),5,
        Paint()..color=i.isEven?const Color(0xFF225CD4):const Color(0xFF4F9AE8));
    }
    final tp=TextPainter(text:const TextSpan(text:'Illustrative preview · no remote connection',
      style:TextStyle(fontSize:10,color:Color(0xFF285891))),textDirection:TextDirection.ltr);
    tp.layout();tp.paint(canvas,const Offset(10,10));
  }
  @override bool shouldRepaint(covariant _DemoScreenPainter oldDelegate)=>false;
}

class _SecondaryPanels extends StatelessWidget {
  final PrototypeState app;
  final bool tablet;
  final ValueChanged<String> onDemo;
  const _SecondaryPanels({required this.app,required this.tablet,required this.onDemo});
  @override Widget build(BuildContext context) {
    if(tablet) {
      return Column(children:[_ConnectionCard(app:app,onDemo:onDemo),const SizedBox(height:11),
        Row(crossAxisAlignment:CrossAxisAlignment.start,children:[Expanded(child:_FileCard(onDemo:onDemo)),
          const SizedBox(width:11),Expanded(child:_ClipboardCard(app:app))])]);
    }
    return Row(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Expanded(flex:12,child:_ConnectionCard(app:app,onDemo:onDemo)),const SizedBox(width:11),
      Expanded(flex:10,child:_FileCard(onDemo:onDemo)),const SizedBox(width:11),
      Expanded(flex:10,child:_ClipboardCard(app:app)),
    ]);
  }
}
class _PanelHeading extends StatelessWidget {
  final String title,subtitle;
  final IconData icon;
  const _PanelHeading({required this.title,required this.subtitle,required this.icon});
  @override Widget build(BuildContext context) {
    final c=LiquidColors(Theme.of(context).brightness==Brightness.light);
    return Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Row(children:[Icon(icon,size:17,color:LiquidColors.aqua),const SizedBox(width:5),
        Flexible(child:Text(title,style:TextStyle(fontSize:15,color:c.text,fontWeight:FontWeight.w700)))]),
      const SizedBox(height:4),Text(subtitle,style:TextStyle(fontSize:11,color:c.muted)),
      const SizedBox(height:12),
    ]);
  }
}
class _ConnectionCard extends StatelessWidget {
  final PrototypeState app;
  final ValueChanged<String> onDemo;
  const _ConnectionCard({required this.app,required this.onDemo});
  @override Widget build(BuildContext context) {
    final c=LiquidColors(Theme.of(context).brightness==Brightness.light);
    return GlassPanel(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      const _PanelHeading(title:'Connection',subtitle:'LAN discovery · secure pairing lab',icon:Icons.shield_outlined),
      Row(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Expanded(child:Column(children:[
          for(final d in app.connectionDevices)Padding(padding:const EdgeInsets.only(bottom:6),
            child:Container(padding:const EdgeInsets.all(8),decoration:BoxDecoration(color:c.panel,borderRadius:BorderRadius.circular(7)),
              child:Row(children:[Icon(d.windows?Icons.computer:Icons.phone_android,size:14,color:c.text),
                const SizedBox(width:5),Expanded(child:Text(d.name,maxLines:1,overflow:TextOverflow.ellipsis,
                  style:TextStyle(fontSize:10,color:c.text))),Text(app.lan.peers.isEmpty?'Demo':'Unpaired',style:const TextStyle(fontSize:9,color:Color(0xFF50EEB2)))]))),
          const SizedBox(height:7),LiquidAction(label:'Manual IP',icon:Icons.add,gradient:true,
            onTap:()=>_showManualIpDialog(context,app,onDemo)),
        ])),const SizedBox(width:10),Column(children:[
          Container(width:103,height:103,padding:const EdgeInsets.all(6),color:Colors.white,child:CustomPaint(painter:_DemoQrPainter())),
          const SizedBox(height:5),Text('QR placeholder',style:TextStyle(fontSize:9,color:c.muted)),
        ]),
      ]),
    ]));
  }
}
class _DemoQrPainter extends CustomPainter {
  @override void paint(Canvas canvas,Size size){
    final cell=size.width/21;
    final p=Paint()..color=Colors.black;
    for(var y=0;y<21;y++){
      for(var x=0;x<21;x++){
        if(((x*y+3*x+7*y)%9)<4){
          canvas.drawRect(Rect.fromLTWH(x*cell,y*cell,cell*.93,cell*.93),p);
        }
      }
    }
    canvas.drawRect(Rect.fromCenter(center:Offset(size.width/2,size.height/2),width:50,height:18),Paint()..color=Colors.white);
    final t=TextPainter(text:const TextSpan(text:'DEMO',style:TextStyle(color:Color(0xFF215EC6),fontSize:12,fontWeight:FontWeight.bold)),
      textDirection:TextDirection.ltr)..layout();
    t.paint(canvas,Offset(size.width/2-t.width/2,size.height/2-t.height/2));
  }
  @override bool shouldRepaint(covariant _DemoQrPainter oldDelegate)=>false;
}
class _FileCard extends StatelessWidget {
  final PrototypeState app;
  const _FileCard({required this.app});
  @override Widget build(BuildContext context) {
    final c = LiquidColors(app.lightMode);
    final active = app.fileTransferActive;
    final total = app.fileTotalBytes;
    final sent = app.fileTransferredBytes;
    return GlassPanel(child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _PanelHeading(title:'File Transfer',
          subtitle:'Android → Windows · one-shot encrypted lab',
          icon:Icons.folder_copy_outlined),
        Container(
          padding:const EdgeInsets.all(14),
          decoration:BoxDecoration(color:c.panel,
            borderRadius:BorderRadius.circular(10),
            border:Border.all(color:c.border)),
          child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            Text(active ? 'Transferring: $sent / $total bytes' :
              app.fileTransferVerified ? 'Last transfer verified by receiver' :
              'Choose a file with the Android system picker',
              style:TextStyle(color:c.text,fontWeight:FontWeight.w600)),
            const SizedBox(height:10),
            LinearProgressIndicator(value:total > 0 ? (sent/total).clamp(0.0,1.0).toDouble() : (active ? null : 0.0),
              minHeight:5),
            const SizedBox(height:8),
            Text('Maximum 64 MiB. Select a discovered Windows host running the Node lab with --listen --receive-file=<folder>. Verify six-digit pairing on both devices; the Windows receiver must type FILE to approve.',
              style:TextStyle(color:c.muted,fontSize:11)),
            const SizedBox(height:6),
            Text('No background file access, no Android receiver yet. The custom lab handshake is not approved for production.',
              style:TextStyle(color:c.muted,fontSize:10)),
          ]),
        ),
        const SizedBox(height:10),
        Align(alignment:Alignment.centerLeft,child:LiquidAction(
          label:active ? 'Transfer in progress' : 'Choose file and send',
          gradient:true,
          onTap:() async {
            if (app.fileTransferActive) return;
            try {
              final file = await openFile();
              if (file == null) return;
              final result = await app.sendFileSelected(
                (challenge) => _pairDialog(context, challenge), file);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content:Text('Windows verified ${result.bytes} bytes · SHA-256 ${result.sha256.substring(0,16)}…')));
              }
            } catch (e) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content:Text('File was NOT transferred: $e')));
              }
            }
          },
        )),
      ],
    ));
  }
}
class _ClipboardCard extends StatelessWidget {
  final PrototypeState app;
  const _ClipboardCard({required this.app});
  @override Widget build(BuildContext context) {
    final c=LiquidColors(app.lightMode);
    return GlassPanel(child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      const _PanelHeading(title:'Shared Clipboard',subtitle:'Android → Android/Windows · manual text · receiver approval required',icon:Icons.content_paste_outlined),
      Container(height:115,padding:const EdgeInsets.all(9),decoration:BoxDecoration(color:c.panel,borderRadius:BorderRadius.circular(10),border:Border.all(color:c.border)),
        child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          const Text('Android ↔ Android / Windows',style:TextStyle(fontSize:11,fontWeight:FontWeight.w700,color:LiquidColors.aqua)),
          Expanded(child:TextFormField(initialValue:app.clipboardText,onChanged:app.setClipboardText,
            maxLines:2,style:TextStyle(fontSize:11,color:c.text),
            decoration:InputDecoration(contentPadding:const EdgeInsets.all(7),filled:true,fillColor:c.panelDark,
              border:const OutlineInputBorder(borderSide:BorderSide.none)))),
        ])),const SizedBox(height:10),
       Text('Select a discovered Android or Windows device, or use Devices → Add device by IP → Send text IP. Android receivers must have this app open and approve both dialogs. On Windows run the LAN agent with --listen --receive-clipboard and approve CLIP. Every transfer requires new consent.',
         style:TextStyle(color:c.muted,fontSize:11)),
       const SizedBox(height:10),
       Align(alignment:Alignment.centerLeft,child:LiquidAction(label:'Send text to selected device',gradient:true,
         onTap:() async {
           try {
             await app.sendClipboardSelected((challenge) => _pairDialog(context, challenge));
             if (context.mounted) {
               ScaffoldMessenger.of(context).showSnackBar(
                 const SnackBar(content:Text('Receiver approved and wrote clipboard text')));
             }
           } catch (e) {
             if (context.mounted) {
               ScaffoldMessenger.of(context).showSnackBar(
                 SnackBar(content:Text('Clipboard not transferred: $e')));
             }
           }
         })),
    ]));
  }
}
class _SettingsCard extends StatelessWidget {
  final PrototypeState app;
  const _SettingsCard({required this.app});
  @override Widget build(BuildContext context) {
    final c=LiquidColors(app.lightMode);
    return GlassPanel(child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      const _PanelHeading(title:'Themes & Customization',subtitle:'Liquid Fusion · visual preferences',icon:Icons.palette_outlined),
      Wrap(spacing:10,runSpacing:10,children:[
        LiquidAction(label:'Dark mode',active:!app.lightMode,onTap:()=>app.setLight(false)),
        LiquidAction(label:'Light mode',active:app.lightMode,onTap:()=>app.setLight(true)),
      ]),const SizedBox(height:12),
      Row(children:[Expanded(child:Text('Reduce motion (recommended during remote sessions)',
        style:TextStyle(color:c.text,fontSize:12))),Switch(value:app.reduceMotion,onChanged:app.setReduceMotion)]),
      Text('View-only MJPEG diagnostic stream is implemented. Production H.264/WebRTC is not.',
        style:TextStyle(color:c.muted,fontSize:11)),
      const SizedBox(height: 18),
      Text('Trusted device identities · experimental',
        style:TextStyle(color:c.text,fontWeight:FontWeight.w700)),
      const SizedBox(height: 7),
      Text('Recorded after encrypted PING. Trust does not grant control, files or unattended access.',
        style:TextStyle(color:c.muted,fontSize:11)),
      const SizedBox(height: 9),
      if(app.pairing.trusted.isEmpty)
        Text('No paired devices',style:TextStyle(color:c.muted,fontSize:11)),
      ...app.pairing.trusted.keys.map((fingerprint)=>Row(children:[
        Expanded(child:Text('${fingerprint.substring(0,20)}…',style:TextStyle(color:c.text,fontSize:11))),
        TextButton.icon(onPressed:()=>app.pairing.revoke(fingerprint),
          icon:const Icon(Icons.block,size:14), label:const Text('Revoke')),
      ])),
    ]));
  }
}
