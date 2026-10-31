// ===== features/{{feature}}/domain/entities/{{entity}}.dart =====
import 'package:equatable/equatable.dart';

class {{Entity}} extends Equatable {
  const {{Entity}}({required this.id});
  final String id;

  @override
  List<Object?> get props => [id];
}

// ===== features/{{feature}}/domain/repositories/{{feature}}_repository.dart =====
import 'package:{{app}}/core/error/result.dart';
import 'package:{{app}}/features/{{feature}}/domain/entities/{{entity}}.dart';

abstract interface class {{Feature}}Repository {
  Future<Result<List<{{Entity}}>>> get{{Entity}}s();
}

// ===== features/{{feature}}/domain/use_cases/get_{{entity}}s.dart =====
// OPTIONAL: this is a pass-through use case. Keep it only if the project convention is
// "cubits talk to use cases". For a thin display-only feature, delete this section and
// inject {{Feature}}Repository into the cubit and providers instead (and say so in the
// feature README). Add real use cases only for actions with rules or reuse.
class Get{{Entity}}s {
  const Get{{Entity}}s(this._repository);
  final {{Feature}}Repository _repository;

  Future<Result<List<{{Entity}}>>> call() => _repository.get{{Entity}}s();
}
