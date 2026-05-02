class Ascendkit < Formula
  desc "Local-first App Store release preparation toolkit"
  homepage "https://github.com/rushairer/AscendKit"
  url "https://github.com/rushairer/AscendKit/releases/download/v0.16.0/ascendkit-0.16.0-macos-arm64.tar.gz"
  sha256 "f01aa2770ef4f421428a7d992f6fc4d00f6b1b684d7310a174ebd54b8222aa47"
  license "MIT"

  def install
    bin.install "bin/ascendkit"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/ascendkit --version")
  end
end
