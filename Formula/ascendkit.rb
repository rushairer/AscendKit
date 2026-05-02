class Ascendkit < Formula
  desc "Local-first App Store release preparation toolkit"
  homepage "https://github.com/rushairer/AscendKit"
  url "https://github.com/rushairer/AscendKit/releases/download/v0.31.0/ascendkit-0.31.0-macos-arm64.tar.gz"
  sha256 "acfa5b4c07c9fb20651572ef530c914319e15b25493c40edf1b4dde558e6478e"
  license "MIT"

  def install
    bin.install "bin/ascendkit"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/ascendkit --version")
  end
end
