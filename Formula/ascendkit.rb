class Ascendkit < Formula
  desc "Local-first App Store release preparation toolkit"
  homepage "https://github.com/rushairer/AscendKit"
  url "https://github.com/rushairer/AscendKit/releases/download/v0.25.0/ascendkit-0.25.0-macos-arm64.tar.gz"
  sha256 "32cd27f3e21fb20dd7a6ba2b2dd46ad0d70e9be97b073385991c0cd45886e9a9"
  license "MIT"

  def install
    bin.install "bin/ascendkit"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/ascendkit --version")
  end
end
