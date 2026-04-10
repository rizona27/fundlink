class ProfitResult {
  final double absolute;
  final double annualized;

  const ProfitResult({
    required this.absolute,
    required this.annualized,
  });

  factory ProfitResult.empty() {
    return const ProfitResult(absolute: 0.0, annualized: 0.0);
  }

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