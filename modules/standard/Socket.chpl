/*
 * Copyright 2020-2021 Hewlett Packard Enterprise Development LP
 * Copyright 2004-2019 Cray Inc.
 * Other additional copyright holders may be indicated within.
 *
 * The entirety of this work is licensed under the Apache License,
 * Version 2.0 (the "License"); you may not use this file except
 * in compliance with the License.
 *
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
module Socket {

  public use Sys;
  use Time;
  use SysCTypes;
  use SysError;
  use SysBasic;
  use CPtr;
  use IO;

  enum IPFamily {
    IPv4 = 2,
    IPv6 = 10
  }

  const IPv4Localhost = INADDR_LOOPBACK;
  const IPv6Localhost = in6addr_loopback;

  record ipAddr {
    var _addressStorage:sys_sockaddr_t;
  }

  proc ipAddr.init(inout host:string = "localhost", port:uint(16) = 8000, family:IPFamily = IPFamily.IPv4) {
    if(host == "localhost"){
      host = if family == IPFamily.IPv4 then "127.0.0.1" else "::1";
    }

    _addressStorage = new sys_sockaddr_t();

    try! {
      _addressStorage.set(host.c_str(), port, family:c_int);
    }
  }

  proc ipAddr.init(host:sys_in_addr_t, port: uint(16) = 8000) {
    _addressStorage = new sys_sockaddr_t();

    try! {
      _addressStorage.set(host,port);
    }
  }

  proc ipAddr.init(host:sys_in6_addr_t, port: uint(16) = 8000) {
    _addressStorage = new sys_sockaddr_t();

    try! {
      _addressStorage.set(host,port);
    }
  }

  pragma "no doc"
  proc ipAddr.init(in address:sys_sockaddr_t) {
    this._addressStorage = new sys_sockaddr_t();
    try! {
      _addressStorage.set(address.numericHost().c_str(), address.port(), address.family);
    }
  }

  proc ipAddr.family {
    return _addressStorage.family;
  }

  proc ipAddr.host throws {
    return _addressStorage.numericHost();
  }

  proc ipAddr.port throws {
    return _addressStorage.port();
  }

  private extern proc qio_get_fd(fl:qio_file_ptr_t, ref fd:c_int):syserr;

  type tcpConn = file;

  proc tcpConn.fd():c_int throws {
    var tempfd:c_int;
    var err:syserr = ENOERR;
    on this.home {
      err = qio_get_fd(this._file_internal, tempfd);
    }
    if err then try ioerror(err, "in file.fd()");
    return tempfd;
  }

  proc tcpConn.addr throws {
    return getAddress(this.fd());
  }

  private extern proc sizeof(e): size_t;

  record tcpListener {
    var socketFd:int(32);
    var address:ipAddr;

    pragma "no doc"
    proc init(socketFd:int(32), address:ipAddr) {
      this.complete();
      this.socketFd = socketFd;
      this.address = address;
    }
  }

  proc tcpListener.accept(seconds = 0):file throws {
    var client_addr:sys_sockaddr_t = new sys_sockaddr_t();
    var fdOut:int(32);
    var rset, allset: fd_set;
    var timeout:timeval = new timeval(seconds,0);

    sys_fd_zero(allset);
    sys_fd_set(this.socketFd,allset);
    rset = allset;
    var nready:int(32);

    var err = sys_select(socketFd+1,c_ptrTo(rset),nil,nil,c_ptrTo(timeout),nready);
    if(nready == 0){
      writeln("timed out");
    }

    if(sys_fd_isset(socketFd,rset)){
      sys_accept(socketFd,client_addr,fdOut);
    }

    var sockFile:tcpConn = openfd(fdOut);
    return sockFile;
  }

  proc tcpListener.close() throws {
    sys_close(socketFd);
  }

  proc tcpListener.addr {
    return address;
  }

  proc tcpListener.family {
    return address.family;
  }

  proc listen(in address:ipAddr, reuseAddr=true, backlog=5) throws {
    var family = if address.family == AF_INET6 then IPFamily.IPv6 else IPFamily.IPv4;
    var socketFd = socket(family,SOCK_STREAM|SOCK_NONBLOCK);

    bind(socketFd, address, reuseAddr);

    var err = sys_listen(socketFd,backlog:int(32));
    if(err != 0){
      throw SystemError.fromSyserr(err,"Failed to listen on socket");
    }

    const tcpObject = new tcpListener(socketFd, address);
    return tcpObject;
  }

  proc connect(in address:ipAddr, in timeout = new timeval(0,0)):tcpConn throws {
    var family = if address.family == AF_INET6 then IPFamily.IPv6 else IPFamily.IPv4;
    var socketFd = socket(family, SOCK_STREAM|SOCK_NONBLOCK);

    var err = sys_connect(socketFd, address._addressStorage);
    if(err != 0 && err != EINPROGRESS){
      throw SystemError.fromSyserr(err,"Failed to connect");
    }

    if(err == 0) {
      var sockFile:tcpConn = openfd(socketFd);
      return sockFile;
    }

    var rset, wset: fd_set;

    sys_fd_zero(wset);
    sys_fd_set(socketFd, wset);
    rset = wset;
    var nready:int(32);

    err = sys_select(socketFd + 1, c_ptrTo(rset), c_ptrTo(wset), nil, c_ptrTo(timeout), nready);
    if(nready == 0){
      sys_close(socketFd);
      throw SystemError.fromSyserr(ETIMEDOUT, "connection timed out");
    }
    if(err != 0){
      throw SystemError.fromSyserr(err,"Failed to connect");
    }

    if(sys_fd_isset(socketFd, rset) != 0 || sys_fd_isset(socketFd, wset) != 0){
      var tempAddress = new sys_sockaddr_t();
      err = sys_getpeername(socketFd, address._addressStorage);
      if(err != 0) {
        var berkleyError:err_t;
        var ptrberkleyError = c_ptrTo(berkleyError);
        var voidPtrberkleyError:c_void_ptr = ptrberkleyError;
        var berkleySize:socklen_t = sizeof(berkleyError):socklen_t;
        err = sys_getsockopt(socketFd, SOL_SOCKET, SO_ERROR, voidPtrberkleyError, berkleySize);

        defer sys_close(socketFd);
        if(err != 0){
          throw SystemError.fromSyserr(err,"Failed to connect");
        }
        else if(berkleyError != 0){
          throw SystemError.fromSyserr(berkleyError,"Failed to connect");
        }
      }
    }
    else {
      sys_close(socketFd);
      throw new Error("Socket can't be connected");
    }

    var sockFile:tcpConn = openfd(socketFd);
    return sockFile;
  }

  /**
  * TODO: complete this
  */
  proc connect(host:string, port:int, family:int):tcpConn throws {

  }

  record udpSocket {
    var socketFd:int(32);

    proc init(family:IPFamily = IPFamily.IPv4) {
      this.socketFd = -1;
      try! {
        var sockFd = socket(family, SOCK_DGRAM|SOCK_NONBLOCK);
        this.socketFd = sockFd;
      }
    }
  }

  proc udpSocket.addr throws {
    return getAddress(this.socketFd);
  }

  extern proc sys_recv(sockfd:fd_t, buffer:c_void_ptr, len:size_t, flags:c_int, ref recvd_out:ssize_t):err_t;

  proc udpSocket.recv(buffer_len: int, in timeout = new timeval(0,0), flags:c_int = 0) throws {

    var rset: fd_set;
    sys_fd_zero(rset);
    sys_fd_set(this.socketFd, rset);
    var nready:int(32);

    var err_out = sys_select(socketFd + 1, c_ptrTo(rset), nil, nil, c_ptrTo(timeout), nready);
    if(nready == 0){
      throw SystemError.fromSyserr(ETIMEDOUT, "recv timed out");
    }
    if(err_out != 0){
      throw SystemError.fromSyserr(err_out);
    }

    var buffer = c_calloc(c_uchar, buffer_len);
    var length:ssize_t;
    err_out = sys_recv(this.socketFd, buffer, buffer_len:size_t, 0, length);
    if err_out != 0 {
      throw SystemError.fromSyserr(err_out, "error on recv");
    }

    return createBytesWithOwnedBuffer(buffer, length, buffer_len);
  }

  extern proc sys_recvfrom(sockfd:fd_t, buffer:c_void_ptr, len:size_t, flags:c_int, ref addr:sys_sockaddr_t,  ref recvd_out:ssize_t):err_t;

  proc udpSocket.recvfrom(buffer_len:int, in timeout = new timeval(0,0), flags:c_int = 0) throws {
    var rset: fd_set;
    sys_fd_zero(rset);
    sys_fd_set(this.socketFd, rset);
    var nready:int(32);

    var err_out = sys_select(socketFd + 1, c_ptrTo(rset), nil, nil, c_ptrTo(timeout), nready);
    if(nready == 0){
      throw SystemError.fromSyserr(ETIMEDOUT, "recv timed out");
    }
    if(err_out != 0){
      throw SystemError.fromSyserr(err_out);
    }

    var buffer = c_calloc(c_uchar, buffer_len);
    var length:c_int;
    var addressStorage = new sys_sockaddr_t();
    err_out = sys_recvfrom(this.socketFd, buffer, buffer_len, 0, addressStorage, length);
    if err_out != 0 {
      throw SystemError.fromSyserr(err_out);
    }

    return (createBytesWithOwnedBuffer(buffer, length, buffer_len), new ipAddr(addressStorage));
  }

  extern proc sys_sendto(sockfd:fd_t, buffer:c_void_ptr, len:size_t, flags:c_int, ref addr:sys_sockaddr_t,  ref recvd_out:ssize_t):err_t;

  proc udpSocket.send(data: bytes, in addr: ipAddr, in timeout = new timeval(0,0), flags:c_int = 0) throws {
    var wset: fd_set;
    sys_fd_zero(wset);
    sys_fd_set(this.socketFd, wset);
    var nready:int(32);

    var err_out = sys_select(socketFd + 1, nil, c_ptrTo(wset), nil, c_ptrTo(timeout), nready);
    if(nready == 0){
      throw SystemError.fromSyserr(ETIMEDOUT, "send timed out");
    }
    if(err_out != 0){
      throw SystemError.fromSyserr(err_out);
    }

    var length:ssize_t;
    err_out = sys_sendto(this.socketFd, data.c_str():c_void_ptr, data.size:size_t, flags, addr._addressStorage, length);
    if err_out != 0 {
      throw SystemError.fromSyserr(err_out);
    }

    return length;
  }

  /**
  * TODO: complete this
  */
  proc setSocketOpt() throws {

  }

  /**
  * TODO: getsocketOpt with tcpConn, tcpListener and udpSocket
  */
  proc getSocketOpt() throws {

  }

  proc getAddress(socketFD: int(32)) throws {
    var addressStorage = new sys_sockaddr_t();
    var err = sys_getpeername(socketFD, addressStorage);
    if(err != 0){
      throw SystemError.fromSyserr(err,"Failed to get address");
    }

    return new ipAddr(addressStorage);
  }

  proc socket(family:IPFamily = IPFamily.IPv4, sockType:c_int = SOCK_STREAM, protocol = 0) throws {
    var socketFd: int(32);
    var err = sys_socket(family:int(32), sockType|SOCK_CLOEXEC, 0, socketFd);
    if(err != 0){
      throw SystemError.fromSyserr(err,"Failed to create Socket");
    }

    return socketFd;
  }

  proc bind(socketFd:fd_t, in address: ipAddr, reuseAddr = true) throws {
    var enable:int = if reuseAddr then 1 else 0;
    if enable {
      var ptrEnable:c_ptr(int) = c_ptrTo(enable);
      var voidPtrEnable:c_void_ptr = ptrEnable;
      sys_setsockopt(socketFd,SOL_SOCKET,SO_REUSEADDR,voidPtrEnable,sizeof(enable):int(32));
    }

    var err = sys_bind(socketFd, address._addressStorage);
    if(err != 0){
      throw SystemError.fromSyserr(err,"Failed to bind Socket");
    }
  }

  proc bind(socket:udpSocket, in address: ipAddr, reuseAddr = true) throws {
    var socketFd = socket.socketFd;

    bind(socketFd, address, reuseAddr);
  }

  proc bind(socket:tcpListener, in address: ipAddr, reuseAddr = true) throws {
    var socketFd = socket.socketFd;

    bind(socketFd, address, reuseAddr);
  }

  proc bind(socket:tcpConn, in address: ipAddr, reuseAddr = true) throws {
    var socketFd = socket.fd();

    bind(socketFd, address, reuseAddr);
  }
}
