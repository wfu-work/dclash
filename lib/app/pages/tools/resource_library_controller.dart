import 'package:file_picker/file_picker.dart';
import 'package:get/get.dart';

import '../../../domains/resource_item.dart';
import '../../../services/resource_library_service.dart';

class ResourceLibraryController extends GetxController {
  ResourceLibraryController(this.service);

  final ResourceLibraryService service;
  final query = ''.obs;
  final selectedKind = Rxn<ResourceKind>();

  List<ResourceItem> get visibleItems {
    final needle = query.value.trim().toLowerCase();
    return service.items
        .where((item) {
          if (selectedKind.value != null && item.kind != selectedKind.value) {
            return false;
          }
          return needle.isEmpty ||
              '${item.name} ${item.source}'.toLowerCase().contains(needle);
        })
        .toList(growable: false);
  }

  void setQuery(String value) => query.value = value;
  void setKind(ResourceKind? kind) => selectedKind.value = kind;

  Future<ResourceItem> saveItem({
    ResourceItem? existing,
    required String name,
    required ResourceKind kind,
    required ResourceSourceType sourceType,
    required String source,
  }) => service.save(
    id: existing?.id,
    name: name,
    kind: kind,
    sourceType: sourceType,
    source: source,
    content: existing?.content,
    enabled: existing?.enabled ?? true,
  );

  Future<void> removeItem(ResourceItem item) => service.remove(item.id);
  Future<void> toggleItem(ResourceItem item) =>
      service.setEnabled(item.id, !item.enabled);
  Future<ResourceItem> refreshItem(ResourceItem item) =>
      service.refresh(item.id);

  Future<String?> pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['yaml', 'yml', 'txt', 'json'],
      withData: false,
    );
    return result?.files.single.path;
  }
}
