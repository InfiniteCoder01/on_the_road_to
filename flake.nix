{
  inputs = {
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem
      (system: let
        pkgs = nixpkgs.legacyPackages.${system};
      in
        {
          devShell = pkgs.mkShell {
            buildInputs = with pkgs; [
              zig
              zls
              python3
              ldtk
            ];
            inputsFrom = [
              pkgs.raylib { alsaSupport = true; }
            ];
          };
        }
      );
}
