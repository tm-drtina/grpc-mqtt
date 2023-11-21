{ mkDerivation, base, bytestring, cereal, containers, criterion
, deepseq, doctest, fetchgit, hashable, lib, parameterized
, primitive, QuickCheck, random, safe, tasty, tasty-hunit
, tasty-quickcheck, template-haskell, text, text-short
, transformers, unordered-containers, vector, word-compat
}:
mkDerivation {
  pname = "proto3-wire";
  version = "1.4.1";
  src = fetchgit {
    url = "https://github.com/awakesecurity/proto3-wire.git";
    sha256 = "1mq5qp778g5zjj17lj9d0db7b7j6bhv94lf68xlla5dba8vzfl8r";
    rev = "938523213d5de2d0ad9ece051d1a03002ee539cc";
    fetchSubmodules = true;
  };
  libraryHaskellDepends = [
    base bytestring cereal containers deepseq hashable parameterized
    primitive QuickCheck safe template-haskell text text-short
    transformers unordered-containers vector word-compat
  ];
  testHaskellDepends = [
    base bytestring cereal doctest QuickCheck tasty tasty-hunit
    tasty-quickcheck text text-short transformers vector
  ];
  benchmarkHaskellDepends = [ base bytestring criterion random ];
  description = "A low-level implementation of the Protocol Buffers (version 3) wire format";
  license = lib.licenses.asl20;
}
