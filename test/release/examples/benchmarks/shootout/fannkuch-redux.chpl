/* The Computer Language Benchmarks Game
 * http://benchmarksgame.alioth.debian.org/
 *
 * contributed by Kyle Brady and Brad Chamberlain
 * based on C implementation by Ledrug Katz
 *
 */

config const n = 7;

assert(n >= 3, "N must be in 3..");

const D = {0..n};
var s, t: [D] int;

proc main() {
  for i in D do
    s[i] = i;
  const (checksum, maxFlips) = tk();
  writeln(checksum);
  writeln("Pfannkuchen(", n, ") = ", maxFlips);
}


// Tompkin-Paige iterative permutation generation
proc tk() {
  var checksum, maxFlips = 0;
  var odd = false;
  var c: [D] int;

  var i = 0;
  while i < n {
    rotate(i);
    if c[i] >= i {
      c[i] = 0;
      i += 1;
      continue;
    }

    c[i] += 1;
    i = 1;
    odd = !odd;
    if s[0] {
      const f = if s[s[0]] then flip() else 1;
      if f > maxFlips then maxFlips = f;
      checksum += if odd then -f else f;
    }
  }

  return (checksum, maxFlips);
}


inline proc rotate(x) {
  const c = s[0];
  for i in 1..x {
    s[i-1] = s[i];
  }
  s[x] = c;
}


proc flip() {
  for i in D do
    t[i] = s[i];

  for i in 2..max(int) {
    var x = 0;
    var y = t[0];
    while x < y {
      t[x] <=> t[y];
      x += 1;
      y -= 1;
    }
    if t[t[0]] == 0 then return i;
  }
  return -1;
}
