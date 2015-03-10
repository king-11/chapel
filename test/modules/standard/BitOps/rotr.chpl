use BitOps;

var x: uint(64) = 0xFFFFFFFF00000000;
writef("%@018xu\n", rotr(x, 17));

var x2: uint(32) = 0xFFFF0000;
writef("%@010xu\n", rotr(x2, 9));

var x3: uint(16) = 0xFF00;
writef("%@06xu\n", rotr(x3, 5));

var x4: uint(8) = 0xF0;
writef("%@04xu\n", rotr(x4, 3));
