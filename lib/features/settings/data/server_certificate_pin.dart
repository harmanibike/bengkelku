import 'dart:convert';
import 'package:crypto/crypto.dart';

/// Fingerprint helper for the public X.509 certificate distributed at pairing.
///
/// The Client must also trust only this certificate through a dedicated
/// SecurityContext. A fingerprint comparison alone must never be used as a
/// replacement for normal TLS certificate validity and hostname checks.
class ServerCertificatePin {
  const ServerCertificatePin._();

  static String fingerprintOfDer(List<int> certificateDer) {
    if (certificateDer.isEmpty) {
      throw ArgumentError.value(
        certificateDer,
        'certificateDer',
        'Data sertifikat tidak boleh kosong.',
      );
    }
    return sha256.convert(certificateDer).toString().toUpperCase();
  }

  static String fingerprintOfPem(String certificatePem) {
    final match = RegExp(
      r'-----BEGIN CERTIFICATE-----([\s\S]+?)-----END CERTIFICATE-----',
    ).firstMatch(certificatePem);
    if (match == null) {
      throw const FormatException('Sertifikat PEM tidak valid.');
    }

    final encoded = match.group(1)!.replaceAll(RegExp(r'\s'), '');
    try {
      return fingerprintOfDer(base64.decode(encoded));
    } on FormatException {
      throw const FormatException('Isi sertifikat PEM tidak valid.');
    }
  }

  static bool isValidFingerprint(String fingerprint) {
    final normalized = normalizeFingerprint(fingerprint);
    return RegExp(r'^[A-F0-9]{64}$').hasMatch(normalized);
  }

  static String normalizeFingerprint(String fingerprint) =>
      fingerprint.replaceAll(RegExp(r'[^a-fA-F0-9]'), '').toUpperCase();

  static bool matchesDer({
    required List<int> certificateDer,
    required String expectedFingerprint,
  }) {
    final expected = normalizeFingerprint(expectedFingerprint);
    if (!RegExp(r'^[A-F0-9]{64}$').hasMatch(expected)) return false;

    final actual = fingerprintOfDer(certificateDer);
    // Constant-time comparison avoids leaking the first differing byte.
    var difference = 0;
    for (var i = 0; i < actual.length; i++) {
      difference |= actual.codeUnitAt(i) ^ expected.codeUnitAt(i);
    }
    return difference == 0;
  }

  static bool certificateIsWithinValidity({
    required DateTime startValidity,
    required DateTime endValidity,
    DateTime? now,
  }) {
    final instant = (now ?? DateTime.now()).toUtc();
    return !instant.isBefore(startValidity.toUtc()) &&
        !instant.isAfter(endValidity.toUtc());
  }

}
