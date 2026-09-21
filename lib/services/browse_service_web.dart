import '../models/storage_models.dart';
import 'browse_service.dart';

BrowseService createBrowseService() => WebBrowseService();

class WebBrowseService implements BrowseService {
  @override
  bool get available => false;

  @override
  Future<List<BrowseEntry>> list(String path) async =>
      throw BrowseException('A browser cannot read your local disk.');

  @override
  Future<List<FileEntry>> collectFiles(Iterable<BrowseEntry> entries) async =>
      const [];
}
