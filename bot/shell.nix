{pkgs ? import <nixpkgs> {} }:

pkgs.mkShell {
  name = "bot";

  buildInputs = with pkgs; [
    deno
  ];

  shellHook = ''

    # Install deployctl globally
    deno install -gArf jsr:@deno/deployctl
    # write the correct home fir and uncomment it
    # export PATH="/home/[Home dir]/.deno/bin:$PATH"
    # Confirm installation
    echo "deployctl version: $(deployctl --version)"
  '';

}
