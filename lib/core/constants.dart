// lib/core/constants.dart
// BLE UUIDs and protocol constants for the RobotArm-BLE ESP32 firmware.

/// Nordic UART-style service UUID.
const String kServiceUUID = '6E400001-B5A3-F393-E0A9-E50E24DCCA9E';

/// RX characteristic – phone writes to this (write-without-response preferred).
const String kRxCharUUID = '6E400002-B5A3-F393-E0A9-E50E24DCCA9E';

/// TX characteristic – ESP32 notifies; phone subscribes for incoming data.
const String kTxCharUUID = '6E400003-B5A3-F393-E0A9-E50E24DCCA9E';

/// Advertised BLE device name.
const String kDeviceName = 'RobotArm-BLE';

// ── Protocol bytes ──────────────────────────────────────────────────────────

/// Command byte: set all 6 servo angles at once (7 bytes total).
const int kCmdMove = 0x4D; // 'M'

/// Command byte: set a single servo (3 bytes total).
const int kCmdSetOne = 0x53; // 'S'

/// Command byte: go to home position (all 90°, 1 byte).
const int kCmdHome = 0x48; // 'H'

/// Command byte: request current state (1 byte).
const int kCmdGet = 0x47; // 'G'

/// Response byte: current state response from ESP32 (7 bytes).
const int kCmdAck = 0x41; // 'A'

// ── Joint indices ───────────────────────────────────────────────────────────

const int kJointBase = 0;
const int kJointShoulder = 1;
const int kJointElbow = 2;
const int kJointWristPitch = 3;
const int kJointWristRot = 4;
const int kJointGripper = 5;

const List<String> kJointNames = [
  'Base',
  'Shoulder',
  'Elbow',
  'Wrist Pitch',
  'Wrist Rot.',
  'Gripper',
];

const List<String> kJointIcons = ['🔄', '💪', '🦾', '↕️', '🔃', '✊'];

// ── Motion limits ───────────────────────────────────────────────────────────

/// Firmware moves servos at max 1 deg / 15 ms → ~66 deg/s absolute maximum.
const double kFirmwareMaxDegPerSec = 66.0;

/// Control loop period in Hz.
const int kControlHz = 30;

/// Default joint limits [min, max] in degrees.
const List<List<int>> kDefaultJointLimits = [
  [0, 180], // Base
  [0, 180], // Shoulder
  [0, 180], // Elbow
  [0, 180], // Wrist Pitch
  [0, 180], // Wrist Rot
  [0, 180], // Gripper
];

/// Default home position angles (degrees).
const List<int> kHomeAngles = [90, 90, 90, 90, 90, 90];

// ── Kinematics defaults (mm) ────────────────────────────────────────────────
const double kDefaultD1 = 60.0; // Base height
const double kDefaultL1 = 100.0; // Shoulder → elbow
const double kDefaultL2 = 100.0; // Elbow → wrist
const double kDefaultL3 = 80.0; // Wrist → tip

// ── SharedPreferences keys ──────────────────────────────────────────────────
const String kPrefLastDeviceId = 'last_device_id';
const String kPrefSimMode = 'sim_mode';
const String kPrefDarkMode = 'dark_mode';
const String kPrefSpeedFactor = 'speed_factor';
const String kPrefD1 = 'ik_d1';
const String kPrefL1 = 'ik_l1';
const String kPrefL2 = 'ik_l2';
const String kPrefL3 = 'ik_l3';
const String kPrefCalibration = 'calibration_json';
const String kPrefPoses = 'poses_json';
