class Ascendkit < Formula
  desc "Local-first App Store release preparation toolkit"
  homepage "https://github.com/rushairer/AscendKit"
  url "https://github.com/rushairer/AscendKit/releases/download/v1.10.0/ascendkit-1.10.0-macos-universal.tar.gz"
  sha256 "a3545e3c153ab78ac4f504a56c5118bf1c5c8b7b104adae03cd2b898162dcaa9"
  license "MIT"

  def install
    bin.install "bin/ascendkit"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/ascendkit --version")
  end
end
