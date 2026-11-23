class Ascendkit < Formula
  desc "Local-first App Store release preparation toolkit"
  homepage "https://github.com/rushairer/AscendKit"
  url "https://github.com/rushairer/AscendKit/releases/download/v1.13.1/ascendkit-1.13.1-macos-universal.tar.gz"
  sha256 "296eaef1622d155c55b1382e3220f92378f098e20330c31e34b7fc3a56abb2ba"
  license "MIT"

  def install
    bin.install "bin/ascendkit"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/ascendkit --version")
  end
end
