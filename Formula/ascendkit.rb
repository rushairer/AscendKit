class Ascendkit < Formula
  desc "Local-first App Store release preparation toolkit"
  homepage "https://github.com/rushairer/AscendKit"
  url "https://github.com/rushairer/AscendKit/releases/download/v0.30.0/ascendkit-0.30.0-macos-arm64.tar.gz"
  sha256 "b5893df447ef7198758f499a6c8866be5bc5fc7ed4a867132029f885f16f5c82"
  license "MIT"

  def install
    bin.install "bin/ascendkit"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/ascendkit --version")
  end
end
