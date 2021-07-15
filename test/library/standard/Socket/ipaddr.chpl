use Socket;
use UnitTest;

proc test_ipaddr_string_ipv4(test: borrowed Test) throws {
  var host = "127.0.0.1";
  var port:uint(16) = 8000;
  var family = IPFamily.IPv4;
  var addr = new ipAddr(host, port, family);
  test.assertEqual(addr.family:int, family:int);
  test.assertEqual(addr.host, host);
  test.assertEqual(addr.port, port);
}

proc test_ipaddr_string_ipv6(test: borrowed Test) throws {
  var host = "::1";
  var port:uint(16) = 8000;
  var family = IPFamily.IPv6;
  var addr = new ipAddr(host, port, family);
  test.assertEqual(addr.family:int, family:int);
  test.assertEqual(addr.host, host);
  test.assertEqual(addr.port, port);
}

proc test_ipaddr_ipv4_standard(test: borrowed Test) throws {
  var host = IPv4Localhost;
  var port:uint(16) = 8000;
  var family = IPFamily.IPv4;
  var addr = new ipAddr(host, port);
  test.assertEqual(addr.family:int, family:int);
  test.assertEqual(addr.host, "127.0.0.1");
  test.assertEqual(addr.port, port);
}

proc test_ipaddr_ipv6_standard(test: borrowed Test) throws {
  var host = IPv6Localhost;
  var port:uint(16) = 8000;
  var family = IPFamily.IPv6;
  var addr = new ipAddr(host, port);
  test.assertEqual(addr.family:int, family:int);
  test.assertEqual(addr.host, "::1");
  test.assertEqual(addr.port, port);
}

proc test_ipaddr_sockaddr_ipv4(test: borrowed Test) throws {
  var socket_addr:sys_sockaddr_t = new sys_sockaddr_t();
  var host = "127.0.0.1";
  var port:uint(16) = 8000;
  var family = AF_INET;
  socket_addr.set(host.c_str(), port, family);

  var addr = new ipAddr(socket_addr);
  test.assertEqual(addr.family, family);
  test.assertEqual(addr.host, host);
  test.assertEqual(addr.port, port);
}

proc test_ipaddr_sockaddr_ipv6(test: borrowed Test) throws {
  var socket_addr:sys_sockaddr_t = new sys_sockaddr_t();
  var host = "::1";
  var port:uint(16) = 8000;
  var family = AF_INET6;
  socket_addr.set(host.c_str(), port, family);

  var addr = new ipAddr(socket_addr);
  test.assertEqual(addr.family, family);
  test.assertEqual(addr.host, host);
  test.assertEqual(addr.port, port);
}

UnitTest.main();
