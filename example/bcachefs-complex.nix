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
						disk1 = {
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
						disk2 = {
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
    bpool = {
      broot = {
        type = "bpool";
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
				askPassword = true;
      };
    };
  };
}
