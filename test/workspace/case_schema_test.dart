import 'package:flutter_test/flutter_test.dart';

import '../helpers/workspace_sandbox.dart';

void main() {
  // ignore: missing-test-assertion, the assertions live in the helper below.
  test(
    'the committed schema rejects an off-contract case',
    _expectSchemaRejectsOffContractCases,
    skip: caseSchema == null
        ? 'needs a gleon checkout at ../gleon with the pinned commit $gleonPin'
        : null,
  );
}

void _expectSchemaRejectsOffContractCases() {
  final valid = {
    'candidate': {'sha256': '0' * 64},
    'comparison': {
      'masks': <Object>[],
      'policy_version': 2,
      'tolerance': {'kind': 'exact'},
    },
    'golden': {'path': 'a.png', 'sha256': '0' * 64},
    'name': 'a',
    'outcome': 'identical',
    'platform': {'arch': 'aarch64', 'os': 'macos'},
    'recorded_at': '2026-09-27T12:00:00.000Z',
    'regions': <Object>[],
    'schema_version': 4,
    'source': {'tool': 'gleon_flutter', 'tool_version': '0.1.0'},
    'timings_ms': {'total': 1.5},
  };
  final failed = {
    ...valid,
    'artifacts': {
      'candidate': '.gleon/runs/latest/artifacts/macos-aarch64/a/candidate.png',
    },
    'error_kind': 'image',
    'golden': {'blob': 'sha256:${'0' * 64}', 'path': 'a.png'},
    'outcome': 'error',
    'run_id': '12345',
  };
  final schema = caseSchema;

  expect(schema?.validate(valid).isValid, isTrue);
  expect(schema?.validate(failed).isValid, isTrue);
  for (final broken in [
    {...valid, 'schema_version': 2},
    {
      ...failed,
      'artifacts': {
        'candidate': '.gleon/runs/latest/artifacts/a/candidate.png',
      },
    },
    {...valid, 'outcome': 'passed'},
    {...valid, 'name': 'Upper/Case'},
    {...valid, 'extra': 1},
    {...failed, 'error_kind': 'disk'},
    {...failed, 'run_id': 'run 1'},
    {
      ...failed,
      'artifacts': {'image': 'a.png'},
    },
    {
      ...valid,
      'comparison': {
        'masks': <Object>[],
        'policy_version': 2,
        'tolerance': {'kind': 'exact', 'max_diff_ratio': 0.1},
      },
    },
  ]) {
    expect(schema?.validate(broken).isValid, isFalse, reason: '$broken');
  }
}
