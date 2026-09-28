import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// web/index.html holds Google's GIS script back until the app first uses
// Google sign-in (.llmwiki/FlutterAuth.md). These tests run that guard, as
// the file has it, in headless Chrome over the loader of the
// google_identity_services_web this project resolves, compiled to
// JavaScript (test/gis_guard/load_gis.dart): if a new version of the plugin
// inserts its script by anything but appendChild, the request to
// accounts.google.com comes back and the first test fails.

const _gis = 'https://accounts.google.com/gsi/client';

/// Where each run's files go; removed after the test.
Directory _scratch() {
  final dir = Directory.systemTemp.createTempSync('zapzap_gis_guard_');
  addTearDown(() => dir.deleteSync(recursive: true));
  return dir;
}

/// Flutter's `dart`, which `flutter test` runs under (`FLUTTER_ROOT`).
String _dart() {
  final root = Platform.environment['FLUTTER_ROOT'];
  return root == null ? 'dart' : '$root/bin/dart';
}

/// Chrome as `flutter run -d chrome` finds it: `CHROME_EXECUTABLE`, else on
/// the PATH (a GitHub-hosted Ubuntu runner has `google-chrome`).
String _chrome() {
  final defined = Platform.environment['CHROME_EXECUTABLE'];
  if (defined != null && defined.isNotEmpty) return defined;
  for (final name in [
    'google-chrome',
    'google-chrome-stable',
    'chromium',
    'chromium-browser',
  ]) {
    final which = Process.runSync('which', [name]);
    if (which.exitCode == 0) return (which.stdout as String).trim();
  }
  const mac = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
  if (File(mac).existsSync()) return mac;
  throw StateError('No Chrome found: set CHROME_EXECUTABLE');
}

/// web/index.html with [body] in place of the Flutter bootstrap, and the
/// browser's own appendChild kept as `nativeAppendChild` before the guard
/// replaces it. [body]'s script leaves its findings in `window.result`.
String _page(String body) {
  final html = File('web/index.html').readAsStringSync();
  const bootstrap = '<script src="flutter_bootstrap.js" async></script>';
  expect(html, contains(bootstrap));
  expect(html, contains('<head>'));
  return html
      .replaceFirst('\$FLUTTER_BASE_HREF', './')
      .replaceFirst(
        '<head>',
        '<head><script>window.nativeAppendChild = '
            'Node.prototype.appendChild;</script>',
      )
      .replaceFirst(
        bootstrap,
        '<script>window.onerror = function (message) {'
        ' window.result = {error: String(message)}; };</script>'
        '$body'
        '<script>var out = document.createElement("pre");'
        ' out.id = "result"; out.textContent = JSON.stringify(window.result);'
        ' document.body.append(out);</script>',
      );
}

/// Opens [page] in headless Chrome, with every host name unresolvable (no
/// request leaves the machine), and returns what its script found.
Future<Map<String, Object?>> _run(Directory dir, String page) async {
  final file = File('${dir.path}/page.html')..writeAsStringSync(page);
  final chrome = await Process.run(_chrome(), [
    '--headless=new',
    '--no-sandbox',
    '--disable-gpu',
    '--user-data-dir=${dir.path}/profile',
    '--host-resolver-rules=MAP * ~NOTFOUND',
    '--dump-dom',
    file.uri.toString(),
  ]);
  final dom = chrome.stdout as String;
  final found = RegExp(r'<pre id="result">(.*?)</pre>').firstMatch(dom);
  expect(found, isNotNull, reason: 'Chrome: ${chrome.stderr}\n$dom');
  return jsonDecode(found!.group(1)!) as Map<String, Object?>;
}

/// The GIS script elements in the page or in the detached `gisTarget`.
const _gisScripts =
    '''
function gisScripts() {
  var all = [].slice.call(document.querySelectorAll('script'));
  if (window.gisTarget) {
    all = all.concat([].slice.call(gisTarget.querySelectorAll('script')));
  }
  return all.filter(function (s) { return String(s.src).indexOf('$_gis') === 0; }).length;
}
function isNative() {
  return Node.prototype.appendChild === nativeAppendChild &&
      Function.prototype.toString.call(Node.prototype.appendChild)
          .indexOf('[native code]') >= 0;
}
''';

void main() {
  test('the resolved GIS loader\'s script is held until '
      'zapzapLoadGoogleScript, which releases it once and gives the page the '
      'browser\'s own appendChild back', () async {
    final dir = _scratch();
    final compiled = await Process.run(_dart(), [
      'compile',
      'js',
      '-O1',
      '-o',
      '${dir.path}/load_gis.js',
      'test/gis_guard/load_gis.dart',
    ]);
    expect(
      compiled.exitCode,
      0,
      reason: '${compiled.stdout}${compiled.stderr}',
    );

    final result = await _run(
      dir,
      _page('''
<script>
  $_gisScripts
  window.gisTarget = document.createElement('div');
  var meta = document.createElement('meta');
  document.head.appendChild(meta);
</script>
<script src="load_gis.js"></script>
<script>
  var held = {scripts: gisScripts(), inTarget: gisTarget.childNodes.length};
  var others = meta.parentNode === document.head;
  var guarded = !isNative();
  zapzapLoadGoogleScript();
  var released = {scripts: gisScripts(), inTarget: gisTarget.childNodes.length};
  zapzapLoadGoogleScript();
  window.result = {
    held: held, others: others, guarded: guarded, released: released,
    nativeAfter: isNative(), twice: gisScripts(),
  };
</script>'''),
    );

    expect(result, {
      // The loader ran and its script went nowhere...
      'held': {'scripts': 0, 'inTarget': 0},
      // ...while any other element was appended as usual.
      'others': true,
      'guarded': true,
      // Released where the loader put it, once.
      'released': {'scripts': 1, 'inTarget': 1},
      'nativeAfter': true,
      'twice': 1,
    });
  });

  test('a wrapper installed after the guard is kept at release, and still '
      'lets the GIS script through', () async {
    final dir = _scratch();
    final result = await _run(
      dir,
      _page('''
<script>
  $_gisScripts
  var guard = Node.prototype.appendChild;
  function wrapper(child) { return guard.call(this, child); }
  Node.prototype.appendChild = wrapper;
  zapzapLoadGoogleScript();
  var kept = Node.prototype.appendChild === wrapper;
  var late = document.createElement('div');
  var script = document.createElement('script');
  script.src = '$_gis';
  late.appendChild(script);
  window.result = {kept: kept, through: script.parentNode === late};
</script>'''),
    );

    expect(result, {'kept': true, 'through': true});
  });

  test('google_sign_in_web loads GIS through that loader, and creates no '
      'script element of its own', () {
    final config = jsonDecode(
      File('.dart_tool/package_config.json').readAsStringSync(),
    ) as Map<String, Object?>;
    final base = File('.dart_tool/package_config.json').absolute.uri;
    final packages = config['packages']! as List<Object?>;
    final entry = packages.cast<Map<String, Object?>>().firstWhere(
      (p) => p['name'] == 'google_sign_in_web',
    );
    final lib = Directory.fromUri(
      base
          .resolve('${entry['rootUri']}/')
          .resolve(entry['packageUri']! as String),
    );
    final sources = lib
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .map((f) => f.readAsStringSync())
        .join('\n');

    expect(sources, contains('loader.loadWebSdk('));
    expect(sources, isNot(contains('HTMLScriptElement')));
    expect(sources, isNot(contains("createElement('script')")));
    expect(sources, isNot(contains('createElement("script")')));
  });
}
