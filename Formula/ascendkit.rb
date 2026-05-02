class Ascendkit < Formula
  desc "Local-first App Store release preparation toolkit"
  homepage "https://github.com/rushairer/AscendKit"
  url "https://github.com/rushairer/AscendKit/releases/download/v0.21.0/ascendkit-0.21.0-macos-arm64.tar.gz"
  sha256 "b7b01a81f680e5ec930a878fe94da707211d52a0e3ae1659c7e4ebfdd2b4dc46"
  license "MIT"

  def install
    bin.install "bin/ascendkit"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/ascendkit --version")
  end
end
