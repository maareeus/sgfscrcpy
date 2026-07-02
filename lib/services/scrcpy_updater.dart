import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:path_provider/path_provider.dart';

/// A published scrcpy release from GitHub.
class ReleaseInfo {
  final String version; // normalized, e.g. "3.1"
  final String tag; // raw tag, e.g. "v3.1"
  final Map<String, String> assets; // filename -> download url

  ReleaseInfo({required this.version, required this.tag, required this.assets});

  /// Picks the Windows x64 zip asset url, if present.
  String? get windowsZipUrl {
    for (final entry in assets.entries) {
      final name = entry.key.toLowerCase();
      if (name.endsWith('.zip') && name.contains('win64')) return entry.value;
    }
    for (final entry in assets.entries) {
      final name = entry.key.toLowerCase();
      if (name.endsWith('.zip') && name.contains('win')) return entry.value;
    }
    return null;
  }
}

/// Reports installer progress (0.0 – 1.0), or null for indeterminate steps.
typedef ProgressCallback = void Function(double? progress, String status);

/// Handles checking GitHub for scrcpy releases and, on Windows, downloading
/// and unpacking them into the app's support directory.
class ScrcpyUpdater {
  static const _releasesApi =
      'https://api.github.com/repos/Genymobile/scrcpy/releases/latest';

  /// Extracts a comparable version like "3.1.1" from an arbitrary string.
  static String? normalizeVersion(String? raw) {
    if (raw == null) return null;
    final match = RegExp(r'(\d+(?:\.\d+)+)').firstMatch(raw);
    return match?.group(1);
  }

  /// Returns 1 if [a] > [b], -1 if a < b, 0 if equal. Null-safe.
  static int compareVersions(String? a, String? b) {
    final va = normalizeVersion(a);
    final vb = normalizeVersion(b);
    if (va == null || vb == null) return 0;
    final pa = va.split('.').map(int.parse).toList();
    final pb = vb.split('.').map(int.parse).toList();
    for (var i = 0; i < pa.length || i < pb.length; i++) {
      final x = i < pa.length ? pa[i] : 0;
      final y = i < pb.length ? pb[i] : 0;
      if (x != y) return x > y ? 1 : -1;
    }
    return 0;
  }

  /// Fetches the latest release metadata from GitHub.
  Future<ReleaseInfo> fetchLatest() async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(_releasesApi));
      request.headers.set(HttpHeaders.userAgentHeader, 'SgfScrcpy');
      request.headers.set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
      final response = await request.close();
      if (response.statusCode != 200) {
        throw Exception('GitHub API returned ${response.statusCode}');
      }
      final body = await response.transform(utf8.decoder).join();
      final json = jsonDecode(body) as Map<String, dynamic>;
      final tag = (json['tag_name'] ?? '').toString();
      final assets = <String, String>{};
      for (final asset in (json['assets'] as List? ?? [])) {
        final name = asset['name']?.toString();
        final url = asset['browser_download_url']?.toString();
        if (name != null && url != null) assets[name] = url;
      }
      return ReleaseInfo(
        version: normalizeVersion(tag) ?? tag,
        tag: tag,
        assets: assets,
      );
    } finally {
      client.close(force: true);
    }
  }

  /// Downloads and extracts the Windows scrcpy build for [release].
  /// Returns the absolute path to the extracted `scrcpy.exe`.
  Future<String> installWindows(
    ReleaseInfo release,
    ProgressCallback onProgress,
  ) async {
    final url = release.windowsZipUrl;
    if (url == null) {
      throw Exception('No Windows build found in release ${release.tag}.');
    }

    onProgress(null, 'Downloading scrcpy ${release.tag}…');
    final support = await getApplicationSupportDirectory();
    final tmpZip = File('${support.path}/scrcpy-${release.version}.zip');
    await _download(url, tmpZip, onProgress);

    onProgress(null, 'Extracting…');
    final targetDir = Directory('${support.path}/scrcpy-${release.version}');
    if (targetDir.existsSync()) targetDir.deleteSync(recursive: true);
    targetDir.createSync(recursive: true);
    await _extractZip(tmpZip, targetDir);
    try {
      tmpZip.deleteSync();
    } catch (_) {}

    final exe = _findExecutable(targetDir, 'scrcpy.exe');
    if (exe == null) {
      throw Exception('scrcpy.exe not found in the downloaded archive.');
    }
    onProgress(1.0, 'Installed scrcpy ${release.tag}');
    return exe;
  }

  Future<void> _download(String url, File dest, ProgressCallback onProgress) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(url));
      request.headers.set(HttpHeaders.userAgentHeader, 'SgfScrcpy');
      final response = await request.close(); // follows redirects
      if (response.statusCode != 200) {
        throw Exception('Download failed (${response.statusCode}).');
      }
      final total = response.contentLength;
      final sink = dest.openWrite();
      var received = 0;
      await for (final chunk in response) {
        received += chunk.length;
        sink.add(chunk);
        if (total > 0) {
          onProgress(received / total, 'Downloading… '
              '${(received / 1048576).toStringAsFixed(1)} MB');
        }
      }
      await sink.close();
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _extractZip(File zip, Directory targetDir) async {
    final bytes = await zip.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);
    for (final file in archive) {
      final outPath = '${targetDir.path}/${file.name}';
      if (file.isFile) {
        final outFile = File(outPath);
        outFile.parent.createSync(recursive: true);
        await outFile.writeAsBytes(file.content as List<int>);
      } else {
        Directory(outPath).createSync(recursive: true);
      }
    }
  }

  /// Recursively finds a file named [name] under [dir].
  String? _findExecutable(Directory dir, String name) {
    for (final entity in dir.listSync(recursive: true)) {
      if (entity is File && entity.uri.pathSegments.last == name) {
        return entity.path;
      }
    }
    return null;
  }
}
