// Conditional export
export 'launcher_stub.dart'
    if (dart.library.io) 'launcher_io.dart'
    if (dart.library.html) 'launcher_web.dart';
