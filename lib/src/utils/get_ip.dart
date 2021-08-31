import 'dart:io';

import 'package:shelf/shelf.dart';

/// Get remote IP address.
String getIp(Request request) {
  final info =
      request.context['shelf.io.connection_info'] as HttpConnectionInfo;
  return info.remoteAddress.host;
}
