import 'local_file_source.dart';

LocalFileSource createLocalFileSource() => WebFileSource();

class WebFileSource implements LocalFileSource {
  @override
  bool get canReadLocalFiles => false;

  @override
  Future<int> lengthOf(String path) async =>
      throw UnsupportedError('The web build cannot read local paths.');

  @override
  Stream<List<int>> openRead(String path) =>
      throw UnsupportedError('The web build cannot read local paths.');

  @override
  Future<void> delete(String path) async =>
      throw UnsupportedError('The web build cannot delete local files.');

  @override
  String mimeTypeFor(String path) => 'application/octet-stream';
}
