class Ascendkit < Formula
  desc "Local-first App Store release preparation toolkit"
  homepage "https://github.com/rushairer/AscendKit"
  url "https://github.com/rushairer/AscendKit/releases/download/v1.4.1/ascendkit-1.4.1-macos-universal.tar.gz"
  sha256 "65e06b63207b2860c8ce2a6d9c1d1edbed0bde13df7cac59b760a0934f1954d2"
  license "MIT"

  def install
    bin.install "bin/ascendkit"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/ascendkit --version")
  end
end
