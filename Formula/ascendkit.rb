class Ascendkit < Formula
  desc "Local-first App Store release preparation toolkit"
  homepage "https://github.com/rushairer/AscendKit"
  url "https://github.com/rushairer/AscendKit/releases/download/v1.13.0/ascendkit-1.13.0-macos-universal.tar.gz"
  sha256 "5a18872642f3f9e44c8169e24eb16c54c0bd1d00b225e141113c98afb56cde5d"
  license "MIT"

  def install
    bin.install "bin/ascendkit"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/ascendkit --version")
  end
end
