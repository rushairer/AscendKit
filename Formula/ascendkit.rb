class Ascendkit < Formula
  desc "Local-first App Store release preparation toolkit"
  homepage "https://github.com/rushairer/AscendKit"
  url "https://github.com/rushairer/AscendKit/releases/download/v1.2.0/ascendkit-1.2.0-macos-universal.tar.gz"
  sha256 "9037b23b5648e5fbb6f8086530c7089f30af2870d43cf898b423677519e97f7f"
  license "MIT"

  def install
    bin.install "bin/ascendkit"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/ascendkit --version")
  end
end
