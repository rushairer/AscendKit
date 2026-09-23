class Ascendkit < Formula
  desc "Local-first App Store release preparation toolkit"
  homepage "https://github.com/rushairer/AscendKit"
  url "https://github.com/rushairer/AscendKit/releases/download/v1.10.0/ascendkit-1.10.0-macos-universal.tar.gz"
  sha256 "226dc6af3ff844fb5d06b533f87c86ac8d2edd28cf42758e9959b25b985eb097"
  license "MIT"

  def install
    bin.install "bin/ascendkit"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/ascendkit --version")
  end
end
