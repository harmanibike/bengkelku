import 'dart:io';

class TestCertificate {
  const TestCertificate({
    required this.directory,
    required this.certificate,
    required this.privateKey,
  });

  final Directory directory;
  final File certificate;
  final File privateKey;

  Future<void> dispose() => directory.delete(recursive: true);
}

/// Creates disposable test-only credentials at runtime. No private key is
/// checked into the repository. CI's Ubuntu image provides OpenSSL.
///
/// The self-signed certificate is a CA trust anchor for this isolated PoC.
/// It also acts as the HTTPS server certificate, allowing the client to pin
/// this exact certificate without disabling normal TLS verification.
Future<TestCertificate> createTestCertificate(String dnsName) async {
  final directory = await Directory.systemTemp.createTemp('bikepos-tls-poc-');
  final certificate = File('${directory.path}/certificate.pem');
  final privateKey = File('${directory.path}/private-key.pem');

  final result = await Process.run('openssl', [
    'req',
    '-x509',
    '-newkey',
    'rsa:2048',
    '-sha256',
    '-nodes',
    '-days',
    '2',
    '-keyout',
    privateKey.path,
    '-out',
    certificate.path,
    '-subj',
    '/CN=$dnsName/O=Bike POS TLS PoC',
    '-addext',
    'subjectAltName=DNS:$dnsName',
    '-addext',
    'basicConstraints=critical,CA:TRUE',
    '-addext',
    'keyUsage=critical,digitalSignature,keyEncipherment,keyCertSign,cRLSign',
    '-addext',
    'extendedKeyUsage=serverAuth',
  ]);

  if (result.exitCode != 0) {
    await directory.delete(recursive: true);
    throw StateError('OpenSSL gagal membuat sertifikat PoC: ${result.stderr}');
  }

  return TestCertificate(
    directory: directory,
    certificate: certificate,
    privateKey: privateKey,
  );
}
