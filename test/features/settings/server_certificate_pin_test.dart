import 'dart:convert';

import 'package:bengkelku_pos/features/settings/data/server_certificate_pin.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ServerCertificatePin', () {
    final certificateDer = <int>[1, 2, 3, 4, 5, 6, 7, 8];

    test('creates a stable SHA-256 fingerprint from DER bytes', () {
      final fingerprint =
          ServerCertificatePin.fingerprintOfDer(certificateDer);

      expect(fingerprint, hasLength(64));
      expect(fingerprint, matches(RegExp(r'^[A-F0-9]{64}$')));
      expect(
        ServerCertificatePin.matchesDer(
          certificateDer: certificateDer,
          expectedFingerprint: fingerprint,
        ),
        isTrue,
      );
    });

    test('accepts colon-separated fingerprint formatting', () {
      final fingerprint =
          ServerCertificatePin.fingerprintOfDer(certificateDer);
      final formatted = fingerprint.replaceAllMapped(
        RegExp(r'.{2}'),
        (match) => '${match.group(0)}:',
      ).substring(0, 95);

      expect(
        ServerCertificatePin.matchesDer(
          certificateDer: certificateDer,
          expectedFingerprint: formatted,
        ),
        isTrue,
      );
    });

    test('rejects a different certificate and malformed pin', () {
      final fingerprint =
          ServerCertificatePin.fingerprintOfDer(certificateDer);

      expect(
        ServerCertificatePin.matchesDer(
          certificateDer: [8, 7, 6, 5, 4, 3, 2, 1],
          expectedFingerprint: fingerprint,
        ),
        isFalse,
      );
      expect(
        ServerCertificatePin.matchesDer(
          certificateDer: certificateDer,
          expectedFingerprint: 'not-a-fingerprint',
        ),
        isFalse,
      );
    });

    test('reads fingerprint from PEM certificate data', () {
      final pem = '-----BEGIN CERTIFICATE-----\n'
          '${base64.encode(certificateDer)}\n'
          '-----END CERTIFICATE-----';

      expect(
        ServerCertificatePin.fingerprintOfPem(pem),
        ServerCertificatePin.fingerprintOfDer(certificateDer),
      );
    });

    test('rejects malformed or empty certificate data', () {
      expect(
        () => ServerCertificatePin.fingerprintOfPem('not a certificate'),
        throwsFormatException,
      );
      expect(
        () => ServerCertificatePin.fingerprintOfDer([]),
        throwsArgumentError,
      );
    });

    test('checks certificate validity window including boundaries', () {
      final start = DateTime.utc(2026, 1, 1);
      final end = DateTime.utc(2027, 1, 1);

      expect(
        ServerCertificatePin.certificateIsWithinValidity(
          startValidity: start,
          endValidity: end,
          now: start,
        ),
        isTrue,
      );
      expect(
        ServerCertificatePin.certificateIsWithinValidity(
          startValidity: start,
          endValidity: end,
          now: end,
        ),
        isTrue,
      );
      expect(
        ServerCertificatePin.certificateIsWithinValidity(
          startValidity: start,
          endValidity: end,
          now: start.subtract(const Duration(seconds: 1)),
        ),
        isFalse,
      );
      expect(
        ServerCertificatePin.certificateIsWithinValidity(
          startValidity: start,
          endValidity: end,
          now: end.add(const Duration(seconds: 1)),
        ),
        isFalse,
      );
    });
  });
}
