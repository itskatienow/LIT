/// "2", "1.5", "0.33": [value] to at most [maxDecimals] places, without
/// trailing zeros.
String formatDecimal(double value, {int maxDecimals = 2}) {
  final fixed = value.toStringAsFixed(maxDecimals);
  return fixed.contains('.') ? fixed.replaceFirst(RegExp(r'\.?0+$'), '') : fixed;
}
