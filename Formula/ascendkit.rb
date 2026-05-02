class Ascendkit < Formula
  desc "Local-first App Store release preparation toolkit"
  homepage "https://github.com/rushairer/AscendKit"
  url "https://github.com/rushairer/AscendKit/releases/download/v0.34.0/ascendkit-0.34.0-macos-arm64.tar.gz"
  sha256 "9057312a4f248fe27ec61229b56d0b40b399ee938757bb7a371f2f0b3dda60a3"
  license "MIT"

  def install
    bin.install "bin/ascendkit"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/ascendkit --version")
  end
end
