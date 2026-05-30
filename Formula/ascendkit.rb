class Ascendkit < Formula
  desc "Local-first App Store release preparation toolkit"
  homepage "https://github.com/rushairer/AscendKit"
  url "https://github.com/rushairer/AscendKit/releases/download/v1.6.2/ascendkit-1.6.2-macos-universal.tar.gz"
  sha256 "4613b1c6ae400d1b566c00f6e60168e71cfea6a7dba5967c8124495d9e678983"
  license "MIT"

  def install
    bin.install "bin/ascendkit"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/ascendkit --version")
  end
end
