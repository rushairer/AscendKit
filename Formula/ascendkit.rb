class Ascendkit < Formula
  desc "Local-first App Store release preparation toolkit"
  homepage "https://github.com/rushairer/AscendKit"
  url "https://github.com/rushairer/AscendKit/releases/download/v0.16.0/ascendkit-0.16.0-macos-arm64.tar.gz"
  sha256 "5d585d7bcdb23b36cc6a159e5a99427ab1c07dc51fbb627b3d5472c595f8495c"
  license "MIT"

  def install
    bin.install "bin/ascendkit"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/ascendkit --version")
  end
end
