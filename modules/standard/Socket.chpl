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
  proc ipAddr.init(ref address:sys_sockaddr_t) {
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
    var addressStorage = new sys_sockaddr_t();
    var err = sys_getpeername(this.fd(), addressStorage);
    if(err != 0){
      throw SystemError.fromSyserr(err,"Failed to create Socket");
    }

    return new ipAddr(addressStorage);
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

  proc tcpListener.accept():file throws {
    var client_addr:sys_sockaddr_t = new sys_sockaddr_t();
    var fdOut:int(32);
    var rset, allset: fd_set;
    var timeo:timeval = new timeval(10,0);

    sys_fd_zero(allset);
    sys_fd_set(this.socketFd,allset);
    rset = allset;
    var nready:int(32);

    var err = sys_select(socketFd+1,c_ptrTo(rset),nil,nil,c_ptrTo(timeo),nready);
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

  proc bind(socketFd:fd_t, ref address: ipAddr, reuseAddr = true) throws {
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

  proc bind(socket:udpSocket, ref address: ipAddr, reuseAddr = true) throws {
    var socketFd = socket.socketFd;

    bind(socketFd, address, reuseAddr);
  }

  proc bind(socket:tcpListener, ref address: ipAddr, reuseAddr = true) throws {
    var socketFd = socket.socketFd;

    bind(socketFd, address, reuseAddr);
  }

  proc bind(socket:tcpConn, ref address: ipAddr, reuseAddr = true) throws {
    var socketFd = socket.fd();

    bind(socketFd, address, reuseAddr);
  }
}
