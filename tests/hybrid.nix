{ pkgs ? (import <nixpkgs> { })
, makeDiskoTest ? (pkgs.callPackage ./lib.nix { }).makeDiskoTest
}:
makeDiskoTest {
  disko-config = ../example/hybrid.nix;
  extraTestScript = ''
    machine.succeed("mountpoint /");
  '';
}