class Ascendkit < Formula
  desc "Local-first App Store release preparation toolkit"
  homepage "https://github.com/rushairer/AscendKit"
  url "https://github.com/rushairer/AscendKit/releases/download/v1.3.0/ascendkit-1.3.0-macos-universal.tar.gz"
  sha256 "304f3103f95bf822a4ec0aa2c70da9cd5a4964b3781090358112cda6095c2098"
  license "MIT"

  def install
    bin.install "bin/ascendkit"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/ascendkit --version")
  end
end
