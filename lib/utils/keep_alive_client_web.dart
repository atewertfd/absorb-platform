import 'package:http/http.dart' as http;

http.Client newKeepAliveClient(Duration idle) => http.Client();
