class Ascendkit < Formula
  desc "Local-first App Store release preparation toolkit"
  homepage "https://github.com/rushairer/AscendKit"
  url "https://github.com/rushairer/AscendKit/releases/download/v1.9.0/ascendkit-1.9.0-macos-universal.tar.gz"
  sha256 "6f36f500e498bb5d7431613a584f5da39d6514ff85c23ccdde1633101434b705"
  license "MIT"

  def install
    bin.install "bin/ascendkit"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/ascendkit --version")
  end
end
