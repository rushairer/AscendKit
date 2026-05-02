class Ascendkit < Formula
  desc "Local-first App Store release preparation toolkit"
  homepage "https://github.com/rushairer/AscendKit"
  url "https://github.com/rushairer/AscendKit/releases/download/v0.20.0/ascendkit-0.20.0-macos-arm64.tar.gz"
  sha256 "497de9def2936d6816263b58b01172a22eded66f542fa971a7f9fba0cb55b07a"
  license "MIT"

  def install
    bin.install "bin/ascendkit"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/ascendkit --version")
  end
end
