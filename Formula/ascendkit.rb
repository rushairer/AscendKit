class Ascendkit < Formula
  desc "Local-first App Store release preparation toolkit"
  homepage "https://github.com/rushairer/AscendKit"
  url "https://github.com/rushairer/AscendKit/releases/download/v0.13.0/ascendkit-0.13.0-macos-arm64.tar.gz"
  sha256 "d68a7559195359a134b4f9ef142e2c709d5cad6f9c1b9fee2c5889618b25f375"
  license "MIT"

  def install
    bin.install "bin/ascendkit"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/ascendkit --version")
  end
end
