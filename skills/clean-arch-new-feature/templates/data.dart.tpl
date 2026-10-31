// ===== features/{{feature}}/data/dtos/{{entity}}_dto.dart =====
import 'package:json_annotation/json_annotation.dart';
part '{{entity}}_dto.g.dart';

@JsonSerializable()
class {{Entity}}Dto {
  const {{Entity}}Dto({required this.id});
  factory {{Entity}}Dto.fromJson(Map<String, dynamic> json) => _${{Entity}}DtoFromJson(json);
  final String id;
  Map<String, dynamic> toJson() => _${{Entity}}DtoToJson(this);
}

// ===== features/{{feature}}/data/mappers/{{entity}}_mapper.dart =====
extension {{Entity}}DtoMapper on {{Entity}}Dto {
  {{Entity}} toEntity() => {{Entity}}(id: id);
}

// ===== features/{{feature}}/data/sources/remote_{{feature}}_data_source.dart =====
// `HttpClient` is the core/http abstraction (base URL, auth, interceptors). It throws
// ApiException for network errors and non-2xx responses and returns decoded JSON.
class Remote{{Feature}}DataSource {
  Remote{{Feature}}DataSource(this._client);
  final HttpClient _client;

  Future<List<{{Entity}}Dto>> fetch{{Entity}}s() async {
    final json = await _client.get('/{{feature}}') as List<dynamic>;
    return json.cast<Map<String, dynamic>>().map({{Entity}}Dto.fromJson).toList();
  }
}

// ===== features/{{feature}}/data/{{feature}}_repository_impl.dart =====
class {{Feature}}RepositoryImpl implements {{Feature}}Repository {
  {{Feature}}RepositoryImpl(this._remote);
  final Remote{{Feature}}DataSource _remote;

  @override
  Future<Result<List<{{Entity}}>>> get{{Entity}}s() async {
    try {
      final dtos = await _remote.fetch{{Entity}}s();
      return Success(dtos.map((d) => d.toEntity()).toList());
    } on ApiException catch (e) {
      return Failure(e.toFailure());
    }
  }
}

// ===== features/{{feature}}/data/mock_{{feature}}_repository.dart =====
class Mock{{Feature}}Repository implements {{Feature}}Repository {
  @override
  Future<Result<List<{{Entity}}>>> get{{Entity}}s() async =>
      const Success([{{Entity}}(id: '1')]);
}
