import 'package:flutter_test/flutter_test.dart';
import 'package:selfstream/state/updater.dart';

Map<String, dynamic> release(String body, {String name = 'selfstream-setup.exe', String? url}) => {
      'body': body,
      'assets': [
        {
          'name': name,
          'size': 100,
          'browser_download_url': url ?? 'https://github.com/$kUpdateRepo/releases/download/windows-latest/$name',
        }
      ],
    };

void main() {
  test('a newer build is offered', () {
    final u = Updater.parse(release('Run it.\n\nBuild: 12\nBuilt from abc.'), 10);
    expect(u?.build, 12);
    expect(u?.url, endsWith('selfstream-setup.exe'));
  });

  test('the same or an older build is not', () {
    expect(Updater.parse(release('Build: 12'), 12), isNull);
    expect(Updater.parse(release('Build: 11'), 12), isNull);
  });

  test('a release without a build number or installer is ignored', () {
    expect(Updater.parse(release('no number here'), 1), isNull);
    expect(Updater.parse(release('Build: 5', name: 'other.zip'), 1), isNull);
    expect(Updater.parse(null, 1), isNull);
  });

  test('downloads from anywhere but this project are refused', () {
    expect(Updater.parse(release('Build: 5', url: 'https://evil.example/selfstream-setup.exe'), 1), isNull);
  });
}
