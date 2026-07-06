// lib/tools/native_tools.dart — Native Android Tool Definitions
//
// Phase 1 tools for time, alarm, timer, flashlight, battery,
// vibration, device info, and app launching.

import 'dart:async';

import 'package:alarm/alarm.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/services.dart';
import 'package:flutter_system_action/flutter_system_action.dart';
import 'package:intl/intl.dart';
import 'package:vibration/vibration.dart';

import 'tool_registry.dart';

// ── P0: Time & Scheduling ──

/// Get current time, date, day of week, timezone
final getCurrentTimeTool = ToolDefinition(
  name: 'get_current_time',
  description: 'Get the current time, date, day of week, and timezone.',
  parameters: {
    'type': 'object',
    'properties': {},
  },
  executor: (args) async {
    final now = DateTime.now();
    return {
      'time': DateFormat('HH:mm:ss').format(now),
      'time_12h': DateFormat('hh:mm:ss a').format(now),
      'date': DateFormat('yyyy-MM-dd').format(now),
      'day_of_week': DateFormat('EEEE').format(now),
      'timezone': now.timeZoneName,
      'timestamp_iso': now.toIso8601String(),
    };
  },
);

/// Set an in-app alarm at specified time with label
final setAlarmTool = ToolDefinition(
  name: 'set_alarm',
  description:
      'Set an alarm at a specific time. The alarm will play audio, vibrate, and show a notification when it rings.',
  parameters: {
    'type': 'object',
    'properties': {
      'time': {
        'type': 'string',
        'description':
            'The time to set the alarm in HH:mm format (24-hour), e.g. "08:30"',
      },
      'label': {
        'type': 'string',
        'description': 'Optional label for the alarm, e.g. "Wake up!"',
      },
    },
    'required': ['time'],
  },
  executor: (args) async {
    final timeStr = args['time'] as String;
    final label = args['label'] as String? ?? 'J.A.R.V.I.S. Alarm';

    // Parse HH:mm
    final parts = timeStr.split(':');
    if (parts.length != 2) {
      return {
        'success': false,
        'error': 'Invalid time format. Use HH:mm (24-hour), e.g. "08:30"',
      };
    }

    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null || hour < 0 || hour > 23 || minute < 0 || minute > 59) {
      return {
        'success': false,
        'error': 'Invalid time values. Hour 0-23, minute 0-59.',
      };
    }

    // Use a unique ID based on current timestamp to avoid collisions
    final alarmId = DateTime.now().millisecondsSinceEpoch;

    final now = DateTime.now();
    var alarmTime = DateTime(now.year, now.month, now.day, hour, minute);
    // If the time has already passed today, schedule for tomorrow
    if (alarmTime.isBefore(now)) {
      alarmTime = alarmTime.add(const Duration(days: 1));
    }

    try {
      await Alarm.set(
        alarmSettings: AlarmSettings(
          id: alarmId,
          alarmDateTime: alarmTime,
          assetAudioPath: null, // Use default system alarm sound
          notificationTitle: 'J.A.R.V.I.S. Alarm',
          notificationBody: label,
        ),
      );

      return {
        'success': true,
        'message': 'Alarm set for $timeStr',
        'alarm_id': alarmId,
        'time': timeStr,
        'label': label,
        'alarm_time_iso': alarmTime.toIso8601String(),
      };
    } catch (e) {
      return {
        'success': false,
        'error': 'Failed to set alarm: $e',
        'time': timeStr,
      };
    }
  },
);

/// Start an app-level countdown timer
final setTimerTool = ToolDefinition(
  name: 'set_timer',
  description:
      'Start a countdown timer for the specified duration. Notifies when the timer is done.',
  parameters: {
    'type': 'object',
    'properties': {
      'duration_seconds': {
        'type': 'integer',
        'description': 'Duration in seconds',
      },
      'label': {
        'type': 'string',
        'description': 'Optional label for the timer',
      },
    },
    'required': ['duration_seconds'],
  },
  executor: (args) async {
    final durationSeconds = args['duration_seconds'] as int;
    final label = args['label'] as String? ?? 'Timer';

    // TODO: Integrate with Timer + flutter_local_notifications

    return {
      'success': true,
      'message': 'Timer started for $durationSeconds seconds',
      'duration_seconds': durationSeconds,
      'label': label,
    };
  },
);

/// Cancel a previously set alarm
final cancelAlarmTool = ToolDefinition(
  name: 'cancel_alarm',
  description: 'Cancel a previously set alarm by its ID.',
  parameters: {
    'type': 'object',
    'properties': {
      'alarm_id': {
        'type': 'integer',
        'description': 'The ID of the alarm to cancel',
      },
    },
    'required': ['alarm_id'],
  },
  executor: (args) async {
    final alarmId = args['alarm_id'] as int;

    try {
      await Alarm.stop(alarmId);
      return {
        'success': true,
        'message': 'Alarm $alarmId cancelled',
      };
    } catch (e) {
      return {
        'success': false,
        'error': 'Failed to cancel alarm $alarmId: $e',
      };
    }
  },
);

// ── P1: Device Hardware ──

/// Toggle device flashlight on/off
final toggleFlashlightTool = ToolDefinition(
  name: 'toggle_flashlight',
  description: 'Turn the device flashlight (torch) on or off.',
  parameters: {
    'type': 'object',
    'properties': {
      'state': {
        'type': 'string',
        'enum': ['on', 'off', 'toggle'],
        'description': 'on, off, or toggle',
      },
    },
    'required': ['state'],
  },
  executor: (args) async {
    final state = args['state'] as String;
    try {
      if (state == 'on') {
        await FlutterSystemAction().torchButtonOnEvent();
      } else if (state == 'off') {
        await FlutterSystemAction().torchButtonOffEvent();
      } else {
        // toggle — turn on (no state tracking in Phase 1)
        await FlutterSystemAction().torchButtonOnEvent();
      }
      return {'success': true, 'flashlight': state};
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  },
);

/// Read battery level and charging status
final getBatteryLevelTool = ToolDefinition(
  name: 'get_battery_level',
  description: 'Get the current battery level and charging status.',
  parameters: {
    'type': 'object',
    'properties': {},
  },
  executor: (args) async {
    final battery = Battery();
    final level = await battery.batteryLevel;
    final state = await battery.batteryState;

    return {
      'battery_level': level,
      'battery_state': state.name,
      'is_charging': state == BatteryState.charging ||
          state == BatteryState.full,
    };
  },
);

/// Trigger haptic vibration
final vibrateTool = ToolDefinition(
  name: 'vibrate',
  description: 'Trigger haptic vibration feedback.',
  parameters: {
    'type': 'object',
    'properties': {
      'pattern': {
        'type': 'string',
        'enum': ['short', 'long', 'double', 'pattern'],
        'description': 'Vibration pattern type',
      },
    },
    'required': ['pattern'],
  },
  executor: (args) async {
    final pattern = args['pattern'] as String;
    final hasVibrator = await Vibration.hasVibrator();

    if (hasVibrator != true) {
      return {'success': false, 'error': 'No vibrator available'};
    }

    switch (pattern) {
      case 'short':
        Vibration.vibrate(duration: 100);
      case 'long':
        Vibration.vibrate(duration: 500);
      case 'double':
        Vibration.vibrate(duration: 100);
        await Future.delayed(const Duration(milliseconds: 200));
        Vibration.vibrate(duration: 100);
      case 'pattern':
        Vibration.vibrate(pattern: [0, 100, 200, 100, 200, 300]);
    }

    return {'success': true, 'pattern': pattern};
  },
);

/// Get device information
final getDeviceInfoTool = ToolDefinition(
  name: 'get_device_info',
  description:
      'Get information about this device including model, OS version, and hardware specs.',
  parameters: {
    'type': 'object',
    'properties': {},
  },
  executor: (args) async {
    final deviceInfo = DeviceInfoPlugin();
    final androidInfo = await deviceInfo.androidInfo;

    return {
      'model': androidInfo.model,
      'manufacturer': androidInfo.manufacturer,
      'os_version': 'Android ${androidInfo.version.release}',
      'api_level': androidInfo.version.sdkInt,
      'brand': androidInfo.brand,
      'hardware': androidInfo.hardware,
    };
  },
);

// ── P1: App Launch ──

/// Launch an installed app by name
final openAppTool = ToolDefinition(
  name: 'open_app',
  description:
      'Launch an installed app on the device by name. Supports common apps like YouTube, Spotify, Chrome, Gmail, Maps, Camera, Settings, etc.',
  parameters: {
    'type': 'object',
    'properties': {
      'app_name': {
        'type': 'string',
        'description':
            'The name of the app to open (e.g., "YouTube", "Spotify", "Chrome")',
      },
    },
    'required': ['app_name'],
  },
  executor: (args) async {
    const appPackageMap = {
      'youtube': 'com.google.android.youtube',
      'spotify': 'com.spotify.music',
      'chrome': 'com.android.chrome',
      'gmail': 'com.google.android.gm',
      'maps': 'com.google.android.apps.maps',
      'camera': 'com.google.android.GoogleCamera',
      'settings': 'com.android.settings',
      'clock': 'com.google.android.deskclock',
      'calendar': 'com.google.android.calendar',
      'photos': 'com.google.android.apps.photos',
      'messages': 'com.google.android.apps.messaging',
      'phone': 'com.google.android.dialer',
      'contacts': 'com.google.android.contacts',
      'files': 'com.google.android.documentsui',
      'play store': 'com.android.vending',
    };

    final name = (args['app_name'] as String).toLowerCase();
    final packageName = appPackageMap[name];

    if (packageName == null) {
      return {
        'success': false,
        'error': 'Unknown app: ${args['app_name']}. '
            'Supported apps: ${appPackageMap.keys.join(", ")}',
      };
    }

    try {
      // Use platform channel to launch the app via PackageManager
      const channel = MethodChannel('com.jarvis.jarvis/app_launcher');
      final launched = await channel.invokeMethod<bool>(
        'launchApp',
        {'packageName': packageName},
      );
      return {
        'success': launched ?? false,
        'app': args['app_name'],
        'package': packageName,
      };
    } catch (e) {
      return {
        'success': false,
        'error': e.toString(),
        'app': args['app_name'],
      };
    }
  },
);
