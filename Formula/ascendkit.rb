class Ascendkit < Formula
  desc "Local-first App Store release preparation toolkit"
  homepage "https://github.com/rushairer/AscendKit"
  url "https://github.com/rushairer/AscendKit/releases/download/v1.11.0/ascendkit-1.11.0-macos-universal.tar.gz"
  sha256 "34c4460b2db29bc9a2b51c3d871c4108b3532d10fd530d2854a0f725053c1bdd"
  license "MIT"

  def install
    bin.install "bin/ascendkit"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/ascendkit --version")
  end
end
