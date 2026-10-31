import 'package:absorb/utils/unmetered_network.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';

// "Wi-Fi only" downloads and the local-server check accept a wired
// connection too: a desktop on Ethernet is on the home network.
void main() {
  test('Wi-Fi and Ethernet count, alone or with other links', () {
    expect(isWifiOrEthernet([ConnectivityResult.wifi]), isTrue);
    expect(isWifiOrEthernet([ConnectivityResult.ethernet]), isTrue);
    expect(
      isWifiOrEthernet([ConnectivityResult.vpn, ConnectivityResult.ethernet]),
      isTrue,
    );
    expect(
      isWifiOrEthernet([ConnectivityResult.mobile, ConnectivityResult.wifi]),
      isTrue,
    );
  });

  test('mobile data, VPN alone and no connection do not count', () {
    expect(isWifiOrEthernet([ConnectivityResult.mobile]), isFalse);
    expect(isWifiOrEthernet([ConnectivityResult.vpn]), isFalse);
    expect(isWifiOrEthernet([ConnectivityResult.bluetooth]), isFalse);
    expect(isWifiOrEthernet([ConnectivityResult.none]), isFalse);
    expect(isWifiOrEthernet(const []), isFalse);
  });
}
