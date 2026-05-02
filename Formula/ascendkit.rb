class Ascendkit < Formula
  desc "Local-first App Store release preparation toolkit"
  homepage "https://github.com/rushairer/AscendKit"
  url "https://github.com/rushairer/AscendKit/releases/download/v0.28.0/ascendkit-0.28.0-macos-arm64.tar.gz"
  sha256 "90641ab20ebc42d20f80e342dc9a72472533dc8e2aa8d249878025912de87b91"
  license "MIT"

  def install
    bin.install "bin/ascendkit"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/ascendkit --version")
  end
end
