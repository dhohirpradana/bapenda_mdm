import 'package:bapenda_mdm/constants/constant.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get_state_manager/src/simple/get_controllers.dart';
import 'package:pocketbase/pocketbase.dart';

class ContentController extends GetxController {
  updateImageVideo(RecordModel record) {
    debugPrint("Updating content record: ${record.toJson()}");
    final collectionId = record.collectionId;
    final recordId = record.id;
    final file = record.data['file'] as String?;

    final url = file != null && file.isNotEmpty
        ? "${Constants.pocketbaseUrl}/api/files/$collectionId/$recordId/$file"
        : null;

    debugPrint("Content file URL: $url");
  }
}
