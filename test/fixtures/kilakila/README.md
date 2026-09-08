# Kilakila public share vectors

The 28 cases in `share-vectors.json` are independent .NET AES-CBC/PKCS7 and MD5
vectors generated from the reviewed public website codec, plus one actual
anonymous desktop share observed on 2026-09-08. They are public room/owner links,
not user authentication credentials. No user account or media credentials occur
in this file.

Source: https://download.hongrenshuo.com.cn/h5/assets/oss/uxin-security-url-crypto-v2.min.js
SHA-256: `2a031560d9ccd3770ff57969b8818e5eafd6d8a1e4f54c87e0f4bd983d4607e2`.
The [generator](../../../tool/probes/generate_kilakila_share_vectors.ps1) uses
PowerShell/.NET only. Download the reviewed public source separately, then pass
its file path as `-OfficialCodecPath` and the desired JSON path as `-OutputPath`.
The generator verifies the source digest before reading its public constants.

Synthetic cases cover both public reading keys, both room hosts, owner paths,
host-bound signatures, extra parameters and malformed plaintext. The native
crypto provider generating these inputs is independent of the Dart parser and
PointyCastle implementation under test. Legacy-key vectors prove the algorithm
path, not that every historical website link remains accepted by the service.

The ordinary test suite performs no network requests. A parsed broadcast ID
remains distinct from a durable owner UID and requires an API lookup before
being used as an owner favorite.
