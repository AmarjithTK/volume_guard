import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const VolumeApp());
}

class VolumeApp extends StatefulWidget {
  const VolumeApp({super.key});

  @override
  State<VolumeApp> createState() => VolumeAppState();

  static VolumeAppState? of(BuildContext context) =>
      context.findAncestorStateOfType<VolumeAppState>();
}

class VolumeAppState extends State<VolumeApp> {
  ThemeMode _themeMode = ThemeMode.system;

  void toggleTheme() {
    setState(() {
      final isDark = _themeMode == ThemeMode.dark ||
          (_themeMode == ThemeMode.system &&
              WidgetsBinding.instance.platformDispatcher.platformBrightness ==
                  Brightness.dark);
      _themeMode = isDark ? ThemeMode.light : ThemeMode.dark;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Volume Guard',
      debugShowCheckedModeBanner: false,
      themeMode: _themeMode,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.deepPurple, brightness: Brightness.light),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.deepPurple, brightness: Brightness.dark),
        useMaterial3: true,
      ),
      home: const VolumeHomePage(),
    );
  }
}

class VolumeHomePage extends StatefulWidget {
  const VolumeHomePage({super.key});

  @override
  State<VolumeHomePage> createState() => _VolumeHomePageState();
}

class _VolumeHomePageState extends State<VolumeHomePage> {
  static const _channel =
      MethodChannel('com.example.volume_controller/service');
  static const _eventChannel =
      EventChannel('com.example.volume_controller/events');

  late SharedPreferences _prefs;
  bool _isLoading = true;
  StreamSubscription? _eventSub;

  bool _isServiceEnabled = false;

  RangeValues _mediaRange = const RangeValues(0, 100);
  RangeValues _ringRange = const RangeValues(0, 100);
  RangeValues _alarmRange = const RangeValues(0, 100);
  RangeValues _notifRange = const RangeValues(0, 100);
  RangeValues _brightnessRange = const RangeValues(0, 100);

  double _btLaunchValue = 30;
  bool _btLocked = false;
  bool _mediaLocked = false;
  bool _ringLocked = false;
  bool _alarmLocked = false;
  bool _notifLocked = false;
  bool _brightnessLocked = false;

  double _liveMedia = 0, _liveRing = 0, _liveAlarm = 0, _liveNotif = 0,
      _liveBrightness = 0;

  @override
  void initState() {
    super.initState();
    _initPrefs();
    _eventSub = _eventChannel.receiveBroadcastStream().listen((event) {
      if (event is Map) {
        setState(() {
          _liveMedia = (event['music'] as double?) ?? _liveMedia;
          _liveRing = (event['ring'] as double?) ?? _liveRing;
          _liveAlarm = (event['alarm'] as double?) ?? _liveAlarm;
          _liveNotif = (event['notification'] as double?) ?? _liveNotif;
          _liveBrightness = (event['brightness'] as double?) ?? _liveBrightness;
          // Sync lock states from notification button toggles
          if (event.containsKey('media_locked')) {
            _mediaLocked = event['media_locked'] as bool;
            _prefs.setBool('media_lock_enabled', _mediaLocked);
          }
          if (event.containsKey('ring_locked')) {
            _ringLocked = event['ring_locked'] as bool;
            _prefs.setBool('ring_lock_enabled', _ringLocked);
          }
          if (event.containsKey('bt_locked')) {
            _btLocked = event['bt_locked'] as bool;
            _prefs.setBool('bt_lock_enabled', _btLocked);
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    super.dispose();
  }

  Future<void> _initPrefs() async {
    _prefs = await SharedPreferences.getInstance();

    RangeValues _rng(String k1, String k2) => RangeValues(
          _prefs.getInt(k1)?.toDouble() ?? 0.0,
          _prefs.getInt(k2)?.toDouble() ?? 100.0,
        );

    setState(() {
      _mediaRange = _rng('media_lock_min', 'media_lock_max');
      _ringRange = _rng('ring_lock_min', 'ring_lock_max');
      _alarmRange = _rng('alarm_lock_min', 'alarm_lock_max');
      _notifRange = _rng('notif_lock_min', 'notif_lock_max');
      _brightnessRange = _rng('brightness_min_value', 'brightness_max_value');
      _btLaunchValue = _prefs.getInt('bt_launch_volume')?.toDouble() ?? 30.0;

      // Save defaults
      void si(String k, int v) => _prefs.setInt(k, v);
      si('media_lock_min', _mediaRange.start.toInt());
      si('media_lock_max', _mediaRange.end.toInt());
      si('ring_lock_min', _ringRange.start.toInt());
      si('ring_lock_max', _ringRange.end.toInt());
      si('alarm_lock_min', _alarmRange.start.toInt());
      si('alarm_lock_max', _alarmRange.end.toInt());
      si('notif_lock_min', _notifRange.start.toInt());
      si('notif_lock_max', _notifRange.end.toInt());
      si('brightness_min_value', _brightnessRange.start.toInt());
      si('brightness_max_value', _brightnessRange.end.toInt());
      si('bt_launch_volume', _btLaunchValue.toInt());

      _mediaLocked = _prefs.getBool('media_lock_enabled') ?? false;
      _ringLocked = _prefs.getBool('ring_lock_enabled') ?? false;
      _alarmLocked = _prefs.getBool('alarm_lock_enabled') ?? false;
      _notifLocked = _prefs.getBool('notif_lock_enabled') ?? false;
      _brightnessLocked =
          _prefs.getBool('brightness_min_lock_enabled') ?? false;
      _btLocked = _prefs.getBool('bt_lock_enabled') ?? false;
      _isServiceEnabled = _prefs.getBool('master_service_enabled') ?? false;
      _isLoading = false;
    });
    if (_isServiceEnabled) _startService();
  }

  Future<void> _requestPermissions() async {
    await Permission.notification.request();
    await Permission.accessNotificationPolicy.request();
    try {
      final bool ok = await _channel.invokeMethod('hasWriteSettingsPermission');
      if (!ok) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Grant Write Settings for brightness control.')));
        }
        await _channel.invokeMethod('requestWriteSettingsPermission');
      }
    } catch (_) {}
  }

  Future<void> _startService() async {
    await _requestPermissions();
    try {
      final bool enabled =
          await _channel.invokeMethod('isAccessibilityEnabled');
      if (!enabled) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text(
                  'Enable Volume Controller in Accessibility Settings')));
        }
        await _channel.invokeMethod('requestAccessibility');
      } else {
        await _channel.invokeMethod('startService');
      }
    } catch (_) {}
  }

  Future<void> _stopService() async {
    try {
      await _channel.invokeMethod('stopService');
    } catch (_) {}
  }

  void _onMasterToggle(bool v) {
    setState(() => _isServiceEnabled = v);
    _prefs.setBool('master_service_enabled', v);
    if (v) {
      _startService();
    } else {
      _stopService();
    }
  }

  void _sb(String k, bool v) => _prefs.setBool(k, v);
  void _si(String k, double v) => _prefs.setInt(k, v.toInt());

  // ---- Compact Range Row ----
  Widget _rangeCard({
    required String title,
    required IconData icon,
    required RangeValues values,
    required bool isLocked,
    required double live,
    required ValueChanged<RangeValues> onChanged,
    required ValueChanged<RangeValues> onEnd,
    required ValueChanged<bool> onToggle,
    required String minKey,
    required String maxKey,
    required String lockKey,
  }) {
    final cs = Theme.of(context).colorScheme;
    final active = isLocked ? cs.primary : cs.secondary;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isLocked ? cs.primary.withOpacity(0.4) : Colors.transparent,
          width: 1.5,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 4),
        child: Column(
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: isLocked ? cs.primary : cs.onSurfaceVariant),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w600)),
                      if (!isLocked)
                        Text('Live: ${live.round()}%',
                            style: TextStyle(
                                fontSize: 11,
                                color: cs.secondary,
                                fontWeight: FontWeight.w500)),
                    ],
                  ),
                ),
                Transform.scale(
                  scale: 0.8,
                  child: Switch.adaptive(
                    value: isLocked,
                    onChanged: (v) {
                      onToggle(v);
                      _sb(lockKey, v);
                    },
                    activeColor: cs.primary,
                  ),
                ),
              ],
            ),
            Row(
              children: [
                SizedBox(
                    width: 30,
                    child: Text('${values.start.round()}%',
                        style: const TextStyle(fontSize: 10),
                        textAlign: TextAlign.center)),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 4,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                      activeTrackColor: active,
                      thumbColor: active,
                      rangeThumbShape: const RoundRangeSliderThumbShape(enabledThumbRadius: 7),
                      rangeTrackShape: const RoundedRectRangeSliderTrackShape(),
                    ),
                    child: RangeSlider(
                      values: values,
                      min: 0,
                      max: 100,
                      divisions: 100,
                      onChanged: onChanged,
                      onChangeEnd: (v) {
                        onEnd(v);
                        _si(minKey, v.start);
                        _si(maxKey, v.end);
                      },
                    ),
                  ),
                ),
                SizedBox(
                    width: 30,
                    child: Text('${values.end.round()}%',
                        style: const TextStyle(fontSize: 10),
                        textAlign: TextAlign.center)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ---- Compact Single Slider Card ----
  Widget _singleCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required double value,
    required bool isLocked,
    required ValueChanged<double> onChanged,
    required ValueChanged<double> onEnd,
    required ValueChanged<bool> onToggle,
    required String valueKey,
    required String lockKey,
  }) {
    final cs = Theme.of(context).colorScheme;
    final active = isLocked ? cs.primary : cs.secondary;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isLocked ? cs.primary.withOpacity(0.4) : Colors.transparent,
          width: 1.5,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 4),
        child: Column(
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: isLocked ? cs.primary : cs.onSurfaceVariant),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w600)),
                      Text(subtitle,
                          style: TextStyle(
                              fontSize: 11, color: cs.onSurfaceVariant)),
                    ],
                  ),
                ),
                Transform.scale(
                  scale: 0.8,
                  child: Switch.adaptive(
                    value: isLocked,
                    onChanged: (v) {
                      onToggle(v);
                      _sb(lockKey, v);
                    },
                    activeColor: cs.primary,
                  ),
                ),
              ],
            ),
            Row(
              children: [
                const SizedBox(width: 30, child: Text('0%', style: TextStyle(fontSize: 10), textAlign: TextAlign.center)),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 4,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                      activeTrackColor: active,
                      thumbColor: active,
                    ),
                    child: Slider(
                      value: value,
                      min: 0,
                      max: 100,
                      divisions: 100,
                      onChanged: onChanged,
                      onChangeEnd: (v) {
                        onEnd(v);
                        _si(valueKey, v);
                      },
                    ),
                  ),
                ),
                SizedBox(
                    width: 30,
                    child: Text('${value.round()}%',
                        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: const Text('Volume Guard', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        actions: [
          IconButton(
            icon: const Icon(Icons.brightness_6, size: 20),
            onPressed: () => VolumeApp.of(context)?.toggleTheme(),
          ),
        ],
        centerTitle: false,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        children: [
          // Master Switch — compact banner
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: _isServiceEnabled
                    ? [cs.primaryContainer, cs.secondaryContainer]
                    : [cs.surfaceContainerHighest, cs.surfaceContainerHighest],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: _isServiceEnabled
                  ? [BoxShadow(color: cs.primary.withOpacity(0.18), blurRadius: 10, offset: const Offset(0, 3))]
                  : [],
            ),
            child: Row(
              children: [
                Icon(
                  _isServiceEnabled ? Icons.shield : Icons.shield_outlined,
                  size: 26,
                  color: _isServiceEnabled ? cs.onPrimaryContainer : cs.onSurfaceVariant,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Background Protection',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: _isServiceEnabled ? cs.onPrimaryContainer : cs.onSurfaceVariant)),
                      Text(_isServiceEnabled ? 'Active & Monitoring' : 'Disabled',
                          style: TextStyle(
                              fontSize: 11,
                              color: _isServiceEnabled ? cs.onPrimaryContainer : cs.onSurfaceVariant)),
                    ],
                  ),
                ),
                Transform.scale(
                  scale: 0.85,
                  child: Switch.adaptive(
                    value: _isServiceEnabled,
                    onChanged: _onMasterToggle,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Bluetooth Section
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text('Bluetooth Protection',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: cs.onSurfaceVariant)),
          ),
          _singleCard(
            title: 'Initial Connect Limit',
            subtitle: 'Caps volume when headset connects',
            icon: Icons.bluetooth_audio,
            value: _btLaunchValue,
            isLocked: _btLocked,
            onChanged: (v) => setState(() => _btLaunchValue = v),
            onEnd: (v) {},
            onToggle: (v) => setState(() => _btLocked = v),
            valueKey: 'bt_launch_volume',
            lockKey: 'bt_lock_enabled',
          ),
          const SizedBox(height: 10),

          // Audio Section
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text('Audio & Screen Range Limits',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: cs.onSurfaceVariant)),
          ),
          _rangeCard(
            title: 'Media Volume',
            icon: Icons.music_note,
            values: _mediaRange,
            isLocked: _mediaLocked,
            live: _liveMedia,
            onChanged: (v) => setState(() => _mediaRange = v),
            onEnd: (v) {},
            onToggle: (v) => setState(() => _mediaLocked = v),
            minKey: 'media_lock_min',
            maxKey: 'media_lock_max',
            lockKey: 'media_lock_enabled',
          ),
          _rangeCard(
            title: 'Ringtone & Calls',
            icon: Icons.phone_in_talk,
            values: _ringRange,
            isLocked: _ringLocked,
            live: _liveRing,
            onChanged: (v) => setState(() => _ringRange = v),
            onEnd: (v) {},
            onToggle: (v) => setState(() => _ringLocked = v),
            minKey: 'ring_lock_min',
            maxKey: 'ring_lock_max',
            lockKey: 'ring_lock_enabled',
          ),
          _rangeCard(
            title: 'Alarm Volume',
            icon: Icons.access_alarms,
            values: _alarmRange,
            isLocked: _alarmLocked,
            live: _liveAlarm,
            onChanged: (v) => setState(() => _alarmRange = v),
            onEnd: (v) {},
            onToggle: (v) => setState(() => _alarmLocked = v),
            minKey: 'alarm_lock_min',
            maxKey: 'alarm_lock_max',
            lockKey: 'alarm_lock_enabled',
          ),
          _rangeCard(
            title: 'Notifications',
            icon: Icons.notifications_active,
            values: _notifRange,
            isLocked: _notifLocked,
            live: _liveNotif,
            onChanged: (v) => setState(() => _notifRange = v),
            onEnd: (v) {},
            onToggle: (v) => setState(() => _notifLocked = v),
            minKey: 'notif_lock_min',
            maxKey: 'notif_lock_max',
            lockKey: 'notif_lock_enabled',
          ),
          _rangeCard(
            title: 'Screen Brightness',
            icon: Icons.brightness_high,
            values: _brightnessRange,
            isLocked: _brightnessLocked,
            live: _liveBrightness,
            onChanged: (v) => setState(() => _brightnessRange = v),
            onEnd: (v) {},
            onToggle: (v) => setState(() => _brightnessLocked = v),
            minKey: 'brightness_min_value',
            maxKey: 'brightness_max_value',
            lockKey: 'brightness_min_lock_enabled',
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}
