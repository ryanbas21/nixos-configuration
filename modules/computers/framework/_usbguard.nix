# USBGuard for the framework — allowlist-only policy, manually imported.
#
# This file is `_`-prefixed (manual import, per the repo convention):
# framework.nix imports it directly. The policy was generated ON the
# laptop (`sudo usbguard generate-policy`, everything desired plugged
# in) — a policy generated elsewhere, or hand-written, is a lockout
# risk: a blocked fingerprint reader bricks the PAM login path
# (framework/_pam.nix), and the camera/audio/keyboard sit on internal
# USB hubs that must stay allowed.
#
# ADDING A DEVICE (easy): plug it in, then
#   just usbguard-add                  # rule appended here + allowed at runtime
#   git diff modules/computers/framework/_usbguard.nix   # review
#   just rebuild framework
# By hand: append a list element below (any indentation — see GOTCHA).
# Device not at hand? A partial rule is valid policy; every omitted
# condition is a wildcard:
#   ''allow id 046d:c52b name "USB Receiver"''
# Tighten to the full hashed form (usbguard-add does) once it's plugged.
# A trusted dock can be covered wholesale with one via-port rule:
#   ''allow via-port "1-2"''  (everything behind that hub port)
#
# GOTCHA: usbguard requires every rule at column 0 — one indented
# rule line fails the WHOLE file with a misleading ":1:1 parse
# error" (happened: pasted lines at mixed indentation inside a `''`
# string; Nix dedents only the shared minimum). Hence the list form:
# each rule is its own string, dedented independently, so a rule can
# never inherit stray indentation.
#
# Implicit policy (nixpkgs default ImplicitPolicyTarget=block) blocks
# anything NOT matched below. The mutable `ruleFile` escape hatch
# (`usbguard allow-device -p` appends without a rebuild) is
# deliberately NOT used: policy would drift out of git, and this repo
# is the source of truth.
#
# Threat model: evil-maid / malicious-charger USB attacks while
# traveling. The desktop (never leaves the LAN closet of the house)
# does not need this.
{ ... }:
{
  services.usbguard = {
    enable = true;
    # builtins.concatStringsSep (not lib.*): feature files bind no args
    rules = builtins.concatStringsSep "\n" [
      ''allow id 1d6b:0002 serial "0000:c1:00.3" name "xHCI Host Controller" hash "p9XdYtshh7dWZvylwnT2mODxf1un62IZMB3s1EZjqbs=" parent-hash "mJdJHWCEQ2iPsjBBi4Yl9tmTcJQmdVpgafPRzXlRV9U=" with-interface 09:00:00 with-connect-type ""''
      ''allow id 1d6b:0003 serial "0000:c1:00.3" name "xHCI Host Controller" hash "PLChdK1BFKqH43U/F3lMvYogMm+XT9HtnlHOTAFi7I8=" parent-hash "mJdJHWCEQ2iPsjBBi4Yl9tmTcJQmdVpgafPRzXlRV9U=" with-interface 09:00:00 with-connect-type ""''
      ''allow id 1d6b:0002 serial "0000:c1:00.4" name "xHCI Host Controller" hash "Hc8P2OygD2+wF1fFNwvlpeIVyRbf+OODwtf4qnle/Y8=" parent-hash "nZZ3nkqoEMlYNSKO2SeX1nR/LwLPE6GTayrbRu3D1pU=" with-interface 09:00:00 with-connect-type ""''
      ''allow id 1d6b:0003 serial "0000:c1:00.4" name "xHCI Host Controller" hash "AjHctB1ikRsMOZb3MFwkEap+3OJ2CNEvgva7qId8w6U=" parent-hash "nZZ3nkqoEMlYNSKO2SeX1nR/LwLPE6GTayrbRu3D1pU=" with-interface 09:00:00 with-connect-type ""''
      ''allow id 1d6b:0002 serial "0000:c3:00.3" name "xHCI Host Controller" hash "oSRBqitQDOgWuBAedOGgTHiwDU//ZY3Hg/EJsQfNmvM=" parent-hash "MoJ8FZSZJd/VDdGtr28IOLmQPH6G5m24G50ldOqGdfo=" with-interface 09:00:00 with-connect-type ""''
      ''allow id 1d6b:0003 serial "0000:c3:00.3" name "xHCI Host Controller" hash "yk4omAkIgm8hhcOiCo1YDe3mTaXCcxEIrpW0uIoamd0=" parent-hash "MoJ8FZSZJd/VDdGtr28IOLmQPH6G5m24G50ldOqGdfo=" with-interface 09:00:00 with-connect-type ""''
      ''allow id 1d6b:0002 serial "0000:c3:00.4" name "xHCI Host Controller" hash "ytflbcUR58vOaTlsVdDp+prbapFyL+b4z2vdOAgegjM=" parent-hash "0Zqwj+n2tT57N8mqsEeUWN4fJNpMYtDdL3cN6GSctzI=" with-interface 09:00:00 with-connect-type ""''
      ''allow id 1d6b:0003 serial "0000:c3:00.4" name "xHCI Host Controller" hash "8LvDdXu4NWbVU1Eh+I9LUc9dxnpFqnSPUFWXpeUyPtc=" parent-hash "0Zqwj+n2tT57N8mqsEeUWN4fJNpMYtDdL3cN6GSctzI=" with-interface 09:00:00 with-connect-type ""''
      ''allow id 05e3:0610 serial "" name "USB2.1 Hub" hash "wN6zO9hMsq5Y7khYb4zruchqQRKmvE5x5ezZhAsqsBs=" parent-hash "p9XdYtshh7dWZvylwnT2mODxf1un62IZMB3s1EZjqbs=" via-port "1-2" with-interface { 09:00:01 09:00:02 } with-connect-type "hardwired"''
      ''allow id 05e3:0610 serial "" name "USB2.0 Hub" hash "HtK/V9+iwK2EoOneULC1IMFJ2IxQr0rL9Q+N6BDFNak=" parent-hash "p9XdYtshh7dWZvylwnT2mODxf1un62IZMB3s1EZjqbs=" via-port "1-3" with-interface { 09:00:01 09:00:02 } with-connect-type "hardwired"''
      ''allow id 05e3:0610 serial "" name "USB2.0 Hub" hash "HtK/V9+iwK2EoOneULC1IMFJ2IxQr0rL9Q+N6BDFNak=" parent-hash "p9XdYtshh7dWZvylwnT2mODxf1un62IZMB3s1EZjqbs=" via-port "1-4" with-interface { 09:00:01 09:00:02 } with-connect-type "hardwired"''
      ''allow id 0e8d:e616 serial "000000000" name "Wireless_Device" hash "erna9raFW4Dl/v6M4pInxogL0kJv1XNVxBTVuoNFhBA=" parent-hash "p9XdYtshh7dWZvylwnT2mODxf1un62IZMB3s1EZjqbs=" with-interface { e0:01:01 e0:01:01 e0:01:01 e0:01:01 e0:01:01 e0:01:01 e0:01:01 e0:01:01 e0:01:01 e0:01:01 } with-connect-type "hardwired"''
      ''allow id 05e3:0625 serial "" name "USB3.2 Hub" hash "0olEPRnQvNPnpwy/UOWkolLZq6ny+vSecKk30lFkhaU=" parent-hash "PLChdK1BFKqH43U/F3lMvYogMm+XT9HtnlHOTAFi7I8=" via-port "2-2" with-interface 09:00:00 with-connect-type "hardwired"''
      ''allow id 0bda:5634 serial "200901010001" name "Laptop Camera" hash "kdGy3lEIo5D1obiHNVzRRuYdr6RtRQ9vx0YyT88kozE=" parent-hash "Hc8P2OygD2+wF1fFNwvlpeIVyRbf+OODwtf4qnle/Y8=" with-interface { 0e:01:00 0e:02:00 0e:02:00 0e:02:00 0e:02:00 0e:02:00 0e:02:00 0e:02:00 0e:02:00 } with-connect-type "hardwired"''
      ''allow id 32ac:0002 serial "11AD1D00A1D54004250F0B00" name "HDMI Expansion Card" hash "w5grSavP21MFyj8ITQWaHd5owgZ5t8YNsWekbTwPvI4=" parent-hash "oSRBqitQDOgWuBAedOGgTHiwDU//ZY3Hg/EJsQfNmvM=" with-interface { 11:00:00 03:00:00 } with-connect-type "hotplug"''
      ''allow id 27c6:609c serial "UID4DE1136C_XXXX_MOC_B0" name "Goodix Fingerprint USB Device" hash "FGZuFVh8bvyFC8DFsERwdqYOLspftbbt7IXkQrUT7Sg=" parent-hash "HtK/V9+iwK2EoOneULC1IMFJ2IxQr0rL9Q+N6BDFNak=" with-interface ff:00:00 with-connect-type "not used"''
      ''allow id 32ac:0012 serial "FRAKDKEN0100000000" name "Laptop 16 Keyboard Module - ANSI" hash "wAComNf/bbgUFa/Sa6/eN48MV26Rgltx2qirvRTUCs4=" parent-hash "HtK/V9+iwK2EoOneULC1IMFJ2IxQr0rL9Q+N6BDFNak=" with-interface { 03:01:01 03:00:00 03:00:00 03:00:00 } with-connect-type "not used"''
      ''allow id 1050:0407 serial "" name "YubiKey OTP+FIDO+CCID" hash "Q+A8QQReKclmBSaDIYja0w4Bx6ld2IU6wF7HFKdtJ3Q=" parent-hash "ytflbcUR58vOaTlsVdDp+prbapFyL+b4z2vdOAgegjM=" via-port "7-1" with-interface { 03:01:01 03:00:00 0b:00:00 } with-connect-type "hotplug"''
      ''allow id 346d:5678 serial "6623251307111393524" name "Disk 2.0" hash "lxcOp3T8O0DCOG3UPZOTq5ckAOfkROIo07G8ZGLLzDo=" parent-hash "wN6zO9hMsq5Y7khYb4zruchqQRKmvE5x5ezZhAsqsBs=" with-interface 08:06:50 with-connect-type "unknown"''
      ''allow id 346d:5678 serial "8395121156645118612" name "Disk 2.0" hash "b4L5kaEkCOnrV/KF+c41ChqlkaNwCscbic/VwyFR/48=" parent-hash "wN6zO9hMsq5Y7khYb4zruchqQRKmvE5x5ezZhAsqsBs=" with-interface 08:06:50 with-connect-type "unknown"''
  ''allow id 1050:0402 serial "" name "YubiKey FIDO" hash "YpBQwR62nUO3dTvHlfctSZzMY72nYdr+i+QW5VHUNEM=" parent-hash "wN6zO9hMsq5Y7khYb4zruchqQRKmvE5x5ezZhAsqsBs=" via-port "1-2.1" with-interface 03:00:00 with-connect-type "unknown"''
  ''allow id 1050:0402 serial "" name "YubiKey FIDO" hash "YpBQwR62nUO3dTvHlfctSZzMY72nYdr+i+QW5VHUNEM=" parent-hash "wN6zO9hMsq5Y7khYb4zruchqQRKmvE5x5ezZhAsqsBs=" via-port "1-2.2" with-interface 03:00:00 with-connect-type "unknown"''
  ''allow id 1050:0407 serial "" name "YubiKey OTP+FIDO+CCID" hash "Q+A8QQReKclmBSaDIYja0w4Bx6ld2IU6wF7HFKdtJ3Q=" parent-hash "wN6zO9hMsq5Y7khYb4zruchqQRKmvE5x5ezZhAsqsBs=" via-port "1-2.1" with-interface { 03:01:01 03:00:00 0b:00:00 } with-connect-type "unknown"''
  ''allow id 1050:0407 serial "" name "YubiKey OTP+FIDO+CCID" hash "Q+A8QQReKclmBSaDIYja0w4Bx6ld2IU6wF7HFKdtJ3Q=" parent-hash "wN6zO9hMsq5Y7khYb4zruchqQRKmvE5x5ezZhAsqsBs=" via-port "1-2.2" with-interface { 03:01:01 03:00:00 0b:00:00 } with-connect-type "unknown"''
      # usbguard-add appends new rules above this marker — keep it last
    ];
  };
}
