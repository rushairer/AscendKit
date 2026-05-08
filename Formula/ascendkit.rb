class Ascendkit < Formula
  desc "Local-first App Store release preparation toolkit"
  homepage "https://github.com/rushairer/AscendKit"
  url "https://github.com/rushairer/AscendKit/releases/download/v1.4.6/ascendkit-1.4.6-macos-universal.tar.gz"
  sha256 "412925f540a0277a625db08c9fc62c5b6ab82d139fd90b8ae5058db491f7a886"
  license "MIT"

  def install
    bin.install "bin/ascendkit"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/ascendkit --version")
  end
end
