{ config
, options
, lib
, rootMountPoint
, diskoLib
, toplevel-config
, ...
}: let unlock_disk = ''
  readarray -t bcachefs_devices < <(cat "$disko_devices_dir"/bcachefs_${config.name}/devices)
  unlock_disk="''${bcachefs_devices[0]}"
  <(set +x; echo -n "$unlock_disk"; set -x)
''; in {
  options = {
    name = lib.mkOption {
      type = lib.types.str;
      default = config._module.args.name;
      description = "Name of BcacheFS Pool";
    };
    type = lib.mkOption {
      type = lib.types.enum [ "bpool" ];
      default = "bpool";
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
    askPassword = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether to ask for a password for encryption";
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
    initrdUnlock = lib.mkOption {
      type = lib.types.bool;
      default = config.passwordFile != null || config.askPassword;
      description = "Whether to add a boot.initrd entry for auto-unlock.";
    };
    _meta = lib.mkOption {
      internal = true;
      readOnly = true;
      type = diskoLib.jsonType;
      default = dev:
        lib.optionalAttrs (config.content != null) (config.content._meta dev);
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

        ${lib.optionalString (config.passwordFile == null && config.askPassword) ''
          askPassword() {
            if [ -z "''${IN_DISKO_TEST+x}" ]; then
              set +x
              echo "Enter the password for the test: "
              IFS= read -r -s password
              echo "Please confirm the password: "
              IFS= read -r -s password_check

              if [ "$password" != "$password_check" ]; then
                return 1  # Indicate that the passwords did not match
              fi

              encryption_key=$password
            else
              encryption_key="disko"
            fi

            return 0  # Indicate success
          }
          until askPassword; do
            echo "Passwords did not match, please try again."
          done
        ''}

        ${lib.optionalString (config.passwordFile != null) "encryption_key=\"$(cat ${config.passwordFile})\""}

        # Currently the keyutils package is required due to an upstream bug
        # https://github.com/NixOS/nixpkgs/issues/32279
        keyctl link @u @s
        if [ -n "$encryption_key" ]; then
            bcachefs format --fs_label=${config.name} ${lib.concatStringsSep " " config.extraArgs} \
              $(IFS=' \' ; echo "''${device_configs[*]}") \
              --encrypted <<<$encryption_key
        else
            bcachefs format --fs_label=${config.name} ${lib.concatStringsSep " " config.extraArgs} \
              $(IFS=' \' ; echo "''${device_configs[*]}")
        fi
        disks=$(IFS=':' ; echo "''${bcachefs_devices[*]}")
        if [ -n "$encryption_key" ]; then
            bcachefs unlock ${unlock_disk} <<<$encryption_key
        fi
        ${lib.concatMapStrings (subvol: ''
          (
            MNTPOINT=$(mktemp -d)
            mount -t bcachefs $disks "$MNTPOINT"
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
            ${lib.optionalString (config.passwordFile == null && config.askPassword) ''
              askPassword() {
                if [ -z "''${IN_DISKO_TEST+x}" ]; then
                  set +x
                  echo "Enter the password for the test: "
                  IFS= read -r -s password
                  echo "Please confirm the password: "
                  IFS= read -r -s password_check

                  if [ "$password" != "$password_check" ]; then
                    return 1  # Indicate that the passwords did not match
                  fi

                  encryption_key=$password
                else
                  encryption_key="disko"
                fi

                return 0  # Indicate success
              }
              until askPassword; do
                echo "Passwords did not match, please try again."
              done
            ''}

            ${lib.optionalString (config.passwordFile != null) "encryption_key=\"$(cat ${config.passwordFile})\""}
            if [ -n "$encryption_key" ]; then
                bcachefs unlock ${unlock_disk} <<<$encryption_key
            fi
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
      default =
        [
          {
            fileSystems.${config.mountpoint} = {
              device = "${lib.concatStringsSep ":" (lib.traceVal toplevel-config.disko.devices._internal.bpools).${config.name}}";
              fsType = "bcachefs";
              options = config.mountOptions;
            };
          }
        ]
        # If initrdUnlock is true, then add a device entry to the initrd config.
        ++ (lib.optional config.initrdUnlock [
          {
            boot.initrd.systemd.enable = true;
            boot.initrd.systemd.services."unlock-${config.name}" = {
              enable = true;
              unitConfig = { Description = "Unlock ${config.name} bcachefs drive"; };
              serviceConfig = {
                Type = "oneshot";
                User = "root";
                ExecStart="bcachefs unlock ${unlock_disk}";
              };
              after = [ "local-fs.target" ];
              wantedBy = [ "multi-user.target" ];
            };
          }
        ]);
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
