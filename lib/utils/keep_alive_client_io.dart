import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

http.Client newKeepAliveClient(Duration idle) =>
    IOClient(HttpClient()..idleTimeout = idle);
