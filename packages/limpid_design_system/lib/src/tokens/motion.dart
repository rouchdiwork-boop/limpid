import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';

/// The four motion curves of the Limpid design system.
///
/// They mirror the CSS `cubic-bezier(x1, y1, x2, y2)` specification so that
/// the Flutter application and the HTML mockups share the exact same timing
/// feel.
abstract final class LimpidCurves {
  /// The default curve for elements entering or moving on screen.
  static const Curve standard = LimpidCubicBezier(0.2, 0, 0, 1);

  /// The curve for elements that decelerate into their final position.
  static const Curve decelerate = LimpidCubicBezier(0, 0, 0, 1);

  /// The curve for elements leaving the screen.
  static const Curve exit = LimpidCubicBezier(0.4, 0, 1, 1);

  /// The curve for emphasised, attention drawing transitions.
  static const Curve emphasized = LimpidCubicBezier(0.2, 0, 0, 1);

  /// Every curve of the system, keyed by its token name.
  static const Map<String, Curve> values = <String, Curve>{
    'standard': standard,
    'decelerate': decelerate,
    'exit': exit,
    'emphasized': emphasized,
  };
}

/// A CSS compatible `cubic-bezier` easing curve.
///
/// The horizontal component of the curve is inverted with a Newton-Raphson
/// iteration (backed by a bisection fallback) and the vertical component is
/// then evaluated with the resulting parameter.
@immutable
class LimpidCubicBezier extends Curve {
  /// Creates a cubic bezier easing curve from its four control values.
  const LimpidCubicBezier(this.x1, this.y1, this.x2, this.y2);

  /// The x coordinate of the first control point.
  final double x1;

  /// The y coordinate of the first control point.
  final double y1;

  /// The x coordinate of the second control point.
  final double x2;

  /// The y coordinate of the second control point.
  final double y2;

  /// Maximum number of Newton-Raphson iterations.
  static const int _maxIterations = 8;

  /// Precision used by the solver and by the fallback bisection.
  static const double _epsilon = 1e-6;

  @override
  double transformInternal(double t) {
    if (t <= 0) {
      return 0;
    }
    if (t >= 1) {
      return 1;
    }
    return _y(_solveX(t));
  }

  double _solveX(double x) {
    double t = x;
    for (int i = 0; i < _maxIterations; i++) {
      final double error = _x(t) - x;
      if (error.abs() < _epsilon) {
        return t;
      }
      final double derivative = _dx(t);
      if (derivative.abs() < _epsilon) {
        break;
      }
      t -= error / derivative;
    }
    return _bisect(x);
  }

  double _bisect(double x) {
    double low = 0;
    double high = 1;
    double t = x;
    while (high - low > _epsilon) {
      t = (low + high) / 2;
      if (_x(t) > x) {
        high = t;
      } else {
        low = t;
      }
    }
    return t;
  }

  double _x(double t) {
    final double inverse = 1 - t;
    return 3 * x1 * t * inverse * inverse +
        3 * x2 * t * t * inverse +
        t * t * t;
  }

  double _dx(double t) {
    final double inverse = 1 - t;
    return 3 * x1 * inverse * inverse + 6 * x2 * t * inverse + 3 * t * t;
  }

  double _y(double t) {
    final double inverse = 1 - t;
    return 3 * y1 * t * inverse * inverse +
        3 * y2 * t * t * inverse +
        t * t * t;
  }
}

/// The canonical durations and curves of the Limpid design system.
@immutable
class LimpidMotion {
  /// Creates the motion scale.
  const LimpidMotion({
    this.instant = Duration.zero,
    this.fast = const Duration(milliseconds: 120),
    this.base = const Duration(milliseconds: 180),
    this.slow = const Duration(milliseconds: 260),
    this.slower = const Duration(milliseconds: 400),
    this.standard = LimpidCurves.standard,
    this.decelerate = LimpidCurves.decelerate,
    this.exit = LimpidCurves.exit,
    this.emphasized = LimpidCurves.emphasized,
  });

  /// No animation at all.
  final Duration instant;

  /// Fast feedback, for hover and press states.
  final Duration fast;

  /// Default duration, for most transitions.
  final Duration base;

  /// Slow duration, for large surfaces.
  final Duration slow;

  /// Slowest duration, for page level transitions.
  final Duration slower;

  /// Curve used by elements entering or moving on screen.
  final Curve standard;

  /// Curve used by elements decelerating into their final position.
  final Curve decelerate;

  /// Curve used by elements leaving the screen.
  final Curve exit;

  /// Curve used by emphasised transitions.
  final Curve emphasized;

  /// Every duration of the scale, in milliseconds.
  static const List<int> durations = <int>[0, 120, 180, 260, 400];

  @override
  String toString() => 'LimpidMotion(${durations.join(', ')} ms)';
}
