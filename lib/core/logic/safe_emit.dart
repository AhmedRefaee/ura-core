import 'package:flutter_bloc/flutter_bloc.dart';

/// Cubit.emit() throws StateError if called after close(). Async callbacks
/// (network responses, realtime events) can resolve after a screen is popped
/// and its cubit closed, so every emit following an await is a crash risk.
/// safeEmit is a no-op once the cubit is closed instead of throwing.
mixin SafeEmit<State> on Cubit<State> {
  void safeEmit(State state) {
    if (!isClosed) emit(state);
  }
}
