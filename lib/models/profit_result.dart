class ProfitResult {
  final double absolute;
  final double annualized;

  const ProfitResult({
    required this.absolute,
    required this.annualized,
  });

  ProfitResult copyWith({
    double? absolute,
    double? annualized,
  }) {
    return ProfitResult(
      absolute: absolute ?? this.absolute,
      annualized: annualized ?? this.annualized,
    );
  }

  @override
  String toString() => 'ProfitResult(absolute: $absolute, annualized: $annualized)';
}