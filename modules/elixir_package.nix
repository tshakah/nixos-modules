{
  pkgs,
  name,
  src,
  binaryName ? name,
  preBuild ? "",
  postBuild ? null,
  postInstall ? "",
  postUnpack ? "",
  ...
}:
with pkgs;
with beamPackages; let
  mixNixDeps = import "${src}/deps.nix" {
    inherit beamPackages lib pkgs;
  };

  version = runCommand "get-rev" {} ''
    cd ${src}
    cat mix.exs | grep version | sed -e 's/.*version: "\(. * \)",/\1/' > $out
  '';
in
  mixRelease {
    inherit mixNixDeps version preBuild postUnpack;

    pname = name;
    src = src;
    meta.mainProgram = binaryName;
    PRECOMPILED_NIF = true;
    stripDebug = true;

    postBuild =
      if postBuild != null
      then postBuild
      else ''
        tailwind_path="$(mix do \
          app.config --no-deps-check --no-compile, \
          eval 'Tailwind.bin_path() |> IO.puts()')"
        esbuild_path="$(mix do \
          app.config --no-deps-check --no-compile, \
          eval 'Esbuild.bin_path() |> IO.puts()')"

        ln -sfv ${tailwindcss_4}/bin/tailwindcss "$tailwind_path"
        ln -sfv ${esbuild}/bin/esbuild "$esbuild_path"
        ln -sfv ${mixNixDeps.heroicons} deps/heroicons

        mix do \
          app.config --no-deps-check --no-compile, \
          assets.deploy --no-deps-check

        mkdir -p "$out/nginx"
        cp nginx/* "$out/nginx/"
      '';

    postInstall = ''
      ${postInstall}

      wrapProgram $out/bin/${binaryName} \
        --prefix PATH : ${
        lib.makeBinPath [
          elixir
          erlang
          pkgs.gawk
        ]
      } \
        --set MIX_REBAR3 ${rebar3}/bin/rebar3
    '';
  }
