import 'package:connectivity_plus/connectivity_plus.dart';

/// Whether [results] (from `Connectivity().checkConnectivity()`) include a
/// connection that counts as "Wi-Fi" for the Wi-Fi-only download setting and
/// the local-server check.
///
/// Wired Ethernet counts too: a desktop on a cable is on the same home network
/// as one on Wi-Fi, and Windows PCs often have no Wi-Fi adapter at all.
bool isWifiOrEthernet(List<ConnectivityResult> results) =>
    results.contains(ConnectivityResult.wifi) ||
    results.contains(ConnectivityResult.ethernet);
