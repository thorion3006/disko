{ diskoLib, config, options, lib, parent, device, ... }:
{
  options = {
    type = lib.mkOption {
      type = lib.types.enum [ "swap" ];
      internal = true;
      description = "Type";
    };
    device = lib.mkOption {
      type = lib.types.str;
      default = device;
      description = "Device";
    };
    discardPolicy = lib.mkOption {
      default = null;
      example = "once";
      type = lib.types.nullOr (lib.types.enum [ "once" "pages" "both" ]);
      description = lib.mdDoc ''
        Specify the discard policy for the swap device. If "once", then the
        whole swap space is discarded at swapon invocation. If "pages",
        asynchronous discard on freed pages is performed, before returning to
        the available pages pool. With "both", both policies are activated.
        See swapon(8) for more information.
      '';
    };
    extraArgs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Extra arguments";
    };
    randomEncryption = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether to randomly encrypt the swap";
    };
    resumeDevice = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether to use this as a boot.resumeDevice";
    };
    _parent = lib.mkOption {
      internal = true;
      default = parent;
    };
    _meta = lib.mkOption {
      internal = true;
      readOnly = true;
      type = lib.types.functionTo diskoLib.jsonType;
      default = _dev: { };
      description = "Metadata";
    };
    _create = diskoLib.mkCreateOption {
      inherit config options;
      default = ''
        if ! blkid "${config.device}" -o export | grep -q '^TYPE='; then
          mkswap \
            ${toString config.extraArgs} \
            ${config.device}
        fi
      '';
    };
    _mount = diskoLib.mkMountOption {
      inherit config options;
      # TODO: we don't support encrypted swap yet
      default = lib.optionalAttrs (!config.randomEncryption) {
        fs.${config.device} = ''
          if ! swapon --show | grep -q "^$(readlink -f ${config.device}) "; then
            swapon ${
              lib.optionalString (config.discardPolicy != null)
                "--discard${lib.optionalString (config.discardPolicy != "both")
                "=${config.discardPolicy}"
              }"} ${config.device}
          fi
        '';
      };
    };
    _config = lib.mkOption {
      internal = true;
      readOnly = true;
      default = [{
        swapDevices = [{
          device = config.device;
          inherit (config) discardPolicy randomEncryption;
        }];
        boot.resumeDevice = lib.mkIf config.resumeDevice config.device;
      }];
      description = "NixOS configuration";
    };
    _pkgs = lib.mkOption {
      internal = true;
      readOnly = true;
      type = lib.types.functionTo (lib.types.listOf lib.types.package);
      default = pkgs: [ pkgs.gnugrep pkgs.util-linux ];
      description = "Packages";
    };
  };
}
