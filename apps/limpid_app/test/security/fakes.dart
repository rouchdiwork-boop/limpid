import 'package:limpid_app/src/domain/two_factor_repository.dart';

/// The state of an account whose second factor is off.
const TwoFactorStatus fakeTwoFactorOff = TwoFactorStatus(
  enrolled: false,
  enabled: false,
  required: false,
);

/// The state of an account whose second factor is on.
const TwoFactorStatus fakeTwoFactorOn = TwoFactorStatus(
  enrolled: true,
  enabled: true,
  required: false,
);

/// The state of an account whose plan requires the second factor, which the
/// account has not enabled yet.
const TwoFactorStatus fakeTwoFactorRequired = TwoFactorStatus(
  enrolled: false,
  enabled: false,
  required: true,
);

/// The enrollment the fake serves.
const TwoFactorEnrollment fakeTwoFactorEnrollment = TwoFactorEnrollment(
  secret: 'JBSWY3DPEHPK3PXP',
  otpauthUrl: 'otpauth://totp/Limpid:auteur@test?secret=JBSWY3DPEHPK3PXP',
  digits: 6,
  periodSeconds: 30,
);

/// The recovery codes the fake serves.
const List<String> fakeRecoveryCodes = <String>[
  'limpid-aaaa-bbbb',
  'limpid-cccc-dddd',
];

/// The proof the fake serves.
final TwoFactorProof fakeTwoFactorProof = TwoFactorProof(
  proof: 'preuve-1',
  expiresAt: DateTime.utc(2099),
  method: TwoFactorMethod.totp,
);

/// A [TwoFactorRepository] the test drives by hand.
///
/// The fake holds l'état du compte, l'inscription et la preuve que le test
/// donne à l'écran : il ne lit rien du serveur.
final class FakeTwoFactorRepository implements TwoFactorRepository {
  /// Creates a repository.
  FakeTwoFactorRepository({TwoFactorStatus? state})
    : state = state ?? fakeTwoFactorOff;

  /// The state the repository serves.
  TwoFactorStatus state;

  /// The error every operation throws when it is set.
  Object? error;

  /// The error the confirmation throws when it is set.
  Object? confirmError;

  /// The error the verification throws when it is set.
  Object? verifyError;

  /// The codes the author confirmed.
  final List<String> confirmed = <String>[];

  /// The codes the author verified.
  final List<String> verified = <String>[];

  /// The number of times the second factor was disabled.
  int disableCount = 0;

  @override
  Future<TwoFactorStatus> status() async {
    final Object? failure = error;
    if (failure != null) throw failure;
    return state;
  }

  @override
  Future<TwoFactorEnrollment> enroll() async {
    final Object? failure = error;
    if (failure != null) throw failure;
    return fakeTwoFactorEnrollment;
  }

  @override
  Future<List<String>> confirm({required String code}) async {
    final Object? failure = confirmError ?? error;
    if (failure != null) throw failure;
    confirmed.add(code);
    state = TwoFactorStatus(
      enrolled: true,
      enabled: true,
      required: state.required,
    );
    return fakeRecoveryCodes;
  }

  @override
  Future<TwoFactorProof> verify({required String code}) async {
    final Object? failure = verifyError ?? error;
    if (failure != null) throw failure;
    verified.add(code);
    return fakeTwoFactorProof;
  }

  @override
  Future<void> disable() async {
    final Object? failure = error;
    if (failure != null) throw failure;
    disableCount++;
    state = TwoFactorStatus(
      enrolled: false,
      enabled: false,
      required: state.required,
    );
  }
}
