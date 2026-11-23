/// Guesses the rest of the line being typed. The heuristic one is the default; F7 adds API-backed ones.
public protocol PredictionProvider: Sendable {
    func predict(_ context: PredictionContext) -> Prediction?
}
