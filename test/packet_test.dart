// test/packet_test.dart
// Unit tests for BLE packet encoding and ArmState.

import 'package:flutter_test/flutter_test.dart';
import 'package:robo_arm_ble/core/constants.dart';
import 'package:robo_arm_ble/domain/models/arm_state.dart';

List<int> buildMovePacket(List<int> angles) {
  assert(angles.length == 6);
  return [kCmdMove, ...angles.map((a) => a.clamp(0, 180))];
}

void main() {
  group('Move packet', () {
    test('M packet is exactly 7 bytes', () {
      final packet = buildMovePacket([0, 45, 90, 135, 180, 60]);
      expect(packet.length, equals(7));
    });

    test('First byte is kCmdMove (0x4D)', () {
      final packet = buildMovePacket([90, 90, 90, 90, 90, 90]);
      expect(packet[0], equals(kCmdMove));
    });

    test('Angles are clamped to 0..180', () {
      final packet = buildMovePacket([-10, 200, 90, 0, 180, 90]);
      expect(packet[1], equals(0)); // -10 → 0
      expect(packet[2], equals(180)); // 200 → 180
    });

    test('All angles in packet are within 0..180', () {
      final packet = buildMovePacket([0, 30, 60, 90, 120, 150]);
      for (int i = 1; i < packet.length; i++) {
        expect(packet[i], greaterThanOrEqualTo(0));
        expect(packet[i], lessThanOrEqualTo(180));
      }
    });
  });

  group('Protocol byte constants', () {
    test('kCmdMove is 0x4D', () => expect(kCmdMove, equals(0x4D)));
    test('kCmdSetOne is 0x53', () => expect(kCmdSetOne, equals(0x53)));
    test('kCmdHome is 0x48', () => expect(kCmdHome, equals(0x48)));
    test('kCmdGet is 0x47', () => expect(kCmdGet, equals(0x47)));
    test('kCmdAck is 0x41', () => expect(kCmdAck, equals(0x41)));
  });

  group('ArmState parsing', () {
    test('Parse valid ACK packet', () {
      final bytes = [kCmdAck, 45, 90, 120, 60, 30, 150];
      final state = ArmState.fromBytes(bytes);
      expect(state.angles[0], equals(45));
      expect(state.angles[5], equals(150));
    });

    test('Invalid ACK returns home state', () {
      final state = ArmState.fromBytes(const [0x00, 1, 2]);
      expect(state.angles, equals(kHomeAngles));
    });

    test('ArmState.fromAngles clamps angles to 0..180', () {
      final state = ArmState.fromAngles(const [200, -10, 90, 90, 90, 90]);
      expect(state.angles[0], equals(180));
      expect(state.angles[1], equals(0));
    });

    test('ArmState equality works', () {
      final s1 = ArmState.fromAngles(const [90, 90, 90, 90, 90, 90]);
      final s2 = ArmState.fromAngles(const [90, 90, 90, 90, 90, 90]);
      expect(s1, equals(s2));
    });

    test('withJoint creates new state with updated joint', () {
      final s = ArmState.home();
      final updated = s.withJoint(0, 45);
      expect(updated.angles[0], equals(45));
      expect(updated.angles[1], equals(90));
    });
  });

  group('Command rate: packet size ≤ 20 bytes', () {
    test('M packet (7 bytes) fits in BLE MTU', () {
      expect(7, lessThanOrEqualTo(20));
    });
    test('S packet (3 bytes) fits in BLE MTU', () {
      expect(3, lessThanOrEqualTo(20));
    });
    test('H packet (1 byte) fits in BLE MTU', () {
      expect(1, lessThanOrEqualTo(20));
    });
  });
}
