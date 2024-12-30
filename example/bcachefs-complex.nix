{
  disko.devices = {
    disk = {
      vda = {
        type = "disk";
				device = "/dev/vda";
				content = {
					type = "gpt";
					partitions = {
						ESP = {
							size = "1G";
							type = "EF00";
							content = {
								type = "filesystem";
					format = "vfat";
					mountpoint = "/boot";
							};
						};
						bcachefs = {
							end = "-0";
							content = {
								type = "bcachefs";
					pool = "broot";
					label = "disk1";
							};
						};
					};
				};
      };
      vdb = {
        type = "disk";
				device = "/dev/vdb";
				content = {
					type = "gpt";
					partitions = {
						bcachefs = {
							end = "-0";
							content = {
								type = "bcachefs";
					pool = "broot";
					label = "disk2";
							};
						};
					};
				};
      };
    };
    xbpool = {
      broot = {
        type = "xbpool";
				mountpoint = "/";
				extraArgs = [
					"--compression zstd:3"
					"--background_compression zstd:5"
					"--discard"
				];
				subvolumes = {
					"/home" = {};
					"/nix" = {};
				};
				passwordFile = "/tmp/secret.key";
      };
    };
  };
}
