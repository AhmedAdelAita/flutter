// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:convert' show jsonEncode;
import 'dart:io' show Directory, File;

import 'package:coverage/src/hitmap.dart';
import 'package:flutter_tools/src/test/coverage_collector.dart';
import 'package:flutter_tools/src/test/test_device.dart' show TestDevice;
import 'package:flutter_tools/src/test/test_time_recorder.dart';
import 'package:stream_channel/stream_channel.dart' show StreamChannel;
import 'package:vm_service/vm_service.dart';

import '../src/common.dart';
import '../src/fake_vm_services.dart';
import '../src/logging_logger.dart';

void main() {
  testWithoutContext('Coverage collector Can handle coverage SentinelException', () async {
    final FakeVmServiceHost fakeVmServiceHost = FakeVmServiceHost(
      requests: <VmServiceExpectation>[
        FakeVmServiceRequest(
          method: 'getVersion',
          jsonResponse: Version(major: 3, minor: 51).toJson(),
        ),
        FakeVmServiceRequest(
          method: 'getVM',
          jsonResponse: (VM.parse(<String, Object>{})!
            ..isolates = <IsolateRef>[
              IsolateRef.parse(<String, Object>{
                'id': '1',
              })!,
            ]
          ).toJson(),
        ),
        const FakeVmServiceRequest(
          method: 'getScripts',
          args: <String, Object>{
            'isolateId': '1',
          },
          jsonResponse: <String, Object>{
            'type': 'Sentinel',
          },
        ),
      ],
    );

    final Map<String, Object?> result = await collect(
      null,
      <String>{'foo'},
      connector: (Uri? uri) async {
        return fakeVmServiceHost.vmService;
      },
    );

    expect(result, <String, Object>{'type': 'CodeCoverage', 'coverage': <Object>[]});
    expect(fakeVmServiceHost.hasRemainingExpectations, false);
  });

  testWithoutContext('Coverage collector processes coverage and script data', () async {
    final FakeVmServiceHost fakeVmServiceHost = FakeVmServiceHost(
      requests: <VmServiceExpectation>[
        FakeVmServiceRequest(
          method: 'getVersion',
          jsonResponse: Version(major: 3, minor: 51).toJson(),
        ),
        FakeVmServiceRequest(
          method: 'getVM',
          jsonResponse: (VM.parse(<String, Object>{})!
            ..isolates = <IsolateRef>[
              IsolateRef.parse(<String, Object>{
                'id': '1',
              })!,
            ]
          ).toJson(),
        ),
        FakeVmServiceRequest(
          method: 'getScripts',
          args: <String, Object>{
            'isolateId': '1',
          },
          jsonResponse: ScriptList(scripts: <ScriptRef>[
            ScriptRef(uri: 'package:foo/foo.dart', id: '1'),
            ScriptRef(uri: 'package:bar/bar.dart', id: '2'),
          ]).toJson(),
        ),
        FakeVmServiceRequest(
          method: 'getSourceReport',
          args: <String, Object>{
            'isolateId': '1',
            'reports': <Object>['Coverage'],
            'scriptId': '1',
            'forceCompile': true,
            'reportLines': true,
          },
          jsonResponse: SourceReport(
            ranges: <SourceReportRange>[
              SourceReportRange(
                scriptIndex: 0,
                startPos: 0,
                endPos: 0,
                compiled: true,
                coverage: SourceReportCoverage(
                  hits: <int>[1, 3],
                  misses: <int>[2],
                ),
              ),
            ],
            scripts: <ScriptRef>[
              ScriptRef(
                uri: 'package:foo/foo.dart',
                id: '1',
              ),
            ],
          ).toJson(),
        ),
      ],
    );

    final Map<String, Object?> result = await collect(
      null,
      <String>{'foo'},
      connector: (Uri? uri) async {
        return fakeVmServiceHost.vmService;
      },
    );

    expect(result, <String, Object>{
      'type': 'CodeCoverage',
      'coverage': <Object>[
        <String, Object>{
          'source': 'package:foo/foo.dart',
          'script': <String, Object>{
            'type': '@Script',
            'fixedId': true,
            'id': 'libraries/1/scripts/package%3Afoo%2Ffoo.dart',
            'uri': 'package:foo/foo.dart',
            '_kind': 'library',
          },
          'hits': <Object>[1, 1, 3, 1, 2, 0],
        },
      ],
    });
    expect(fakeVmServiceHost.hasRemainingExpectations, false);
  });

  testWithoutContext('Coverage collector with null libraryNames accepts all libraries', () async {
    final FakeVmServiceHost fakeVmServiceHost = createFakeVmServiceHostWithFooAndBar();

    final Map<String, Object?> result = await collect(
      null,
      null,
      connector: (Uri? uri) async {
        return fakeVmServiceHost.vmService;
      },
    );

    expect(result, <String, Object>{
      'type': 'CodeCoverage',
      'coverage': <Object>[
        <String, Object>{
          'source': 'package:foo/foo.dart',
          'script': <String, Object>{
            'type': '@Script',
            'fixedId': true,
            'id': 'libraries/1/scripts/package%3Afoo%2Ffoo.dart',
            'uri': 'package:foo/foo.dart',
            '_kind': 'library',
          },
          'hits': <Object>[1, 1, 3, 1, 2, 0],
        },
        <String, Object>{
          'source': 'package:bar/bar.dart',
          'script': <String, Object>{
            'type': '@Script',
            'fixedId': true,
            'id': 'libraries/1/scripts/package%3Abar%2Fbar.dart',
            'uri': 'package:bar/bar.dart',
            '_kind': 'library',
          },
          'hits': <Object>[47, 1, 21, 1, 32, 0, 86, 0],
        },
      ],
    });
    expect(fakeVmServiceHost.hasRemainingExpectations, false);
  });

  testWithoutContext('Coverage collector with libraryFilters', () async {
    final FakeVmServiceHost fakeVmServiceHost = FakeVmServiceHost(
      requests: <VmServiceExpectation>[
        FakeVmServiceRequest(
          method: 'getVersion',
          jsonResponse: Version(major: 3, minor: 57).toJson(),
        ),
        FakeVmServiceRequest(
          method: 'getVM',
          jsonResponse: (VM.parse(<String, Object>{})!
            ..isolates = <IsolateRef>[
              IsolateRef.parse(<String, Object>{
                'id': '1',
              })!,
            ]
          ).toJson(),
        ),
        FakeVmServiceRequest(
          method: 'getSourceReport',
          args: <String, Object>{
            'isolateId': '1',
            'reports': <Object>['Coverage'],
            'forceCompile': true,
            'reportLines': true,
            'libraryFilters': <Object>['package:foo/'],
          },
          jsonResponse: SourceReport(
            ranges: <SourceReportRange>[
              SourceReportRange(
                scriptIndex: 0,
                startPos: 0,
                endPos: 0,
                compiled: true,
                coverage: SourceReportCoverage(
                  hits: <int>[1, 3],
                  misses: <int>[2],
                ),
              ),
            ],
            scripts: <ScriptRef>[
              ScriptRef(
                uri: 'package:foo/foo.dart',
                id: '1',
              ),
            ],
          ).toJson(),
        ),
      ],
    );

    final Map<String, Object?> result = await collect(
      null,
      <String>{'foo'},
      connector: (Uri? uri) async {
        return fakeVmServiceHost.vmService;
      },
    );

    expect(result, <String, Object>{
      'type': 'CodeCoverage',
      'coverage': <Object>[
        <String, Object>{
          'source': 'package:foo/foo.dart',
          'script': <String, Object>{
            'type': '@Script',
            'fixedId': true,
            'id': 'libraries/1/scripts/package%3Afoo%2Ffoo.dart',
            'uri': 'package:foo/foo.dart',
            '_kind': 'library',
          },
          'hits': <Object>[1, 1, 3, 1, 2, 0],
        },
      ],
    });
    expect(fakeVmServiceHost.hasRemainingExpectations, false);
  });

  testWithoutContext('Coverage collector with libraryFilters and null libraryNames', () async {
    final FakeVmServiceHost fakeVmServiceHost = FakeVmServiceHost(
      requests: <VmServiceExpectation>[
        FakeVmServiceRequest(
          method: 'getVersion',
          jsonResponse: Version(major: 3, minor: 57).toJson(),
        ),
        FakeVmServiceRequest(
          method: 'getVM',
          jsonResponse: (VM.parse(<String, Object>{})!
            ..isolates = <IsolateRef>[
              IsolateRef.parse(<String, Object>{
                'id': '1',
              })!,
            ]
          ).toJson(),
        ),
        FakeVmServiceRequest(
          method: 'getSourceReport',
          args: <String, Object>{
            'isolateId': '1',
            'reports': <Object>['Coverage'],
            'forceCompile': true,
            'reportLines': true,
          },
          jsonResponse: SourceReport(
            ranges: <SourceReportRange>[
              SourceReportRange(
                scriptIndex: 0,
                startPos: 0,
                endPos: 0,
                compiled: true,
                coverage: SourceReportCoverage(
                  hits: <int>[1, 3],
                  misses: <int>[2],
                ),
              ),
            ],
            scripts: <ScriptRef>[
              ScriptRef(
                uri: 'package:foo/foo.dart',
                id: '1',
              ),
            ],
          ).toJson(),
        ),
      ],
    );

    final Map<String, Object?> result = await collect(
      null,
      null,
      connector: (Uri? uri) async {
        return fakeVmServiceHost.vmService;
      },
    );

    expect(result, <String, Object>{
      'type': 'CodeCoverage',
      'coverage': <Object>[
        <String, Object>{
          'source': 'package:foo/foo.dart',
          'script': <String, Object>{
            'type': '@Script',
            'fixedId': true,
            'id': 'libraries/1/scripts/package%3Afoo%2Ffoo.dart',
            'uri': 'package:foo/foo.dart',
            '_kind': 'library',
          },
          'hits': <Object>[1, 1, 3, 1, 2, 0],
        },
      ],
    });
    expect(fakeVmServiceHost.hasRemainingExpectations, false);
  });

  testWithoutContext('Coverage collector caches read files', () async {
    Directory? tempDir;
    try {
      tempDir = Directory.systemTemp.createTempSync('flutter_coverage_collector_test.');
      final File packagesFile = writeFooBarPackagesJson(tempDir);
      final Directory fooDir = Directory('${tempDir.path}/foo/');
      fooDir.createSync();
      final File fooFile = File('${fooDir.path}/foo.dart');
      fooFile.writeAsStringSync('hit\nnohit but ignored // coverage:ignore-line\nhit\n');

      final String packagesPath = packagesFile.path;
      final CoverageCollector collector = CoverageCollector(
          libraryNames: <String>{'foo', 'bar'},
          verbose: false,
          packagesPath: packagesPath,
          resolver: await CoverageCollector.getResolver(packagesPath)
        );
      await collector.collectCoverage(TestTestDevice(), connector: (Uri? uri) async {
        return createFakeVmServiceHostWithFooAndBar().vmService;
      });

      Future<void> getHitMapAndVerify() async {
        final Map<String, HitMap> gottenHitmap = <String, HitMap>{};
        await collector.finalizeCoverage(formatter: (Map<String, HitMap> hitmap) {
          gottenHitmap.addAll(hitmap);
          return '';
        });
        expect(gottenHitmap.keys.toList()..sort(), <String>['package:bar/bar.dart', 'package:foo/foo.dart']);
        expect(gottenHitmap['package:foo/foo.dart']!.lineHits, <int, int>{1: 1, /* 2: 0, is ignored in file */ 3: 1});
        expect(gottenHitmap['package:bar/bar.dart']!.lineHits, <int, int>{21: 1, 32: 0, 47: 1, 86: 0});
      }

      Future<void> verifyHitmapEmpty() async {
        final Map<String, HitMap> gottenHitmap = <String, HitMap>{};
        await collector.finalizeCoverage(formatter: (Map<String, HitMap> hitmap) {
          gottenHitmap.addAll(hitmap);
          return '';
        });
        expect(gottenHitmap.isEmpty, isTrue);
      }

      // Get hit map the first time.
      await getHitMapAndVerify();

      // Getting the hitmap clears it so we now doesn't get any data.
      await verifyHitmapEmpty();

      // Collecting again gets us the same data even though the foo file has been deleted.
      // This means that the fact that line 2 was ignored has been cached.
      fooFile.deleteSync();
      await collector.collectCoverage(TestTestDevice(), connector: (Uri? uri) async {
        return createFakeVmServiceHostWithFooAndBar().vmService;
      });
      await getHitMapAndVerify();
    } finally {
      tempDir?.deleteSync(recursive: true);
    }
  });

  testWithoutContext('Coverage collector records test timings when provided TestTimeRecorder', () async {
    Directory? tempDir;
    try {
      tempDir = Directory.systemTemp.createTempSync('flutter_coverage_collector_test.');
      final File packagesFile = writeFooBarPackagesJson(tempDir);
      final Directory fooDir = Directory('${tempDir.path}/foo/');
      fooDir.createSync();
      final File fooFile = File('${fooDir.path}/foo.dart');
      fooFile.writeAsStringSync('hit\nnohit but ignored // coverage:ignore-line\nhit\n');

      final String packagesPath = packagesFile.path;
      final LoggingLogger logger = LoggingLogger();
      final TestTimeRecorder testTimeRecorder = TestTimeRecorder(logger);
      final CoverageCollector collector = CoverageCollector(
          libraryNames: <String>{'foo', 'bar'},
          verbose: false,
          packagesPath: packagesPath,
          resolver: await CoverageCollector.getResolver(packagesPath),
          testTimeRecorder: testTimeRecorder
        );
      await collector.collectCoverage(TestTestDevice(), connector: (Uri? uri) async {
        return createFakeVmServiceHostWithFooAndBar().vmService;
      });

      // Expect one message for each phase.
      final List<String> logPhaseMessages = testTimeRecorder.getPrintAsListForTesting().where((String m) => m.startsWith('Runtime for phase ')).toList();
      expect(logPhaseMessages, hasLength(TestTimePhases.values.length));

      // Several phases actually does something, but here we just expect at
      // least one phase to take a non-zero amount of time.
      final List<String> logPhaseMessagesNonZero = logPhaseMessages.where((String m) => !m.contains(Duration.zero.toString())).toList();
      expect(logPhaseMessagesNonZero, isNotEmpty);
    } finally {
      tempDir?.deleteSync(recursive: true);
    }
  });
}

File writeFooBarPackagesJson(Directory tempDir) {
  final File file = File('${tempDir.path}/packages.json');
  file.writeAsStringSync(jsonEncode(<String, dynamic>{
    'configVersion': 2,
    'packages': <Map<String, String>>[
      <String, String>{
        'name': 'foo',
        'rootUri': 'foo',
      },
      <String, String>{
        'name': 'bar',
        'rootUri': 'bar',
      },
    ],
  }));
  return file;
}

FakeVmServiceHost createFakeVmServiceHostWithFooAndBar() {
  return FakeVmServiceHost(
    requests: <VmServiceExpectation>[
      FakeVmServiceRequest(
        method: 'getVersion',
        jsonResponse: Version(major: 3, minor: 51).toJson(),
      ),
      FakeVmServiceRequest(
        method: 'getVM',
        jsonResponse: (VM.parse(<String, Object>{})!
          ..isolates = <IsolateRef>[
            IsolateRef.parse(<String, Object>{
              'id': '1',
            })!,
          ]
        ).toJson(),
      ),
      FakeVmServiceRequest(
        method: 'getScripts',
        args: <String, Object>{
          'isolateId': '1',
        },
        jsonResponse: ScriptList(scripts: <ScriptRef>[
          ScriptRef(uri: 'package:foo/foo.dart', id: '1'),
          ScriptRef(uri: 'package:bar/bar.dart', id: '2'),
        ]).toJson(),
      ),
      FakeVmServiceRequest(
        method: 'getSourceReport',
        args: <String, Object>{
          'isolateId': '1',
          'reports': <Object>['Coverage'],
          'scriptId': '1',
          'forceCompile': true,
          'reportLines': true,
        },
        jsonResponse: SourceReport(
          ranges: <SourceReportRange>[
            SourceReportRange(
              scriptIndex: 0,
              startPos: 0,
              endPos: 0,
              compiled: true,
              coverage: SourceReportCoverage(
                hits: <int>[1, 3],
                misses: <int>[2],
              ),
            ),
          ],
          scripts: <ScriptRef>[
            ScriptRef(
              uri: 'package:foo/foo.dart',
              id: '1',
            ),
          ],
        ).toJson(),
      ),
      FakeVmServiceRequest(
        method: 'getSourceReport',
        args: <String, Object>{
          'isolateId': '1',
          'reports': <Object>['Coverage'],
          'scriptId': '2',
          'forceCompile': true,
          'reportLines': true,
        },
        jsonResponse: SourceReport(
          ranges: <SourceReportRange>[
            SourceReportRange(
              scriptIndex: 0,
              startPos: 0,
              endPos: 0,
              compiled: true,
              coverage: SourceReportCoverage(
                hits: <int>[47, 21],
                misses: <int>[32, 86],
              ),
            ),
          ],
          scripts: <ScriptRef>[
            ScriptRef(
              uri: 'package:bar/bar.dart',
              id: '2',
            ),
          ],
        ).toJson(),
      ),
    ],
  );
}

class TestTestDevice extends TestDevice {
  @override
  Future<void> get finished => Future<void>.delayed(const Duration(seconds: 1));

  @override
  Future<void> kill() => Future<void>.value();

  @override
  Future<Uri?> get observatoryUri => Future<Uri?>.value();

  @override
  Future<StreamChannel<String>> start(String entrypointPath) {
    throw UnimplementedError();
  }
}
