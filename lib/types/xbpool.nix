{ config, options, lib, rootMountPoint, diskoLib, toplevel-config, ... }:
{
  options = {
    name = lib.mkOption {
      type = lib.types.str;
      default = config._module.args.name;
      description = "Name of BcacheFS Pool";
    };
    type = lib.mkOption {
      type = lib.types.enum [ "xbpool" ];
      default = "xbpool";
      internal = true;
      description = "Type";
    };
    extraArgs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Extra arguments";
    };
    passwordFile = lib.mkOption {
      type = lib.types.nullOr diskoLib.optionTypes.absolute-pathname;
      default = null;
      description = "Path to the file containing the password for encryption";
      example = "/tmp/disk.key";
    };
    mountOptions = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "defaults" ];
      description = "A list of options to pass to mount.";
    };
    mountpoint = lib.mkOption {
      type = lib.types.nullOr diskoLib.optionTypes.absolute-pathname;
      default = null;
      description = "A path to mount the bcachefs filesystem to.";
    };
    subvolumes = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule ({ config, ... }: {
        options = {
          name = lib.mkOption {
            type = lib.types.str;
            default = config._module.args.name;
            description = "Name of the Bcachefs subvolume.";
          };
        };
      }));
      default = { };
      description = "Subvolumes to define for Bcachefs.";
    };
    _meta = lib.mkOption {
      internal = true;
      readOnly = true;
      type = diskoLib.jsonType;
      default = { };
      description = "Metadata";
    };
    _create = diskoLib.mkCreateOption {
      inherit config options;
      default = ''
        readarray -t bcachefs_devices < <(cat "$disko_devices_dir"/bcachefs_${config.name}/devices)
        readarray -t bcachefs_labels < <(cat "$disko_devices_dir"/bcachefs_${config.name}/labels)
        readarray -t bcachefs_extra_arguments < <(cat "$disko_devices_dir"/bcachefs_${config.name}/extra_args)

        device_configs=()
        for ((i=0; i<''${#bcachefs_devices[@]}; i++)); do
            device=''${bcachefs_devices[$i]}
            label=''${bcachefs_labels[$i]}
            extra_arguments=''${bcachefs_extra_arguments[$i]}
            device_configs+=("--label=$label $extra_arguments $device")
        done

        # Currently the keyutils package is required due to an upstream bug
        # https://github.com/NixOS/nixpkgs/issues/32279
        keyctl link @u @s
        bcachefs format --fs_label=${config.name} ${lib.concatStringsSep " " config.extraArgs} \
          $(IFS=' \' ; echo "''${device_configs[*]}") \
          ${lib.optionalString (config.passwordFile != null) "--encrypted <<<\"$(cat ${config.passwordFile})\""}
        disks=$(IFS=':' ; echo "''${bcachefs_devices[*]}")
        disks=${disks: 2}
        ${lib.optionalString (config.passwordFile != null) "bcachefs unlock $disks <<<\"$(cat ${config.passwordFile})\""}
        ${lib.concatMapStrings (subvol: ''
          (
            MNTPOINT=$(mktemp -d)
            mount $disks "$MNTPOINT"
            trap 'umount $MNTPOINT; rm -rf $MNTPOINT' EXIT
            echo "creating subvol ${subvol.name}"
            bcachefs subvolume create "$MNTPOINT"${subvol.name}
          )
        '') (lib.attrValues config.subvolumes)}
      '';
    };
    _mount = diskoLib.mkMountOption {
      inherit config options;
      default = {
        fs = lib.optionalAttrs (config.mountpoint != null) {
          ${config.mountpoint} = ''
            readarray -t bcachefs_devices < <(cat "$disko_devices_dir"/bcachefs_${config.name}/devices)
            disks=$(IFS=':' ; echo "''${bcachefs_devices[*]}")
            disks=${disks: 2}
            ${lib.optionalString (config.passwordFile != null) "bcachefs unlock $disks <<<\"$(cat ${config.passwordFile})\""}
            mount -t bcachefs $disks "${rootMountPoint}${config.mountpoint}" \
              ${lib.concatMapStringsSep " " (opt: "-o ${opt}") config.mountOptions} \
              -o X-mount.mkdir
          '';
        };
      };
    };
    _config = lib.mkOption {
      internal = true;
      readOnly = true;
      default = [ {
          fileSystems.${config.mountpoint} = {
            device = "${lib.concatStringsSep ":" (lib.traceVal toplevel-config.disko.devices._internal.xbpools).${config.name}}";
            fsType = "bcachefs";
            options = config.mountOptions;
          };
        }
      ];
      description = "NixOS configuration";
    };
    _pkgs = lib.mkOption {
      internal = true;
      readOnly = true;
      type = lib.types.functionTo (lib.types.listOf lib.types.package);
      default = pkgs:
        # Currently the keyutils package is required due to an upstream bug
        # https://github.com/NixOS/nixpkgs/issues/32279
        with pkgs; [ bcachefs-tools coreutils keyutils ];
      description = "Packages";
    };
  };
}
