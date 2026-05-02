class Ascendkit < Formula
  desc "Local-first App Store release preparation toolkit"
  homepage "https://github.com/rushairer/AscendKit"
  url "https://github.com/rushairer/AscendKit/releases/download/v0.35.0/ascendkit-0.35.0-macos-arm64.tar.gz"
  sha256 "75da0c35d23c6fc5da879f9a723d19a5d8817e521ee2f90ef3d15b3cdb7b3228"
  license "MIT"

  def install
    bin.install "bin/ascendkit"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/ascendkit --version")
  end
end
