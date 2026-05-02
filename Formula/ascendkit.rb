class Ascendkit < Formula
  desc "Local-first App Store release preparation toolkit"
  homepage "https://github.com/rushairer/AscendKit"
  url "https://github.com/rushairer/AscendKit/releases/download/v0.18.0/ascendkit-0.18.0-macos-arm64.tar.gz"
  sha256 "3d728569a5e3ad97d13a3289442205f64be603b27d8183dfd8839c0b3d1370b3"
  license "MIT"

  def install
    bin.install "bin/ascendkit"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/ascendkit --version")
  end
end
