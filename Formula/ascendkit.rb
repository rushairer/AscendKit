class Ascendkit < Formula
  desc "Local-first App Store release preparation toolkit"
  homepage "https://github.com/rushairer/AscendKit"
  url "https://github.com/rushairer/AscendKit/releases/download/v0.22.0/ascendkit-0.22.0-macos-arm64.tar.gz"
  sha256 "b014f344197c09b45b2815dadba837358d0777e570e139caaccad9352f4dbae3"
  license "MIT"

  def install
    bin.install "bin/ascendkit"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/ascendkit --version")
  end
end
