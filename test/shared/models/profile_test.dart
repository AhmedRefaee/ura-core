import 'package:flutter_test/flutter_test.dart';
import 'package:ura_core/shared/models/profile.dart';

void main() {
  group('Profile', () {
    const baseMap = <String, dynamic>{
      'id': 'user-123',
      'full_name': 'Ahmed Refaee',
      'phone': '+966501234567',
      'role': 'verifier',
      'is_approved': true,
      'created_at': '2024-01-01T00:00:00.000Z',
    };

    // ─── fromMap ──────────────────────────────────────────────────────────────
    test('fromMap parses all fields correctly', () {
      final p = Profile.fromMap(baseMap);
      expect(p.id, 'user-123');
      expect(p.fullName, 'Ahmed Refaee');
      expect(p.phone, '+966501234567');
      expect(p.role, UserRole.verifier);
      expect(p.isApproved, true);
      expect(p.createdAt, isNotNull);
    });

    // ─── Round-trip ───────────────────────────────────────────────────────────
    test('toMap → fromMap round-trip preserves all fields', () {
      final original = Profile.fromMap(baseMap);
      final roundTripped = Profile.fromMap(original.toMap());
      expect(roundTripped, original);
    });

    // ─── Null / missing fields ────────────────────────────────────────────────
    test('null phone is preserved', () {
      final p = Profile.fromMap({...baseMap, 'phone': null});
      expect(p.phone, isNull);
    });

    test('is_approved defaults to false when missing', () {
      final map = Map<String, dynamic>.from(baseMap)..remove('is_approved');
      final p = Profile.fromMap(map);
      expect(p.isApproved, false);
    });

    test('is_approved false is correctly parsed', () {
      final p = Profile.fromMap({...baseMap, 'is_approved': false});
      expect(p.isApproved, false);
    });

    test('null created_at is preserved', () {
      final p = Profile.fromMap({...baseMap, 'created_at': null});
      expect(p.createdAt, isNull);
    });

    // ─── Empty data ───────────────────────────────────────────────────────────
    test('unapproved profile has isApproved=false', () {
      final p = Profile.fromMap({...baseMap, 'is_approved': false});
      expect(p.isApproved, false);
    });

    // ─── Role parsing ─────────────────────────────────────────────────────────
    group('role parsing', () {
      for (final entry in const {
        'verifier': UserRole.verifier,
        'rep': UserRole.rep,
        'storage_actor': UserRole.storageActor,
        'manager': UserRole.manager,
      }.entries) {
        test('"${entry.key}" → ${entry.value}', () {
          final p = Profile.fromMap({...baseMap, 'role': entry.key});
          expect(p.role, entry.value);
        });
      }

      test('unknown role string → null', () {
        final p = Profile.fromMap({...baseMap, 'role': 'admin'});
        expect(p.role, isNull);
      });

      test('null role → null', () {
        final p = Profile.fromMap({...baseMap, 'role': null});
        expect(p.role, isNull);
      });
    });

    // ─── Equality ─────────────────────────────────────────────────────────────
    test('two profiles with same data are equal', () {
      final a = Profile.fromMap(baseMap);
      final b = Profile.fromMap(baseMap);
      expect(a, b);
    });

    test('profiles with different ids are not equal', () {
      final a = Profile.fromMap(baseMap);
      final b = Profile.fromMap({...baseMap, 'id': 'user-999'});
      expect(a, isNot(b));
    });
  });
}
