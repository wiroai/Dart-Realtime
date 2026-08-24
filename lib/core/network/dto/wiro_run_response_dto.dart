import 'package:json_annotation/json_annotation.dart';

part 'wiro_run_response_dto.g.dart';

@JsonSerializable(
  checked: true,
  createToJson: false,
)
final class WiroRunResponseDto {
  const WiroRunResponseDto({
    required this.result,
    required this.errors,
    required this.taskId,
    required this.taskToken,
  });

  factory WiroRunResponseDto.fromJson(Map<String, dynamic> json) {
    return _$WiroRunResponseDtoFromJson(json);
  }

  final bool? result;
  final List<Object?>? errors;

  @JsonKey(name: 'taskid')
  final String? taskId;

  @JsonKey(name: 'socketaccesstoken')
  final String? taskToken;
}
