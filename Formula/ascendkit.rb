class Ascendkit < Formula
  desc "Local-first App Store release preparation toolkit"
  homepage "https://github.com/rushairer/AscendKit"
  url "https://github.com/rushairer/AscendKit/releases/download/v1.13.1/ascendkit-1.13.1-macos-universal.tar.gz"
  sha256 "94ae8aa440650405af9c0f3e86e9ca308f7e5e605f5552a99bc491ae61ce9736"
  license "MIT"

  def install
    bin.install "bin/ascendkit"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/ascendkit --version")
  end
end
