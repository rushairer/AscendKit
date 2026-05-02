class Ascendkit < Formula
  desc "Local-first App Store release preparation toolkit"
  homepage "https://github.com/rushairer/AscendKit"
  url "https://github.com/rushairer/AscendKit/releases/download/v0.25.0/ascendkit-0.25.0-macos-arm64.tar.gz"
  sha256 "c27f6f7758f2bc69591e93084f936307affd86bf4b16727f227068708eddf36c"
  license "MIT"

  def install
    bin.install "bin/ascendkit"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/ascendkit --version")
  end
end
