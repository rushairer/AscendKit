class Ascendkit < Formula
  desc "Local-first App Store release preparation toolkit"
  homepage "https://github.com/rushairer/AscendKit"
  url "https://github.com/rushairer/AscendKit/releases/download/v1.4.0/ascendkit-1.4.0-macos-universal.tar.gz"
  sha256 "76079e492a82feabdca195896e06728ce71379ec4ed935ac6cf5b5b1a9aa9435"
  license "MIT"

  def install
    bin.install "bin/ascendkit"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/ascendkit --version")
  end
end
