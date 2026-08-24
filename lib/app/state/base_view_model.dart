import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

abstract base class BaseViewModel<State extends Equatable>
    extends ValueNotifier<State> {
  BaseViewModel(super._value);

  State get state => value;

  @protected
  void emit(State nextState) {
    if (nextState == value) {
      return;
    }
    value = nextState;
  }
}
