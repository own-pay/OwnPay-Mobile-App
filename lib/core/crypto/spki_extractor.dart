import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Extracts the SubjectPublicKeyInfo (SPKI) from an X.509 certificate DER blob
/// and returns the SHA-256 of that region, hex encoded.
///
/// The SPKI is the canonical stable identity of a TLS endpoint: two certificates
/// issued for the same key pair (e.g. a self-signed server renewing its cert with the
/// same key) share the exact same SPKI, while different keys never do.
///
/// TBSCertificate layout:
///   TBSCertificate ::= SEQUENCE {
///       [0] EXPLICIT version OPTIONAL,
///       serialNumber INTEGER,
///       signature AlgorithmIdentifier,
///       issuer Name, validity SEQUENCE, subject Name,
///       subjectPublicKeyInfo SubjectPublicKeyInfo,
///   }
/// SubjectPublicKeyInfo ::= SEQUENCE { algorithm SEQUENCE, subjectPublicKey BIT STRING }
///
/// We walk the declared children to find the SPKI SEQUENCE rather than hard-coding
/// offsets, so optional extensions do not shift the index.
String? spkiSha256Hex(Uint8List certificateDer) {
  try {
    final _Tlv certificate = _readTlv(certificateDer, 0);
    if (certificate.tag != 0x30) {
      return null; // not a SEQUENCE
    }
    final _Tlv tbs = _readTlv(certificateDer, certificate.offset + certificate.headerLength);
    if (tbs.tag != 0x30) {
      return null;
    }

    // Collect the children of TBS.
    final int tbsEnd = tbs.offset + tbs.headerLength + tbs.contentLength;
    final List<_Tlv> children = <_Tlv>[];
    int cursor = tbs.offset + tbs.headerLength;
    while (cursor < tbsEnd) {
      final _Tlv child = _readTlv(certificateDer, cursor);
      children.add(child);
      cursor = child.offset + child.headerLength + child.contentLength;
    }

    int index = 0;
    if (children.isNotEmpty && children[0].tag == 0xA0) {
      index = 1; // explicit [0] version present, skip it
    }
    // After optional version: INTEGER serial, SEQ signature, SEQ issuer,
    // SEQ validity, SEQ subject -> the next SEQ is SPKI.
    if (children.length <= index + 5) {
      return null;
    }
    final _Tlv spki = children[index + 5];
    if (spki.tag != 0x30) {
      return null;
    }
    final int start = spki.offset;
    final int end = spki.offset + spki.headerLength + spki.contentLength;
    return sha256.convert(certificateDer.sublist(start, end)).toString();
  } catch (_) {
    return null;
  }
}

final class _Tlv {
  const _Tlv(this.tag, this.headerLength, this.contentLength, this.offset);

  final int tag;
  final int headerLength;
  final int contentLength;
  final int offset;
}

_Tlv _readTlv(Uint8List data, int offset) {
  if (offset + 2 > data.length) {
    throw const FormatException('TLV header overruns buffer');
  }
  final int tag = data[offset];
  int index = offset + 1;
  final int firstLength = data[index];
  index += 1;

  int length;
  if (firstLength == 0x80) {
    // Indefinite length form (not valid in DER for this shape).
    throw const FormatException('Indefinite length form unsupported');
  } else if ((firstLength & 0x80) == 0) {
    length = firstLength;
  } else {
    final int numBytes = firstLength & 0x7F;
    if (numBytes == 0 || numBytes > 4 || index + numBytes > data.length) {
      throw const FormatException('Bad long-form length');
    }
    length = 0;
    for (int i = 0; i < numBytes; i++) {
      length = (length << 8) | data[index];
      index += 1;
    }
  }
  if (index + length > data.length) {
    throw const FormatException('TLV content overruns buffer');
  }
  return _Tlv(tag, index - offset, length, offset);
}
