class Ascendkit < Formula
  desc "Local-first App Store release preparation toolkit"
  homepage "https://github.com/rushairer/AscendKit"
  url "https://github.com/rushairer/AscendKit/releases/download/v0.23.0/ascendkit-0.23.0-macos-arm64.tar.gz"
  sha256 "9472c95baddb3f96c0b9a13a5c1368f3054499a6ef135ae9ff8c871f19e12ad2"
  license "MIT"

  def install
    bin.install "bin/ascendkit"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/ascendkit --version")
  end
end
