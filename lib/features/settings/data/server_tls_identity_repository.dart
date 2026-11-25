import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:basic_utils/basic_utils.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'server_certificate_pin.dart';

/// Small storage contract keeps identity lifecycle tests independent from
/// Android Keystore and MethodChannel implementations.
abstract interface class SecureValueStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class FlutterSecureValueStore implements SecureValueStore {
  FlutterSecureValueStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

class ServerTlsIdentity {
  const ServerTlsIdentity({
    required this.serverId,
    required this.dnsName,
    required this.certificatePem,
    required this.privateKeyPem,
    required this.fingerprint,
  });

  final String serverId;
  final String dnsName;
  final String certificatePem;

  /// Keep this value in memory only while configuring the TLS listener.
  /// Never log it, include it in pairing QR data, or send it to a Client.
  final String privateKeyPem;
  final String fingerprint;
}

class ServerTlsIdentityMaterial {
  const ServerTlsIdentityMaterial({
    required this.certificatePem,
    required this.privateKeyPem,
  });

  final String certificatePem;
  final String privateKeyPem;
}

abstract interface class ServerTlsIdentityMaterialGenerator {
  Future<ServerTlsIdentityMaterial> generate({
    required String dnsName,
  });
}

class SelfSignedServerTlsIdentityGenerator
    implements ServerTlsIdentityMaterialGenerator {
  SelfSignedServerTlsIdentityGenerator({Random? random})
      : _random = random ?? Random.secure();

  final Random _random;

  String _serialNumber() {
    // ASN.1 INTEGER is signed. Keep the high bit clear so the X.509 serial
    // is always positive and can be parsed by Android/OpenSSL TLS providers.
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    bytes[0] = bytes[0] & 0x7f;
    if (bytes.every((value) => value == 0)) {
      bytes[bytes.length - 1] = 1;
    }
    return BigInt.parse(
      bytes.map((value) => value.toRadixString(16).padLeft(2, '0')).join(),
      radix: 16,
    ).toString();
  }

  @override
  Future<ServerTlsIdentityMaterial> generate({
    required String dnsName,
  }) async {
    if (!RegExp(r'^bikepos-[a-f0-9]{32}\.invalid$').hasMatch(dnsName)) {
      throw ArgumentError.value(
        dnsName,
        'dnsName',
        'Identitas DNS Bike POS tidak valid.',
      );
    }

    // RSA 2048 and SHA-256 are broadly supported by Android TLS providers.
    final pair = CryptoUtils.generateRSAKeyPair(keySize: 2048);
    final privateKey = pair.privateKey as RSAPrivateKey;
    final publicKey = pair.publicKey as RSAPublicKey;
    final csr = X509Utils.generateRsaCsrPem(
      {'CN': dnsName},
      privateKey,
      publicKey,
      san: [dnsName],
      signingAlgorithm: 'SHA-256',
    );
    final certificatePem = X509Utils.generateSelfSignedCertificate(
      privateKey,
      csr,
      825,
      sans: [dnsName],
      // Keep the leaf certificate extensions minimal. The current
      // basic_utils X.509 extension encoder has produced DER that Android's
      // TLS parser rejects when optional KeyUsage/EKU/BasicConstraints are
      // added. SAN is required for hostname verification; absent KU/EKU
      // means no additional certificate-purpose restriction is asserted.
      serialNumber: _serialNumber(),
    );
    final privateKeyPem = CryptoUtils.encodeRSAPrivateKeyToPem(privateKey);

    // Fail closed if the generated material cannot be loaded by dart:io TLS.
    SecurityContext(withTrustedRoots: false)
      ..useCertificateChainBytes(utf8.encode(certificatePem))
      ..usePrivateKeyBytes(utf8.encode(privateKeyPem));

    return ServerTlsIdentityMaterial(
      certificatePem: certificatePem,
      privateKeyPem: privateKeyPem,
    );
  }
}

/// Persists the Server UUID, certificate, and private key in encrypted
/// platform storage. A partial/corrupt record is never silently replaced:
/// doing so would change the certificate fingerprint and strand paired
/// Clients without an explicit re-pair operation.
class ServerTlsIdentityRepository {
  ServerTlsIdentityRepository({
    required SecureValueStore store,
    ServerTlsIdentityMaterialGenerator? generator,
    Random? random,
  })  : _store = store,
        _generator = generator ?? SelfSignedServerTlsIdentityGenerator(),
        _random = random ?? Random.secure();

  static const _prefix = 'bikepos.server_tls.v1';
  static const _versionKey = '$_prefix.version';
  static const _serverIdKey = '$_prefix.server_id';
  static const _certificateKey = '$_prefix.certificate_pem';
  static const _privateKeyKey = '$_prefix.private_key_pem';
  static const _fingerprintKey = '$_prefix.fingerprint';

  final SecureValueStore _store;
  final ServerTlsIdentityMaterialGenerator _generator;
  final Random _random;
  Future<ServerTlsIdentity>? _pending;

  Future<ServerTlsIdentity> loadOrCreate() {
    final pending = _pending;
    if (pending != null) return pending;

    final future = _loadOrCreate();
    _pending = future;
    return future.whenComplete(() {
      if (identical(_pending, future)) _pending = null;
    });
  }

  String _newServerId() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    return bytes.map((value) => value.toRadixString(16).padLeft(2, '0')).join();
  }

  Future<ServerTlsIdentity> _loadOrCreate() async {
    final values = await Future.wait([
      _store.read(_versionKey),
      _store.read(_serverIdKey),
      _store.read(_certificateKey),
      _store.read(_privateKeyKey),
      _store.read(_fingerprintKey),
    ]);
    final version = values[0];
    final serverId = values[1];
    final certificatePem = values[2];
    final privateKeyPem = values[3];
    final savedFingerprint = values[4];

    final allMissing = values.every((value) => value == null);
    if (allMissing) return _createAndPersist();

    if (version != '1' ||
        serverId == null ||
        certificatePem == null ||
        privateKeyPem == null ||
        savedFingerprint == null) {
      throw StateError(
        'Identitas TLS Server tidak lengkap. Server dinonaktifkan demi keamanan; '
        'Admin perlu melakukan pemulihan identitas dan pairing ulang.',
      );
    }

    if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(serverId)) {
      throw StateError('ID Server TLS tersimpan tidak valid.');
    }

    final dnsName = 'bikepos-$serverId.invalid';
    final fingerprint = ServerCertificatePin.fingerprintOfPem(certificatePem);
    if (!ServerCertificatePin.isValidFingerprint(savedFingerprint) ||
        fingerprint !=
            ServerCertificatePin.normalizeFingerprint(savedFingerprint)) {
      throw StateError(
        'Fingerprint sertifikat Server tidak cocok dengan data tersimpan.',
      );
    }

    _validateKeyPair(certificatePem, privateKeyPem);
    return ServerTlsIdentity(
      serverId: serverId,
      dnsName: dnsName,
      certificatePem: certificatePem,
      privateKeyPem: privateKeyPem,
      fingerprint: fingerprint,
    );
  }

  Future<ServerTlsIdentity> _createAndPersist() async {
    final serverId = _newServerId();
    final dnsName = 'bikepos-$serverId.invalid';
    final material = await _generator.generate(dnsName: dnsName);
    _validateKeyPair(material.certificatePem, material.privateKeyPem);
    final fingerprint =
        ServerCertificatePin.fingerprintOfPem(material.certificatePem);

    try {
      await _store.write(_serverIdKey, serverId);
      await _store.write(_certificateKey, material.certificatePem);
      await _store.write(_privateKeyKey, material.privateKeyPem);
      await _store.write(_fingerprintKey, fingerprint);
      // Write the commit marker last so interrupted writes fail closed.
      await _store.write(_versionKey, '1');
    } catch (_) {
      for (final key in [
        _versionKey,
        _serverIdKey,
        _certificateKey,
        _privateKeyKey,
        _fingerprintKey,
      ]) {
        try {
          await _store.delete(key);
        } catch (_) {
          // Preserve the original storage error.
        }
      }
      rethrow;
    }

    return ServerTlsIdentity(
      serverId: serverId,
      dnsName: dnsName,
      certificatePem: material.certificatePem,
      privateKeyPem: material.privateKeyPem,
      fingerprint: fingerprint,
    );
  }

  void _validateKeyPair(String certificatePem, String privateKeyPem) {
    if (!certificatePem.contains('-----BEGIN CERTIFICATE-----') ||
        !privateKeyPem.contains('PRIVATE KEY-----')) {
      throw StateError('Material sertifikat atau private key tidak valid.');
    }
    try {
      SecurityContext(withTrustedRoots: false)
        ..useCertificateChainBytes(utf8.encode(certificatePem))
        ..usePrivateKeyBytes(utf8.encode(privateKeyPem));
    } on Object {
      throw StateError('Sertifikat dan private key Server tidak dapat dimuat.');
    }
  }
}
