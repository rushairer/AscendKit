class Ascendkit < Formula
  desc "Local-first App Store release preparation toolkit"
  homepage "https://github.com/rushairer/AscendKit"
  url "https://github.com/rushairer/AscendKit/releases/download/v1.12.0/ascendkit-1.12.0-macos-universal.tar.gz"
  sha256 "284ae4956f7ab955a8fa3980ff68a8d55c4d92fa6d8ac1d552b67013431c2f30"
  license "MIT"

  def install
    bin.install "bin/ascendkit"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/ascendkit --version")
  end
end
