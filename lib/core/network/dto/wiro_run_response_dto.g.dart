// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'wiro_run_response_dto.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

WiroRunResponseDto _$WiroRunResponseDtoFromJson(Map<String, dynamic> json) =>
    $checkedCreate(
      'WiroRunResponseDto',
      json,
      ($checkedConvert) {
        final val = WiroRunResponseDto(
          result: $checkedConvert('result', (v) => v as bool?),
          errors: $checkedConvert('errors', (v) => v as List<dynamic>?),
          taskId: $checkedConvert('taskid', (v) => v as String?),
          taskToken: $checkedConvert('socketaccesstoken', (v) => v as String?),
        );
        return val;
      },
      fieldKeyMap: const {'taskId': 'taskid', 'taskToken': 'socketaccesstoken'},
    );
